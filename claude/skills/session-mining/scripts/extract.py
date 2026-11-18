#!/usr/bin/env python3
"""Claude Code のセッションログからユーザー発話を取り出し、会計表・反復・チャンクを出す。

使い方:
    extract.py --out-dir DIR [--since YYYY-MM-DD | --days N]
               [--project SUBSTR] [--exclude-project SUBSTR ...]

DIR に turns.jsonl (抽出した発話) と chunk-NN.txt (サブエージェントに渡す単位) を書き、
標準出力に会計表・project 別件数・反復・チャンク一覧を出す。
user が agent を中断した・tool を拒否した位置は、直前の tool 名つきの印として発話に混ぜる。
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
CAP = 3000            # 1 発話の最大文字数
CHUNK_CHARS = 110000  # 1 チャンクの目安文字数
TOP = 30              # 反復の表示件数

# isMeta / isCompactSummary / origin.kind で落とせないもの。
# origin の無い旧いログの通知と、origin が human のまま届く自動投入
DROP_PREFIXES = {
    "task-notification": ("<task-notification",),
    "scheduled-task": ("<scheduled-task",),
    "side-sessions-event": ("<side-sessions-event",),
    "ci-monitor-event": ("<ci-monitor-event",),
    "local-command": ("<local-command-stdout", "<local-command-stderr"),
}

INTERRUPT = "[Request interrupted"
REJECTED = "The user doesn't want to proceed with this tool use"
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
PASTED = re.compile(r"<pasted_content\b[^>]*>(.*?)</pasted_content>", re.S)
CMD_NAME = re.compile(r"<command-name>(.*?)</command-name>", re.S)
CMD_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)


def block_text(blk):
    c = blk.get("content")
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return c if isinstance(c, str) else ""


def classify(ev, tool_names, last_tool):
    """(理由, 本文 or None) を返す。本文があるものだけが分析対象になる。"""
    content = (ev.get("message") or {}).get("content")
    if isinstance(content, str):
        blocks = [{"type": "text", "text": content}]
    elif isinstance(content, list):
        blocks = [b for b in content if isinstance(b, dict)]
    else:
        blocks = []
    texts = [b.get("text", "") for b in blocks if b.get("type") == "text"]
    results = [b for b in blocks if b.get("type") == "tool_result"]
    raw = "\n".join(t for t in texts if t)

    if not raw.strip():
        for b in results:
            if block_text(b).startswith(REJECTED):
                return "tool-rejected", f"[user が tool を拒否した: {tool_names.get(b.get('tool_use_id'), '?')}]"
        return ("tool_result" if results else "empty"), None
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
    if body.startswith(INTERRUPT):
        return "interrupt", f"[user が中断した。直前の tool: {last_tool or 'なし'}]"
    for reason, prefixes in DROP_PREFIXES.items():
        if body.startswith(prefixes):
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


def collect(since, since_epoch, project, excludes):
    reasons = Counter()
    rows = []
    scanned = 0
    for fp in sorted(glob.glob(os.path.join(ROOT, "*", "*.jsonl"))):
        proj = os.path.basename(os.path.dirname(fp))
        if project and project.lower() not in proj.lower():
            continue
        if any(x.lower() in proj.lower() for x in excludes):
            continue
        # 最終更新が since より前のファイルには since 以降の行が無い
        if os.path.getmtime(fp) < since_epoch:
            continue
        scanned += 1
        session = os.path.basename(fp)[:-len(".jsonl")]
        tool_names, last_tool = {}, None
        with open(fp, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except ValueError:
                    reasons["(壊れた行)"] += 1
                    continue
                if not isinstance(ev, dict):
                    continue
                # 中断・拒否の印に直前の tool 名を付けるため、since より前の行でも追う
                if ev.get("type") == "assistant":
                    for b in (ev.get("message") or {}).get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            tool_names[b.get("id")] = last_tool = b.get("name")
                    continue
                if ev.get("type") != "user" or ev.get("timestamp", "")[:10] < since:
                    continue
                reason, body = classify(ev, tool_names, last_tool)
                reasons[reason] += 1
                if body is not None:
                    rows.append({"ts": ev.get("timestamp", ""), "project": proj, "session": session,
                                 "uuid": ev.get("uuid", ""), "marker": reason != "user", "text": body})
    rows.sort(key=lambda r: r["ts"])
    return rows, reasons, scanned


def repeats(rows):
    """短い発話の完全一致 (空白を正規化) を、件数と別セッション数で数える。"""
    count = Counter()
    sessions = defaultdict(set)
    for r in rows:
        key = " ".join(r["text"].split())
        if r["marker"] or len(key) <= 3 or len(key) > 200:
            continue
        count[key] += 1
        sessions[key].add(r["session"])
    multi = [(k, n, len(sessions[k])) for k, n in count.items() if len(sessions[k]) >= 2]
    multi.sort(key=lambda x: (-x[2], -x[1]))
    return multi[:TOP]


def write_chunks(rows, out_dir):
    chunks, cur, size = [], [], 0
    for r in rows:
        text = r["text"]
        if len(text) > CAP:
            text = text[:CAP] + f"\n[以下 {len(r['text']) - CAP} 字は打ち切り]"
        cur.append((r, text))
        size += len(text)
        if size >= CHUNK_CHARS:
            chunks.append((cur, size))
            cur, size = [], 0
    if cur:
        chunks.append((cur, size))
    out = []
    for i, (part, size) in enumerate(chunks, 1):
        path = os.path.join(out_dir, f"chunk-{i:02d}.txt")
        with open(path, "w", encoding="utf-8") as f:
            for r, text in part:
                f.write(f"===== {r['ts'][:16]} {r['project']} {r['session'][:8]}\n{text}\n\n")
        out.append((path, len(part), size, part[0][0]["ts"][:10], part[-1][0]["ts"][:10]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", required=True)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--since", help="この日 (UTC, YYYY-MM-DD) 以降の発話だけを見る")
    g.add_argument("--days", type=int, default=30, help="直近 N 日 (既定 30)")
    ap.add_argument("--project", help="project ディレクトリ名の部分一致 (大小無視)")
    ap.add_argument("--exclude-project", action="append", default=[],
                    help="この部分一致の project を外す (大小無視、複数指定可)")
    args = ap.parse_args()

    since = args.since or (datetime.datetime.now(datetime.timezone.utc).date()
                           - datetime.timedelta(days=args.days)).isoformat()
    try:
        since_epoch = datetime.datetime.strptime(since, "%Y-%m-%d").timestamp()
    except ValueError:
        sys.exit(f"--since は YYYY-MM-DD で渡す: {since}")
    os.makedirs(args.out_dir, exist_ok=True)
    # 前回の実行のチャンクが残ると、発話 0 件の回でも古いチャンクを読ませてしまう
    for p in glob.glob(os.path.join(args.out_dir, "chunk-*.txt")):
        os.remove(p)

    rows, reasons, scanned = collect(since, since_epoch, args.project, args.exclude_project)
    with open(os.path.join(args.out_dir, "turns.jsonl"), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"=== 会計表 (since {since}, project={args.project or '全部'}, "
          f"除外={','.join(args.exclude_project) or 'なし'}, 対象ファイル {scanned}) ===")
    for k, v in reasons.most_common():
        mark = "  <= 分析対象" if k == "user" else "  <= 印として分析対象" if k in ("interrupt", "tool-rejected") else ""
        print(f"{v:8d}  {k}{mark}")
    print(f"{sum(reasons.values()):8d}  合計 (type=user の行)")
    if not rows:
        print("\nユーザー発話が 0 件。--since / --days / --project を見直す。")
        return

    print("\n=== project 別の発話数 ===")
    for p, n in Counter(r["project"] for r in rows).most_common():
        print(f"{n:6d}  {p}")

    total = sum(len(r["text"]) for r in rows)
    print(f"\n発話 {len(rows)} 件 / 打ち切り前 {total:,} 字 / 期間 {rows[0]['ts'][:10]} .. {rows[-1]['ts'][:10]}")

    print("\n=== 2 セッション以上で同じ文面の発話 (セッション数 / 件数 / 文面) ===")
    for text, n, s in repeats(rows):
        print(f"{s:4d} {n:5d}  {text}")

    print("\n=== チャンク ===")
    for path, n, c, a, b in write_chunks(rows, args.out_dir):
        print(f"{path}  発話 {n} / {c:,} 字 / {a} .. {b}")


if __name__ == "__main__":
    main()
