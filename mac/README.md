# Sentrel for Mac

A native shell around https://sentrel.ai — one WKWebView in a real macOS window.
No Electron, no bundled runtime, no `node_modules`. The built app is ~460 KB and
uses the system WebKit, so it launches instantly and stays current with Safari.

## Build

```sh
./mac/build.sh
```

Needs only the Xcode command line tools (`swiftc`, `sips`, `iconutil`) — no Rust,
Node or package manager. Produces a universal (arm64 + x86_64) `mac/dist/Sentrel.app`.

```sh
open mac/dist/Sentrel.app        # run it
cp -R mac/dist/Sentrel.app /Applications/   # install it
```

## What it does

- **Opens the product, not the marketing site.** The app loads `/dashboard`,
  which sits behind `authenticate_user!` — so a signed-out launch redirects
  straight to the sign-in page, and a signed-in launch goes to the dashboard.
  Same URL, correct either way.
- **Its own session.** Cookies live in the app's data store, separate from Safari,
  and persist across launches — sign in once.
- **Links go to the right place.** `sentrel.ai` navigations stay in the window;
  anything else opens in your default browser. `mailto:` and other schemes go to
  the system.
- **OAuth works.** `window.open` popups for Google, Slack, Nango, Stripe and the
  other providers listed in `Sources/Config.swift` open as in-app windows sharing
  the session, so the callback lands back inside the app instead of stranding you
  in Safari.
- **Downloads** save to `~/Downloads` and reveal in Finder.
- **Follows the system appearance.** The window background mirrors `--background`
  from `backend/app/frontend/entrypoints/global.css`, so there is no flash of the
  wrong colour before the page paints.
- **File uploads, camera and microphone** are wired to native panels and prompts.

## Shortcuts

| | |
|---|---|
| `⌘R` / `⇧⌘R` | Reload / reload ignoring cache |
| `⌘[` / `⌘]` | Back / forward (two-finger swipe also works) |
| `⇧⌘H` | Home (`/dashboard`) |
| `⌘0` / `⌘+` / `⌘-` | Actual size / zoom in / zoom out |
| `⌃⌘F` | Full screen |

Plus **Navigate ▸ Copy Page Address** and **Open in Default Browser**, and
**Sentrel ▸ Clear Local Data…** to sign out and wipe cookies and cache.

## Pointing it somewhere else

`SENTREL_URL` overrides the home URL, which is how you aim a build at a local
Rails server:

```sh
SENTREL_URL=http://localhost:3200 open -n mac/dist/Sentrel.app
```

A bare origin picks up `/dashboard`; pass an explicit path and it is used as-is.
`localhost` and `127.0.0.1` are already treated as in-app hosts.

## Notes

- **User agent.** WKWebView sends no `Version/… Safari/…` token by default, and
  `allow_browser versions: :modern` in `backend/app/controllers/application_controller.rb`
  answers **406** to anything it cannot recognise as a current browser. The app
  reports the Safari version actually installed (same WebKit doing the rendering)
  plus `SentrelDesktop/<version>`, so server-side analytics can tell desktop from web.
- **Signing.** `build.sh` ad-hoc signs the bundle, which is enough to run locally.
  To hand it to someone else without a Gatekeeper warning it needs a Developer ID
  signature and notarization.
- **Icon** is `mac/icon.svg` — the bloub logo, violet `#8b5cf6` with the eyes
  knocked out through a mask. `build.sh` fits it to the icon canvas (centred on
  its own path bounding box, sized to 86 of 100 units so the drop shadow has
  room), rasterises it through WebKit — no rsvg/ImageMagick needed — and cuts the
  `.icns`. The artwork is used exactly as authored: no palette or shading is
  imposed on it. Drop in a different `icon.svg` and it is picked up on the next
  build, or point elsewhere with `ICON_SOURCE=path/to/logo.svg`.

  **Fallback.** Delete `icon.svg` (or set `ICON_SOURCE=` to something missing)
  and the build generates the product's own blobatar instead — what
  `<AgentBlob name="Sentrel" />` draws — with a gradient, highlight and shade
  standing in for the contrast a background tile would have given:

  ```sh
  ICON_HUE=210 ./mac/build.sh                # 0–360; default 180 (aqua)
  ICON_TONE=0.6 ./mac/build.sh               # which swatch of that hue; default 0.9
  ICON_EXPRESSION=wink ./mac/build.sh        # happy (default), idle, smug, sleepy, …
  ICON_SEED="Sentrel" ./mac/build.sh         # shape; also colour when hue/tone are unset
  ICON_BACKGROUND=squircle ./mac/build.sh    # put a tile back (824-in-1024 geometry)
  ```

  `tone` selects from a discrete swatch set rather than sliding continuously —
  `0.9` holds the vivid swatches, `0.6` the mid-strength ones, `0.35` is washed
  out and `0.95` is near-black. Last resort if node is unavailable:
  `mobile/assets/icon.png`.
