#!/usr/bin/env python3
"""dotfiles の codex/config.toml が ~/.codex/config.toml の部分集合か検査する。

usage: codex-config-subset.py <base.toml> <live.toml>

base の全キーが live に同じ値で存在すれば exit 0。欠落・値の相違があれば
その キーパスを stdout に並べて exit 1。
"""

import sys
import tomllib


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


def load(path):
    with open(path, "rb") as fh:
        return tomllib.load(fh)


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        base, live = load(argv[1]), load(argv[2])
    except (OSError, tomllib.TOMLDecodeError) as err:
        print(f"読めない: {err}")
        return 1
    out = []
    walk(base, live, [], out)
    for line in out:
        print(line)
    return 1 if out else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
