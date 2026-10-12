import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Issue } from '../types'

const LIMIT = 5

const issues = atom({ plugin: 'issue-suggest', key: 'issues' } as const, [])
const query = atom({ plugin: 'issue-suggest', key: 'query' } as const, null)

type HashWord = { q: string; start: number; end: number }

// `end` reaches over the digits after the cursor, so a press replaces the whole number.
export function hashWordAt(text: string, cursor: number): HashWord | null {
  let start = cursor
  while (start > 0 && !/\s/.test(text[start - 1])) start -= 1
  if (text[start] !== '#') return null
  const digitsAfter = /^\d*/.exec(text.slice(cursor))?.[0] ?? ''
  return { q: text.slice(start + 1, cursor), start, end: cursor + digitsAfter.length }
}

export function filterIssues(list: readonly Issue[], q: string): Issue[] {
  const needle = q.toLowerCase()
  const hit = /^\d+$/.test(q)
    ? (issue: Issue) => String(issue.number).startsWith(q)
    : (issue: Issue) => issue.title.toLowerCase().includes(needle)
  return list.filter(hit).slice(0, LIMIT)
}

export function replaceWord(text: string, { start, end }: HashWord, number: number): string {
  const rest = text.slice(end)
  return `${text.slice(0, start)}#${number}${/^\s/.test(rest) ? '' : ' '}${rest}`
}

let isFetching = false

async function refresh($: EngineInterface) {
  if (isFetching) return
  isFetching = true
  try {
    const ran = await $.process.run(
      ['gh', 'issue', 'list', '--state', 'open', '--limit', '100', '--json', 'number,title'],
      { timeoutMs: 20_000 },
    )
    if (ran.exitCode !== 0) return
    const parsed: unknown = JSON.parse(ran.stdout)
    if (!Array.isArray(parsed)) return
    await update($, issues, () => parsed as Issue[])
  } catch {
    // No gh, not a GitHub repo, or no network: the band just stays empty.
  } finally {
    isFetching = false
  }
}

export const register: Register = on => {
  on('prompt.edit', async ($, e, next) => {
    // Returning anything but next's answer would swallow the person's edit.
    const box = await next(e)
    const q = hashWordAt(box.text, box.cursor)?.q ?? null
    const before = await read($, query)
    if (q !== null && before === null) void refresh($)
    if (q !== before) await update($, query, () => q)
    return box
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const q = await read($, query)
    if (e.props.hasSurvey || q === null) return next(e)
    const hits = filterIssues(await read($, issues), q)
    if (hits.length === 0) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {hits.map(issue => (
          <Button
            key={`issue-${issue.number}`}
            plain
            onPress={async () => {
              // A fill raises no prompt.edit, so the band is cleared here.
              await update($, query, () => null)
              const box = await $.prompt.read()
              const word = hashWordAt(box.text, box.cursor)
              if (word === null) return
              await $.prompt.fill({ text: replaceWord(box.text, word, issue.number), mode: 'replace' })
            }}
          >
            #{issue.number} <Text dimColor>{issue.title}</Text>
          </Button>
        ))}
      </Box>
    )
  })
}
