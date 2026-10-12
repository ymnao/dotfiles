// Runs under `claude plugin test plugin/` against Claude Code's own engine.
// gh, the prompt box and the composer's edits are answered beneath the plugin.

import type { Engine } from 'claude-code/testing'
import { describe, expect, mock, test } from 'claude-code/testing'
import type { On, PromptBox, ProcessRunResult } from 'claude-code'

import { filterIssues, hashWordAt, replaceWord } from '../hooks/issue-suggest.tsx'

const ISSUES = [
  { number: 432, title: 'agent-ready の issue を夜間に進めるランナー' },
  { number: 431, title: '/grill-issue skill を作る' },
  { number: 428, title: 'Desktop に状態の帯を出す mod' },
  { number: 427, title: '# で issue を補完する mod' },
  { number: 42, title: 'old one' },
  { number: 4, title: 'older one' },
]

const BAND = {
  plugin: 'issue-suggest',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 80 },
} as const

function world(on: On, gh: Partial<ProcessRunResult> = {}) {
  const clock = mock.clock(on)
  const w = { ghRuns: 0, fills: [] as string[], box: { text: '', cursor: 0 } as PromptBox, settle: clock.settle }
  // The engine's own band: an empty Box, so a mount sees nothing of the plugin's.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
  on('process.run', () => {
    w.ghRuns += 1
    return {
      value: {
        exitCode: 0,
        stdout: JSON.stringify(ISSUES),
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
        ...gh,
      },
    }
  })
  on('prompt.edit', ($, e) => {
    w.box = {
      text: e.text.slice(0, e.start) + e.inputText + e.text.slice(e.end),
      cursor: e.start + e.inputText.length,
    }
    return w.box
  })
  on('prompt.read', () => ({ value: w.box }))
  on('prompt.fill', ($, e) => {
    w.fills.push(e.text)
    return { isFilled: true }
  })
  return w
}

type World = ReturnType<typeof world>

async function type($: Engine, w: World, inputText: string) {
  const { text, cursor } = w.box
  const shown = await $.prompt.edit({ origin: { kind: 'composer' }, text, cursor, start: cursor, end: cursor, inputText })
  expect(shown).toEqual(w.box)
  await w.settle()
}

async function backspace($: Engine, w: World) {
  const { text, cursor } = w.box
  await $.prompt.edit({ origin: { kind: 'composer' }, text, cursor, start: cursor - 1, end: cursor, inputText: '' })
  await w.settle()
}

describe('hashWordAt', () => {
  test('takes the #-word that ends at the cursor', () => {
    expect(hashWordAt('/dev #42', 8)).toEqual({ q: '42', start: 5, end: 8 })
    expect(hashWordAt('#', 1)?.q).toBe('')
  })

  test('reaches over the digits after the cursor, not over other text', () => {
    expect(hashWordAt('fix #42の件', 6)).toEqual({ q: '4', start: 4, end: 7 })
  })

  test('is null when the word does not start with #', () => {
    expect(hashWordAt('/dev 42', 7)).toBeNull()
    expect(hashWordAt('C#', 2)).toBeNull()
    expect(hashWordAt('# 見出し', 2)).toBeNull()
    expect(hashWordAt('#4　4', 4)).toBeNull()
  })

  test('is null when the cursor stands before the #', () => {
    expect(hashWordAt('/dev #42', 5)).toBeNull()
    expect(hashWordAt('#', 0)).toBeNull()
  })
})

describe('filterIssues', () => {
  test('matches a number by its leading digits', () => {
    expect(filterIssues(ISSUES, '42').map(i => i.number)).toEqual([428, 427, 42])
  })

  test('matches a title fragment case-insensitively', () => {
    expect(filterIssues(ISSUES, 'MOD').map(i => i.number)).toEqual([428, 427])
  })

  test('keeps at most five', () => {
    expect(filterIssues(ISSUES, '')).toHaveLength(5)
  })
})

describe('replaceWord', () => {
  test('writes #N and a space in place of the word', () => {
    expect(replaceWord('/dev #4', { q: '4', start: 5, end: 7 }, 427)).toBe('/dev #427 ')
  })

  test('keeps the text after the word without doubling a space', () => {
    expect(replaceWord('fix #42の件', { q: '4', start: 4, end: 7 }, 427)).toBe('fix #427 の件')
    expect(replaceWord('fix #4 now', { q: '4', start: 4, end: 6 }, 427)).toBe('fix #427 now')
  })
})

describe('band', () => {
  for (const surface of ['terminal', 'desktop'] as const) {
    test(`lists the matching issues while a #-word is typed (${surface})`, async ($, on) => {
      const w = world(on)
      for (const ch of '/dev #42') await type($, w, ch)

      const ui = await $.ui.mount({ ...BAND, surface })
      const rows = await ui.findAll({ type: 'Button' })
      expect(rows.map(row => row.text)).toEqual([
        expect.stringContaining('#428'),
        expect.stringContaining('#427'),
        expect.stringContaining('#42'),
      ])

      await ui.press({ key: 'issue-427' })
      expect(w.fills).toEqual(['/dev #427 '])
      expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
      await ui.unmount()
    })
  }

  test('draws nothing of its own once the word is not a #-word', async ($, on) => {
    const w = world(on)
    for (const ch of '/dev #4 ') await type($, w, ch)

    const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
    await ui.unmount()
  })

  test('fetches when a #-word begins, not on every key', async ($, on) => {
    const w = world(on)
    for (const ch of '/dev #42') await type($, w, ch)
    expect(w.ghRuns).toBe(1)

    for (let i = 0; i < 3; i += 1) await backspace($, w)
    await type($, w, '#')
    expect(w.ghRuns).toBe(2)
  })

  test('clears the band when the prompt is sent', async ($, on) => {
    const w = world(on)
    on('prompt.submit', ($, e) => ({ text: e.text }))
    for (const ch of '/dev #4') await type($, w, ch)
    await $.prompt.submit({ text: '/dev #4' })
    await w.settle()

    const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
    await ui.unmount()
  })

  test('stays quiet when gh fails', async ($, on) => {
    const w = world(on, { exitCode: 1, stdout: '', stderr: 'not a git repository' })
    await type($, w, '#')
    expect(w.ghRuns).toBe(1)

    const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
    await ui.unmount()
  })
})
