#!/usr/bin/env node
/*
 * html-brief renderer — 構造化データ (JSON) を、固定デザインの自己完結 HTML に変換する。
 *
 *   node render.mjs <brief.json> [out.html]
 *
 * 出力先を省略すると stdout に書く。検証に失敗したら stderr に
 * `html-brief: <理由>` を出して exit 1 する (stack trace を出さない —
 * 呼び出し側の agent が直すべき JSON の場所を特定できるようにするため)。
 *
 * 設計の意図: agent に書かせるのは「意味」だけにし、「見せ方」(CSS・エスケープ・
 * バーの幅・表の整合) は全てこちらが決定的に行う。これにより
 *   - 出力トークンが中身の量だけで決まる (CSS が毎回出力に乗らない)
 *   - ページ間で見た目がぶれない
 *   - 型の誤り (列数不一致・未知の section・キーの typo) が publish 前に落ちる
 * Node の標準ライブラリだけで動く (依存追加なし)。
 *
 * データモデルの正本は reference/data-model.md。
 */

import {
  closeSync,
  constants as fsConstants,
  fstatSync,
  ftruncateSync,
  openSync,
  readFileSync,
  realpathSync,
  statSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const BADGE_KINDS = new Set(["ok", "warn", "stop", "info"]);

// 許可キーの正本。未知のキーは黙って無視せず落とす — `takeaways` のような
// 1 文字違いが黙殺されると、書いたはずの内容が消えたことに publish 後まで
// 気付けないため (reference/data-model.md と対で維持する)。
const TOP_KEYS = ["title", "verdict", "sections", "date", "subject", "lead", "footer"];
const COMMON_SECTION_KEYS = ["type", "title", "details"];
const SECTION_KEYS = {
  decision: ["columns", "rows"],
  walkthrough: ["steps"],
  series: ["points", "unit", "labelHeader", "valueHeader", "noteHeader", "takeaway"],
  notes: ["body"],
  diagram: ["mermaid"],
};

function fail(message) {
  process.stderr.write(`html-brief: ${message}\n`);
  process.exit(1);
}

/* ---------- 文字列の扱い (エスケープは 1 箇所に集約する) ---------- */

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

// 本文で使えるインライン記法は `code` と **bold** の 2 つだけ。ここから増やさない
// (増やすほど md 実装になる)。bold を入れているのは、agent が md の癖でそのまま
// 書くため — 実際に最初の実使用で結論ボックスに `**...**` が literal で出た。
// esc() を先に通すので、キャプチャした中身に生のタグは入らない。
function inline(value) {
  return esc(value)
    .replaceAll(/`([^`]+)`/g, "<code>$1</code>")
    .replaceAll(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
}

// 空行区切りを段落にする
function paragraphs(value) {
  return String(value)
    .split(/\n{2,}/)
    .map((chunk) => chunk.trim())
    .filter(Boolean)
    .map((chunk) => `<p>${inline(chunk).replaceAll("\n", "<br>")}</p>`)
    .join("\n");
}

/* ---------- 検証 ---------- */

function requireObject(value, where) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail(`${where} はオブジェクトが必要です`);
  }
  return value;
}

function requireString(value, where) {
  if (typeof value !== "string" || value.trim() === "") {
    fail(`${where} は空でない文字列が必要です`);
  }
  return value;
}

function requireArray(value, where) {
  if (!Array.isArray(value) || value.length === 0) {
    fail(`${where} は 1 件以上の配列が必要です`);
  }
  return value;
}

// 任意フィールドも型を見る。素通しにすると非文字列が esc() を通って
// `[object Object]` としてページに出る (rc=0 のまま誤った成果物が publish される)。
function optionalString(value, where) {
  if (value === undefined) return undefined;
  if (typeof value !== "string") fail(`${where} は文字列が必要です`);
  return value;
}

function requireStringArray(value, where) {
  requireArray(value, where);
  value.forEach((item, i) => {
    if (typeof item !== "string") fail(`${where}[${i}] は文字列が必要です`);
  });
  return value;
}

function checkKeys(object, allowed, where) {
  for (const key of Object.keys(object)) {
    if (!allowed.includes(key)) {
      fail(`${where} に未知のキーがあります: ${key} (使えるのは ${allowed.join(" / ")})`);
    }
  }
}

/* ---------- section ごとの描画 ---------- */

function renderBadge(badge, where) {
  if (badge === undefined) return "";
  requireObject(badge, `${where}.badge`);
  checkKeys(badge, ["kind", "text"], `${where}.badge`);
  const kind = badge.kind ?? "info";
  if (!BADGE_KINDS.has(kind)) {
    fail(`${where}.badge.kind が不正です: ${kind} (使えるのは ${[...BADGE_KINDS].join(" / ")})`);
  }
  requireString(badge.text, `${where}.badge.text`);
  return `<span class="badge ${kind}">${esc(badge.text)}</span>`;
}

function renderDecision(section, where) {
  const columns = requireStringArray(section.columns, `${where}.columns`);
  if (columns.length < 2) fail(`${where}.columns は 2 列以上が必要です (1 列目=対象, 2 列目=判定)`);
  const rows = requireArray(section.rows, `${where}.rows`);
  const head = columns.map((c) => `<th>${esc(c)}</th>`).join("");
  const body = rows
    .map((row, i) => {
      const at = `${where}.rows[${i}]`;
      requireObject(row, at);
      checkKeys(row, ["label", "badge", "cells"], at);
      requireString(row.label, `${at}.label`);
      // 配列でないときに空配列へ落とさない。落とすと「書いた内容が rc=0 のまま
      // 消える」経路になり、未知キー拒否で塞いだのと同じ事故が別経路で残る。
      // (2 列構成では cells が空になるので requireStringArray は使えない)
      let cells = [];
      if (row.cells !== undefined) {
        if (!Array.isArray(row.cells)) fail(`${at}.cells は配列が必要です`);
        row.cells.forEach((cell, j) => {
          if (typeof cell !== "string") fail(`${at}.cells[${j}] は文字列が必要です`);
        });
        cells = row.cells;
      }
      if (cells.length !== columns.length - 2) {
        fail(
          `${at}.cells の数が列数と合いません (columns=${columns.length} なので cells=${columns.length - 2} 件が必要、実際は ${cells.length} 件)`,
        );
      }
      const rest = cells.map((c) => `<td>${inline(c)}</td>`).join("");
      return `<tr><td>${inline(row.label)}</td><td>${renderBadge(row.badge, at)}</td>${rest}</tr>`;
    })
    .join("\n");
  return `<div class="scroll"><table>
<thead><tr>${head}</tr></thead>
<tbody>
${body}
</tbody>
</table></div>`;
}

function renderWalkthrough(section, where) {
  const steps = requireArray(section.steps, `${where}.steps`);
  const items = steps
    .map((step, i) => {
      const at = `${where}.steps[${i}]`;
      requireObject(step, at);
      checkKeys(step, ["title", "body", "code"], at);
      requireString(step.title, `${at}.title`);
      optionalString(step.body, `${at}.body`);
      optionalString(step.code, `${at}.code`);
      const body = step.body ? paragraphs(step.body) : "";
      const code = step.code ? `<pre><code>${esc(step.code)}</code></pre>` : "";
      return `<li><p class="step-title">${inline(step.title)}</p>${body}${code}</li>`;
    })
    .join("\n");
  return `<ol class="steps">\n${items}\n</ol>`;
}

function renderSeries(section, where) {
  for (const key of ["unit", "labelHeader", "valueHeader", "noteHeader", "takeaway"]) {
    optionalString(section[key], `${where}.${key}`);
  }
  const points = requireArray(section.points, `${where}.points`);
  const values = points.map((point, i) => {
    const at = `${where}.points[${i}]`;
    requireObject(point, at);
    checkKeys(point, ["label", "value", "note"], at);
    requireString(point.label, `${at}.label`);
    optionalString(point.note, `${at}.note`);
    if (typeof point.value !== "number" || !Number.isFinite(point.value) || point.value < 0) {
      fail(`${at}.value は 0 以上の数値が必要です`);
    }
    return point.value;
  });
  // バーの幅は最大値からこちらが決める (agent に割合を推測させない)。
  // Math.max(...values) は点数が多いと spread で RangeError になるので畳み込む
  const max = values.reduce((a, b) => (b > a ? b : a), 0);
  const unit = section.unit ? esc(section.unit) : "";
  const rows = points
    .map((point, i) => {
      const width = max > 0 ? Math.round((values[i] / max) * 1000) / 10 : 0;
      const note = point.note ? inline(point.note) : "";
      return `<tr><td>${inline(point.label)}</td><td class="num">${esc(point.value)}${unit}</td><td class="bar-cell"><span class="bar" style="width: ${width}%"></span></td><td>${note}</td></tr>`;
    })
    .join("\n");
  const takeaway = section.takeaway ? paragraphs(section.takeaway) : "";
  return `<div class="scroll"><table>
<thead><tr><th>${esc(section.labelHeader ?? "時点")}</th><th>${esc(section.valueHeader ?? "値")}</th><th>推移</th><th>${esc(section.noteHeader ?? "備考")}</th></tr></thead>
<tbody>
${rows}
</tbody>
</table></div>${takeaway}`;
}

function renderNotes(section, where) {
  return paragraphs(requireString(section.body, `${where}.body`));
}

function renderDiagram(section, where) {
  // Artifact は mermaid をネイティブに描画する。図を画像で外部から読み込まない。
  return `<pre class="mermaid">${esc(requireString(section.mermaid, `${where}.mermaid`))}</pre>`;
}

const RENDERERS = {
  decision: renderDecision,
  walkthrough: renderWalkthrough,
  series: renderSeries,
  notes: renderNotes,
  diagram: renderDiagram,
};

function renderSection(section, i) {
  const where = `sections[${i}]`;
  requireObject(section, where);
  if (!Object.hasOwn(SECTION_KEYS, section.type)) {
    fail(`${where}.type が不正です: ${section.type} (使えるのは ${Object.keys(SECTION_KEYS).join(" / ")})`);
  }
  checkKeys(section, [...COMMON_SECTION_KEYS, ...SECTION_KEYS[section.type]], where);
  optionalString(section.title, `${where}.title`);
  const heading = section.title ? `<h2>${inline(section.title)}</h2>` : "";
  const body = RENDERERS[section.type](section, where);
  let details = "";
  if (section.details !== undefined) {
    requireObject(section.details, `${where}.details`);
    checkKeys(section.details, ["summary", "body"], `${where}.details`);
    requireString(section.details.summary, `${where}.details.summary`);
    requireString(section.details.body, `${where}.details.body`);
    details = `<details><summary>${inline(section.details.summary)}</summary>${paragraphs(section.details.body)}</details>`;
  }
  return `<section>\n${heading}\n${body}\n${details}\n</section>`;
}

/* ---------- ページ全体 ---------- */

// CSS のコメントは publish するページには不要。剥がしておくと、外部参照ゼロの
// 検査 (tests/html-brief) がコメント中の url() を誤検出しなくなる。
function stripCssComments(css) {
  return css
    .replaceAll(/\/\*[\s\S]*?\*\//g, "")
    .replaceAll(/\n{3,}/g, "\n\n")
    .trim();
}

function render(data, css) {
  requireObject(data, "トップレベル");
  checkKeys(data, TOP_KEYS, "トップレベル");
  requireString(data.title, "title");
  requireString(data.verdict, "verdict");
  for (const key of ["date", "subject", "lead", "footer"]) {
    optionalString(data[key], key);
  }
  const sections = requireArray(data.sections, "sections");

  const metaParts = [data.date, data.subject].filter(Boolean).map(esc);
  const meta = metaParts.length ? `<p class="meta">${metaParts.join(" · ")}</p>` : "";
  const lead = data.lead ? `<p class="lead">${inline(data.lead)}</p>` : "";
  const footer = data.footer ? `<footer>${inline(data.footer)}</footer>` : "";

  // <title> はマークアップを解釈しないので、h1 と文言をずらさないため
  // 両方 esc() で描く (title だけ `code` が生の backtick で残るのを避ける)。
  return `<meta charset="utf-8">
<title>${esc(data.title)}</title>
<style>
${stripCssComments(css)}
</style>
<div class="wrap">
<h1>${esc(data.title)}</h1>
${meta}
${lead}
<div class="verdict">
<p class="verdict-label">結論</p>
${paragraphs(data.verdict)}
</div>
${sections.map(renderSection).join("\n\n")}
${footer}
</div>
`;
}

/* ---------- 出力 ---------- */

/*
 * 出力先のガード。書き込みは 5 条件を全て満たすときだけ行う:
 *
 *   1. 拡張子が .html
 *   2. パスに `..` セグメントを含まない
 *   3. 親ディレクトリの realpath が一時ディレクトリ配下 (作業中 repo のファイルを
 *      沈黙のうちに壊さない。realpath を取るのでディレクトリ symlink 越しの
 *      迂回も塞がる)
 *   4. 親ディレクトリが自分の所有で world-writable でない (共有一時領域では
 *      検証と open の間に親 symlink を差し替えられる = TOCTOU)
 *   5. 最終要素が symlink でも hardlink でもない (O_NOFOLLOW + nlink 検査。
 *      hardlink は拡張子チェックを迂回して任意 inode を truncate できるため)
 *
 * 2 が要るのは、`resolve()` が `..` を**字句的に**畳むのに対しカーネルは
 * **symlink を辿ってから** `..` を解決するため。`<tmp>/dirlink/../x.html` は
 * ガードからは `<tmp>/x.html` に見えるが、実際には dirlink の実体の親に書かれる。
 * `realpathSync` も内部で `path.resolve()` を掛けるので、この差は realpath では
 * 埋まらない (Node と POSIX realpath(3) で結果が割れる)。
 *
 * これは**誤爆防止のガードであってセキュリティ境界ではない**。shell の
 * リダイレクト (`> path`) はこのプロセスの外なので、ここでは塞げない。
 * 当初はこのレンダラを settings.json の allow に載せて確認プロンプトを
 * 省く案だったが、matcher がリダイレクト付きコマンドをどう扱うかを実測できず、
 * 「確認できない」を緩める根拠にしない方針 (claude/rules/shell.md) に従って
 * allow は入れないことにした。
 */
const OUTPUT_ROOTS_NOTE = "scratchpad などの一時ディレクトリ配下";

function tempRoots() {
  const roots = new Set();
  // プロセスの TMPDIR と /tmp の両方を許す。harness が渡す scratchpad と
  // 対話 shell の TMPDIR (macOS は /var/folders/.../T) が別物になる環境で、
  // 正常な出力先が拒否されるのを避けるため。
  for (const candidate of [tmpdir(), "/tmp"]) {
    try {
      roots.add(realpathSync(candidate));
    } catch {
      // 解決できない候補は単に使わない
    }
  }
  return [...roots];
}

function writeOutput(outputPath, html) {
  if (!outputPath.endsWith(".html")) {
    fail(`出力先は .html で終わるパスにしてください: ${outputPath}`);
  }

  if (outputPath.split(/[/\\]/).includes("..")) {
    fail(`出力先に .. を含めないでください: ${outputPath}`);
  }

  const parent = dirname(resolve(outputPath));
  let realParent;
  try {
    realParent = realpathSync(parent);
  } catch (error) {
    fail(`出力先のディレクトリを解決できません: ${parent} (${error.code ?? error.message})`);
  }

  const roots = tempRoots();
  if (roots.length === 0) {
    fail("一時ディレクトリを解決できません (TMPDIR を確認してください)");
  }
  const inside = roots.some((root) => realParent === root || realParent.startsWith(root + sep));
  if (!inside) {
    fail(`出力先は ${OUTPUT_ROOTS_NOTE} にしてください (${roots.join(" / ")}): ${outputPath}`);
  }

  // 親ディレクトリが自分の所有で、かつ other から書けないことを要求する。
  // `/tmp` 直下は 1777 (world-writable) なので、ここで弾かれる — 共有一時領域では
  // 検証と open の間に親 symlink を差し替えられる (TOCTOU) ため、そもそも受けない。
  // scratchpad や mktemp -d が作るディレクトリは 0700 なので通る。
  let parentStat;
  try {
    parentStat = statSync(realParent);
  } catch (error) {
    fail(`出力先のディレクトリを stat できません: ${realParent} (${error.code ?? error.message})`);
  }
  if (typeof process.getuid === "function" && parentStat.uid !== process.getuid()) {
    fail(`出力先のディレクトリが自分の所有ではありません: ${realParent}`);
  }
  if (parentStat.mode & 0o002) {
    fail(`出力先のディレクトリが world-writable です: ${realParent}`);
  }

  let fd;
  try {
    // O_TRUNC はここでは付けない。nlink を検査してから truncate する
    // 0600 で作る。生成物は調査内容を含みうるので、他ユーザーから読ませない
    fd = openSync(outputPath, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_NOFOLLOW, 0o600);
  } catch (error) {
    if (error.code === "ELOOP") fail(`出力先が symlink です: ${outputPath}`);
    fail(`出力先を開けません: ${outputPath} (${error.code ?? error.message})`);
  }

  try {
    const stat = fstatSync(fd);
    if (stat.nlink > 1) {
      fail(`出力先が hardlink です (nlink=${stat.nlink}): ${outputPath}`);
    }
    ftruncateSync(fd, 0);
    writeSync(fd, html);
  } catch (error) {
    fail(`出力先に書けません: ${outputPath} (${error.code ?? error.message})`);
  } finally {
    closeSync(fd);
  }
}

/* ---------- CLI ---------- */

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath) {
  fail("使い方: node render.mjs <brief.json> [out.html]");
}

// 入力は通常ファイルかつ上限サイズ以内に限る。`/dev/zero` のような
// character device や巨大ファイルを渡されると readFileSync が返ってこない。
const MAX_INPUT_BYTES = 4 * 1024 * 1024;

let raw;
try {
  const stat = statSync(inputPath);
  if (!stat.isFile()) {
    fail(`入力は通常ファイルが必要です: ${inputPath}`);
  }
  if (stat.size > MAX_INPUT_BYTES) {
    fail(`入力が大きすぎます (${stat.size} バイト > ${MAX_INPUT_BYTES}): ${inputPath}`);
  }
  raw = readFileSync(inputPath, "utf8");
} catch (error) {
  fail(`入力を読めません: ${inputPath} (${error.code ?? error.message})`);
}

let data;
try {
  data = JSON.parse(raw);
} catch {
  // error.message は入力の先頭数文字を含むので出さない
  // (入力パスは無制約なので、JSON でないファイルの中身が stderr に漏れる)
  fail(`JSON として解析できません: ${inputPath}`);
}

let css;
try {
  css = readFileSync(join(HERE, "style.css"), "utf8");
} catch (error) {
  fail(`style.css を読めません (make link は済んでいますか): ${error.code ?? error.message}`);
}

const html = render(data, css);

if (outputPath) {
  writeOutput(outputPath, html);
} else {
  process.stdout.write(html);
}
