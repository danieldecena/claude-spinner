# STATUS

## Confirmed working

- The window detail pane carries the whole statusLine payload, not the eight
  fields the app used to decode: wall vs API time, lines changed, context and
  window size, prompt-cache hit ratio and warmth, effort, thinking, model id,
  Claude Code version and repo. No dollar figures anywhere (2026-10-01): nothing
  is billed on a Max plan, and the api-equivalent number read as though it were.
  One Usage card holds every ring -- the session's context and cache, the 5h/7d
  rate-limit windows, and this Mac's CPU, memory and disk -- with each ring's
  detail and its colour key on hover. CPU and memory draw their parts.
- The window opens on a Home tab: the Usage rings, every session as a row
  (status, context, wall time, click to open) and the open TASKS.md items per
  project. A session's own pane also carries a Graph card for any repo with a
  `graphify-out/graph.json`: its size and a bar per community. A checkered flag
  marks any session on a timed `/goal` run. All observed on screen 2026-10-01.
- `TranscriptReader` shows what a session is *doing* — the last thing Claude
  said, what you last asked, and what it just ran — read from the last 256KB of
  its own transcript. Observed on screen 2026-09-04 against a live 4.7MB file.
- The context ring and the context columns in the This session card are both
  scaled to the window so they mean the same thing: how close this session is to needing a compact, and
  how fast it got there. Behind them is the app's first per-session time series
  -- `contextHistory`, sampled on each rescan, only when the count actually
  moves, capped at 240 points and dropped when the session goes away. Both
  observed on screen 2026-09-15 against `fix-dock-passwords-icon` (24 samples,
  98,834 -> 160,939 on a 1M window): the meter fills ~16% and the chart draws a
  1.5pt line with its tinted area fill, flat along the floor. Flat is correct
  there, not a failure -- 0.099 to 0.157 of a 1M window is a 1.6pt rise inside a
  28pt frame. What separates "flat" from "not drawing" is the *absence* of the
  `no context history yet` fallback text, which is what `TrendColumns` renders
  when `unitPoints` returns nil.
- Six session actions under the reply field: Interrupt, Compact and Clear
  through the tmux pane, Reveal folder / Open transcript / Copy session id
  locally. Each is enabled or carries a stated reason.
- The Git card states what the repo can do rather than a row of greyed
  buttons. An action with a finished answer ("already in sync", "#3 is
  already open") is not drawn at all; one whose state could not be read stays
  on screen greyed with its reason printed underneath. Five rows -- branch,
  changes, remote, pr, checks -- each carry their own age, because the local
  half is read every 5s and the network half every 90s, and Refresh forces
  the network half early. Merge runs `gh pr merge --squash --delete-branch`
  and is offered only when gh reports the PR mergeable, reviewed and passing.
- Compact reports a refusal in Claude Code's own words under the reply field
  ("Claude Code didn't run it: Not enough messages to compact."), read from the
  transcript's `local_command` line. Seen live 2026-09-30 on a tmux probe.

- Notifications reach you. Authorization was denied for the app's whole life
  until 2026-09-15; granted, a posted ask clears the entitlement check, runs the
  full `usernotificationsd` pipeline and lands in `destinations=[notices]`. Both
  surfaces carry the denied notice for the case where it is off again, and the
  read refreshes whenever the app becomes active.
- Questions and permission prompts can be answered without going back to the
  terminal. `ask.sh` blocks on `PreToolUse`/`AskUserQuestion` and
  `PermissionRequest`, the app renders the request, and the answer returns as
  `allow` + `updatedInput` (or `decision{behavior}`). Proven end to end on
  2026-09-04: a click in the window produced
  `{"permissionDecision":"allow","updatedInput":{...,"answers":{"Which surface
  should own the reply field?":"Window only"}}}` from a live hook.
- The window is its own UI now — sidebar grouped Needs you / Working / Idle, and
  a detail pane carrying the full question with every option *and its
  description*, session stats, subagents, and a reply field. Observed on screen
  2026-09-04.

- Menu-bar panel tracks live Claude Code sessions via `~/.claude/spinnerfeed/`
  feed files (hooks + statusLine in `~/.claude/settings.json`).
- The app survives macOS refusing to place the status item (a full menu bar,
  which a notched display reaches early). It detects the unplaced item by frame,
  opens the panel as a real window titled with the live readout, and hangs the
  full settings menu off a "Spinner" main-menu submenu so nothing is stranded
  behind an icon that isn't there.   Both placed and unplaced observed live
  2026-08-12.
- First-run one-click installer (Install hooks button) writes the scripts and
  back-up-then-merges the hooks/statusLine into settings.json.
- CI actually runs now: 221 unit tests green on a self-hosted macOS runner
  registered 2026-09-15 (`~/Tools/actions-runner`, kept alive by the LaunchAgent
  `svc.sh install` wrote). Before that no runner had ever been registered, so
  every run queued until GitHub cancelled it at the 24h await-runner limit.
  GitHub-hosted images are not an option on this account: they refuse jobs
  outright over a billing block. See the 2026-09-15 decision log.
- Both session lists group by project, with anything blocked on a person pinned
  above. Section headers carry the session count and the section's context
  added up (untinted -- separate windows, so a summed 210k is not one session's
  210k). Sidebar observed on screen 2026-09-15.
- Which surface the app presents is a choice, not luck. `Show in` (Menu bar /
  Window, persisted, default Menu bar) sits in the settings menu; Window creates
  no status item at all, Menu bar keeps the automatic window fallback.
- Row names get every point the model and status columns don't need, and the
  columns are sized once per panel so they still align. Verified on screen:
  `compact-vscode-density`, `statusline-drift-perf` and `scan-jobs-task-runner`
  all render in full at panelWidth 470, where they truncated at 424.
- Panel rows carry the session's own name (`session_name` from status.json,
  falling back to the directory), its context token count banded on absolute
  usage (100k/150k/200k), and sort heaviest-first within each status band.
  The header totals context across all sessions. Legible in both appearances.
