// Runs under `claude plugin test plugin/` against Claude Code's own engine.
// gh, the prompt box and the composer's edits are answered beneath the plugin.

import type { Engine } from 'claude-code/testing'
import { describe, expect, test } from 'claude-code/testing'
import type { On, ProcessRunResult } from 'claude-code'

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

type World = { ghRuns: number; fills: string[] }

function world(on: On, gh: Partial<ProcessRunResult> = {}) {
  const w: World = { ghRuns: 0, fills: [] }
  on('session.start', ($, e) => ({ cwd: e.cwd }))
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
  on('prompt.edit', ($, e) => ({
    text: e.text.slice(0, e.start) + e.inputText + e.text.slice(e.end),
    cursor: e.start + e.inputText.length,
  }))
  on('prompt.fill', ($, e) => {
    w.fills.push(e.text)
    return { isFilled: true }
  })
  return w
}

async function settle() {
  for (let i = 0; i < 20; i += 1) await new Promise(resolve => setTimeout(resolve, 0))
}

async function start($: Engine) {
  await $.session.start({ cwd: '/repo', surface: 'desktop', isInteractive: true })
  await settle()
}

async function type($: Engine, before: string, inputText: string) {
  await $.prompt.edit({
    origin: { kind: 'composer' },
    text: before,
    cursor: before.length,
    start: before.length,
    end: before.length,
    inputText,
  })
  await settle()
}

describe('hashWordAt', () => {
  test('takes the #-word that ends at the cursor', () => {
    expect(hashWordAt('/dev #42', 8)).toEqual({ q: '42', text: '/dev #42', start: 5, end: 8 })
    expect(hashWordAt('#', 1)?.q).toBe('')
  })

  test('reaches over the digits after the cursor, not over other text', () => {
    expect(hashWordAt('fix #42の件', 6)).toEqual({ q: '4', text: 'fix #42の件', start: 4, end: 7 })
  })

  test('is null when the word does not start with #', () => {
    expect(hashWordAt('/dev 42', 7)).toBeNull()
    expect(hashWordAt('C#', 2)).toBeNull()
    expect(hashWordAt('# 見出し', 2)).toBeNull()
    expect(hashWordAt('#4　4', 4)).toBeNull()
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
    expect(replaceWord({ q: '4', text: '/dev #4', start: 5, end: 7 }, 427)).toBe('/dev #427 ')
  })

  test('keeps the text after the word without doubling a space', () => {
    expect(replaceWord({ q: '4', text: 'fix #42の件', start: 4, end: 7 }, 427)).toBe('fix #427 の件')
    expect(replaceWord({ q: '4', text: 'fix #4 now', start: 4, end: 6 }, 427)).toBe('fix #427 now')
  })
})

describe('band', () => {
  for (const surface of ['terminal', 'desktop'] as const) {
    test(`lists the matching issues while a #-word is typed (${surface})`, async ($, on) => {
      const w = world(on)
      await start($)
      await type($, '/dev #4', '2')

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
    world(on)
    await start($)
    await type($, '/dev #4', ' ')

    const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
    await ui.unmount()
  })

  test('fetches again when a #-word begins, not on every key', async ($, on) => {
    const w = world(on)
    await start($)
    await type($, '/dev ', '#')
    await type($, '/dev #', '4')
    await type($, '/dev #4', '2')
    expect(w.ghRuns).toBe(2)
  })

  test('stays quiet when gh fails', async ($, on) => {
    const w = world(on, { exitCode: 1, stdout: '', stderr: 'not a git repository' })
    await start($)
    await type($, '', '#')

    expect(w.ghRuns).toBe(2)
    const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(0)
    await ui.unmount()
  })
})
