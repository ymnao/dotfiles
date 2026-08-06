#!/usr/bin/env node
/*
 * html-brief renderer — 構造化データ (JSON) を、固定デザインの自己完結 HTML に変換する。
 *
 *   node render.mjs <brief.json> [out.html]
 *
 * 出力先を省略すると stdout に書く。検証に失敗したら stderr にメッセージを出して exit 1。
 *
 * 設計の意図: agent に書かせるのは「意味」だけにし、「見せ方」(CSS・エスケープ・
 * バーの幅・表の整合) は全てこちらが決定的に行う。これにより
 *   - 出力トークンが中身の量だけで決まる (CSS が毎回出力に乗らない)
 *   - ページ間で見た目がぶれない
 *   - 型の誤り (列数不一致・未知の section) が publish 前に落ちる
 * Node の標準ライブラリだけで動く (依存追加なし)。
 *
 * データモデルの正本は reference/data-model.md。
 */

import { lstatSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const BADGE_KINDS = new Set(["ok", "warn", "stop", "info"]);
const SECTION_TYPES = new Set(["decision", "walkthrough", "series", "notes", "diagram"]);

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
    .replaceAll('"', "&quot;");
}

// 本文で使えるインライン記法は `code` だけ。増やさない (増やすほど md 実装になる)。
function inline(value) {
  return esc(value).replaceAll(/`([^`]+)`/g, "<code>$1</code>");
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

/* ---------- section ごとの描画 ---------- */

function renderBadge(badge, where) {
  if (badge === undefined) return "";
  if (typeof badge !== "object" || badge === null) fail(`${where}.badge はオブジェクトが必要です`);
  const kind = badge.kind ?? "info";
  if (!BADGE_KINDS.has(kind)) {
    fail(`${where}.badge.kind が不正です: ${kind} (ok / warn / stop / info)`);
  }
  requireString(badge.text, `${where}.badge.text`);
  return `<span class="badge ${kind}">${esc(badge.text)}</span>`;
}

function renderDecision(section, where) {
  const columns = requireArray(section.columns, `${where}.columns`);
  if (columns.length < 2) fail(`${where}.columns は 2 列以上が必要です (1 列目=対象, 2 列目=判定)`);
  const rows = requireArray(section.rows, `${where}.rows`);
  const head = columns.map((c) => `<th>${esc(c)}</th>`).join("");
  const body = rows
    .map((row, i) => {
      const at = `${where}.rows[${i}]`;
      requireString(row.label, `${at}.label`);
      const cells = Array.isArray(row.cells) ? row.cells : [];
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
      requireString(step.title, `${at}.title`);
      const body = step.body ? paragraphs(step.body) : "";
      const code = step.code ? `<pre><code>${esc(step.code)}</code></pre>` : "";
      return `<li><p class="step-title">${inline(step.title)}</p>${body}${code}</li>`;
    })
    .join("\n");
  return `<ol class="steps">\n${items}\n</ol>`;
}

function renderSeries(section, where) {
  const points = requireArray(section.points, `${where}.points`);
  const values = points.map((point, i) => {
    const at = `${where}.points[${i}]`;
    requireString(point.label, `${at}.label`);
    if (typeof point.value !== "number" || !Number.isFinite(point.value) || point.value < 0) {
      fail(`${at}.value は 0 以上の数値が必要です`);
    }
    return point.value;
  });
  // バーの幅は最大値からこちらが決める (agent に割合を推測させない)
  const max = Math.max(...values);
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
  if (typeof section !== "object" || section === null) fail(`${where} はオブジェクトが必要です`);
  if (!SECTION_TYPES.has(section.type)) {
    fail(`${where}.type が不正です: ${section.type} (使えるのは ${[...SECTION_TYPES].join(" / ")})`);
  }
  const heading = section.title ? `<h2>${inline(section.title)}</h2>` : "";
  const body = RENDERERS[section.type](section, where);
  let details = "";
  if (section.details !== undefined) {
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
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    fail("トップレベルはオブジェクトが必要です");
  }
  requireString(data.title, "title");
  requireString(data.verdict, "verdict");
  const sections = requireArray(data.sections, "sections");

  const metaParts = [data.date, data.subject].filter(Boolean).map(esc);
  const meta = metaParts.length ? `<p class="meta">${metaParts.join(" · ")}</p>` : "";
  const lead = data.lead ? `<p class="lead">${inline(data.lead)}</p>` : "";
  const footer = data.footer ? `<footer>${inline(data.footer)}</footer>` : "";

  return `<title>${esc(data.title)}</title>
<style>
${stripCssComments(css)}
</style>
<div class="wrap">
<h1>${inline(data.title)}</h1>
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

/* ---------- CLI ---------- */

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath) {
  fail("使い方: node render.mjs <brief.json> [out.html]");
}

let raw;
try {
  raw = readFileSync(inputPath, "utf8");
} catch (error) {
  fail(`入力を読めません: ${inputPath} (${error.code ?? error.message})`);
}

let data;
try {
  data = JSON.parse(raw);
} catch (error) {
  fail(`JSON として解析できません: ${error.message}`);
}

const css = readFileSync(join(HERE, "style.css"), "utf8");
const html = render(data, css);

if (outputPath) {
  // 出力先のガード。この renderer は settings.json の allow リストに入っていて
  // 確認プロンプト無しで走るため、argv 経由で任意のファイルを上書きできる状態に
  // しない。拡張子を .html に限り、symlink 越しの書き込みを拒否する
  // (~/.zshrc 等を指す symlink を作られると拡張子チェックを迂回できるため)。
  if (!outputPath.endsWith(".html")) {
    fail(`出力先は .html で終わるパスにしてください: ${outputPath}`);
  }
  let stat = null;
  try {
    stat = lstatSync(outputPath);
  } catch {
    stat = null; // 未作成なら新規作成する
  }
  if (stat && stat.isSymbolicLink()) {
    fail(`出力先が symlink です: ${outputPath}`);
  }
  writeFileSync(outputPath, html);
} else {
  process.stdout.write(html);
}
