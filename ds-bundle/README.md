# App Kit: design conventions

Apple's neutrals and system colours, capsule buttons tinted like Notes
highlights, glass only for controls that float over content. The system this
project syncs is **App Kit** (`~/developer/app-kit`), the design system shared by
Claude Spinner, WA Fish Map and Footage Library.

## Setup
Load `styles.css`: it imports `tokens/tokens.css` (every token as a CSS
variable) and `_ds_bundle.css` (component styles). Light is default; dark
follows `prefers-color-scheme`, and `<html data-theme="light|dark">` forces
either. Components live on `window.AppKit`:

```jsx
const { Button, FilterPill, SegmentedControl, Badge, Flag, StatTile, Panel, ListRow, Highlight, BarChart } = window.AppKit;
```

Use these ten before drawing anything yourself. Their `.d.ts` is the API; the
`dc-*` classes are their internals, so pass props rather than hand-writing
`dc-btn` markup. The only `dc-*` classes to use directly are the layout helpers:
`.dc-row` (wrapping flex row, `space-3` gap), `.dc-stack` (column, `space-5`
gap) and `.dc-list` (a `surface` card that holds `ListRow`s).

## Tokens (plain names, no prefix)
- Neutrals: `--ground` (page), `--surface` (panels, rows), `--surface-sunk`
  (tracks, thumbs), `--ink`, `--ink-soft`, `--hair` (decoration only),
  `--edge` (control borders), `--fill`.
- Accent is for acting and selection only: `--accent`, `--accent-wash`,
  `--accent-ink`, `--accent-fill` with `--on-accent` text.
- Status pairs, each with a word or glyph too: `--ok`/`--ok-wash`,
  `--warn`/`--warn-wash`/`--warn-ink`, `--bad`/`--bad-wash`.
- Data: `--series-1..5` for chart series, `--chart-base` for non-emphasised
  marks, `--heat-1..4` for ranked scales (a scale is not a status).
- Highlights: `--hl-<purple|pink|orange|mint|blue>` on its own `-wash`.
- Glass: `--glass`, `--glass-edge`, `--shadow-glass`; only over content.
- Type: `--font-sans`, `--font-display`, `--font-round`, `--font-mono`
  (SF system stacks). Space `--space-1..8` (2, 4, 6, 8, 12, 16, 20, 32px),
  `--touch` (44px). Radii `--radius-sm|md|lg|pill` (6, 10, 14, capsule); nest
  one step down.

## Rules
- Sentence case, verb-first buttons ("Import 42 clips"). Uppercase only in the
  mono label style (StatTile keys, Badges).
- One `variant="filled"` Button per view; everything else tinted, gray or plain.
- Real units and tabular figures: "2,400 fish", "6 min ago", "94 %".
- Separate with `surface` on `ground` and hairlines, not shadows.
- No emoji. Fonts are SF only, via the system stack; there are no web fonts.

## Example
```jsx
<div style={{ background: 'var(--ground)', padding: 'var(--space-6)' }} className="dc-stack">
  <Panel title="Sessions" meta="Updated 6 min ago">
    <div className="dc-row">
      <StatTile label="Context" value="142" unit="k" meter={0.71} />
      <StatTile label="5h limit" value="94" unit="%" meter={0.94} attention />
    </div>
    <div className="dc-row"><Badge tone="ok">Synced</Badge><Badge>Opus</Badge></div>
  </Panel>
  <Flag tone="warn">Usage is at 94%. It resets at 3:00.</Flag>
  <div className="dc-row"><Button variant="filled">Install hooks</Button><Button variant="gray">Cancel</Button></div>
</div>
```

# AppKit (app-kit@1.0.0)

This design system is the published app-kit React library, bundled as a single
browser global. All 10 components are the real upstream code.

## Where things are

- `_ds_bundle.js` — the whole-DS bundle at the project root; loads every component to `window.AppKit`. First line is a `/* @ds-bundle: … */` metadata header.
- `styles.css` — the single stylesheet entry: it `@import`s the tokens, fonts, and component styles (`_ds_bundle.css`). Link this one file.
- `components/<group>/<Name>/<Name>.prompt.md` (example JSX + variants), `<Name>.d.ts` (types), `<Name>.html` (variant grid).
- `tokens/*.css` — CSS custom properties, names verbatim from upstream.
- `fonts/` — `@font-face` files + `fonts.css` (when the package ships fonts).
- `guidelines/` — the design system's own usage guidance (1 doc(s), see `guidelines/index.md`). Read these before composing larger layouts.

For a specific component, `read_file("components/<group>/<Name>/<Name>.prompt.md")`.

## Loading

Add these two lines to your page once (React must be on the page first):

```html
<link rel="stylesheet" href="styles.css">
<script src="_ds_bundle.js"></script>
```

Components are then available at `window.AppKit.*`. Mount into a dedicated child node (e.g. `<div id="ds-root">`), not the host page's own React root, so the two trees don't collide:

```jsx
const { Badge } = window.AppKit;
ReactDOM.createRoot(document.getElementById('ds-root')).render(<Badge />);
```

## Tokens

65 CSS custom properties from app-kit. Names are
preserved verbatim from upstream. See `tokens/` for the full list.

- **color** (4): `--surface`, `--surface-sunk`, `--fill`, …
- **spacing** (8): `--space-1`, `--space-2`, `--space-3`, …
- **typography** (5): `--font-sans`, `--font-display`, `--font-round`, …
- **radius** (4): `--radius-sm`, `--radius-md`, `--radius-lg`, …
- **shadow** (3): `--shadow-segment`, `--shadow-float`, `--shadow-glass`
- **other** (41): `--ground`, `--ink`, `--ink-soft`, …

## Components

### status
- `Badge` — Short uppercase metadata tag.
- `Flag` — Inline status callout with a glyph and a sentence.

### data
- `BarChart` — Bar chart, stacked when a row carries several values. Y axis on the trailing edge, starting at zero.
- `StatTile` — One figure with a mono key, optional unit and 0..1 meter.

### actions
- `Button` — Action button, an iOS 26 capsule. tinted (translucent) is the default filled at most once per view.
- `FilterPill` — Toggleable filter pill with an optional count.

### content
- `Highlight` — Inline text highlight in one of Apple Notes' five colours.

### layout
- `ListRow` — Selectable row with optional thumbnail and trailing value. Place inside a .dc-list with rolelistbox.
- `Panel` — A surface grouping related content on the ground.

### navigation
- `SegmentedControl` — 2 to 5 mutually exclusive views of the same content.
