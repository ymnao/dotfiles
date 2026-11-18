#!/usr/bin/env python3
"""Claude Code のセッションログからユーザー発話を取り出し、会計表・反復・チャンクを出す。

使い方:
    extract.py --out-dir DIR [--since YYYY-MM-DD | --days N] [--project SUBSTR]
               [--cap 3000] [--chunk-chars 110000]

DIR に turns.jsonl (抽出した発話) と chunk-NN.txt (サブエージェントに渡す単位) を書き、
標準出力に会計表・project 別件数・反復・チャンク一覧を出す。
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.expanduser("~/.claude/projects")

# 先頭がこれで始まる発話は user が打った文ではない (通知・出力・自動投入)
DROP_PREFIXES = (
    ("<task-notification", "task-notification"),
    ("<scheduled-task", "scheduled-task"),
    ("<side-sessions-event", "side-sessions-event"),
    ("<ci-monitor-event", "ci-monitor-event"),
    ("<teammate-message", "teammate"),
    ("Another Claude session sent a message", "teammate"),
    ("<local-command-stdout", "local-command"),
    ("<local-command-stderr", "local-command"),
    ("<local-command-caveat", "local-command"),
    ("Caveat:", "local-command"),
    ("[Request interrupted", "interrupt"),
    ("This session is being continued from a previous conversation", "compaction-summary"),
)

REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
PASTED = re.compile(r"<pasted_content\b[^>]*>(.*?)</pasted_content>", re.S)
CMD_NAME = re.compile(r"<command-name>(.*?)</command-name>", re.S)
CMD_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)


def event_text(ev):
    content = (ev.get("message") or {}).get("content")
    if isinstance(content, str):
        return content, False
    if not isinstance(content, list):
        return "", False
    texts, has_tool_result = [], False
    for blk in content:
        if not isinstance(blk, dict):
            continue
        if blk.get("type") == "text":
            texts.append(blk.get("text", ""))
        elif blk.get("type") == "tool_result":
            has_tool_result = True
    return "\n".join(t for t in texts if t), has_tool_result


def classify(ev):
    """(除外理由, None) か ("user", 本文) を返す。"""
    raw, has_tool_result = event_text(ev)
    if not raw.strip():
        return ("tool_result" if has_tool_result else "empty"), None
    if ev.get("isMeta"):
        return "isMeta", None
    if ev.get("isCompactSummary"):
        return "compaction-summary", None
    kind = (ev.get("origin") or {}).get("kind")
    if kind and kind != "human":
        return f"origin:{kind}", None
    body = REMINDER.sub("", raw).strip()
    if not body:
        return "system-reminder-only", None
    for prefix, reason in DROP_PREFIXES:
        if body.startswith(prefix):
            return reason, None
    if body.startswith(("<command-message>", "<command-name>")):
        name = CMD_NAME.search(body)
        args = CMD_ARGS.search(body)
        args = args.group(1).strip() if args else ""
        if not args:
            return "slash-command-noarg", None
        body = f"[{name.group(1).strip() if name else '/?'}] {args}"
    body = PASTED.sub(lambda m: f"[貼り付け {len(m.group(1))} 字は省略]", body)
    return "user", body


def collect(since, project):
    reasons = Counter()
    rows = []
    files = sorted(glob.glob(os.path.join(ROOT, "*", "*.jsonl")))
    since_epoch = datetime.datetime.strptime(since, "%Y-%m-%d").timestamp()
    scanned = 0
    for fp in files:
        proj = os.path.basename(os.path.dirname(fp))
        if project and project.lower() not in proj.lower():
            continue
        # 最終更新が since より前のファイルには since 以降の行が無い
        if os.path.getmtime(fp) < since_epoch:
            continue
        scanned += 1
        session = os.path.basename(fp)[:-len(".jsonl")]
        with open(fp, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except ValueError:
                    reasons["(壊れた行)"] += 1
                    continue
                if not isinstance(ev, dict) or ev.get("type") != "user":
                    continue
                if ev.get("timestamp", "")[:10] < since:
                    continue
                reason, body = classify(ev)
                reasons[reason] += 1
                if body is not None:
                    rows.append({"ts": ev.get("timestamp", ""), "project": proj,
                                 "session": session, "uuid": ev.get("uuid", ""), "text": body})
    rows.sort(key=lambda r: r["ts"])
    return rows, reasons, scanned


def repeats(rows, top):
    """短い発話の完全一致 (空白を正規化) を、件数と別セッション数で数える。"""
    count = Counter()
    sessions = defaultdict(set)
    for r in rows:
        key = " ".join(r["text"].split())
        if len(key) <= 3 or len(key) > 200:
            continue
        count[key] += 1
        sessions[key].add(r["session"])
    multi = [(k, n, len(sessions[k])) for k, n in count.items() if len(sessions[k]) >= 2]
    multi.sort(key=lambda x: (-x[2], -x[1]))
    return multi[:top]


def write_chunks(rows, out_dir, cap, chunk_chars):
    chunks, cur, size = [], [], 0
    for r in rows:
        text = r["text"]
        if len(text) > cap:
            text = text[:cap] + f"\n[以下 {len(r['text']) - cap} 字は打ち切り]"
        cur.append((r, text))
        size += len(text)
        if size >= chunk_chars:
            chunks.append(cur)
            cur, size = [], 0
    if cur:
        chunks.append(cur)
    out = []
    for i, part in enumerate(chunks, 1):
        path = os.path.join(out_dir, f"chunk-{i:02d}.txt")
        with open(path, "w", encoding="utf-8") as f:
            for r, text in part:
                f.write(f"===== {r['ts'][:16]} {r['project']} {r['session'][:8]}\n{text}\n\n")
        out.append((path, len(part), sum(len(t) for _, t in part),
                    part[0][0]["ts"][:10], part[-1][0]["ts"][:10]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", required=True)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--since", help="この日 (UTC, YYYY-MM-DD) 以降の発話だけを見る")
    g.add_argument("--days", type=int, default=30, help="直近 N 日 (既定 30)")
    ap.add_argument("--project", help="project ディレクトリ名の部分一致 (大小無視)")
    ap.add_argument("--cap", type=int, default=3000, help="1 発話の最大文字数")
    ap.add_argument("--chunk-chars", type=int, default=110000, help="1 チャンクの目安文字数")
    ap.add_argument("--top", type=int, default=30, help="反復の表示件数")
    args = ap.parse_args()

    since = args.since or (datetime.datetime.now(datetime.timezone.utc).date()
                           - datetime.timedelta(days=args.days)).isoformat()
    try:
        datetime.datetime.strptime(since, "%Y-%m-%d")
    except ValueError:
        sys.exit(f"--since は YYYY-MM-DD で渡す: {since}")
    os.makedirs(args.out_dir, exist_ok=True)
    # 前回の実行のチャンクが残ると、発話 0 件の回でも古いチャンクを読ませてしまう
    for p in glob.glob(os.path.join(args.out_dir, "chunk-*.txt")):
        os.remove(p)

    rows, reasons, scanned = collect(since, args.project)
    with open(os.path.join(args.out_dir, "turns.jsonl"), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"=== 会計表 (since {since}, project={args.project or '全部'}, 対象ファイル {scanned}) ===")
    for k, v in reasons.most_common():
        print(f"{v:8d}  {k}{'  <= 分析対象' if k == 'user' else ''}")
    print(f"{sum(reasons.values()):8d}  合計 (type=user の行)")
    if not rows:
        print("\nユーザー発話が 0 件。--since / --days / --project を見直す。")
        return

    print("\n=== project 別の発話数 ===")
    for p, n in Counter(r["project"] for r in rows).most_common():
        print(f"{n:6d}  {p}")

    lens = [len(r["text"]) for r in rows]
    print(f"\n発話 {len(rows)} 件 / 打ち切り前 {sum(lens):,} 字 / 期間 {rows[0]['ts'][:10]} .. {rows[-1]['ts'][:10]}")

    print("\n=== 2 セッション以上で同じ文面の発話 (セッション数 / 件数 / 文面) ===")
    for text, n, s in repeats(rows, args.top):
        print(f"{s:4d} {n:5d}  {text}")

    print("\n=== チャンク ===")
    for path, n, c, a, b in write_chunks(rows, args.out_dir, args.cap, args.chunk_chars):
        print(f"{path}  発話 {n} / {c:,} 字 / {a} .. {b}")


if __name__ == "__main__":
    main()
