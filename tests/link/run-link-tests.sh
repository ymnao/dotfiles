#!/usr/bin/env bash
set -euo pipefail

# scripts/link.sh の end-to-end fixture 回帰テスト。
#
# 検証観点:
#   1. fresh install → 期待される symlink がすべて作成される
#   2. 既存 regular file → .backup にリネームされ symlink が新規作成される
#   3. 既存 symlink (別 target) → backup せず削除・置換される
#   4. source 側 dotfile dir が無ければ HOME 側にも symlink を作らない
#   5. codex/skills は per-skill 個別 symlink (skills 親ディレクトリを一括 symlink しない)
#   6. HOME/.codex/skills が既存 symlink (旧挙動) → 実ディレクトリ + per-skill symlink に置換
#   7. codex/config.toml は symlink されず merge (regular file として出力)
#
# isolation: fake dotfiles root を mktemp で作り、link.sh 本体と lib/*.sh /
# codex-merge-config.sh を symlink する。link.sh 内の cd は pwd (no -P) なので
# fake root が DOTFILES_DIR として解釈される。HOME も fake HOME に差し替える。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TARGET="$REPO_ROOT/scripts/link.sh"

if [ ! -f "$TARGET" ]; then
  echo "ERROR: target not found: $TARGET" >&2
  exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/link-tests.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

pass=0
fail=0

# fake dotfiles root を組み立てる。scripts/ 配下は real repo への symlink、
# それ以外 (wezterm/ 等の fixture) は各テストで自由に配置する。
make_fake_root() {
  local root="$1"
  mkdir -p "$root/scripts/lib"
  ln -s "$REPO_ROOT/scripts/link.sh"              "$root/scripts/link.sh"
  ln -s "$REPO_ROOT/scripts/codex-merge-config.sh" "$root/scripts/codex-merge-config.sh"
  ln -s "$REPO_ROOT/scripts/lib/log.sh"           "$root/scripts/lib/log.sh"
  ln -s "$REPO_ROOT/scripts/lib/backup.sh"        "$root/scripts/lib/backup.sh"
}

# fake HOME を空で用意
make_fake_home() {
  mkdir -p "$1"
}

run_link() {
  local root="$1" home="$2" out="$3" err="$4"
  local rc=0
  HOME="$home" bash "$root/scripts/link.sh" >"$out" 2>"$err" || rc=$?
  echo "$rc"
}

# ---- case 1: fresh install → 期待 symlink が作成される
c1_root="$WORKDIR/c1_root"
c1_home="$WORKDIR/c1_home"
make_fake_root "$c1_root"
make_fake_home "$c1_home"
mkdir -p "$c1_root/wezterm" "$c1_root/nvim"
mkdir -p "$c1_root/starship"; printf 'x\n' > "$c1_root/starship/starship.toml"
rc=$(run_link "$c1_root" "$c1_home" "$c1_home/out" "$c1_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c1: rc=$rc"; ok=0; }
[ -L "$c1_home/.config/wezterm" ] && [ "$(readlink "$c1_home/.config/wezterm")" = "$c1_root/wezterm" ] \
  || { echo "FAIL c1: wezterm symlink"; ok=0; }
[ -L "$c1_home/.config/nvim" ] || { echo "FAIL c1: nvim symlink"; ok=0; }
[ -L "$c1_home/.config/starship.toml" ] || { echo "FAIL c1: starship symlink"; ok=0; }
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c1_home/err"; fi

# ---- case 2: 既存 regular file → .backup にリネーム、symlink 新規作成
c2_root="$WORKDIR/c2_root"
c2_home="$WORKDIR/c2_home"
make_fake_root "$c2_root"
make_fake_home "$c2_home"
mkdir -p "$c2_root/wezterm"; printf 'new\n' > "$c2_root/wezterm/wezterm.lua"
mkdir -p "$c2_home/.config"
printf 'old-user-config\n' > "$c2_home/.config/wezterm"  # 事前 regular file
rc=$(run_link "$c2_root" "$c2_home" "$c2_home/out" "$c2_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c2: rc=$rc"; ok=0; }
[ -L "$c2_home/.config/wezterm" ] || { echo "FAIL c2: not symlink"; ok=0; }
# backup は .backup または .backup.<ts> のいずれか
if ! ls "$c2_home/.config/wezterm".backup* >/dev/null 2>&1 && [ ! -e "$c2_home/.config/wezterm.backup" ]; then
  echo "FAIL c2: backup not created"; ok=0
fi
# backup の中身が元 file 内容と一致する
backup_file=$(ls "$c2_home/.config/wezterm".backup* 2>/dev/null | head -1)
[ -z "$backup_file" ] && backup_file="$c2_home/.config/wezterm.backup"
if [ -f "$backup_file" ]; then
  content=$(cat "$backup_file")
  [ "$content" = "old-user-config" ] || { echo "FAIL c2: backup content mismatch: $content"; ok=0; }
else
  echo "FAIL c2: backup path not a file: $backup_file"; ok=0
fi
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c2_home/err"; fi

