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