- Each row carries a 10-box `□□□□□□□□□□ --%` task-completion bar (TodoWrite
  counts via `emit.sh`), with the session's status/activity text beside it on
  a second line. Verified on screen across several rebuilds.
- Subagent sessions nest under their parent as indented 2-line rows (todo
  bar + that child's own tool/status). Child hook events write
  `<parent>.<agent_id>.state.json` and no longer overwrite the parent file.
  Verified on screen against a live parent+Explore; 95 unit tests green.
- The standalone window (right-click icon → Open Window) pins its content to
  the top and shrinks an oversized/stale remembered frame back to
  panelWidth × panelDefaultHeight on open, on whichever axis overran.
  Verified on screen: a window carrying a leftover 573×1900ish remembered
  frame from earlier automated testing now opens flush, no dead space above,
  below, or past the row content.

- Clicking a row focuses the editor the session actually runs in — including
  Zed and any editor not in `hostBundleIDs`, which previously opened a stray
  Ghostty window (bug-130). **Verified by hand 2026-07-17**: clicking the Zed
  row focused zed and Ghostty never launched. The panel *can* be driven from an
  agent session after all, when the host app has Accessibility permission.
- The panel's gauges and row layout are verified on screen, not just in tests:
  7d at 9% draws a visible sliver, `chg +52%` fills ~72% of its track rather
  than saturating, and `review code and ui` / `needs input` render in full.
- A long tool name no longer draws two ellipses. `RowLayout.fit` pre-truncates
  the status label to its column so SwiftUI never adds its own tail `…` beside
  the animated dots. Verified on screen with a throwaway 51-char MCP tool
  (`running mcp__claude_ai_Google_Calendar__list_events`): the cut row's trailing
  marker is identical to the un-truncatable `running bash…` / `thinking…` rows
  (dots only). bug-201.
- `.wolf/buglog.json` no longer races between concurrent sessions. The OpenWolf
  auto-logger (`.wolf/hooks/post-write.js`) now serializes its read-modify-write
  behind an exclusive lockfile and mints ids as `max+1` (strictly above every id
  present). Proven with a barrier-synchronized 20-way race: the old
  `length+1`/no-lock pattern lost 15 of 20 writes; the locked version kept 20/20
  with unique ids. bug-200. (The 10 *historical* duplicate ids are left as-is —
  they're referenced in commits/STATUS/cerebrum, so renumbering would break refs.)
- A clean build (`xcodebuild clean build-for-testing`) prints no warnings. Types
  that are used off the main actor say `nonisolated`; the test target shares the
  app's main-actor default.
- The menu-bar label is the status button's attributed title (`MenuBarTitle`),
  not a hosted SwiftUI view. With a session working and no window open the app
  reads 11 to 14% of a core.
- A pinned page opens with its artifacts as a row of small cards (170pt, with a
  quarter-scale picture of the page), fills the pane's height, and leaves no
  empty column beside a card.

## Known broken

- Nothing known broken.

## Scope / by-design limitations

- **Captures Claude Code sessions only** — CLI (terminal/VS Code/Ghostty/iTerm)
  and the Claude **Desktop app's Code tab** (same engine, fires the same
  settings.json hooks). It does NOT capture the Desktop app's **Chat tab** or
  claude.ai web chat: those run no lifecycle hooks and no statusLine, and there
  is no supported API for their live turn state. Wiring to Desktop internals
  (`~/Library/Logs/Claude/main.log`, `~/Library/Application Support/Claude/`,
  or accessibility scraping) was considered and rejected as brittle. To see a
  desktop session in the spinner, use the Code tab.

## Next Up

- Allow the Calendars (and, if asked, Automation) prompt for the notarized build:
  the Calendar card still reads "Reading the calendar..." until it is answered.
- Not yet seen live, listed in `HANDOFF.md`: a tinted bar (needs a dark cover) and
  play/pause/previous/next; both mean changing what the user is listening to.

`TASKS.md` has no open item.

## Decision log

### 2026-10-03
- Explained: the main window's frame changing between captures (roadmap open question,
  2026-10-02) is the display configuration, not the app. This Mac's built-in display is
  mirrored to a Sidecar iPad and there is also a BetterDisplay "Virtual 16:9" screen; the
  main screen's visible area is 1572 x 932, exactly the saved frame
  (`NSWindow Frame SpinnerWindow = "0 55 1572 928 ... 1572 987"`, which records the
  screen it was saved on). The defaults hold five different recorded screen geometries
  (1572x987, 1603x1006, 1875x1178, 1935x1215, 2238x1405), and macOS rescales a window's
  frame as the display setup changes. Not proven for the specific 2026-10-02 captures, but
  every part that can be checked agrees. The app restores the saved frame and clamps it;
  nothing to fix.
- Fixed: `NowPlaying` kept the last track forever when every Apple Event started failing,
  a stale observation drawn as a fact. One failed read still keeps the track (no
  flicker); `failuresBeforeUnreadable` (3) in a row make the status `.unreadable`, the
  strip says "Music isn't answering", controls are off with that reason, and it is asked
  again every second so it recovers by itself. Three tests, one shown to fail when the
  threshold is made unreachable.
- Shipped: `fcfc52d`, the build with the shelf-tile hairline, the empty-divider fix and
  the accessibility fixes. CI was green on that sha before the build; `./notarize.sh`
  returned `status: Accepted`, stapled, Gatekeeper `accepted, source=Notarized Developer
  ID`, origin Developer ID Application: Daniel Decena (877MLS29T9); installed over
  `/Applications/claude spinner.app` (binary `cmp` identical, running process is that
  path; the previous copy is in `build/previous/`). The app was not running when it was
  swapped, so no draft was at risk. Found on the way: the custom link style reported the
  "+N more" links as buttons (AXButton, not AXLink); fixed with the link trait and
  checked in the accessibility tree of the installed build.
