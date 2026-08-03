// Records the character-creation flow against a local dev server.
//
//     mix phx.server                       # in the repo root
//     cd tools/screencast && npm run record
//
// Headless Chromium still renders everything — layout, CSS, the LiveView
// socket, JS transitions. `recordVideo` captures the compositor's frames, so
// the output is the painted page. Headless only means no window on your
// desktop, which also means no macOS screen-recording permission is needed.
//
// Set HEADED=1 to watch it drive the browser. The recording works either way.

import { chromium } from 'playwright'
import { mkdir, rm, readdir, rename } from 'node:fs/promises'
import { join } from 'node:path'

const BASE = process.env.BASE_URL ?? 'http://localhost:4000'
const OUT = process.env.OUT_DIR ?? 'out'
const HEADED = process.env.HEADED === '1'

// Big enough to read in a GIF, small enough that the GIF is not enormous.
const VIEWPORT = { width: 1280, height: 860 }

// Every pause in the recording derives from this, so one knob changes the whole
// tempo. It is the single biggest factor in whether the result is watchable: a
// viewer needs long enough to see what changed and read the label that caused
// it, which is far slower than a machine needs to click.
//
//     BEAT_MS=700 npm run record    # brisker
//     BEAT_MS=1600 npm run record   # slower still
const BEAT = Number(process.env.BEAT_MS ?? 1200)

// Between clicks inside one step, where the viewer is watching a list fill in
// rather than moving between ideas.
const HALF = Math.round(BEAT * 0.6)

// Long enough to actually read a panel.
const DWELL = BEAT * 4

const PASSWORD = 'a-good-long-password'

const log = (msg) => console.log(`  ${msg}`)

// Nothing is clickable until the socket is up. Before that the page is the dead
// render: real HTML, but no `phx-click` or `phx-submit` wired to anything, so a
// click on a form submits it natively and the interaction is silently lost.
// This cost the first run of this script, and it is the one thing to remember
// when scripting a LiveView.
async function connected(page) {
  await page.waitForFunction(() => window.liveSocket?.isConnected(), null, { timeout: 15_000 })
}

async function main() {
  await rm(OUT, { recursive: true, force: true })
  await mkdir(OUT, { recursive: true })

  const browser = await chromium.launch({ headless: !HEADED })
  const context = await browser.newContext({
    viewport: VIEWPORT,
    recordVideo: { dir: OUT, size: VIEWPORT },
    deviceScaleFactor: 1,
  })

  const page = await context.newPage()
  page.setDefaultTimeout(15_000)

  // Surface app-side problems instead of failing later on a missing selector.
  page.on('pageerror', (e) => console.error(`  [page error] ${e.message}`))
  page.on('response', (r) => {
    if (r.status() >= 500) console.error(`  [http ${r.status()}] ${r.url()}`)
  })

  const beat = () => page.waitForTimeout(BEAT)

  // --- register -----------------------------------------------------------
  // A fresh player every run, because character creation only shows to someone
  // who has not made a character yet.
  const username = `wanderer_${Date.now().toString(36)}`

  log(`registering ${username}`)
  await page.goto(`${BASE}/register`)
  await connected(page)
  await page.fill('input[name="player[username]"]', username)
  await page.fill('input[name="player[password]"]', PASSWORD)
  await page.fill('input[name="player[password_confirmation]"]', PASSWORD)

  // Registering posts to /login through `phx-trigger-action`, so a full page
  // load follows rather than a live patch.
  await Promise.all([
    page.waitForURL((url) => !url.pathname.startsWith('/register'), { timeout: 15_000 }),
    page.click('#registration-form button[type="submit"]'),
  ])

  // --- into the game ------------------------------------------------------
  log('entering /play')
  await page.goto(`${BASE}/play`)
  await connected(page)

  if (page.url().includes('/login')) {
    throw new Error('not logged in after registering — check the username and password rules')
  }

  await page.waitForSelector('#cc-name', { state: 'visible' })
  await beat()

  // --- identity -----------------------------------------------------------
  log('naming the character')
  // Typed rather than filled: `phx-keyup` drives the availability check, and a
  // programmatic value set fires no key events.
  await page.locator('#cc-name').pressSequentially('Faelwen', { delay: 150 })
  // Outlast the input's own phx-debounce, then hold so the availability hint
  // underneath has time to be read.
  await page.waitForTimeout(600)
  await page.waitForTimeout(DWELL)

  await pickOption(page, 'species', 'elf', beat)
  await pickOption(page, 'class', 'wizard', beat)
  await pickOption(page, 'background', 'sage', beat)

  // --- abilities ----------------------------------------------------------
  log('assigning the standard array')
  await gotoStep(page, 'abilities', beat)

  // A wizard's array. Each value is used once, so no swap is triggered.
  for (const [ability, value] of [
    ['int', 15],
    ['dex', 14],
    ['con', 13],
    ['wis', 12],
    ['cha', 10],
    ['str', 8],
  ]) {
    await page.click(
      `button[phx-click="creation_assign_ability"][phx-value-ability="${ability}"][phx-value-score="${value}"]`,
    )
    await page.waitForTimeout(HALF)
  }
  await page.waitForTimeout(DWELL)

  // Background increases. Options differ per background, so take the first.
  const spread = page.locator('button[phx-click="creation_spread"]').first()
  if (await spread.count()) {
    await spread.click()
    await beat()
  }

  // --- skills -------------------------------------------------------------
  log('choosing skills')
  await gotoStep(page, 'skills', beat)
  await fillStep(page, 'skills', 'button[phx-click="creation_skill"]:not(.selected)', beat)

  // --- specializations ----------------------------------------------------
  // Whatever this species/class/background actually offers. Nothing here names
  // a fighting style or a lineage; the step is generated from the draft.
  if (await stepExists(page, 'specializations')) {
    log('picking specializations')
    await gotoStep(page, 'specializations', beat)
    await fillStep(page, 'specializations', 'button[phx-click="creation_pick"]:not(.selected)', beat)
  }

  // --- review -------------------------------------------------------------
  log('reviewing')
  await gotoStep(page, 'review', beat)
  // The whole point of the review step is that you read it.
  await page.waitForTimeout(DWELL * 2)

  // --- confirm ------------------------------------------------------------
  const confirm = page.locator('button.cc-confirm')
  if (await confirm.isEnabled()) {
    log('entering the world')
    await confirm.click()
    // Let the world render before cutting.
    await page.waitForSelector('#cc-name', { state: 'detached' }).catch(() => {})
    // Land on the world for a moment rather than cutting the instant it renders.
    await page.waitForTimeout(DWELL * 2)
  } else {
    console.error('  confirm is still disabled — something upstream is incomplete')
    await page.screenshot({ path: join(OUT, 'blocked.png'), fullPage: true })
    process.exitCode = 1
  }

  // The video is only written when the context closes.
  await context.close()
  await browser.close()

  const video = (await readdir(OUT)).find((f) => f.endsWith('.webm'))
  if (video) {
    await rename(join(OUT, video), join(OUT, 'character-creation.webm'))
    log(`wrote ${OUT}/character-creation.webm`)
  }
}

