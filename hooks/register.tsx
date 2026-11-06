import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AgentRun, Area, AreaState, Fleet, Panel } from '../types'

const fleet = atom({ plugin: 'watchtower', key: 'fleet' } as const, null)
const panel = atom({ plugin: 'watchtower', key: 'panel' } as const, { isLandedOpen: false, hiddenFor: '', openedFor: '' })
const agents = atom({ plugin: 'watchtower', key: 'agents' } as const, [])
const now = atom({ plugin: 'watchtower', key: 'now' } as const, 0)

const PANE = 'watchtower-fleet'
const POLL_MS = 1500
const COLUMN_PX = 8.9
const BAND_BUTTONS_PX = 96
// Ahead/behind and dirty counts change without touching the state files.
const GIT_REFRESH_MS = 20_000
// A worker session only needs its own record; the tower watches the fleet.
const WORKER_REFRESH_MS = 90_000

const SANS = "-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',sans-serif"

// Neutral like the app around it. Colour is reserved for state: a dot, a bar, an avatar.
const BASE_CSS = `<style>
text{font-variant-numeric:tabular-nums}
.ink{fill:#1f1f1e}.soft{fill:#6b6b68}.faint{fill:#9a9a96}.track{fill:#00000012}.box{fill:none;stroke:#00000022}.line{stroke:#00000018}
.flying{color:#2f7fd6}.candidate,.review{color:#b56a00}.cleared,.landed{color:#2e8f66}.blocked{color:#c93a3a}.parked{color:#7c8596}.planned{color:#9aa2b1}
@media (prefers-color-scheme: dark){
.ink{fill:#ececeb}.soft{fill:#a3a3a0}.faint{fill:#7d7d7a}.track{fill:#ffffff14}.box{fill:none;stroke:#ffffff1f}.line{stroke:#ffffff17}
.flying{color:#6cb6ff}.candidate,.review{color:#e3a64a}.cleared{color:#6fd3a6}.landed{color:#4fc48e}.blocked{color:#ef7b7b}.parked{color:#98a2b3}.planned{color:#7c8aa2}
}
.fill{fill:currentColor}
</style>`

const WORDS = {
  en: {
    flying: 'Running', candidate: 'Delivered', review: 'In review', cleared: 'Ready to land', landed: 'Landed', blocked: 'Needs you', parked: 'Paused', planned: 'Planned', dropped: 'Dropped',
    worktrees: 'Worktrees', of: 'of', running: 'running', agents: 'Agents', other: 'Other worktrees', cost: 'Cost', tokens: 'Tokens', time: 'Time', after: 'after',
    limit: 'limit', noLimit: 'none', checks: 'checks', noUsage: 'no usage reported yet', done: 'done', failed: 'error', fleet: 'Fleet', noFleet: 'No fleet in this repository yet. It appears once a flight plan exists.', check: 'check', concerns: 'with concerns', round: 'round', gone: 'worktree folder is gone',
  },
  de: {
    flying: 'Läuft', candidate: 'Geliefert', review: 'Im Review', cleared: 'Landebereit', landed: 'Gelandet', blocked: 'Braucht dich', parked: 'Pausiert', planned: 'Geplant', dropped: 'Verworfen',
    worktrees: 'Worktrees', of: 'von', running: 'laufen', agents: 'Agenten', other: 'Weitere Worktrees', cost: 'Kosten', tokens: 'Tokens', time: 'Zeit', after: 'nach',
    limit: 'Limit', noLimit: 'keins', checks: 'Checks', noUsage: 'noch keine Nutzung gemeldet', done: 'fertig', failed: 'Fehler', fleet: 'Flotte', noFleet: 'In diesem Repository gibt es noch keine Flotte. Sie erscheint, sobald ein Flugplan existiert.', check: 'Check', concerns: 'mit Bedenken', round: 'Runde', gone: 'Worktree-Ordner fehlt',
  },
} as const

// Module scope: session.start sets it again on every (re)load.
let words: (typeof WORDS)['en'] | (typeof WORDS)['de'] = WORDS.en

const stateLabel = (state: string): string => (words as Record<string, string>)[state] ?? state

// The order worktrees appear in: what needs the person first.
const WORKTREE_STATES: readonly AreaState[] = ['blocked', 'candidate', 'review', 'cleared', 'flying', 'parked']

const FULL_STATES: readonly string[] = ['landed', 'cleared', 'candidate', 'review']

const shareOf = (a: Area): number => (FULL_STATES.includes(a.state) ? 1 : a.total ? Math.min(1, a.done / a.total) : 0)
const live = (f: Fleet): Area[] => f.areas.filter(a => a.state !== 'dropped')
const named = (f: Fleet, states: readonly string[]): Area[] => live(f).filter(a => states.includes(a.state))

const xml = (s: string): string =>
  // eslint-disable-next-line no-control-regex
  s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g, '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c)