- Reviewed: `design:accessibility-review` on the bar, the pinned page and the sidebar
  (it had been skipped for these). Fixed: placeholders (reply, prompt, workflow
  argument) were the system grey at 3.1:1 on the white card, now drawn in the label ink
  (4.50:1 sampled off a capture, a lower bound; about 5.4:1 by token); the seven
  `.buttonStyle(.link)` buttons drew the system blue, measured 4.16:1 on the light
  sidebar, now `AttentionLinkStyle` (the `attention` blue, held at 4.5:1 across the
  sidebar's possible grounds by a test that also asserts the system blue fails); the
  hero cards get an explicit 2pt focus ring (`HeroFocusRing`); the seek line is
  focusable and the arrows seek 10 s. Left, known: sidebar rows are about 22pt tall
  (2.5.8 asks 24pt; dense on purpose) and selection is a 1.3:1 fill plus semibold.
  Not done: a VoiceOver session, and the Tab order into the sidebar list. A pixel
  sample of a 10pt link cannot resolve its colour (it reads lighter than the true
  colour), so the link fix is proven by the token test, not the capture.
- Polish on `main` after the notarized `f41fcf0` (not in the installed build): the
  Recent sessions tiles get a 0.5pt hairline (they all but vanished on the light page),
  and the sidebar's divider above "Sessions" is drawn only when there is a notice or
  setup banner to separate (it was a hairline over an empty band). Looked at in light
  mode on the build from DerivedData, launched directly so the notarized copy in
  `/Applications` was not overwritten; both visible in
  `docs/reference/2026-10-03-polish-light.png`. 509 tests pass. Re-notarize to ship it.
- Observed live, on the installed notarized build (no rebuild): a two-question form
  answered while a draft sat in the bar. The bar moved to the session that needed me
  (no draft, so it was free to), I typed "draft while a form waits", Return gave the
  notice "That session is waiting on a question. Answer it first." and kept the draft,
  then Green + Olives sent from the card: the session received both answers, no ask or
  answer file was left, and the draft was still in the bar afterwards. Light mode, forced
  through the app's own `NSRequiresAquaSystemAppearance` default and removed again:
  Home and the Job Search page with the bar and music strip read well (captures in
  `docs/reference`); the one weak spot is the Recent sessions tiles, whose neutral
  gradient is faint on the light page. Still not seen: a tinted bar (needs a dark cover,
  which means changing your track) and play/pause/previous/next.
- Shipped: roadmap pushes 2 and 3 (hero cards and sections, the floating bar, Music in
  the bar with the cover tint, and the docs) as `f41fcf0`, code identical to what was
  notarized. CI was green on that sha before the build; `./notarize.sh` returned
  `status: Accepted`, stapled, Gatekeeper `accepted, source=Notarized Developer ID`,
  origin Developer ID Application: Daniel Decena (877MLS29T9). The signed binary
  carries `com.apple.security.automation.apple-events` and the Apple Events usage
  string. Installed over `/Applications/claude spinner.app` (binary `cmp` identical, the
  running process is that path); the previous copy is in `build/previous/`. On first
  launch the music strip showed the live track, so Automation to Music works under this
  signature; the Calendar card again read "Reading the calendar..." (the Calendars
  grant still pending, as after the first notarized install).
- Roadmap: all slices ticked except 7 (trends, parked on purpose). Music and playback
  plans are `done`, the older ui-pass plan is `parked`; `HANDOFF.md`, `README.md` and
  the wireframes describe the app as it is (70 backticked identifiers in the wireframe
  checked against the sources, the check shown to fail on fake names). The window-frame
  question (a different size on every capture on 2026-10-02) was not looked into.
- Decided: the bar's glass takes the playing cover's colour (playback plan slice 4,
  `BarTint.swift`). The mean comes from `CIAreaAverage`, verified exact on sRGB images
  (red gives 1,0,0; a grey 0.502); the tint is mixed at 0.30 and used only when the
  bar's primary and quieter label ink both keep 4.5:1 on the resulting ground, else
  plain glass. That test is the contrast, not the hue: the same yellow passes at 0.05
  strength and fails at 0.30. The crossfade is 0.73 s ease-out, none under Reduce
  Motion; no artwork-specific motion was captured, so this is `music-motion-shelf`, the
  one measured Music ease-out. Consequence worth knowing: in dark mode the quieter label
  ink (`#98989D`) fails 4.5:1 on any cover with a bright mean, so only dark covers tint
  and light mode is stricter still; most covers fall back to plain glass. The current
  cover (mostly white) was seen falling back. A tinted state was not seen live: that
  would mean changing your track.
- Decided: Music in the floating bar is a remote over Apple Events, not a second player
  (playback plan slices 1 to 3; `NowPlaying.swift`, `MusicStrip.swift`). Nothing is sent
  unless Music is already running, checked in Swift and again inside every script with
  `application id "com.apple.Music" is running`, which asks without launching. State is
  refreshed on Music's `com.apple.Music.playerInfo` broadcast and by a once-a-second tick
  that only asks while a track is playing; polling is the fallback, the broadcast was
  not separately observed. The strip is its own row under the reply row, so the session
  keeps the main line and neither name loses width, and it draws nothing while Music is
  closed. Entitlement `com.apple.security.automation.apple-events` and
  `NSAppleEventsUsageDescription` added (both build configs).
- Observed live, on the real Music app (paused on "Jump (feat. Gizzle)"): the strip shows
  the track, "Lupe Fiasco - DROGAS Light", the real cover and a progress line; the
  Automation grant was already in place, so no prompt was seen. Seek: clicking 20% along
  the line moved Music's own `player position` from 163.9 s to 55.2 s of 274.9 s, read
  back from Music itself; I restored your position (163.9 s, still paused). Not done
  live, on purpose: play/pause, previous and next (they would start your audio or change
  your queue), and quitting Music (the quit case is a unit test with a fake that records
  every script, with an open-Music twin). A skip updating the strip within a second was
  not observed, since nothing was playing.
- Found: the cover is `raw data of artwork 1`, not `data of artwork 1`; the latter is a
  picture object with no bytes (count 0). Music returns it as descriptor type 'tdta'.
- Reviewed: the strip's contrast was not measured with `design:accessibility-review`;
  it sits on the same opaque `Color.card` as the reply field, so its text does not
  depend on what is behind the capsule.
- Decided: the floating reply bar (music plan slice 5, `FloatingBar.swift`). A glass
  capsule in a bottom `safeAreaInset` of the detail column. Its target is the open
  session pane's session, else the one that needs you, else the most recently
  working, and it never changes while its field holds an unsent draft
  (`BarTarget.choose`, with an "N waiting" pill for what was held back). Drafts live
  in `ReplyDrafts`, keyed by session id and shared with the conversation card's own
  `ReplyBox`, so a draft follows its session. Deviations from the plan, on purpose:
  the toolbar keeps every action (the bar mirrors only Interrupt and Focus, not
  "replace"); on a session pane the card's reply field is dropped (`replyInBar`) so
  there is not a second one; the bar is hidden on the App Kit tab, whose showcase has
  its own mini player.
- Observed live (dark): the plan's hand test through the real UI. Typed "draft A" in
  the Home bar (target claude-spinner), opened cue-deck (empty field, A did not
  carry), typed "draft B", went Home (the bar held cue-deck and B instead of
  switching), cleared B (it switched to claude-spinner and "draft A" was intact).
  The field grows to four lines, then scrolls inside the capsule without growing it;
  the 2pt focus ring is clear; at the end of the scroll the page clears the bar.
  The field sits on an opaque `Color.card`, so reply text contrast does not depend on
  what is behind the capsule (by construction, not measured). Not done: a pending form
  answered while a draft is in the bar, Interrupt and Focus pressed (Interrupt would
  interrupt a real session), and a light-mode capture.
- Found: giving the session-shelf tile `.accessibilityElement(children: .ignore)`
  dropped its press action. The accessibility API pressed the tile and nothing
  resumed, which is what VoiceOver would have met too. Label and hint now sit on the
  Button itself. Re-tested the same way: the press launched `claude --resume
  76cc4388-...`, the "wrap up" tile's own session (its transcript's last prompt is
  "wrap up"). Likewise the sidebar rows select through `onTapGesture`, which an
  accessibility press does not trigger; they now carry an explicit default action.
  This closes music slice 4's owed click check.
