import { expect, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

import type { AgentRun, Area, Fleet } from '../types'

const area = (over: Partial<Area>): Area => ({
  seq: 1,
  id: 'auth',
  title: 'Token-Refresh im Gateway',
  class: 'scout',
  state: 'flying',
  worktree: 'shop-auth',
  branch: 'area/auth',
  after: '',
  done: 3,
  total: 8,
  note: 'Schreibe Tests',
  round: 1,
  status: '',
  ahead: 2,
  behind: 1,
  dirty: 0,
  missing: 0,
  check: '',
  checkAge: 0,
  tokens: 120000,
  ctx: 200000,
  ctxMax: 1000000,
  model: 'claude-opus-5-5',
  effort: 'high',
  age: 720,
  cost: 1.2,
  ...over,
})

const demo: Fleet = {
  mission: 'Checkout <Launch> & Größe',
  base: 'main',
  sha: 'abc1234',
  ci: { latest: 'abc1234 completed success', finished: 'success', state: 'ok' },
  now: 0,
  limit: null,
  runways: { limit: 3, busy: 1, waiting: 2, timeout: 5400, items: [] },
  areas: [
    area({}),
    area({ id: 'pay', title: 'Zahlung', class: 'ace', state: 'blocked', status: 'NEEDS_CONTEXT', note: 'Welche Zahlungsart?' }),
    area({ id: 'db', class: 'freighter', state: 'landed' }),
    area({ id: 'gone', state: 'dropped' }),
  ],
  loose: [{ worktree: 'old-work', branch: 'old', ahead: 1, behind: 0, dirty: 2, state: 'parked' }],
}

const seed = (on: Parameters<TestBody>[1], value: Fleet | null, crew: AgentRun[] = []) => {
  on('session.usage', () => ({ value: { context: { window: 1_000_000 } } }) as never)
  on('state.get', (_, e) => {
    if (e.key === 'fleet') return { value: { value, version: 1 } }
    if (e.key === 'agents') return { value: { value: crew, version: 1 } }
    if (e.key === 'now') return { value: { value: 60_000, version: 1 } }
    return { value: { value: { isLandedOpen: false, hiddenFor: '', openedFor: '' }, version: 1 } }
  })
}

const PANE = {
  plugin: 'watchtower',
  component: 'Pane',
  requestId: 'watchtower-fleet',
  props: { title: 'Fleet', isFocused: false, bodyColumns: 48, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

const BAND = {
  plugin: 'watchtower',
  component: 'AbovePrompt',
  requestId: 'above',
  props: { bodyColumns: 120, hasSurvey: false, isWorking: false, maxRows: 6, scroll: { offset: 0, bodyRows: 6 }, view: {} },
} as const

test('the terminal pane groups areas by what needs attention', async ($, on) => {
  seed(on, demo)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /Worktrees · 1 running of 2/ }))?.text).toContain('Worktrees')
  expect((await ui.find({ type: 'Text', text: /Cost ≈\$/ }))?.text).toContain('Tokens')
  expect((await ui.find({ type: 'Text', text: /old-work/ }))?.text).toContain('old-work')
  expect(await ui.find({ type: 'Text', text: /gone/i })).toBeUndefined()
  await ui.unmount()
})

test('the desktop pane draws worktrees and escapes what agents wrote', async ($, on) => {
  seed(on, demo)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const header = await ui.find({ type: 'Svg' })
  const source = String(header?.props?.source ?? '')
  expect(source).toContain('Checkout &lt;Launch&gt; &amp; Größe')
  expect(source).not.toContain('<Launch>')
  await ui.unmount()
})

test('with no fleet the band leaves the prompt alone', async ($, on) => {
  seed(on, null)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await ui.unmount()
})

test('the band counts landed areas out of those still in the plan', async ($, on) => {
  seed(on, demo)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    if (surface === 'terminal') {
      expect((await ui.find({ type: 'Text', text: /running/ }))?.text).toContain('1 running · 1/3')
    } else {
      const band = await ui.find({ type: 'Svg' })
      expect(String(band?.props?.source)).toContain('1 running · 1/3')
    }
    await ui.unmount()
  }
})

test('the side panel also lists agents without an area', async ($, on) => {
  const run: AgentRun = { id: 'a1', type: 'watchtower:tower-inspector', description: 'Review landing', model: 'claude-opus-5-5', status: 'running', startedAt: 0, tokens: 2000, ctx: 2000, cost: 0.03 }
  const bound: AgentRun = { ...run, id: 'a2', description: 'auth', areaId: 'auth' }
  seed(on, null, [run, bound])
  const terminal = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await terminal.find({ type: 'Text', text: /Review landing/ }))?.text).toContain('Opus 5.5')
  expect(await terminal.find({ type: 'Text', text: /^auth/ })).toBeUndefined()
  await terminal.unmount()
  const desktop = await $.ui.mount({ ...PANE, surface: 'desktop' })
  const drawings = await desktop.findAll({ type: 'Svg' })
  expect(drawings.map(d => String(d.props?.source)).join('')).toContain('Review landing')
  await desktop.unmount()
})

test('an agent flying an area hangs under its worktree', async ($, on) => {
  const run: AgentRun = { id: 'a3', type: 'tower-scout', description: 'auth', model: 'claude-opus-5-5', status: 'running', startedAt: 0, tokens: 2000, ctx: 2000, cost: 0.03, areaId: 'auth' }
  seed(on, demo, [run])
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /└/ }))?.text).toContain('Opus 5.5')
  await ui.unmount()
})
