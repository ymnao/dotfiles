#!/usr/bin/env bash
set -euo pipefail

# tests/run-locale-matrix.sh (ロケール軸再発防止 driver) の分岐単体テスト
# (issue #193)。CI は matrix で make test を直接並列に回すため driver 本体
# は継続テストされない。ここで locale / make を PATH stub に差し替え、5 分岐
# の各挙動 (別表記正規化 / skip / 失敗集約 / no-locale / UTF-8 gate) を assert
# する。
#
# スタブ方針: driver は `env LC_ALL=X LANG=X make test` で make を外部起動
# するため、shell 関数 override は素通りされる。PATH 前置きの実行可能 stub
# のみが確実に効く。stub は case dir に生成し、driver を
# `env PATH="${stub_dir}:${PATH}" bash driver` で起動する。
#
# 保留: 「LOCALES から UTF-8 を意図的に外した場合はスルー」分岐 (driver
# line 84-106 の utf8_requested=0 ケース) は driver 内 LOCALES 配列が
# ハードコードのため到達不能。issue #193 は driver 本体を変えずテストのみ
# 追加するスコープ。将来必要になれば LOCALE_MATRIX_LOCALES env override を
# 別 issue で追加する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel)"
DRIVER="${REPO_ROOT}/tests/run-locale-matrix.sh"

if [ ! -f "${DRIVER}" ]; then
    echo "ERROR: driver not found: ${DRIVER}" >&2
    exit 1
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/locale-matrix-tests.XXXXXX")"
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "${WORKDIR}"; }
trap cleanup EXIT

pass=0
fail=0

# make stub と locale stub を case_dir 配下に生成する。
# 引数: <case_name> <locale_output_multiline> <exit_codes_space_separated>
setup_case() {
    local case_name="$1"
    local locale_output="$2"
    local exit_codes="$3"
    local case_dir="${WORKDIR}/${case_name}"
    local stub_dir="${case_dir}/stubs"
    mkdir -p "${stub_dir}"

    # locale -a の出力を一度ファイルに落として stub が cat する形にする。
    # 空文字列の場合は 0 バイトファイルを作る (printf '%s\n' "" は空行を
    # 出してしまい、driver 側の grep -Fqx で偽マッチする恐れがある)。
    if [ -z "${locale_output}" ]; then
        : > "${case_dir}/locale_output"
    else
        printf '%s\n' "${locale_output}" > "${case_dir}/locale_output"
    fi

    # locale stub — driver は `locale -a` しか呼ばないので引数は無視する。
    cat > "${stub_dir}/locale" <<EOF
#!/bin/bash
cat "${case_dir}/locale_output"
EOF
    chmod +x "${stub_dir}/locale"

    # make stub の呼び出し回数と exit code の制御ファイル。
    # exit_codes は space 区切りを 1 行 1 exit code に展開したいため、
    # 意図的に word split させる (SC2086 の info はここでは正しい挙動)。
    echo 0 > "${case_dir}/make_count"
    : > "${case_dir}/make_calls.log"
    if [ -z "${exit_codes}" ]; then
        : > "${case_dir}/make_exit_codes"
    else
        printf '%s\n' ${exit_codes} > "${case_dir}/make_exit_codes"
    fi

    # make stub — 呼び出し回数を進め、その回に対応する exit code を返す。
    # 期待 exit code の行数を超えたら default 0。calls.log に LC_ALL を残す
    # ことで、どの locale で呼ばれたか (or 呼ばれなかったか) を assert する。
    # ${LC_ALL:-unset} と \$(( )) は stub 実行時に評価させたいので \$ で
    # deferred、${case_dir} は生成時に埋め込む。
    cat > "${stub_dir}/make" <<EOF
#!/bin/bash
n=\$(cat "${case_dir}/make_count")
echo "\${LC_ALL:-unset}" >> "${case_dir}/make_calls.log"
echo \$(( n + 1 )) > "${case_dir}/make_count"
code=\$(sed -n "\$(( n + 1 ))p" "${case_dir}/make_exit_codes")
exit "\${code:-0}"
EOF
    chmod +x "${stub_dir}/make"
}

# driver を stub PATH で起動し、stdout/stderr/exit code を case_dir に残す。
run_driver() {
    local case_name="$1"
    local case_dir="${WORKDIR}/${case_name}"
    local stub_dir="${case_dir}/stubs"
    local rc=0
    # set -e 下で非 0 exit を拾うため if で受ける。
    if env PATH="${stub_dir}:${PATH}" bash "${DRIVER}" \
        > "${case_dir}/stdout" 2> "${case_dir}/stderr"; then
        rc=0
    else
        rc=$?
    fi
    echo "${rc}" > "${case_dir}/exit"
}