- Reviewed: `design:design-critique` on the bar (the glass was barely lighter than a
  dark page, so a hairline and a shadow were added; an unknown context reading drew
  an empty ring, now dashed). `design:accessibility-review` was not run.
- Decided: the pinned page (Job Search, Plans) no longer uses `TileGrid` (music plan
  slices 6 and 7). It is a VStack of sections: a "Top picks" row of `HeroMetrics`
  170 x 227 hero cards (`LaunchHeroCard` New session and quick start on a fixed
  graphite, one `ArtifactHeroCard` per artifact with its live thumbnail), the prompt
  field under it (a card cannot hold a text field), then Workflow, Job pipeline
  beside Scout daemon, Recent applications beside Tasks. Tasks, Recent sessions,
  Skills and Workflows sit on the pane's ground, not in cards, so nothing is
  stretched to a row's height. `ArtifactCard` is gone (it had one user); the three
  artifact controls became the hero as Expand plus two small buttons. The Start card
  and its path line are gone; the path is the New session hero's eyebrow.
- Observed live: six equal-height heroes; Career Hub opens full from its hero with
  its back link; a hero's Pop out opens the floating window, which closed cleanly.
  Not clicked, on purpose: New session and Apply next job (they start real sessions,
  Apply next job begins a job application) and the Skills chips; their closures are
  the old buttons' own. Dark only was captured for this slice; the hero art is a
  fixed graphite, so light differs only in the ground sections.
- Reviewed: `design:design-critique` (Tasks count was 1,300px from its header and the
  prompt field was invisible: both fixed; the Top picks row fills 55% of its width
  and the live "needs input" run still sits mid-page inside Workflow: left).
  `design:accessibility-review` was not run for this slice; hero caption contrast is
  computed (white on a 0.64-0.78 black scrim, worst case over white art 6.3:1+), not
  measured live.
- Open: music slice 4 (the shelf) still owes a real click on a tile to confirm it
  resumes the right session; automation could not target the tiles reliably.
- Shipped: roadmap push 1 (forms answered from the app, ui-pass closed by looking,
  Music look first half) as `9f9b491`. `./notarize.sh` returned `status: Accepted`
  (submission 10663005-1f89-4b3b-8f65-b15b4cc5a657), stapled, and Gatekeeper reports
  `accepted, source=Notarized Developer ID`, origin Developer ID Application: Daniel
  Decena (877MLS29T9). Installed over `/Applications/claude spinner.app` (binary
  `cmp` identical to the notarized build; the running process is that path); CI was
  green on `9f9b491`. The previous copy is kept in `build/previous/` (gitignored) for
  rollback. First launch of the new signature showed "Reading the calendar..." with a
  system window pending, which is read as the Calendars grant being asked for again
  under the new identity; not confirmed.
- Decided: Music red (`Color.Kit.musicAccent`) is a MARK colour only in Spinner
  (music plan slice 1, `MusicAccentProofTests`, renders in `docs/reference/
  2026-10-02-accent-proof-*.png`). Option B, limited. Measured: far from clay and
  blue (distance 42-46 and 110+ against clay-blue 87-94), so the status pair is not
  blurred; but accent text is 4.13:1 on the light pane (4.61 on a card), a white
  label on the red fill is 3.9:1 (large text only), and the nearest colour is the
  `usageRed` alarm at distance 27-29. So: sidebar symbols and chevrons yes; red
  text on the pane, red button fills, and red inside the Usage card no.
