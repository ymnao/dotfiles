export type Issue = { number: number; title: string }

declare module 'claude-code' {
  interface PluginState {
    'issue-suggest': { issues: Issue[]; query: string | null }
  }
}