assert_eq() {
    local label="$1" want="$2" got="$3"
    if [ "${want}" = "${got}" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL ${label}: want=[${want}] got=[${got}]"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" file="$3"
    if grep -Fq -- "${needle}" "${file}"; then
        pass=$((pass + 1))
    else
        echo "FAIL ${label}: needle=[${needle}] not found in ${file}"
        echo "----- ${file} -----"
        cat "${file}"
        echo "----- end -----"
        fail=$((fail + 1))
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" file="$3"
    if grep -Fq -- "${needle}" "${file}"; then
        echo "FAIL ${label}: needle=[${needle}] unexpectedly found in ${file}"
        echo "----- ${file} -----"
        cat "${file}"
        echo "----- end -----"
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
}

# make_calls.log のように「1 行 = 1 ロケール名」形式のファイルに対する
# 行境界一致版。substring 一致だと将来 LOCALES に "C" を部分文字列として
# 含む名前 (例: zh_CN.UTF-8) が入った時に偽陽性/偽陰性を起こすため分ける。
assert_line_present() {
    local label="$1" needle="$2" file="$3"
    if grep -Fqx -- "${needle}" "${file}"; then
        pass=$((pass + 1))
    else
        echo "FAIL ${label}: line=[${needle}] not found in ${file}"
        echo "----- ${file} -----"
        cat "${file}"
        echo "----- end -----"
        fail=$((fail + 1))
    fi
}

assert_line_absent() {
    local label="$1" needle="$2" file="$3"
    if grep -Fqx -- "${needle}" "${file}"; then
        echo "FAIL ${label}: line=[${needle}] unexpectedly found in ${file}"
        echo "----- ${file} -----"
        cat "${file}"
        echo "----- end -----"
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
}

make_call_count() {
    local case_name="$1"
    wc -l < "${WORKDIR}/${case_name}/make_calls.log" | tr -d ' '
}

# ---------------------------------------------------------------------------
# case 1: 別表記ロケール吸収
#   locale -a が "en_US.utf8" / "ja_JP.utf8" (dot なし桁 / ハイフンなし) を
#   返しても、driver は小文字化 + ハイフン除去で正規化して LOCALES の
#   "en_US.UTF-8" / "ja_JP.UTF-8" と一致判定できる。
# ---------------------------------------------------------------------------
name="01-normalize-alt-spelling"
setup_case "${name}" "C
en_US.utf8
ja_JP.utf8" "0 0 0"
run_driver "${name}"
dir="${WORKDIR}/${name}"
assert_eq "${name} exit" "0" "$(cat "${dir}/exit")"
assert_eq "${name} make call count" "3" "$(make_call_count "${name}")"
assert_line_present "${name} calls has C" "C" "${dir}/make_calls.log"
assert_line_present "${name} calls has en_US.UTF-8 (normalized-back)" \
    "en_US.UTF-8" "${dir}/make_calls.log"
assert_line_present "${name} calls has ja_JP.UTF-8 (normalized-back)" \
    "ja_JP.UTF-8" "${dir}/make_calls.log"
assert_not_contains "${name} no WARN" "WARN:" "${dir}/stderr"

# ---------------------------------------------------------------------------
# case 2: skip 分岐
#   一部 locale (C) が host に無い場合、driver は WARN 出力して skipped に
#   集約し、残りは実行、failed 0 なら exit 0。
# ---------------------------------------------------------------------------
name="02-skip-missing"
setup_case "${name}" "en_US.UTF-8
ja_JP.UTF-8" "0 0"
run_driver "${name}"
dir="${WORKDIR}/${name}"
assert_eq "${name} exit" "0" "$(cat "${dir}/exit")"
assert_eq "${name} make call count" "2" "$(make_call_count "${name}")"
assert_line_absent "${name} C not invoked" \
    "C" "${dir}/make_calls.log"
assert_contains "${name} WARN for C" \
    'WARN: locale "C"' "${dir}/stderr"
assert_contains "${name} summary skipped shows C" \
    "skipped: C" "${dir}/stdout"

# ---------------------------------------------------------------------------
# case 3: 失敗集約
#   2 回目 (en_US.UTF-8) で make が exit 1 しても後続 (ja_JP.UTF-8) は実行
#   され、最終 exit は 1。failed 集約に en_US.UTF-8 が現れる。
# ---------------------------------------------------------------------------
name="03-failure-aggregation"
setup_case "${name}" "C
en_US.UTF-8
ja_JP.UTF-8" "0 1 0"
run_driver "${name}"
dir="${WORKDIR}/${name}"
assert_eq "${name} exit" "1" "$(cat "${dir}/exit")"
assert_eq "${name} make call count (continues after fail)" \
    "3" "$(make_call_count "${name}")"
assert_contains "${name} summary failed shows en_US.UTF-8" \
    "failed:  en_US.UTF-8" "${dir}/stdout"

# ---------------------------------------------------------------------------
# case 4: no-locale エラーパス
#   locale -a が空 (対象 locale がゼロ) の場合、make を 1 度も呼ばず
#   ERROR + exit 1。case 5 (UTF-8 gate) との識別は make 呼び出し回数 0
#   で行う (gate は 1 回以上呼ばれる)。
# ---------------------------------------------------------------------------
name="04-no-locale-error"
setup_case "${name}" "" ""
run_driver "${name}"
dir="${WORKDIR}/${name}"
assert_eq "${name} exit" "1" "$(cat "${dir}/exit")"
assert_eq "${name} make never called" "0" "$(make_call_count "${name}")"
assert_contains "${name} ERROR no locale" \
    "ERROR: no locale in" "${dir}/stderr"

# ---------------------------------------------------------------------------
# case 5: UTF-8 gate (到達可能側)
#   C だけ available → C 分は実行されるが UTF-8 系が 1 つも ran に入らない
#   ため gate 発火で exit 1。case 4 との識別は make 呼び出し回数 ≥1 と
#   gate 専用文言で行う。
# ---------------------------------------------------------------------------
name="05-utf8-gate"
setup_case "${name}" "C" "0"
run_driver "${name}"
dir="${WORKDIR}/${name}"
assert_eq "${name} exit" "1" "$(cat "${dir}/exit")"
assert_eq "${name} make called for C only" "1" "$(make_call_count "${name}")"
assert_line_present "${name} C was invoked" "C" "${dir}/make_calls.log"
assert_not_contains "${name} no UTF-8 in calls" \
    "UTF-8" "${dir}/make_calls.log"
assert_contains "${name} ERROR UTF-8 gate" \
    "ERROR: no UTF-8 locale" "${dir}/stderr"

# ---------------------------------------------------------------------------

printf '\nlocale-matrix driver tests: pass=%d fail=%d\n' "${pass}" "${fail}"
if [ "${fail}" -gt 0 ]; then
    exit 1
fi