- Decided: the sidebar is a full-height see-through column over the window's own
  `.sidebar` material (slice 3), reversing the 2026-09 "opaque card" decision on
  purpose. Rows draw their own neutral rounded fill plus semibold; the List has no
  `selection:` binding (its native highlight is the system accent and `.tint` does
  not override it), and the arrow keys are `.onKeyPress` on a focusable List,
  observed working live after a click. Names are SF, not Menlo (the status glyph
  stays mono).
- Found: slice 1 measured red against the pane, but a see-through sidebar sits on
  the material. Measured live, the bare dark ground was #575757, which put secondary
  labels at 3.1:1 and red symbols near 2:1. `SidebarScrim` (pane colour at 0.62
  dark, 0.94 light) bounds it: dark ground 0.14, labels 6.7:1. Light was captured
  at 0.90 and the value raised to 0.94 afterwards (not recaptured) so clay status
  text keeps 4.5:1 down to a 0.85 backdrop. Light was forced through the app's own
  `NSRequiresAquaSystemAppearance` default, removed after each capture. The needs-you
  section was empty in every capture, so blue-over-clay in the new sidebar was not
  seen live.
- Decided: pinned-page headers are `SectionTitle` (bold, sentence case, `.ui(15)`),
  scoped to `PinnedProjectDetail`; `CardTitle` stays uppercase for the session pane.
  A "›" appears only where the header opens something: Tasks, when more than 5 are
  open. Recent sessions has none (it opens nothing), which departs from the plan's
  "Recent sessions ›". The Tasks symbol in the sidebar is neutral; red marks places
  you can go, not read-outs.
