# UI Screenshots

> **Device:** iPhone 17 Pro (Simulator, iOS 26.3)  
> **App version:** latest `main` (`1b28b58`)  
> **Date:** 2026-04-14  
> **Theme:** Light (forced via `.preferredColorScheme(.light)`)

## Session List

### Empty State
Waveform icon + "No Sessions" text + "+ New Session" CTA button.  
Toolbar: gear icon (circle background) + plus icon (circle background) in a capsule.

<img src="screenshots/01-session-list-empty.png" width="300" />

### Single Session
Session card: folder icon, directory name (bold), full path (secondary), agent badge ("claude").  
Card uses `Theme.surface` background with continuous rounded corners.

<img src="screenshots/02-session-list-single.png" width="300" />

### Multiple Sessions
Long paths get truncated with ellipsis. Cards stack vertically under "ACTIVE" section header.

<img src="screenshots/03-session-list-multiple.png" width="300" />

## Not Yet Captured

The following screens require interactive UI navigation (tap/swipe) which couldn't be automated in headless simulator mode:

- **Settings View** — Connection config (host, port, token), theme selector, app info
- **Chat View** — Message bubbles, markdown rendering, code blocks with syntax highlighting
- **New Session Sheet** — Directory picker + agent selector
- **Disconnected State** — Error banner when daemon is unreachable

These will be added once UI testing infrastructure is set up or captured manually on a physical device.
