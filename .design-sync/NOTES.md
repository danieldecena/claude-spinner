# design-sync notes

- 2026-09-29: repo is SwiftUI, outside the converter's envelope (no JS package,
  dist/ or Storybook). User chose a tokens-only project: `ds-bundle/` is
  hand-authored source, not converter output, so it is committed.
- User asked to "follow the app kit design": chrome tokens mimic macOS AppKit
  semantic colours, system font at 13px, 6/8px radii. Those AppKit values are
  approximations, not sampled; the app palette is copied from `Color.Ink`.
- No `_ds_sync.json`: the anchor recipe needs converter facts this layout lacks,
  so every re-sync re-uploads all 5 files (cheap).
- Re-sync: if `Color.Ink` changes, update `ds-bundle/tokens/colors.css` by hand.