- Reviewed: `design:design-critique` (red on every section out-shouted status,
  light seam nearly invisible: both fixed; empty notice band and divider, and
  sidebar type larger than card text: not fixed) and `design:accessibility-review`
  (tappable rows lacked a button role: fixed; selected state is a ~1.3:1 fill plus
  weight, and rows are ~22pt tall, under 24pt: both left, density was a deliberate
  need; the list's focus ring is suppressed, the selected row is the focus mark).

### 2026-10-02
- Decided: `claude-spinner-ui-pass.md` is closed by looking (roadmap slice 3),
  on a build of `27c94fb` at 1751x928pt, session pane, light and dark, with
  `design:design-critique` and `design:accessibility-review`. Slice 3 (button
  row): overtaken, the actions are an icon `ActionBar`, no label truncates, and
  disabled is whole-control dimming (1.5-2.1:1), not text colour alone. Slice 4
  (git second channel): built, but untracked-only is deliberately neutral
  (`GitStatus.swift:85`) and `in sync` is green, not neutral as the plan said;
  dirty and diverged tones not seen, the tree was untracked-only. Slice 5
  (vitals as meters): overtaken by the Usage rings, not to be rebuilt; no
  wall/API bar, lines-changed pair or reset times, and none is wanted. Slice 7
  (window fills): session pane fills; Home leaves a 12-16% blank band below
  Mail/Calendar at this size, and no `home` heading remains. Slice 8 (eye lands
  on status): still open, the status line is the smallest grey text above the
  conversation card and 5h/7d sit mid-pane in the Usage row. Measured, not
  eyeballed: one enabled-text fail, the reply placeholder at 4.28:1 in light;
  Send disabled in dark is 1.40:1 (`#2e436d` on `#2b2d32`). Captures stay in
  the scratchpad, not the repo: they show Job Search task text.
- Decided: the App Kit tab's copies are synced and checked by `./sync-appkit.sh`
  (`--check` prints OK/DRIFT/BROKEN), and `~/bin/invariants.sh` check 41 runs it
  daily. The boundary in the spike is its `// MARK: - Spike window` line, not
  "lines 1-403". Not a unit test: the fact spans two repos, and an uncommitted
  app-kit edit would fail this repo's CI. Seen on every branch: clean OK, a
  byte appended to each copy DRIFT, missing or empty source and a marker-less
  spike BROKEN.
- Decided: the sidebar material is judged in a pop-out, not in the tab
  (39a100f). A NavigationSplitView nested in the detail pane drew the material
  but clipped the sidebar's first row and inflated the page's top inset, so
  the tab keeps its plain column and "Open in Window" hosts the same page as a
  window's root. Its sidebar matched the spike's own window in key-window
  captures, light and dark. `design:accessibility-review` was NOT run on the
  pop-out: same component and tokens as the spike window app-kit reviewed.
- Seen, not explained: the main window's frame differed on each capture this
  session (1521x857, 1363x846, 1468x871, 1479x881) with nothing resizing it on
  purpose. Not investigated.
- Verified: a PreToolUse hook answers a two-question AskUserQuestion call, one of them
  multiSelect, with `updatedInput.answers` keyed on the question text. The multi-select
  value is the labels joined with ", ". No terminal box was drawn: the pane showed
  `Pick a color? -> Red` / `Pick toppings? -> Ham, Olives` and the model received
  `"Pick toppings?"="Ham, Olives"`. (scratch probe in tmux, Claude Code v2.1.288)

- Decided: the pinned page's padding, grid minimum/spacing, rail gap and rail
  width are named statics, and the 808pt threshold is their sum, so it cannot
  drift from the layout (62101a8). Skipped a TileGrid.width(columns:) helper:
  one caller.
- Decided: the pinned page's rail drops under the grid when the pane is under
  808pt (two 220 columns beside the 300 rail), switched with AnyLayout so cards
  keep their state. Keyed on the visible width, not width / scale, to avoid a
  stack/unstack loop through PaneFit. Seen on screen: 900 window stacks it (grid
  draws 3 scaled columns), 1528 keeps it beside.
- Decided: layout changes start from `docs/WIREFRAMES.md`, a text wireframe of
  every surface labelled by struct and file (not line), with the inline spacing
  values and TileGrid / PaneFit rules. 12 of 12 sampled labels matched grep.
  The App Kit Design Runbook artifact gained section C describing the method.
- Found while mapping: `HomeDashboard.swift:51` writes a debug string to
  `/tmp/claude_debug.txt` on every render. And the pinned page is one column at
  the default 900pt window (grid gets ~274pt; 3 columns need 684).
- Found: CI on `main` after #8 failed twice with the test host gone mid-run
  (a different test each time, `Restarting after unexpected exit`), and #8's
  last PR run reported failure after `** TEST SUCCEEDED **`. `/Applications`
  was rewritten at 17:02:45, one second before the second host died: another
  session's `run.sh`, whose `killall` takes CI's host with it. Not a code
  fault: a rerun with nothing building locally passed 428 with no restart.
- Decided: a Job Search run is drawn under the Workflow step that started it
  (header, question boxes, reply field), and Running now keeps only runs no
  step started. Each step's Start passes `claude --name "Job Search: <step>"`
  and the step matches its runs on that name, because the newest prompt
  changes with the first reply. Seen: a probe launched through the `claude`
  function reached the feed as its `session_name` 2 s after starting. The card
  goes full width while a step has a run. Start is also held until a step's
  link is typed (#7). Seen on screen 16:18: a named probe run drawn under
  "Screen one posting". "Apply next job" now takes the apply step's name.
- Decided, from design:design-critique on that capture: under a step the run
  header drops the repeated "Job Search: <step>" name and the run sits in a
  light tinted box, so the next step does not read as more of the run.
  #7 squash-merged before these landed on its branch; they are PR #8.
- Found: driving the window. `open -a "claude spinner"` reopens it (the
  status item click opens nothing scriptable); the AX tree has 0 elements, so
  select a sidebar row by activate + AXRaise + click in one osascript, or
  Chrome/Ghostty above it take the click.

- Decided: the App Kit tab's "selection moves after launch" is NOT
  reproduced, so no fix was written. Seen twice on 2026-10-02 (TrackList
  Solo -> Nights, SidebarList Home -> Songs). A logging build (`onChange` on
  both selections, with call stacks) was installed and driven three ways:
  AX `AXSelected` on the App Kit row, a real mouse click on it, and arrow
  keys from Home with the app verified frontmost. Zero selection changes in
  10s each. The logging was proven live by a control click on "Albums"
  (logged `nav Home -> Albums`). The two sightings came from sessions that
  were also driving the window with AX and CGEvent clicks, so test tooling
  is the leading suspect, but that is not shown. Neither list takes arrow
  keys unfocused. Re-add the logging if it recurs during normal use.
- Decided: a form ask (several questions, or a multiSelect) waits in the PreToolUse hook
  when the terminal is behind, and the app returns every answer as `updatedInput.answers`.
  Single-select stays non-waiting with the digit. Observed live (scratch tmux session,
  installed `ask.sh`, app from `./run.sh`): a "2 questions" card with no Allow/Deny card
  and Send answers disabled until both had a pick; Green + Ham + Corn sent; the session
  received `"Pick a color?"="Green", "Pick toppings?"="Ham, Corn"` with no terminal box;
  no ask or answer file left. "Answer in terminal" drew the terminal box and removed the
  file. A single-select control kept the old card, a non-waiting ask file and the digit
  click. With the real `lsappinfo`, a form returned at once when the host was frontmost
  and waited (then cleaned up on timeout) when it was not.
- Decided: `ask.sh permission` exits for AskUserQuestion. The Allow/Deny card for a question
  asked nothing and held the real box back.
- Decided: an unknown frontmost app counts as "terminal front" in `ask.sh`, so a form
  falls through to the terminal box instead of holding it for 300s. Only
  `__CFBundleIdentifier` is compared (`TERM_PROGRAM` is "tmux" under tmux, not a bundle
  id). A form reply must answer every question, with strings, or it prints nothing.
  Found by `shell-reviewer`; each has a test that fails on the previous script.
- Known limits: a multi-select answered with nothing ticked, and "Other" free text, are
  terminal-only ("Answer in terminal"). The card's "Answered: ..." line was not caught
  on screen (it cleared inside the wait), and `design:design-critique` /
  `design:accessibility-review` were not run on the form card.

### 2026-10-02 (earlier)

- Decided: auto-merge switches itself on from the watcher, not the Git card,
  so it covers every live session and not only the selected pane (`6a85728`).
  The once-per-PR claim lives on the watcher and the card asks the same set,
  so the two cannot both fire. The watcher ticks every 60 s; the card, when
  shown, still gets there within 5.
- Seen: the watcher path, on docs-only PR #6 staged like #5. App relaunched
  13:41:06, PR read null at 13:41:23, `auto_squash_enabled` at 13:42:10, one
  tick after launch. Window captures at 13:41:36 and 13:42:11 both show Job
  Search, so the card for this session was never on screen. Turned off by hand
  at 13:42:23 and it read null 137 times through 13:44:38, past the 13:43:06
  and 13:44:06 ticks: a hand-off sticks. This also settles the open question
  on #5 only for the new path; whether #5 fired by itself stays unseen.
- Removed afterwards: PR #6 closed unmerged, branch deleted, protection on
  `main` deleted again (read back "Branch not protected").
- Seen: auto-merge came on for a real open PR. Staged on this repo: `test`
  made a required check on `main`, and docs-only PR #5 opened from
  `probe/auto-merge`, which the path filter in `swift.yml` never runs `test`
  for, so the check stayed pending. `autoMergeRequest` read null from 13:22 to
  13:30:43 while the window sat on Home and then Job Search, and the PR
  timeline shows `auto_squash_enabled` at 13:31:17 (SQUASH, by danieldecena).
  Not seen: the Git card itself. Window captures at 13:31:06 and 13:31:26 both
  show Job Search, so the session row was selected and left inside those 20
  seconds, and GitHub cannot say whether the switch fired by itself or was
  flipped by hand through the dialog. No hook or script here runs
  `gh pr merge --auto`; the app is the only caller.
- Found: the card polls only while its session is the selected pane, so a PR
  nobody is looking at never gets auto-merge. Same limit as 2026-09-30. Fixed
  the same day, see the Decided entry above.
- Removed afterwards: auto-merge off, PR #5 closed unmerged, branch deleted,
  protection on `main` deleted (read back 404 "Branch not protected"). Left on,
  the required check would have blocked every docs-only PR, since `test` never
  runs for them.
- Found: `main` was red on CI from `aa0f514` (run 37036052579, 1 of 398) while
  this file said nothing was broken. That commit and `e0a9e34` after it came
  from outside the Claude sessions here (no trailer, no log entry), so nothing
  recorded them. The failure was the transcript size cache: it matched on path
  and size only, so reading one file twice with different tail lengths returned
  the first answer. Fixed in `1b85964` by putting the tail length in the key.
  Production callers all pass the default tail, so nothing on screen was wrong.
- Found: the Graph card had not drawn for any repo since `867d5ca`. That commit
  turned the card's if/else into a `Group` holding only the `if`; an empty
  Group is no view, so the `.task` that reads the file had nothing to attach to.
  The reload it was fixing stayed "unobserved" because there was nothing to see.
  Now an empty `VStack`, which is a view, keeps its identity, and measures zero
  for `TileGrid.pack` to skip.
- Observed 11:25: the card reloads on a switch. claude-spinner 2,174 nodes /
  5,118 edges, app-kit 188 / 216, home 357 / 369 with its "Built at" line, each
  equal to its `graph.json`, both directions, twice. The no-graph case was seen at
  11:54 on a session with no folder at all: no Graph card, and Usage ends the
  pane at the normal margin with no bare row under it.
- Decided: drive the sidebar through the accessibility tree, not coordinates.
  `AXUIElementSetAttributeValue(row, kAXSelected, true)` selects a row, and the
  row is found as the one under the section header whose text starts with the
  project name, so recency reordering does not matter. AppleScript's
  `entire contents` returns 0 for this window; walk `AXChildren` instead.
- Found, fixed in `6853d0a`: the sidebar's TASKS rows were wrong across sections
  (`ForEach(id: \.offset)`; the id now carries the file's path). Afterwards each
  section's rows equalled the open items of its own TASKS.md. With app-kit,
  claude-spinner and home live, claude-spinner (4 open) listed app-kit's three
  titles then its own fourth, and home listed the same three, then
  claude-spinner's fourth, then its own fifth. Counts in each header were
  right. Row N of every section shows whichever section drew row N first, which
  is what colliding row ids across sections look like.
- Found, fixed in `ab31236`: a short pinned page stopped mid-window. `e0a9e34`
  moved the pane to scale-to-fit and swapped the frame's `minHeight` for a
  vertical `fixedSize`, so the grid was no longer proposed a height and the
  2026-10-01 "last row takes the slack" rule had nothing to hand out. The page
  is at least the pane's height again, inside the fixed size.
- Observed 11:30 and 11:31: Plans before (blank from mid-window down) and after
  (Recent Sessions and the rail reach the bottom edge). Job Search already
  filled and is unchanged. The title is not clipped at the top on either, which
  is the look `e0a9e34`'s `ignoresSafeArea` move had not had.
- Reviewed 11:47-11:52, Job Search pinned page, both skills run:
  `design:accessibility-review` found the thumbnails exposing whole web pages
  to assistive tech (6 web areas in the tree, several hundred elements, none
  operable); fixed in `9347165`, tree now holds 0. It measured `label` #98989D
  at 5.93:1 and `attention` #73B2FF at 7.73:1 on the card's #1C1C1E, both over
  4.5. `design:design-critique` found Recent Sessions' Resume buttons a long
  way from their titles at full width; putting Skills beside it in one column
  was tried and reverted, because 17 chips stack one per line there and push
  the page into scrolling. Left as is. It also noted the artifact row leaves
  the right half of its row empty, which is the size that was asked for.
- Found, fixed in `e6fca07`: the app used 34 to 40% of a core whenever a session
  was working, whatever pane was showing and with the window off screen. A
  `sample` put 56% of the main thread in `NSStatusItem _updateReplicants`: the
  system keeps a bitmap of the status item per menu bar and redid measure,
  layout and render of the hosted SwiftUI label for each, every spinner frame.
  The label is now the button's attributed title (`MenuBarTitle`). Replicant
  work is 20% of the main thread; the app reads 11 to 14% with no window.
  Tried first and discarded: `sizingOptions = [.intrinsicContentSize]`, which
  removed the min-size calls and changed nothing.
- Measured, no change made: with the window on a session pane the app read 26
  to 31% in one run and 15 to 21% in the next (12:12). In that sample the app's
  own functions are under 2% of the main thread; the rest is AppKit and Core
  Animation committing the window at the spinner rate. There is no single view
  to blame. The remaining menu-bar cost is the per-bar bitmap
  capture, which only a lower frame rate would cut; the rate was left at 10.
- Status items own no window on this macOS, so the label is captured by the
  rectangle accessibility reports for `menu bar item 1 of menu bar 2`, which
  holds only that item.
- Decided, `d83d19a` and `b44955a`: the build carries no warnings. A clean
  build printed 152, every one the default main-actor isolation being wrong
  about something: the test target lacked the setting (73), and pure namespaces
  and value types were used off the main actor (77). Each now says
  `nonisolated` at the type. A new warning is therefore new, and worth reading.
  The plan and what actually happened are in
  `docs/superpowers/plans/2026-10-02-swift6-isolation-warnings.md`.
- Found: CI's log under-reports warnings. The self-hosted runner builds
  incrementally, so its log named 117 of the 152. Count from
  `xcodebuild clean build-for-testing`.
- Found: `nonisolated` on one function only moves the warning to whatever that
  function calls. Mark the type.
- Not seen on screen: the Skills card's pick line after its `Text +` became an
  interpolation. No session was showing a pick. Rendered offline with
  `ImageRenderer`, old and new are byte-identical and a changed string is not.
- Found while debugging a "missing" window: it was never closed. A window on
  another Space drops out of both `CGWindowList` on-screen and the AX windows
  list, and comes back when the app is frontmost. `.optionAll` with
  `kCGWindowIsOnscreen` tells the two apart. Not an app defect.
- Decided (Daniel, mid-session): artifact cards are a quarter of their size and
  come first. `88b148b`: 170pt wide with a 72pt thumbnail, in one row at the top
  of a pinned page, summary on hover. Seen 11:35 on Job Search. This also
  removed the two half-empty artifact rows at the bottom of that grid. The
  Career Hub pop-out button in Next Up is now the middle of three small buttons
  in the second card of that top row.
- Found, fixed in `0e2f87e` (Daniel asked for a review of the card preview): at
  quarter size the preview was a crop, not a thumbnail. `pageZoom` shrinks the
  outer claude.ai page but not the artifact's own frame, so 138x72 held a
  toolbar, two scrollbars and one heading. Now the web view is laid out at 4x
  the box and drawn with `scaleEffect(0.25)`; seen 11:40, each card shows its
  page's heading, tabs and tiles. Three live web views at 552x288 each is the
  cost; not measured.
- Observed 11:38: the Career Hub pop-out opens and is signed in. Pressed the
  second card's "Pop out to a floating window" with `AXPress`; a floating
  window titled Career Hub appeared (982x846) showing the Application center
  with the account avatar and "Artifact by you", and the card switched to its
  "Open in its own window" placeholder. Closed again afterwards. So this was
  never blocked on a person, only on clicking by coordinate.
- Fixed in `67d1392`: in the pop-out, the window's traffic lights sat on the
  page's own top-left corner. The panel no longer uses a full-size content
  view; seen 11:45, the bar holds the window title and the page starts under it.
- Decided, `62fb21e`: `TileGrid(fillsRows:)`. The last card of a row takes the
  columns nothing else claimed; off by default so the session and Home panes
  pack as before, on for the pinned page. Seen 11:43 on Job Search (Recent
  Sessions and Skills full width) and 11:45 on Plans (Start full width). The
  unused `shift` went in the same commit.
- Rule for captures from here: `screencapture -l <window id>`, never `-R`. A
  region grab at 11:43 took in another app's window that overlapped the pane;
  those files were deleted unread beyond the one look. The id comes from
  `CGWindowListCopyWindowInfo` filtered on the owner name.
- Measured about 12:23 (written here first as 12:35, a time nobody read off a
  clock), the web views behind the artifact thumbnails: 291 MB outside
  the app's own 90 MB. `footprint` on the five WebKit processes whose
  responsible pid is the app (`responsibility_get_pid_responsible_for_pid`):
  three WebContent at 78, 78 and 105 MB, GPU 20 MB, Networking 10 MB. One
  sample, about four minutes after launch, of `/Applications/claude
  spinner.app`; which page each process held and whether the pinned page was on
  screen were not looked at, so this is the cost of three views existing, not
  of a known state. `ps` RSS reads 5 MB for the same processes and is the wrong
  number to quote.
- Found: CI only runs on pushes touching the app, project or test directories
  (`paths:` in the workflow), so doc-only commits such as `62ba3a7` and
  `e105526` get no run and `gh run list --limit 1` shows an older commit.
- Decided (Daniel said go): an artifact card draws a picture of its page, not
  the page. The web view loads as before, and five seconds after the load
  finishes its snapshot replaces it and the view is dropped. The picture is
  kept per URL and per appearance for the life of the app, and thrown away
  when the card is expanded or popped out, since the page is about to change.
  Seen 12:33 on Job Search after a relaunch: three WebContent processes and
  374 to 416 MB at 2 to 3 s, none and 16 to 19 MB (GPU and Networking only) by
  15 s, with all three cards still showing their pages. 401 tests pass.
- Found (fixed below): in 4 of the 8 loads that reached the page, one of the
  three web views outlived its picture, holding about 115 MB. Left alone it
  went at about 128 s; leaving the page and returning also cleared it. All
  three pictures were already in place, so it is a removed view something
  still holds, not a card that failed to snapshot. What holds it is not known.
- Not observed: the picture being retaken after Expand or pop-out, or after
  the appearance flips. Pressing the card's buttons through System Events
  found no buttons this session.
- Three relaunch trials read 0 web processes of any kind and were thrown out:
  sidebar row 3 is Job Search only when no `home` session is listed, and the
  trial script did not check which row it had selected.
- Fixed, 13:12: the page is closed (`_close`, private, as `drawsBackground`
  already is) the moment its picture is taken. 10 of 10 loads ended with no
  WebContent process at 17 s, each load first checked to have shown three;
  cards still draw their pictures, no crash report, 401 tests pass. The
  holder was never found, so the view itself may still outlive its picture;
  it just has no page behind it. Three guesses were built, measured and
  thrown away first, each on loads checked the same way:
  - the view refusing first responder (`leaks --traceTree` showed AppKit's
    `_NSAutomaticFocusRingState.previousActiveFirstResponder` pointing at
    it): 7 of 10 still lingered, and the trace still showed that reference;
  - loading an empty page after the snapshot: 6 of 6 lingered and the empty
    page still held 49 to 103 MB; `stopLoading()` instead: 8 of 8;
  - one debounced snapshot task in case a second finish left a snapshot
    waiting on a removed view: 4 of 8, the same as doing nothing.

