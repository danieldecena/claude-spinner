# design-sync notes

- 2026-09-29: the project syncs **App Kit** (`~/developer/app-kit`, the shared
  design system), not this app's SwiftUI code. "App kit" means that design
  system, not macOS AppKit; the first tokens-only sync guessed wrong and was
  replaced.
- App Kit ships a classic IIFE (`window.React` in, `window.AppKit` out), not an
  npm package. `prep-appkit.mjs` (= `cfg.buildCmd`) wraps it as `app-kit` inside
  `.ds-sync/node_modules`: sets the React global, re-exports the 13 components,
  generates `tokens/tokens.css` from `tokens.json`, copies READMEs as
  `component-docs/` (frontmatter category = the preview's @dsCard group) and the
  system README as the one guideline. Re-run it after any `npm i` in `.ds-sync`,
  which prunes the unlisted package.
- `appkit.css` drops `padding: 16px` from bundle.css's body rule: that is the
  App Kit preview harness, not something designs should inherit.
- Build: `node .ds-sync/resync.mjs --config .design-sync/config.json
  --node-modules .ds-sync/node_modules --entry
  .ds-sync/node_modules/app-kit/index.js --out ./ds-bundle [--remote ...]`.
- Render check: no playwright chromium cache here. Install only the npm package
  (`PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i playwright` in `.ds-sync`) and set
  `DS_CHROMIUM_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`.
- Previews are ports of App Kit's `components/<Name>/preview.html`. Button,
  Highlight and BarChart are `cardMode: column` (clipped in the grid).

## Known render warns
- `[FONT_MISSING]` SF Pro / SF Pro Rounded / SF Compact: App Kit uses the Apple
  system stack by design (SF is not licensed for web embedding). On Apple
  devices `-apple-system` resolves to SF; elsewhere it falls back to system-ui.

## Re-sync risks
- App Kit changes land only after re-running `prep-appkit.mjs`; a stale
  `.ds-sync/node_modules/app-kit` builds the old bundle without complaint.
- A new App Kit component needs a matching `previews/<Name>.tsx` port, else it
  ships the floor card.

- 2026-09-30 re-sync: App Kit grew to 13 components (Fact, Eyebrow, Toolbar added,
  Panel and StatTile changed). The three new ones have authored previews ported from
  their `preview.html` and graded good. The driver printed "unchanged" for Panel,
  StatTile and SegmentedControl while `upload.components` still listed them: the
  verification partition keys on render sources, the upload partition on file
  hashes; upload from the second.
- `DS_CHROMIUM_PATH` must be exported for `package-capture.mjs` run on its own, not
  only for the driver, or it dies looking for a playwright-managed headless shell.

## Open
- `conventions.md` still says "these ten" and its destructure lists ten names;
  the project has 13. Fact, Eyebrow and Toolbar are not mentioned. Names that are
  listed all still verify against the build. Propose adding them; the file is
  Daniel's, not rewritten by the sync.