// A rough advance per character, enough to keep text out of the next column.
const measure = (s: string, size: number): number =>
  [...s].reduce((w, ch) => w + (/[\s.,:;'|!il1()[\]]/.test(ch) ? 0.32 : /[A-ZÄÖÜ@%mw]/.test(ch) ? 0.76 : 0.58) * size, 0)

const fit = (s: string, size: number, maxW: number): string => {
  if (measure(s, size) <= maxW) return s
  let out = ''
  for (const ch of s) {
    if (measure(out + ch + '…', size) > maxW) break
    out += ch
  }
  return out + '…'
}

const fmtAge = (s: number): string =>
  s >= 3600 ? `${Math.floor(s / 3600)}h${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}` : s >= 60 ? `${Math.floor(s / 60)}m` : `${s}s`

const fmtTokens = (n: number): string => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : `${n}`)

// USD per million tokens at list price: input, output, cache read, cache write.
// The engine reports tokens, so every amount shown is an estimate and says so with ≈.
const PRICES: readonly (readonly [RegExp, readonly [number, number, number, number]])[] = [
  [/fable|mythos/, [10, 50, 0.25, 12.5]],
  [/opus-5-5/, [4, 20, 0.2, 5]],
  [/opus/, [5, 25, 0.5, 6.25]],
  [/sonnet-5/, [2, 10, 0.2, 2.5]],
  [/sonnet/, [3, 15, 0.3, 3.75]],
  [/haiku-5/, [0.1, 0.5, 0.01, 0.125]],
  [/haiku/, [1, 5, 0.1, 1.25]],
]

type Spend = { input_tokens: number; output_tokens: number; cache_read_input_tokens: number; cache_creation_input_tokens: number }

const costOf = (model: string, u: Spend): number => {
  const [input, output, read, write] = PRICES.find(([re]) => re.test(model.toLowerCase()))?.[1] ?? [0, 0, 0, 0]
  return ((u.input_tokens || 0) * input + (u.output_tokens || 0) * output + (u.cache_read_input_tokens || 0) * read + (u.cache_creation_input_tokens || 0) * write) / 1e6
}

const fmtCost = (usd: number): string => `≈$${usd < 10 ? usd.toFixed(2) : usd.toFixed(1)}`

const fmtClock = (seconds: number): string => {
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = String(seconds % 60).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`
}

const runSeconds = (run: AgentRun, at: number): number => Math.max(0, Math.round(((run.endedAt ?? Math.max(at, run.startedAt)) - run.startedAt) / 1000))

// What the whole fleet has spent, over every worktree's sessions and the free agents.
const fleetTotals = (f: Fleet | null, crew: AgentRun[], at: number) => {
  const areas = f ? live(f) : []
  const free = crew.filter(run => !run.areaId)
  return {
    cost: areas.reduce((sum, a) => sum + a.cost, 0) + free.reduce((sum, run) => sum + run.cost, 0),
    tokens: areas.reduce((sum, a) => sum + a.tokens, 0) + free.reduce((sum, run) => sum + run.tokens, 0),
    seconds: Math.max(0, ...areas.map(a => a.age), ...free.map(run => runSeconds(run, at))),
  }
}

// Steps done over the whole plan, not landings: progress shows before the first landing.
const progressOf = (f: Fleet): number => {
  const areas = live(f)
  if (!areas.length) return 0
  const share = (a: Area) => (['landed', 'cleared', 'candidate', 'review'].includes(a.state) ? 1 : a.total ? Math.min(1, a.done / a.total) : 0)
  return areas.reduce((sum, a) => sum + share(a), 0) / areas.length
}

const metaOf = (a: Area): string[] => {
  const parts: string[] = []
  if (a.worktree || a.branch) parts.push([a.worktree, a.branch].filter(Boolean).join(' · '))
  if (a.state !== 'planned' && a.state !== 'landed') parts.push(`↑${a.ahead} ↓${a.behind}${a.dirty ? ` ✎${a.dirty}` : ''}`)
  return parts
}

const usageOf = (a: Area): string[] => {
  const parts: string[] = []
  if (a.ctxMax) parts.push(`ctx ${Math.round((a.ctx * 100) / a.ctxMax)}%`)
  if (a.tokens) parts.push(fmtTokens(a.tokens))
  if (a.cost) parts.push(fmtCost(a.cost))
  if (a.age) parts.push(fmtAge(a.age))
  return parts
}

const flagsOf = (a: Area): string[] => {
  const flags: string[] = []
  if (a.status === 'CONCERNS') flags.push(words.concerns)
  if (a.round > 1) flags.push(`${words.round} ${a.round}`)
  if (a.missing) flags.push(words.gone)
  if (a.check) flags.push(`${words.check}: ${a.check} ${fmtAge(a.checkAge)}`)
  return flags
}

// Module scope: session.start fills them again on every (re)load.
let faces: Record<string, string> = {}
let faceCss = ''

const face = (x: number, y: number, size: number, a: Pick<Area, 'class' | 'state'>): string =>
  `<g class="av c-${a.class} is-${a.state} ${a.state}" transform="translate(${x},${y}) scale(${size / 48})">${faces[a.class] ?? ''}</g>`

const svg = (W: number, H: number, body: string): string =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMinYMin meet">${BASE_CSS}${body.includes('class="av ') ? `<style>${faceCss}</style>` : ''}${body}</svg>`

// One slot per area: the whole fleet on a single line.
const fleetBar = (f: Fleet, x: number, y: number, width: number, height: number): string => {
  const areas = live(f)
  if (!areas.length) return ''
  const gap = areas.length > 30 ? 1 : 2
  const slot = Math.max(2, (width - gap * (areas.length - 1)) / areas.length)
  return areas
    .map((a, i) => {
      const sx = x + i * (slot + gap)
      const share = a.state === 'blocked' ? 1 : shareOf(a)
      const fill = Math.round(slot * share)
      return `<g class="${a.state}"><rect class="track" x="${sx}" y="${y}" width="${slot}" height="${height}" rx="${height / 2}"/>${
        fill ? `<rect class="fill" x="${sx}" y="${y}" width="${fill}" height="${height}" rx="${height / 2}"/>` : ''
      }</g>`
    })
    .join('')
}

// What the row's dot says at a glance: someone needs you, work runs, or all is calm.
const fleetMood = (f: Fleet): AreaState => {
  if (named(f, ['blocked']).length) return 'blocked'
  if (named(f, ['flying']).length) return 'flying'
  if (named(f, ['candidate', 'review', 'cleared']).length) return 'review'
  return live(f).every(a => a.state === 'landed') ? 'landed' : 'planned'
}

// Placed from the right edge inward, and the bar takes whatever remains, so nothing overlaps.
const bandSvg = (f: Fleet, W: number): string => {
  const H = 26
  const middle = 17.5
  const size = 12.5
  const flying = named(f, ['flying'])
  const areas = live(f)
  const landed = named(f, ['landed']).length
  const percent = `${Math.round(progressOf(f) * 100)}%`
  const counts = `${flying.length} ${words.running} · ${landed}/${areas.length}`
  const lead = flying[0]
  const showFace = Boolean(lead) && W >= 340
  const faceW = showFace ? 30 : 0
  const percentW = measure('100%', size) + 8
  const countsW = measure(counts, size) + 14
  const barX = 16
  const barW = Math.max(40, W - barX - countsW - percentW - faceW)
  return svg(
    W,
    H,
    `<g class="${fleetMood(f)}"><circle class="fill" cx="6" cy="13" r="4"/></g>
${fleetBar(f, barX, 10, barW, 6)}
<text class="ink" x="${barX + barW + 10}" y="${middle}" font-family="${SANS}" font-size="${size}">${xml(counts)}</text>
<text class="soft" x="${W - faceW - 2}" y="${middle}" text-anchor="end" font-family="${SANS}" font-size="${size}">${percent}</text>
${showFace && lead ? face(W - 27, 0, 26, lead) : ''}`,
  )
}

const headerHeight = (f: Fleet | null): number => (f ? 96 : 42)

const headerSvg = (f: Fleet | null, totals: ReturnType<typeof fleetTotals>, W: number): string => {
  const top = f ? 26 : 0
  const cellW = W / 3
  const cell = (i: number, label: string, value: string) =>
    `<text class="soft" x="${i * cellW}" y="${top + 11}" font-family="${SANS}" font-size="11">${label}</text>
<text class="ink" x="${i * cellW}" y="${top + 28}" font-family="${SANS}" font-size="14.5" font-weight="650">${xml(value)}</text>`
  const cells = cell(0, words.cost, fmtCost(totals.cost)) + cell(1, words.tokens, fmtTokens(totals.tokens)) + cell(2, words.time, fmtClock(totals.seconds))
  if (!f) return svg(W, headerHeight(f), cells)
  const areas = live(f)
  const ciText = f.ci.state === 'ok' ? 'CI ok' : f.ci.state === 'red' ? 'CI red' : f.ci.state === 'running' ? 'CI …' : ''
  const line = [`${f.base} @ ${f.sha}`, ciText, `${named(f, ['landed']).length}/${areas.length} ${words.landed.toLowerCase()}`, `${words.limit} ${f.limit ?? words.noLimit}`, `${words.checks} ${f.runways.busy}/${f.runways.limit}${f.runways.waiting ? ` +${f.runways.waiting}` : ''}`].filter(Boolean).join(' · ')
  return svg(
    W,
    headerHeight(f),
    `<text class="ink" x="0" y="17" font-family="${SANS}" font-size="18" font-weight="800" letter-spacing="-.2">${xml(fit(f.mission || 'Watchtower', 20, W))}</text>
${cells}
${fleetBar(f, 0, top + 39, W, 4)}
<text class="soft" x="0" y="${top + 60}" font-family="${SANS}" font-size="11">${xml(fit(line, 11, W))}</text>`,
  )
}

// Tower workers show their class; any other subagent shows as a liner.
const classOfAgent = (type: string): string => {
  const bare = type.replace(/^[^:]*:/, '').replace(/^tower-/, '')
  return bare in faces ? bare : 'liner'
}

const modelName = (id: string): string => {
  const m = /(fable|opus|sonnet|haiku)-(\d+)(?:-(\d{1,2})(?!\d))?/i.exec(id)
  if (!m) return id.replace(/^claude-/, '')
  return `${(m[1] ?? '').charAt(0).toUpperCase()}${(m[1] ?? '').slice(1).toLowerCase()} ${m[2]}${m[3] ? `.${m[3]}` : ''}`
}

const AGENT_STATE: Record<AgentRun['status'], AreaState> = { running: 'flying', done: 'landed', failed: 'blocked' }

const agentModel = (run: AgentRun): string => {
  const parts = [run.type.replace(/^[^:]*:/, ''), modelName(run.model)]
  if (run.effort) parts.push(run.effort)
  return parts.join(' · ')
}

const agentStats = (run: AgentRun, at: number, window: number): string =>
  [window ? `ctx ${Math.round((run.ctx * 100) / window)}%` : '', run.tokens ? fmtTokens(run.tokens) : '', run.cost ? fmtCost(run.cost) : '', fmtClock(runSeconds(run, at))].filter(Boolean).join(' · ')

// One line in a worktree block: who is working, on what model, at what cost.
type CrewRow = { key: string; name: string; meta: string; face: Pick<Area, 'class' | 'state'> }

const usageMeta = (a: Area): string =>
  [a.model ? modelName(a.model) : '', a.effort, ...usageOf(a)].filter(Boolean).join(' · ') || words.noUsage

const crewOfArea = (a: Area, crew: AgentRun[], at: number, window: number): CrewRow[] => {
  const bound = crew.filter(run => run.areaId === a.id)
  if (bound.length) {
    return bound.map(run => ({
      key: run.id,
      name: run.description === a.id || run.description === a.title ? run.type.replace(/^[^:]*:/, '') : run.description,
      meta: `${modelName(run.model)}${run.effort ? ` · ${run.effort}` : ''} · ${agentStats(run, at, window)}`,
      face: { class: classOfAgent(run.type), state: run.status === 'running' ? a.state : AGENT_STATE[run.status] },
    }))
  }
  // A worker in its own session reports through the usage file; before that, its class is known.
  return [{ key: `session-${a.id}`, name: `tower-${a.class}`, meta: usageMeta(a), face: a }]
}

const CREW_H = 38
const EXTRA_H = 26

const crewRow = (row: CrewRow, y: number, W: number): string =>
  `${face(8, y + 6, 26, row.face)}
<text class="ink" x="40" y="${y + 16}" font-family="${SANS}" font-size="12" font-weight="550">${xml(fit(row.name, 12, W - 50))}</text>
<text class="soft" x="40" y="${y + 30}" font-family="${SANS}" font-size="10.5">${xml(fit(row.meta, 10.5, W - 50))}</text>`

const HEADING_H = 30

const headingSvg = (text: string, W: number): string =>
  svg(W, HEADING_H, `<text class="ink" x="0" y="21" font-family="${SANS}" font-size="15" font-weight="800">${xml(fit(text, 16.5, W))}</text>`)

const blockHead = (a: Area): number => (a.state === 'blocked' ? 62 : 78)

const worktreeHeight = (a: Area, rows: number): number => blockHead(a) + (rows > 1 ? (rows - 1) * EXTRA_H + 4 : 0) + 6

// A worktree is one bordered row: avatar, name, task, progress. Further agents hang below.
const worktreeSvg = (a: Area, rows: CrewRow[], W: number): string => {
  const H = worktreeHeight(a, rows.length)
  const x = 46
  const inner = W - x - 10
  const label = stateLabel(a.state)
  const labelW = measure(label, 11) + 14
  const lead = rows[0]
  const changes = a.state === 'planned' || a.state === 'landed' ? '' : `↑${a.ahead} ↓${a.behind}${a.dirty ? ` ✎${a.dirty}` : ''}`
  const changesW = measure(changes, 10.5) + 8
  const flags = flagsOf(a)
  const count = a.total ? `${a.done}/${a.total}` : ''
  const barW = inner - (count ? measure(count, 10.5) + 8 : 0)
  const fill = Math.round(barW * shareOf(a))
  const note = [...flags, a.note].filter(Boolean).join(' · ') || label
  const meta = lead ? `${lead.name.replace(/^tower-/, '')} · ${lead.meta}` : ''
  const middle =
    a.state === 'blocked'
      ? `<g class="blocked"><text class="fill" x="${x}" y="46" font-family="${SANS}" font-size="11.5" font-weight="550">${xml(fit(note, 11.5, inner - changesW))}</text></g>`
      : `<rect class="track" x="${x}" y="39" width="${barW}" height="3" rx="1.5"/><g class="${a.state}">${fill ? `<rect class="fill" x="${x}" y="39" width="${fill}" height="3" rx="1.5"/>` : ''}</g>
${count ? `<text class="soft" x="${W - 10}" y="44" text-anchor="end" font-family="${SANS}" font-size="10.5">${count}</text>` : ''}
<text class="soft" x="${x}" y="57" font-family="${SANS}" font-size="11">${xml(fit(note, 11, inner - changesW))}</text>`
  const changesY = a.state === 'blocked' ? 46 : 57
  const metaY = a.state === 'blocked' ? 58 : 70
  return svg(
    W,
    H,
    `<rect class="box" x=".5" y=".5" width="${W - 1}" height="${H - 5}" rx="7"/>
${lead ? face(7, a.state === 'blocked' ? 12 : 18, 34, lead.face) : ''}
<text class="ink" x="${x}" y="16" font-family="${SANS}" font-size="13.5" font-weight="750">${xml(fit(a.worktree || a.id, 14.5, inner - labelW))}</text>
<g class="${a.state}"><circle class="fill" cx="${W - labelW - 4}" cy="12" r="2.8"/></g>
<text class="soft" x="${W - 10}" y="16" text-anchor="end" font-family="${SANS}" font-size="11">${xml(label)}</text>
<text class="ink" x="${x}" y="31" font-family="${SANS}" font-size="12">${xml(fit(a.title, 12, inner))}</text>
${middle}
<text class="faint" x="${W - 10}" y="${changesY}" text-anchor="end" font-family="${SANS}" font-size="10.5">${xml(changes)}</text>
<text class="faint" x="${x}" y="${metaY}" font-family="${SANS}" font-size="10.5">${xml(fit(meta, 10.5, inner))}</text>
${rows
  .slice(1)
  .map((row, i) => {
    const y = blockHead(a) + i * EXTRA_H
    return `${face(x - 2, y, 22, row.face)}<text class="ink" x="${x + 24}" y="${y + 15}" font-family="${SANS}" font-size="11.5" font-weight="500">${xml(fit(`${row.name}  `, 11.5, inner * 0.4))}</text><text class="soft" x="${W - 10}" y="${y + 15}" text-anchor="end" font-family="${SANS}" font-size="10.5">${xml(fit(row.meta, 10.5, inner * 0.56))}</text>`
  })
  .join('')}`,
  )
}

// Agents with no worktree of their own, in one block.
const freeAgentsSvg = (runs: AgentRun[], W: number, at: number, window: number): string => {
  const H = runs.length * CREW_H + 8
  return svg(
    W,
    H,
    `<rect class="box" x=".5" y=".5" width="${W - 1}" height="${H - 5}" rx="7"/>
${runs
  .map((run, i) =>
    crewRow(
      {
        key: run.id,
        name: run.description || run.type,
        meta: `${agentModel(run)} · ${agentStats(run, at, window)}`,
        face: { class: classOfAgent(run.type), state: AGENT_STATE[run.status] },
      },
      1 + i * CREW_H,
      W,
    ),
  )
  .join('')}`,
  )
}

// Quiet rows for what is not in the air: planned and landed areas.
const QUIET_H = 26

const quietSvg = (areas: Area[], W: number): string =>
  svg(
    W,
    areas.length * QUIET_H + 4,
    areas
      .map((a, i) => {
        const y = i * QUIET_H
        const right = a.state === 'planned' && a.after ? `${words.after} ${a.after}` : a.tokens ? usageOf(a).join(' · ') : ''
        const rightW = measure(right, 10.5)
        return `${face(2, y + 1, 24, a)}
<text class="ink" x="32" y="${y + 17}" font-family="${SANS}" font-size="12">${xml(fit(a.title, 12, W - 40 - rightW - 10))}</text>
<text class="faint" x="${W - 2}" y="${y + 17}" text-anchor="end" font-family="${SANS}" font-size="10.5">${xml(right)}</text>`
      })
      .join(''),
  )

// Running first, then the most recent few that finished. Those flying an area are in its block.
const agentsToShow = (list: AgentRun[]): AgentRun[] => {
  const free = list.filter(run => !run.areaId)
  return [...free.filter(run => run.status === 'running'), ...free.filter(run => run.status !== 'running').slice(-5).reverse()]
}

const blockAlt = (a: Area): string =>
  `${a.worktree || a.id}: ${a.title}. ${stateLabel(a.state)}${a.total ? `, ${a.done} / ${a.total}` : ''}. ${a.note}`

const textRoute = (a: Area, width: number): string => {
  const full = Math.round((width - 1) * shareOf(a))
  return `${'━'.repeat(full)}${a.state === 'flying' ? '●' : '━'}${'╌'.repeat(Math.max(0, width - 1 - full))}`
}

const TEXT_SHELL: Record<string, string> = { ace: '<>', scout: '()', freighter: '[]', liner: '{}', prop: '||', inspector: '//' }
const TEXT_EYES: Record<string, string> = { flying: '••', planned: '··', candidate: '°°', review: '°°', cleared: '^^', landed: '^^', parked: '--', blocked: 'OO' }

// The same character, for surfaces that only draw text.
const textFace = (a: Pick<Area, 'class' | 'state'>): string => {
  const shell = TEXT_SHELL[a.class] ?? '()'
  return `${shell.charAt(0)}${TEXT_EYES[a.state] ?? '··'}${shell.charAt(1)}`
}

const TERMINAL_COLOR: Record<string, string> = {
  flying: 'blue',
  candidate: 'yellow',
  review: 'yellow',
  cleared: 'green',
  landed: 'green',
  blocked: 'red',
}

// ---------------------------------------------------------------------------

type Link = { root: string; home: string }

// What one loaded module remembers between polls. A reload starts it over, harmlessly.
type Sync = {
  link: Link | null
  fleet: Fleet | null
  signature: string | null
  json: string
  fetchedAt: number
  isFetching: boolean
  canDock: boolean
  isBandSeen: boolean
}

const areaOfSession = (f: Fleet, cwd: string): Area | undefined => {
  const folder = cwd.split('/').filter(Boolean).pop()
  return f.areas.find(a => a.worktree && a.worktree === folder)
}

async function detectWords($: EngineInterface): Promise<void> {
  let language = (await $.env.get('TOWER_LANG')) || ''
  if (!language) try {
    const settings = (await $.settings.read()) as Record<string, unknown>
    if (typeof settings.language === 'string') language = settings.language
  } catch {
    // No settings: the locale decides.
  }
  if (!language) language = (await $.env.get('LC_ALL')) || (await $.env.get('LC_MESSAGES')) || (await $.env.get('LANG')) || ''
  words = /^(de|german|deutsch)/i.test(language.trim()) ? WORDS.de : WORDS.en
}

async function findHome($: EngineInterface, known: Link | null): Promise<Link | null> {
  const root = await $.session.cwd()
  if (known?.root === root) return known
  const override = await $.env.get('TOWER_HOME')
  if (override) return { root, home: override }
  const { exitCode, stdout } = await $.process.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd: root })
  if (exitCode !== 0) return null
  return { root, home: `${stdout.trim()}/watchtower` }
}

async function signatureOf($: EngineInterface, home: string): Promise<string | null> {
  if (!(await $.fs.exists(`${home}/areas`))) return null
  const parts: string[] = []
  // Usage changes with every model call, so it comes along on the slower refresh instead.
  for (const dir of ['areas', 'runways', 'queue']) {
    if (!(await $.fs.exists(`${home}/${dir}`))) continue
    for (const entry of await $.fs.list(`${home}/${dir}`)) {
      if (!entry.name.startsWith('.')) parts.push(`${dir}/${entry.name}:${entry.mtimeMs}:${entry.size}`)
    }
  }
  return parts.sort().join('|')
}

// Beside the tower only, and only where the pane docks instead of covering the prompt.
async function maybeOpen($: EngineInterface, sync: Sync, f: Fleet): Promise<void> {
  if (!sync.canDock || !live(f).length || areaOfSession(f, await $.session.cwd())) return
  const key = f.mission || 'watchtower'
  const p = await read($, panel)
  if (p.openedFor === key) return
  await update($, panel, prev => ({ ...prev, openedFor: key }))
  void $.ui.open({ id: PANE, title: words.fleet })
}

async function fetchFleet($: EngineInterface, sync: Sync, script: string): Promise<void> {
  if (!sync.link) return
  const { exitCode, stdout } = await $.process.run(['bash', script, '--json'], { cwd: sync.link.root, timeoutMs: 20_000 })
  if (exitCode !== 0 || stdout === sync.json) return
  let next: Fleet
  try {
    next = JSON.parse(stdout) as Fleet
  } catch {
    return // Keep the last good picture and try again on the next change.
  }
  sync.json = stdout
  sync.fleet = next
  await update($, fleet, () => next)
}

async function poll($: EngineInterface, sync: Sync, script: string): Promise<void> {
  if (sync.isFetching) return
  sync.isFetching = true
  try {
    sync.link = await findHome($, sync.link)
    const signature = sync.link ? await signatureOf($, sync.link.home) : null
    if (signature === null) {
      if (sync.signature !== null) {
        sync.signature = null
        sync.json = ''
        sync.fleet = null
        await update($, fleet, () => null)
      }
      return
    }
    const at = await $.clock.now()
    const isWorker = sync.fleet !== null && areaOfSession(sync.fleet, sync.link?.root ?? '') !== undefined
    const isDue = sync.fleet !== null && live(sync.fleet).length > 0 && at - sync.fetchedAt > (isWorker ? WORKER_REFRESH_MS : GIT_REFRESH_MS)
    if (signature !== sync.signature || isDue) {
      sync.signature = signature
      sync.fetchedAt = at
      await fetchFleet($, sync, script)
    }
    // Every tick: the first fetch can come before any surface has said whether it docks.
    if (sync.fleet) await maybeOpen($, sync, sync.fleet)
  } finally {
    sync.isFetching = false
  }
}

async function toggleFleet($: EngineInterface): Promise<boolean> {
  const isOpen = (await $.ui.panes()).some(pane => pane.id === PANE)
  if (isOpen) {
    await $.ui.close({ id: PANE })
    return false
  }
  await $.ui.open({ id: PANE, title: words.fleet })
  return true
}

const norm = (s: string): string => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim()

export const register: Register = on => {
  const sync: Sync = { link: null, fleet: null, signature: null, json: '', fetchedAt: 0, isFetching: false, canDock: false, isBandSeen: false }
  const spent = new Map<string, { tokens: number; cost: number }>()

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    sync.canDock = e.surface === 'desktop'
    await detectWords($)
    const script = `${$.plugin.root}/scripts/tower-board.sh`
    faces = JSON.parse(await $.fs.read(`${$.plugin.root}/assets/avatars.json`)) as Record<string, string>
    faceCss = await $.fs.read(`${$.plugin.root}/assets/avatars.css`)
    await $.command.register({ name: 'tower-board', description: 'Show or hide the fleet panel: every worktree and agent, with cost, tokens and time' })
    await $.tool.register({
      name: 'show_board',
      description:
        'Open the Watchtower fleet panel beside the chat and say what it shows. Call it once after writing the flight plan, or when the person cannot see the board.',
      inputSchema: { type: 'object', properties: {} },
    })
    void poll($, sync, script)
    $.clock.every(POLL_MS, () => void poll($, sync, script))
    // Keeps the running agents' clocks moving; quiet when nothing runs.
    $.clock.every(15_000, () => {
      void (async () => {
        if (!(await read($, agents)).some(run => run.status === 'running')) return
        const at = await $.clock.now()
        await update($, now, () => at)
      })()
    })
    return started
  })

  on('command.run', { command: 'tower-board' }, async $ => {
    await update($, panel, prev => ({ ...prev, hiddenFor: '' }))
    return { text: (await toggleFleet($)) ? 'Fleet panel open.' : 'Fleet panel closed.' }
  })

  on('tool.call', { tool: /^mcp__watchtower__show_board$/ }, async $ => {
    // A poll may be under way; its answer is the one to report.
    for (let i = 0; sync.isFetching && i < 20; i++) await $.clock.sleep(150)
    await poll($, sync, `${$.plugin.root}/scripts/tower-board.sh`)
    const { isPlaced } = await $.ui.open({ id: PANE, title: words.fleet })
    await update($, panel, prev => ({ ...prev, hiddenFor: '' }))
    const areas = sync.fleet ? live(sync.fleet) : []
    return {
      result: JSON.stringify({
        state: sync.link?.home ?? null,
        areas: areas.length,
        running: areas.filter(a => a.state === 'flying').length,
        panelPlaced: isPlaced,
        // False means another plugin answers the row above the prompt first and hides this bar.
        barReached: sync.isBandSeen,
      }),
    }
  })

  // Every subagent gets a row; one named after its area also counts on that strip.
  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.deny !== undefined || !started.agentId) return started
    const wanted = norm(e.description)
    const area = sync.fleet?.areas.find(a => norm(a.id) === wanted || norm(a.title) === wanted)
    const at = await $.clock.now()
    const run: AgentRun = {
      id: started.agentId,
      type: e.subagentType,
      description: e.description,
      model: started.model,
      status: 'running',
      startedAt: at,
      tokens: 0,
      ctx: 0,
      cost: 0,
      areaId: area?.id,
    }
    await update($, agents, list => [...list.filter(item => item.id !== run.id), run].slice(-50))
    await update($, now, () => at)
    return started
  })

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const usage = result.usage
    if (!usage) return result
    const context = (usage.input_tokens || 0) + (usage.cache_read_input_tokens || 0) + (usage.cache_creation_input_tokens || 0) + (usage.output_tokens || 0)
    const model = usage.model || e.model
    const stepCost = costOf(model, usage)
    const effort = typeof e.effort === 'string' ? e.effort : ''
    if (e.agentId) {
      await update($, agents, list =>
        list.map(run => (run.id === e.agentId ? { ...run, model, effort: effort || run.effort, tokens: run.tokens + context, ctx: context, cost: run.cost + stepCost } : run)),
      )
    }
    if (!sync.link || !sync.fleet) return result
    const areaId = e.agentId
      ? (await read($, agents)).find(run => run.id === e.agentId)?.areaId
      : areaOfSession(sync.fleet, await $.session.cwd())?.id
    if (!areaId) return result

    const known = sync.fleet.areas.find(a => a.id === areaId)
    const earlier = spent.get(areaId) ?? { tokens: known?.tokens ?? 0, cost: known?.cost ?? 0 }
    const total = { tokens: earlier.tokens + context, cost: earlier.cost + stepCost }
    spent.set(areaId, total)
    const { context: usageWindow } = await $.session.usage()
    await $.fs.write(
      `${sync.link.home}/usage/${areaId}`,
      `tokens=${total.tokens}\nctx=${context}\nctx_max=${usageWindow.window || 0}\nmodel=${model}\neffort=${effort}\ncost=${total.cost.toFixed(4)}\n`,
    )
    return result
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId) {
      const at = await $.clock.now()
      await update($, agents, list =>
        list.map(run => (run.id === e.agentId ? { ...run, status: e.reason === 'answer' ? 'done' : 'failed', endedAt: at } : run)),
      )
      await update($, now, () => at)
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const { Box, Text, Button } = ui
    const f = await read($, fleet)
    const p: Panel = await read($, panel)
    const allAgents = await read($, agents)
    const crew = agentsToShow(allAgents)
    const at = Math.max(await read($, now), ...allAgents.map(run => run.startedAt), 0)
    const totals = fleetTotals(f, allAgents, at)
    const { context: usageWindow } = await $.session.usage()
    const contextWindow = usageWindow.window || 0

    if (!f && !crew.length) {
      return <Text dimColor>{words.noFleet}</Text>
    }

    const landed = f ? named(f, ['landed']) : []
    const toggle = (
      <Button
        key="landed"
        label={`${p.isLandedOpen ? '▾' : '▸'} ${words.landed} · ${landed.length}`}
        plain
        onPress={() => update($, panel, prev => ({ ...prev, isLandedOpen: !prev.isLandedOpen }))}
      />
    )
    const looseLines = (f?.loose ?? []).map(w => `${w.worktree} · ${w.branch} ↑${w.ahead} ↓${w.behind} ✎${w.dirty} · ${w.state}`)

    // Worktrees first, by what needs attention; each carries the agents flying it.
    const worktrees = f ? WORKTREE_STATES.flatMap(state => live(f).filter(a => a.state === state)) : []
    const planned = f ? named(f, ['planned']) : []
    const runningWorktrees = worktrees.filter(a => a.state === 'flying').length

    if (e.surface === 'desktop' && 'Svg' in ui) {
      const { Svg } = ui
      // A column is wider than 8 px on the desktop; 8.9 fills the panel without clipping.
      const W = Math.max(260, Math.min(1100, Math.round((e.props.bodyColumns || 40) * COLUMN_PX) - 4))
      const heading = (key: string, text: string) => <Svg key={key} source={headingSvg(text, W)} alt={text} width={W} height={HEADING_H} />
      return (
        <Box flexDirection="column">
          <Svg source={headerSvg(f, totals, W)} alt={`${words.cost} ${fmtCost(totals.cost)}, ${words.tokens} ${fmtTokens(totals.tokens)}, ${words.time} ${fmtClock(totals.seconds)}`} width={W} height={headerHeight(f)} />
          {worktrees.length > 0 && heading('h-wt', `${words.worktrees} · ${runningWorktrees}/${worktrees.length} ${words.running}`)}
          {worktrees.map(a => {
            const rows = crewOfArea(a, allAgents, at, contextWindow)
            return <Svg key={a.id} source={worktreeSvg(a, rows, W)} alt={blockAlt(a)} width={W} height={worktreeHeight(a, rows.length)} />
          })}
          {crew.length > 0 && heading('h-ag', `${words.agents} · ${crew.filter(run => run.status === 'running').length} ${words.running}`)}
          {crew.length > 0 && <Svg source={freeAgentsSvg(crew, W, at, contextWindow)} alt={crew.map(run => run.description).join(', ')} width={W} height={crew.length * CREW_H + 8} />}
          {planned.length > 0 && heading('h-pl', `${words.planned} · ${planned.length}`)}
          {planned.length > 0 && <Svg source={quietSvg(planned, W)} alt={planned.map(a => a.title).join(', ')} width={W} height={planned.length * QUIET_H + 4} />}
          {landed.length > 0 && toggle}
          {p.isLandedOpen && landed.length > 0 && <Svg source={quietSvg(landed, W)} alt={landed.map(a => a.title).join(', ')} width={W} height={landed.length * QUIET_H + 4} />}
          {looseLines.length > 0 && heading('h-lo', `${words.other} · ${looseLines.length}`)}
          {looseLines.map(line => (
            <Text key={line} dimColor wrap="truncate-end">
              {line}
            </Text>
          ))}
        </Box>
      )
    }

    const cols = Math.max(24, e.props.bodyColumns || 40)
    const routeW = Math.max(8, Math.min(24, cols - 12))
    const crewLine = (row: CrewRow) => (
      <Text key={row.key} wrap="truncate-end">
        {'  └ '}
        <Text color={TERMINAL_COLOR[row.face.state]}>{textFace(row.face)}</Text> {row.name} <Text dimColor>{row.meta}</Text>
      </Text>
    )
    const agentLine = (run: AgentRun, prefix: string) => (
      <Text key={run.id} wrap="truncate-end">
        {prefix}
        <Text color={TERMINAL_COLOR[AGENT_STATE[run.status]]}>{textFace({ class: classOfAgent(run.type), state: AGENT_STATE[run.status] })}</Text> {run.description || run.type}{' '}
        <Text dimColor>
          {agentModel(run)} · {agentStats(run, at, contextWindow)}
        </Text>
      </Text>
    )
    const row = (a: Area) => (
      <Box key={a.id} flexDirection="column" marginBottom={1}>
        <Text wrap="truncate-end">
          <Text color={TERMINAL_COLOR[a.state]}>●</Text> <Text bold>{a.worktree || a.id}</Text> <Text dimColor>{stateLabel(a.state)}</Text>
        </Text>
        <Text wrap="truncate-end">  {a.title}</Text>
        <Text wrap="truncate-end">
          {'  '}
          <Text color={TERMINAL_COLOR[a.state]}>{textRoute(a, routeW)}</Text>
          <Text dimColor> {a.total ? `${a.done}/${a.total}` : ''}</Text>
        </Text>
        <Text dimColor wrap="truncate-end">
          {'  '}
          {[...flagsOf(a), a.note || stateLabel(a.state)].join(' · ')}
        </Text>
        <Text dimColor wrap="truncate-end">
          {'  '}
          {[...metaOf(a), ...usageOf(a)].join('  ')}
        </Text>
        {crewOfArea(a, allAgents, at, contextWindow).map(crewLine)}
      </Box>
    )
    return (
      <Box flexDirection="column">
        {f && (
          <Text bold wrap="truncate-end">
            {f.mission || 'Watchtower'}
          </Text>
        )}
        <Text wrap="truncate-end">
          {words.cost} {fmtCost(totals.cost)} · {words.tokens} {fmtTokens(totals.tokens)} · {words.time} {fmtClock(totals.seconds)}
        </Text>
        {f && (
          <Text dimColor wrap="truncate-end">
            {f.base} @ {f.sha} · {landed.length}/{live(f).length} {words.landed.toLowerCase()} · {words.limit} {f.limit ?? words.noLimit} · {words.checks} {f.runways.busy}/{f.runways.limit}
          </Text>
        )}
        {worktrees.length > 0 && (
          <Box flexDirection="column" marginTop={1}>
            <Text dimColor>
              {words.worktrees} · {runningWorktrees} {words.running} {words.of} {worktrees.length}
            </Text>
            {worktrees.map(row)}
          </Box>
        )}
        {crew.length > 0 && (
          <Text dimColor>
            {words.agents} · {crew.filter(run => run.status === 'running').length} {words.running}
          </Text>
        )}
        {crew.map(run => agentLine(run, ''))}
        {planned.length > 0 && (
          <Text dimColor>
            {words.planned} · {planned.length}
          </Text>
        )}
        {planned.map(row)}
        {landed.length > 0 && toggle}
        {p.isLandedOpen && landed.map(row)}
        {looseLines.map(line => (
          <Text key={line} dimColor wrap="truncate-end">
            {line}
          </Text>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    sync.isBandSeen = true
    sync.canDock = e.surface === 'desktop' || e.viewport?.isFullscreen === true
    const f = await read($, fleet)
    if (!f || e.props.hasSurvey || !live(f).length) return next(e)
    const p: Panel = await read($, panel)
    const key = f.mission || 'watchtower'
    if (p.hiddenFor === key) return next(e)

    const ui = $.ui.resolve(e)
    const { Box, Text, Button } = ui
    const areas = live(f)
    const landedCount = named(f, ['landed']).length
    const fleetButton = <Button key="fleet" label={words.fleet} plain onPress={() => void toggleFleet($)} />
    const hide = <Button key="hide" label="✕" plain role="dismiss" onPress={() => update($, panel, prev => ({ ...prev, hiddenFor: key }))} />

    if (e.surface !== 'terminal' && 'Svg' in ui) {
      const { Svg } = ui
      const width = Math.max(200, Math.min(1600, Math.round((e.props.bodyColumns || 100) * COLUMN_PX) - BAND_BUTTONS_PX))
      return (
        <Box flexDirection="row" alignItems="center" gap={1}>
          <Svg source={bandSvg(f, width)} alt={`${f.mission}: ${named(f, ['flying']).length} ${words.running}, ${landedCount} / ${areas.length} ${words.landed.toLowerCase()}, ${Math.round(progressOf(f) * 100)} %`} width={width} height={26} />
          {fleetButton}
          {hide}
        </Box>
      )
    }

    const cols = e.props.bodyColumns
    const barW = Math.max(6, Math.min(40, cols - 34))
    const slot = Math.max(1, Math.floor((barW - (areas.length - 1)) / Math.max(1, areas.length)))
    return (
      <Box flexDirection="row" gap={1}>
        <Text wrap="truncate-end">{f.mission || 'Watchtower'}</Text>
        <Text>
          {areas.map((a, i) => {
            const full = Math.round(slot * shareOf(a))
            return (
              <Text key={a.id} color={TERMINAL_COLOR[a.state]}>
                {i > 0 ? ' ' : ''}
                {'█'.repeat(full)}
                {'░'.repeat(slot - full)}
              </Text>
            )
          })}
        </Text>
        <Text>
          {named(f, ['flying']).length} {words.running} · {landedCount}/{areas.length}
        </Text>
        <Text dimColor>{Math.round(progressOf(f) * 100)}%</Text>
        {fleetButton}
        {hide}
      </Box>
    )
  })
}
