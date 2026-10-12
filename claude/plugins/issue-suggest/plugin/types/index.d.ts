export type Issue = { number: number; title: string }

// The #-word at the cursor: `start` is where its `#` stands in `text`, `end`
// past the digits that follow the cursor, so a press replaces the whole number.
export type Query = { q: string; text: string; start: number; end: number }

declare module 'claude-code' {
  interface PluginState {
    'issue-suggest': { issues: Issue[]; query: Query | null }
  }
}
