#!/usr/bin/env python3
"""~/.codex/config.toml が dotfiles の codex/config.toml から逸脱していないか検査する。

usage: codex-config-subset.py <base.toml> <live.toml> <home>

次の 2 つを満たせば exit 0。違反があればその内容を stdout に並べて exit 1。
  - base の全キーが live に同じ値で存在する
  - live のトップレベルにある base に無い非テーブルキーが、ALLOWED_EXTRA に
    載っていて値も一致する
"""

import sys

try:
    import tomllib
except ImportError:
    print(f"tomllib が無い (Python 3.11+ が要る。実行したのは {sys.version.split()[0]})")
    sys.exit(1)

# トップレベルの非テーブルキーは最初のテーブル見出しより前にしか書けず、notify のように
# host 側でコマンドを起動するものが含まれる。codex 自身が書き込む既知の値だけを通す。
ALLOWED_EXTRA = {
    "notify": lambda home: [
        f"{home}/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/"
        "SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
        "turn-ended",
    ],
}


def walk(base, live, path, out):
    for key, want in base.items():
        here = path + [key]
        dotted = ".".join(here)
        if key not in live:
            out.append(f"欠落: {dotted}")
            continue
        got = live[key]
        if isinstance(want, dict):
            if not isinstance(got, dict):
                out.append(f"型が違う: {dotted} (テーブルのはずが {type(got).__name__})")
                continue
            walk(want, got, here, out)
        elif got != want:
            out.append(f"値が違う: {dotted} = {got!r} (dotfiles では {want!r})")


def check_extra(base, live, home, out):
    for key, got in live.items():
        if key in base or isinstance(got, dict):
            continue
        expected = ALLOWED_EXTRA.get(key)
        if expected is None:
            out.append(f"base に無いトップレベルキー: {key}")
        elif got != expected(home):
            out.append(f"許可外の値: {key} = {got!r}")


def load(path):
    with open(path, "rb") as fh:
        return tomllib.load(fh)


def main(argv):
    if len(argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        base, live = load(argv[1]), load(argv[2])
    except (OSError, tomllib.TOMLDecodeError) as err:
        print(f"読めない: {err}")
        return 1
    out = []
    walk(base, live, [], out)
    check_extra(base, live, argv[3], out)
    for line in out:
        print(line)
    return 1 if out else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