# ---- case 3: 既存 symlink (別 target) → backup せず置換
c3_root="$WORKDIR/c3_root"
c3_home="$WORKDIR/c3_home"
make_fake_root "$c3_root"
make_fake_home "$c3_home"
mkdir -p "$c3_root/nvim"
mkdir -p "$c3_home/.config" "$c3_home/other-nvim"
ln -s "$c3_home/other-nvim" "$c3_home/.config/nvim"  # 事前 symlink (別 target)
rc=$(run_link "$c3_root" "$c3_home" "$c3_home/out" "$c3_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c3: rc=$rc"; ok=0; }
[ -L "$c3_home/.config/nvim" ] || { echo "FAIL c3: not symlink"; ok=0; }
[ "$(readlink "$c3_home/.config/nvim")" = "$c3_root/nvim" ] || { echo "FAIL c3: symlink not replaced"; ok=0; }
# backup が生成されていないことを確認 (symlink 置換時は backup 不要)
if ls "$c3_home/.config/nvim".backup* >/dev/null 2>&1 || [ -e "$c3_home/.config/nvim.backup" ]; then
  echo "FAIL c3: unexpected backup for symlink replacement"; ok=0
fi
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c3_home/err"; fi

# ---- case 4: source dir 不在 → HOME 側にも symlink を作らない
c4_root="$WORKDIR/c4_root"
c4_home="$WORKDIR/c4_home"
make_fake_root "$c4_root"
make_fake_home "$c4_home"
mkdir -p "$c4_root/wezterm"  # nvim / fish / karabiner / starship は無い
rc=$(run_link "$c4_root" "$c4_home" "$c4_home/out" "$c4_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c4: rc=$rc"; ok=0; }
[ -L "$c4_home/.config/wezterm" ] || { echo "FAIL c4: wezterm should exist"; ok=0; }
for missing in nvim karabiner fish starship.toml; do
  if [ -e "$c4_home/.config/$missing" ] || [ -L "$c4_home/.config/$missing" ]; then
    echo "FAIL c4: unexpected $missing"; ok=0
  fi
done
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c4_home/err"; fi

# ---- case 5: codex/skills は per-skill 個別 symlink
c5_root="$WORKDIR/c5_root"
c5_home="$WORKDIR/c5_home"
make_fake_root "$c5_root"
make_fake_home "$c5_home"
mkdir -p "$c5_root/codex/skills/skillA" "$c5_root/codex/skills/skillB"
printf 'A\n' > "$c5_root/codex/skills/skillA/SKILL.md"
printf 'B\n' > "$c5_root/codex/skills/skillB/SKILL.md"
rc=$(run_link "$c5_root" "$c5_home" "$c5_home/out" "$c5_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c5: rc=$rc"; ok=0; }
# 親 skills は実ディレクトリ (symlink ではない)
[ -d "$c5_home/.codex/skills" ] && [ ! -L "$c5_home/.codex/skills" ] \
  || { echo "FAIL c5: skills should be real dir"; ok=0; }
# 各 skill は symlink で source を指す
[ -L "$c5_home/.codex/skills/skillA" ] && [ "$(readlink "$c5_home/.codex/skills/skillA")" = "$c5_root/codex/skills/skillA" ] \
  || { echo "FAIL c5: skillA symlink"; ok=0; }
[ -L "$c5_home/.codex/skills/skillB" ] || { echo "FAIL c5: skillB symlink"; ok=0; }
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c5_home/err"; fi

# ---- case 6: HOME/.codex/skills が既存 symlink → 実 dir + per-skill symlink に置換
c6_root="$WORKDIR/c6_root"
c6_home="$WORKDIR/c6_home"
make_fake_root "$c6_root"
make_fake_home "$c6_home"
mkdir -p "$c6_root/codex/skills/skillA"
mkdir -p "$c6_home/.codex" "$c6_home/legacy-skills"
ln -s "$c6_home/legacy-skills" "$c6_home/.codex/skills"  # 旧挙動: skills 自体を symlink
rc=$(run_link "$c6_root" "$c6_home" "$c6_home/out" "$c6_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c6: rc=$rc"; ok=0; }
[ -d "$c6_home/.codex/skills" ] && [ ! -L "$c6_home/.codex/skills" ] \
  || { echo "FAIL c6: legacy symlink not replaced with real dir"; ok=0; }
[ -L "$c6_home/.codex/skills/skillA" ] || { echo "FAIL c6: skillA per-skill symlink"; ok=0; }
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c6_home/err"; fi

# ---- case 7: codex/config.toml は symlink されず merge (regular file)
c7_root="$WORKDIR/c7_root"
c7_home="$WORKDIR/c7_home"
make_fake_root "$c7_root"
make_fake_home "$c7_home"
mkdir -p "$c7_root/codex"
printf 'model = "base"\n' > "$c7_root/codex/config.toml"
rc=$(run_link "$c7_root" "$c7_home" "$c7_home/out" "$c7_home/err")
ok=1
[ "$rc" = 0 ] || { echo "FAIL c7: rc=$rc"; ok=0; }
[ -f "$c7_home/.codex/config.toml" ] && [ ! -L "$c7_home/.codex/config.toml" ] \
  || { echo "FAIL c7: config.toml should be regular file, not symlink"; ok=0; }
if ! grep -q '^model = "base"$' "$c7_home/.codex/config.toml"; then
  echo "FAIL c7: base content missing from merged config.toml"; ok=0
fi
if [ "$ok" = 1 ]; then pass=$((pass+1)); else fail=$((fail+1)); sed 's/^/  /' "$c7_home/err"; fi

echo "link tests: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
