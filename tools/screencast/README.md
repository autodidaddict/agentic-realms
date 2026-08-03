# Screencast

Records a UI flow against a local dev server and turns it into video or GIF.

```sh
mix phx.server            # in the repo root

cd tools/screencast
npm install
npx playwright install chromium
npm run record
./convert.sh              # webm -> mp4 + gif
```

Output lands in `out/`, which is wiped at the start of every run — copy
anything you want to keep.

## Headless still renders

Headless Chromium runs the whole pipeline: CSS, layout, paint, JS, the LiveView
socket. `recordVideo` captures the compositor's frames, so the recording is the
painted page rather than HTML source. Headless only means no window on your
desktop, which is also why this needs no macOS screen-recording permission.

`HEADED=1 npm run record` drives a visible browser instead. It records either
way; use it if you want to watch, or if you suspect a font or a GPU-composited
effect renders differently without a window.

## Pace

`BEAT_MS` sets the tempo and everything else derives from it. The default (1200)
runs about seventy seconds, which is slow enough to read.

```sh
BEAT_MS=900 npm run record    # ~50s
```

A GIF grows with duration, so a slow recording and a small GIF pull against each
other. `GIF_WIDTH=800 GIF_FPS=10 ./convert.sh` trades resolution for size. The
mp4 does not have the problem and is usually the better artifact anyway —
LinkedIn and GitHub both re-encode a GIF to video on upload regardless.

## Waiting for the socket

Nothing in a LiveView is clickable until the socket connects. Before that the
page is the dead render: real HTML, but no `phx-click` or `phx-submit` bound to
anything, so a click on a form submits it natively and the interaction is
silently lost. `record.mjs` gates every navigation on
`window.liveSocket.isConnected()`. Skipping that is the first thing to suspect
when a step does nothing.

## Selectors

Driving the real DOM found two bugs the test suite could not, because
`render_click/3` sends the payload the test writes rather than the one a browser
produces. If the app's `phx-value-*` names change, the selectors here change
with them — that coupling is the point.
