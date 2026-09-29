# claude spinner: design conventions

A macOS menu-bar panel listing running Claude Code sessions. **Tokens only:
there are no library components.** The real app is SwiftUI; build every
control yourself in plain HTML/React, styled with the `--cs-*` variables and the
five `.cs-*` classes below. Do not invent other class names.

## Setup
Load `styles.css` (it imports `tokens/colors.css` and `tokens/type.css`).
Light is default; dark follows `prefers-color-scheme`, and
`<html data-theme="light|dark">` forces either. Without `styles.css` nothing
has the palette or the Menlo data font.

## Idiom: AppKit chrome, mono data
- Chrome (buttons, menus, prompts) follows macOS AppKit: `var(--cs-font-ui)` at
  `var(--cs-size-ui)` (13px), radii `--cs-radius-control` (6px) and
  `--cs-radius-card` (8px), hairline `--cs-separator` dividers, no drop shadows
  inside the panel, row hover `--cs-fill-subtle`.
- Data is Menlo: `.cs-mono` (11px, tabular digits). Micro text is
  `--cs-size-micro` (10px); detail titles `--cs-size-title` (18px, 600).
- Rows are label/value pairs: `.cs-label` (clay, `--cs-label`) then
  `.cs-value` (`--cs-text`). Keep this pair; it is what makes columns scannable.
- `--cs-accent` is the brand clay. `--cs-attention` (blue) means only "a session
  is waiting on you"; a waiting row gets `background: color-mix(in srgb,
  var(--cs-attention) 22%, transparent)`.
- Usage gauges: track `--cs-track`, fill by level `--cs-heat-1` (green, low)
  -> `--cs-heat-2` -> `--cs-heat-3` -> `--cs-heat-4` (red, near limit).
- Session identity: `--cs-id-purple|cyan|jade|indigo`. A host chip is
  `.cs-chip` with `background: color-mix(in srgb, var(--cs-id-purple) 16%,
  transparent)` and the hue as text colour.
- `--cs-accent-dim` is for translucent container fills only, never text.

## Where the truth lives
`tokens/colors.css` (every colour, both appearances) and `tokens/type.css`
(fonts, sizes, radii, spacing). Source of record: `Color.Ink` in the app's
`claude_spinnerApp.swift`.

## Example
```html
<div style="background:var(--cs-ground);border-radius:var(--cs-radius-card);padding:var(--cs-space-3) var(--cs-space-4)">
  <div class="cs-mono"><span class="cs-label">ctx </span><span class="cs-value">142k / 200k</span></div>
  <div style="height:4px;border-radius:2px;background:var(--cs-track);margin:var(--cs-space-2) 0">
    <div style="width:71%;height:100%;border-radius:2px;background:var(--cs-heat-3)"></div>
  </div>
  <span class="cs-chip" style="color:var(--cs-id-purple);background:color-mix(in srgb,var(--cs-id-purple) 16%,transparent)">ghostty</span>
</div>
```