// Click a species/class/background by slug, falling back to the first option so
// a content change renames something without breaking the recording.
async function pickOption(page, field, slug, beat) {
  const bySlug = page.locator(
    `button[phx-click="creation_select"][phx-value-field="${field}"][phx-value-slug="${slug}"]`,
  )
  const target = (await bySlug.count())
    ? bySlug
    : page.locator(`button[phx-click="creation_select"][phx-value-field="${field}"]`).first()

  await target.scrollIntoViewIfNeeded()
  await target.click()
  await beat()
}

const stepTab = (step) => `button[phx-click="creation_step"][phx-value-step="${step}"]`

async function stepExists(page, step) {
  return (await page.locator(stepTab(step)).count()) > 0
}

async function gotoStep(page, step, beat) {
  const tab = page.locator(stepTab(step))
  await tab.waitFor({ state: 'visible' })
  // The tab is disabled until the steps before it are done, so this doubles as
  // an assertion that the previous step really completed.
  await tab.click()
  await beat()
}

// Keep picking until the step's tab reports itself done.
//
// One pick per group per pass, rather than always the first unselected option
// anywhere. A step can hold several independent choices, and some of them want
// more than one pick, so sweeping breadth-first converges on both shapes. How
// many picks a choice needs is a rules question the app owns; this just keeps
// offering until the app says the step is satisfied.
async function fillStep(page, step, selector, beat) {
  const done = page.locator(`${stepTab(step)}.done`)

  for (let pass = 0; pass < 6; pass++) {
    if (await done.count()) break

    const groups = page.locator('.cc-group')
    const count = await groups.count()
    let clicked = 0

    for (let g = 0; g < count; g++) {
      if (await done.count()) break

      const next = groups.nth(g).locator(selector).first()
      if (!(await next.count())) continue

      await next.scrollIntoViewIfNeeded()
      await next.click()
      clicked++
      await page.waitForTimeout(HALF)
    }

    // Nothing left to click and still not done means the app wants something
    // this script cannot supply. Stop rather than spin.
    if (clicked === 0) break
  }

  if (!(await done.count())) {
    console.error(`  step "${step}" never reported done — check the picks above`)
  }
  await page.waitForTimeout(DWELL)
}

main().catch(async (err) => {
  console.error(err)
  process.exit(1)
})
