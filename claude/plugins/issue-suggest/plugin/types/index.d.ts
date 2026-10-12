export type Issue = { number: number; title: string }

declare module 'claude-code' {
  interface PluginState {
    // `query` is what follows the # of the word at the cursor, null when that word is not a #-word.
    'issue-suggest': { issues: Issue[]; query: string | null }
  }
}
