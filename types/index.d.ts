export type AreaState = 'planned' | 'flying' | 'parked' | 'candidate' | 'review' | 'cleared' | 'landed' | 'blocked' | 'dropped'

export type Area = {
  seq: number
  id: string
  title: string
  class: string
  state: AreaState
  worktree: string
  branch: string
  after: string
  done: number
  total: number
  note: string
  round: number
  status: string
  ahead: number
  behind: number
  dirty: number
  missing: number
  check: string
  checkAge: number
  tokens: number
  ctx: number
  ctxMax: number
  model: string
  effort: string
  age: number
  /** Estimated from tokens at list price. */
  cost: number
}

export type Loose = {
  worktree: string
  branch: string
  ahead: number
  behind: number
  dirty: number
  state: string
}

export type Fleet = {
  mission: string
  base: string
  sha: string
  ci: { latest: string; finished: string; state: string }
  now: number
  limit: number | null
  runways: {
    limit: number
    busy: number
    waiting: number
    timeout: number
    items: { worktree: string; label: string; age: number }[]
  }
  areas: Area[]
  loose: Loose[]
}

/** A subagent of this session, whether or not it flies an area. */
export type AgentRun = {
  id: string
  type: string
  description: string
  model: string
  status: 'running' | 'done' | 'failed'
  startedAt: number
  endedAt?: number
  tokens: number
  ctx: number
  /** Estimated from tokens at list price. */
  cost: number
  effort?: string
  areaId?: string
}

export type Panel = {
  isLandedOpen: boolean
  hiddenFor: string
  openedFor: string
}

declare module 'claude-code' {
  interface PluginState {
    watchtower: {
      fleet: Fleet | null
      panel: Panel
      agents: AgentRun[]
      now: number
    }
  }
}
