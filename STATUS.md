# STATUS

## Confirmed working

- The window detail pane carries the whole statusLine payload, not the eight
  fields the app used to decode: spend (labelled api-equivalent, since nothing
  here is billed on a Max plan), wall vs API time, lines changed, context and
  window size, prompt-cache hit ratio and warmth, effort, thinking, model id,
  Claude Code version and repo. An overview strip totals them and leads with the
  5h/7d rate-limit windows, which are the only numbers that can actually stop a
  Max session.
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

1. [code] Watch the Career Hub pop-out open (floating mini window, frame remembered). Not
   seen yet: the embed rendered, but Daniel was mid claude.ai sign-in inside it.
2. [code] Menu panel lists `AGENT-<id>` sections with 0 sessions (seen in an offscreen
   render 2026-09-30); find where subagent feeds become project groups.

The rest is in `TASKS.md`.

## Decision log

### 2026-09-30 (goal chip, real last prompt, panel type, spend history dropped)
- Decided: the goal chip is tinted (`series1`, attention when landing) with a flag; in
  label grey Daniel asked where it was twice. A missing deadline file is re-read in
  10s, not 60s. Seen on screen: "GOAL 113 min left".
- Decided: "you asked" prefers the newest typed prompt (a non-meta user record, a
  `/cmd args` command, or a human `queued_command` attachment) over Claude Code's
  `last-prompt` record, which kept re-appending "/compact" after `/goal 120` and three
  questions. Screenshots put the real prompt 2 MB back, so `PromptTracker` walks back
  once (1 MB chunks, 16 MB cap) and then reads only appended bytes, stopping at a
  newline. Four new tests, each mutation-checked.
- Decided: attention stays Spinner blue (the audit's reason: kit warn blurs with clay).
  The menu panel moves to kit type the window's way: chrome on `Font.ui`, gauge figures
  on `Font.figure`, session rows stay Menlo because their columns are measured in it.
  Seen in an offscreen render of `MenuContentView`.
- Decided: `spendHistory` dropped (no reader since the Cost chart went); the app clears
  the stale defaults key on launch.
- Decided: the pinned dashboard's title sits above its ScrollView; inside it, the
  title slid under the toolbar strip and drew cut off. Seen fixed on screen.
- Observed: Plans pin and the plugin skill chips on screen (Job Search tab, 08:32).

### 2026-09-30 (notarized)
- Decided: `./notarize.sh` ships a Developer ID signed, notarized, stapled copy to
  `build/notarized/` (archive -> developer-id export -> `notarytool --keychain-profile
  notary` -> staple). First run Accepted; spctl `source=Notarized Developer ID`. It
  does not install: `run.sh` stays the Debug dev loop, and the export drops
  `get-task-allow`. Supersedes the 2026-07-21 "no paid account" reason for ad-hoc signing.

### 2026-09-30 (Job Search dashboard, Career Hub, goal sign, one-surface window)
- Decided: questions no longer block. ask.sh writes a non-waiting ask (`waits:false`,
  `session_pid`) and returns, the terminal draws its box, and a card/banner click types the
  option's digit into the pane. The ask drops once the state leaves AskUserQuestion or the
  session pid dies. Probe: box drew at once; clicking Green answered it. Installed
  (`~/.claude` fa1e498).
- Decided: card options arm 0.8s after appearing (the stray-click "Red" answers), carry
  accessibility labels, and the needs-you banner is pulled once resolved.
- Decided: the window has no title bar or traffic lights; content runs to the top edge.
- Decided: a pinned Job Search tab (`~/developer/job search`) is a tile-grid dashboard:
  launch (New session, Apply next job), tasks, recent terminal sessions with Resume,
  skills, schedulers, workflows, and each artifact as a live card. Recent sessions keep
  only `entrypoint: cli` transcripts; `sdk-cli` and `claude-desktop` ran 58 to 2.
- Decided: Career Hub embeds via WKWebView on the default persistent store (the URL is
  403 without a claude.ai session), Safari user agent, Pop out = floating NSPanel per URL.
  The Desktop project's "Career Hub sync" task is server-side and cannot be listed.
- Decided: an artifact card is a one-column tile: icon, rounded 15pt title, host, the
  note's first sentence, and the page at 0.75 zoom faded at the bottom (clicks expand, never
  land inside). Expand replaces the dashboard with the page filling the detail pane, with
  a back chevron (Esc); Pop out opens the mini window. Seen: the full-pane view with live
  Career Hub data. Not yet seen: the redesigned collapsed tile (Daniel was using the pane).
- Decided: goal sign beside the You asked title reads `~/.claude/state/goal-deadline-<pane>`;
  landing tint at the 10% reserve; untimed goals and non-tmux sessions show nothing.
- Gotcha: a copied `/bin/sh` renamed `claude` is killed on launch (137); a symlink works.

### 2026-09-30 (probe "auto-answer" explained)
- Decided: nothing auto-answers asks. Every probe "Red" (06:25:29, 06:25:50, 06:26:29,
  07:26:05) is a physical click: WindowServer logs an internal-trackpad button down/up
  7-15ms before the app's `sendAction:` burst, and the ask card's first option was under
  the pointer. Control: Daniel's deliberate Blue click (07:27:53) has the identical
  signature. No banner response was logged for any of them. The card appears ~3-5s after
  the tool call, so a click meant for something else lands on option 1.
- Decided: the 06:25 "app stopped" probe was not stopped: LaunchServices relaunched the
  app 2s after `killall` (pid 39644, `launchedByLS=1`). Relauncher not chased.
- Decided: in the terminal box, a digit key selects that option immediately (sent "2",
  got Green, no Enter). `↑/↓` + Enter also works per its footer.
- Gotcha: in this zsh `log` is a builtin; `log show` silently prints nothing. Use
  `/usr/bin/log`. Earlier "unified log unreadable" was that, not a permission.

### 2026-09-30 (refused /compact seen live)
- Decided: the refused-/compact report is confirmed on screen. A one-exchange session
  does NOT refuse (it compacted); the refusal needs an already-compacted session, so the
  probe was: one exchange, Compact, Compact again. Second press printed the refusal in
  the pane, wrote the `local_command` line, and the app showed it under the reply field.
  Side note, not chased: the compaction left "1 finished" under the probe's row.

### 2026-09-30 (refused /compact; Tasks card; + new session)
- Decided (feature 11, Daniel chose the rule): finished subagents count for 30 minutes
  after they finish (`SubagentSplit.keepFinished`), replacing the turn-based rule that
  could not work. Seen: "4 finished" against feed files aged 3, 20, 20, 21 min, with six
  older ones (59-73 min) dropped. 320 tests pass.
- Decided (feature 10): "+N more" under a project's tasks opens its TASKS.md, and
  "N finished" is a chevron that lists the finished subagents in place. Seen on screen
  (expand and collapse). Feature 11 as designed does NOT work and is off: counting only
  subagents finished since the parent's `turnStart` hid the one that had just finished,
  because a background subagent's completion notice starts a new parent turn (observed:
  child done at 1790777494, parent turn_start 1790777520). `SubagentSplit(since:)` stays
  tested but unused at the call site until a rule is chosen.
- Decided (cleanup 7-8): deleted the chart code the ring-only cards orphaned
  (`Buckets`, `Columns`, `TrendColumns`, `WeekChart`, `SpendChart`, `UsageChart`,
  `ContextChart.ceiling`, `UsageTotalsPoller.weekBars`, the detail pane's history and
  spend inputs) and their 10 tests; 385 lines, 319 tests pass. Kept `Sparkline`,
  `ContextChart.unitPoints`/`bandFloors` and `ContextMeter`, which the menu panel uses.
  Left: `FeedWatcher.spendHistory` still records to UserDefaults with no reader (task).
- Decided (fixes 4-6): the window's Usage card takes only what it draws (the ccusage
  poll stays; the menu panel shows its totals). Context colour follows share of the
  window wherever a window is known (`Color.contextTint(tokens:window:)`: window ring and
  meter, menu row); the menu's heavy-scaled spark keeps token bands. Below the 0.55
  floor the pane scrolls instead of clipping. First version swapped a plain pane for a
  ScrollView and flip-flopped: the two structures measured different ideals (510 vs
  ~680, found with a file probe) and it settled clipped. Now one ScrollView always, with
  scrolling disabled when it fits. Seen: 392pt tall scrolls to the stats row; 977 fills.
- Decided (logic fixes 1-3): pace is not judged in the first 5% of a limit window
  (`StatFormat.aheadOfPace`; 1% just after a reset read "ahead of pace"); the /simplify
  pick uses the uncommitted diff size (`GitSnapshot.dirtyLines` from `git diff HEAD
  --numstat`), not the session's lifetime line count; Claude said re-reads an 8x tail
  (2MB) for that one field when the 256KB tail holds no assistant text (tool output had
  pushed it out). 329 tests pass; seen: 2% 5h ring "within pace" after a reset.
- Decided (critique slice 3): Skills shows one line while the session works (git buttons
  stay); History rows carry the commit subject and drop `origin/HEAD`; finished
  subagents collapse to "N finished" (`SubagentSplit`); the section header reads
  "1 session · 562k"; task rows are bullets; the no-open-PR caption hides only when that
  is the sole reason (`GitAutomation.autoMergeLacksOnlyAPR`); Interrupt, Compact and
  Clear are labelled. Verifier found an expanded-reply fit gap (the opened card took no
  `extra`) and the caption hiding gh-missing; both fixed. 326 tests pass; seen on screen.
- Decided (critique slice 2): Claude said fills the You asked card (a flexible block with
  a 4-line ideal, cut to what fits; the chevron still opens the full text), and when the
  pane fits at full size the leftover window height goes to both top-row cards, so no
  empty band sits under the last row. The math is `PaneFit.fit(available:ideal:)`, pure
  and unit-tested. Seen on screen at 1243x977 and 1000x760.
- Decided (critique slice 1): spend is a plain figure, not a ring (the arc was API share
  under a dollar label), and the context ring is tinted by the share its arc draws
  (`usageTint`), not by token count (`contextTint` made a half-full ring red). Seen on
  screen: 53% context ring yellow, spend "$33.46" with no ring.
- Decided: the reply row (field, Send, model and effort menus) is pinned to the foot of
  the You asked card; the exchange stays at the top. Seen on screen.
- Decided: the Usage card is the two limit rings only; the All sessions totals (today,
  week, block) and the api-equivalent and live-session footer lines are hidden (Daniel:
  "maybe hide this data"). The ccusage poll and `OverviewStrip.split` stay for when
  they come back.
- Decided: the detail pane does not scroll. It is laid out at its natural height and
  drawn smaller to fit the window (`fitScale`, floor 0.55), laid out at the window's
  width divided by the scale so the cards use the room shrinking frees. Below the floor
  the bottom is clipped, not scrolled. Seen at 1143x1068 (scale 1, everything visible)
  and 1000x760 (scaled, everything visible). History is 360pt wide, not the row; Skills
  is 380pt. The sidebar is not scaled.
- Decided: the History and Git row is redesigned. Refs sit beside the SHA on the
  commit's own line (every graph row is one line; the stacked-refs rule from aaceb05 is
  reversed), and the Git card's four status rows are pills that wrap. Seen on screen.
  Daniel's request was the single word "redesign" after a screenshot of this row.
- Decided: the two stat cards are circles only for now (Daniel: smaller, lighter,
  compact). Rings are 52pt with a 5pt stroke; the column charts (context, spend,
  tokens by day, 5h usage) and the facts line are out of the cards. `Columns`,
  `TrendColumns`, `WeekChart`, `Buckets` stay in StatCards.swift, unused and
  unit-tested, for when a chart comes back.
- Decided: the You asked card is the last exchange plus one row: You asked (2 lines),
  Claude said (4 lines), a dim "ran ..." line, and the reply field with the model and
  effort menus beside it; a chevron opens the text out. Dropped: the Show more button,
  the divider, the thinking/style/version facts, and the reserved block heights that
  left a hole under a short reply. History rows tightened from 20pt to 17pt. Seen on
  screen. Daniel's screenshot for this request did not come through, so the target
  was his answer "you asked card" plus the History card he pasted as too spaced.
- Decided: skill, superpower, git and git-skill buttons are content-width chips that
  wrap (`ChipFlow`), not equal-width grid cells. Seen on screen.
- Decided: Git status and Automation are one card (300pt wide) with the four
  switches in one row, name under each (Merge PR, Push main, Commit, Open PR);
  the disabled reason and Auto-fix CI sit under the row. Seen on screen.
- Open: Daniel wants AskUserQuestion boxes in the You asked card as well as the
  terminal (choice: card and terminal both). Not built: which keys the terminal
  box accepts is unverified (probe sessions auto-answered "Red" before a box drew),
  and the auto-answer itself is unexplained.
- Decided: the window follows App Kit (audit of 2026-09-30, Daniel chose "everything
  including type"). Type: SF at the kit's 11pt floor via `Font.ui` (9 and 10 -> 11,
  11 -> 12, 12 -> 13) and `Font.figure` (rounded) for figures; Menlo stays only for
  terminal echo (session names and glyphs, the reply field, transcript prose, ask
  command text, shas, refs, branch name, StatSection values). Colour: pane is the
  kit's `ground`, cards its `surface`, `label` its `ink-soft`. Charts: columns are
  `chartBase` grey with only the latest column coloured (heat band for context and
  5h usage, `series1` for spend); cache and spend rings use `series1`. Spacing: card
  padding 16, grid gap 12, page and sidebar inset 20, radii 10 and 6. Send is a
  tinted capsule. Seen on screen; 319 tests pass, with a pane contrast test added.
- Decided: NOT done from the audit: attention -> `warn`. Spinner's blue "needs you"
  and clay-orange "working" are a deliberate pair; the kit's warn (#C73300) sits next
  to clay and would blur them, and the kit's answer (working = accent blue) inverts
  the palette. Also not done: renaming `usage*` to `heat*` (same values, churn only)
  and the menu-bar panel, which still uses Menlo at 9 to 11pt.
- Decided: the repo's open TASKS.md items are listed in the sidebar under their
  project (5 shown, then +N), read from the nearest TASKS.md at or above the
  session's folder; the Tasks card is gone and /todo is a chip in Skills. The
  panel-less read is not selectable.
- Decided: the git buttons and git skill chips live in the Skills card under a Git
  label, and the Automation switches sit in their own card under the Git status
  card; the Git commands card is gone. History takes the width it freed. Seen on
  screen. Bucketing now clamps a timestamp before the first sample into the first
  slice (a verifier found it trapped; the writers never produce one).
- Decided: Cost, Prompt cache, Session, Context and Usage became two cards,
  This session and Usage, in `StatCards.swift`. No horizontal bars or lines:
  ratios are rings (a tick on the limit rings marks the window's clock), history
  is one column per time slice (`Buckets`, unit-tested). Seen on screen; 317 tests
  pass. Left behind: `SpendChart` and `UsageChart` enums are now used only by
  their tests.
- Decided: subagents are listed in the sidebar under their parent session (dot,
  type, status), not as a Subagents card at the bottom of the detail pane; the
  tree drawing is deleted. Rows are not selectable: a subagent has no pane.
  Seen on screen with two live subagents.
- Decided: the Skills card no longer picks /wrap-up on token count (150k) while
  the session is mid-turn; it waits for the prompt. At 85% of the window it still
  picks it regardless. Seen: it read "160k tokens re-read" on a working session
  at 16% of a 1M window. Unit-tested; 313 pass.
- Decided: Auto-merge PR switches itself on, without the dialog, the first time
  a PR is open and eligible, once per PR (a hand-off keeps it off after you turn it
  off). The other three toggles stay manual; Daniel chose auto-merge only. Built,
  not observed: no open PR with GitHub auto-merge allowed to test against.
- Decided: Config is two rows (model and effort menus, then thinking, style and
  version on one line) with no title. Toolbar action notices (copy, reveal,
  interrupt, compact) now show in the conversation card under the reply field,
  cleared on a new selection. The window no longer shows the idle age line above
  the cards; the menu panel keeps it. Seen on screen except the action notice,
  which a Copy session id click did not raise (a local action succeeds silently).
- Decided: You asked, the reply field and Config are one card in the top row
  (exchange, reply, then a Config subsection). The toolbar keeps only the
  sidebar toggle and session actions; a reply's notice shows in the card.
  Seen on screen.
- Decided: the sidebar is a card (`Color.card`, radius 14, the detail pane's
  14pt inset, mono project headings) instead of a clear glass panel. The glass
  took the desktop's tint and matched none of the cards beside it. Seen on screen.
- Decided: a `/compact` Claude Code refuses ("Not enough messages to compact.")
  ends the wait on the transcript line it writes (`system`/`local_command` with
  `commandRun.command == "compact"`, which a compaction that ran never writes),
  and shows those words, instead of running out the 180 s state-file wait.
  Unit-tested on a real refusal line; not yet seen against a live pane.
  `4dc133b`.
- Decided: a Tasks card lists the repo's open TASKS.md titles (8, then +N) with
  open/done counts, and holds the /todo chip, which is what writes the file.
  You asked | Tasks | Skills share the top row. Seen on screen against
  claude-spinner and save-full-page. The one-line You asked in that narrower
  column is assumed to show its full text on hover; unchecked. `dc9231f`.
- Decided: + beside a Sessions heading starts a session in a project from
  `~/.claude/project-registry.json` (the `ws` list, missing and third-party
  dropped): Ghostty AppleScript opens a window in that folder running
  `zsh -lic claude`, so the user's `claude` function supplies the tmux wrapper
  the app needs to reply. Chosen over a headless tmux session so the session
  is visible. Seen end to end: claude-launch-71495 came up and joined the
  sidebar. `aed4987`.

### 2026-09-30 (git card: buttons back, bundle remotes, auto-merge, visibility)
- Decided: Push/Pull/Merge and the PR buttons are always drawn, dimmed with
  their reason when idle; hiding settled ones (earlier the same day) made them
  look missing. "Nothing to do" still shows when every action is settled.
  `db72288`.
- Decided: a remote that is a `.bundle` file settles push and the gh actions
  (`~/Tools/osmo` offered Push and every push failed). `a227481`.
- Decided: the probe reads GitHub's `allow_auto_merge` and `private` in one
  `gh api` call; the auto-merge switch prints its blocker under itself, and the
  branch row shows a private/public badge. nil (not GitHub, read failed) draws
  nothing. `25eb382`, `cd8f332`.
- Decided: the skill pick also fires on absolute context size, 150k -> /wrap-up
  and 100k idle -> /compact, since a 1M window put the 60% rule at 600k.
  `1be4599`. All observed on screen.

### 2026-09-30 (skill pick covers the common idle states)
- Decided: most sessions matched no pick rule, so the Skills card outlined
  nothing and read as broken. Added an idle session with open todos -> /goal,
  and idle 10m+ with changed lines, clean and in sync -> /wrap-up; when still
  nothing fits the card says "No skill needed right now." Observed both the
  caption (working session) and the wrap-up outline (osmo, idle 11m). `4bb1971`.
  Git skill chips also hide with no snapshot (non-repo). `c69294e`.

### 2026-09-29 (chip confirmation observed; idle git actions hidden)
- Decided: the Git commands grid now honours `GitActions.Block.settled`
  (hide a finished "nothing to do", keep unsettled ones greyed), and git
  skills with an idle reason hide too, with one line when nothing is left.
  A clean pushed main read as a dead card. `569804c`, observed on screen.
- Observed: compact chip on a throwaway tmux session. Dialog opens, Cancel
  sends nothing, Compact delivers (the test session's transcript has `/compact`
  at 06:50:34Z and nothing during the Cancel). Counting `❯ /compact` lines in
  `capture-pane` is not a delivery check: Claude Code redraws and the count
  stayed 1 across two real sends. Read the transcript instead.

### 2026-09-29 (/compact and /clear chips in the Skills card)
- Decided: both were reachable only as toolbar icons; the Skills card now
  carries them after `wrap-up`. `SkillShortcut.sessionAction` maps a chip to
  the toolbar action typing the same text, so the chips reuse its symbol and
  its confirmation rather than restating either. `5fca153`.
- Observed: 292 tests pass, including `testDestructiveShortcutsConfirm`. The
  window captured by id at 20:35 shows both chips, greyed because the session
  was mid-turn. Not observed: the dialog itself, since clicking needs an idle
  real session and a slip clears it.

### 2026-09-29 (todo bar fed from TaskCreate lists; sidebar toggle observed)
- Found: the todo bar could never draw on a Claude Code build that has
  TaskCreate/TaskUpdate instead of TodoWrite. `emit.sh` only counted
  `.tool_input.todos` on a TodoWrite PostToolUse, and TaskCreate carries one
  task, not the list.
- Decided: read `~/.claude/tasks/<session_id>/*.json` (one file per task, with
  `status`) on every root event, after the TodoWrite branch. Every event, not just
  after a task tool, because that list outlives a turn and the per-prompt
  reset would otherwise blank the bar until the next task call. Root only:
  subagents share the parent's session id and would inherit its list. One jq
  call, assigned only on success, so a file caught mid-write keeps the
  carried-over counts (shell-reviewer finding).
- Observed, script: against a scratch HOME -- tasks 3/1, no dir null, empty
  dir null, subagent null, TodoWrite 2/1, half-written file keeps 3/1 with
  empty stderr. Live: this session's state file read `3/2` at 20:31:04,
  matching its task panel.
- Observed, screen: Session card `todos 2/3` with the green "todos done" bar
  (20:31:10); sidebar hidden in that frame, shown after a click on the toggle
  (20:31:26, System Events named the hit as button 1 of the app's window).

### 2026-09-29 (spend history and the Cost trend chart)
- Decided: spend gets its own per-session series (`spendHistory`,
  `SpendSample`) beside `contextHistory`, recorded on the same rescan with the
  same rules: unchanged total appends nothing, a change inside the 15s gap
  rewrites the last point, 240-point cap, dropped with the session.
- Decided: the chart's y-axis runs 0 to the session's own peak. Unlike context
  there is no window to be a share of, so any fixed ceiling would be invented;
  the floor stays at 0 so a small rise draws small. The peak is printed at the
  top because the axis differs per session.
- Observed: recording, not rendering. `spendHistory` in the app's defaults held
  two samples for this session ($1.061 -> $1.109, 35s apart) within 40s of
  relaunch. The chart itself is unobserved: `screencapture -l` of the window
  returned a blank frame twice (window parked on another Space).
- Observed: the chart, 20:29:40, once the window was on the current Space.
  Cost card for this session: `$1.77` peak label top-left, the orange line
  climbing with its fill from `3m ago` to `2s ago`, starting about 60% up the
  box as $1.06 of $1.77 should. `screencapture -l` of an off-Space window
  returns a blank frame with exit 0, not an error.

### 2026-09-29 (detail tiles equal per row, not across the grid)
- Decided: the stat grid equalises card heights per row with a custom
  `TileGrid` Layout, replacing the grid-wide tallest-card PreferenceKey. The
  global rule stretched Git and Session to the Context chart's height, half
  empty; per-row keeps every row reading as equal tiles without that dead
  space. LazyVGrid can't do it (cells keep their own height), and six cards
  gain nothing from laziness. Seen on screen: the Git/Session row is now
  roughly two thirds the height of Cost/Context, with no empty band.

### 2026-09-29 (Clear/Compact landing observed live; git action timeout)
- Observed against a throwaway `claude` in a detached tmux pane, keys sent
  exactly as the app sends them: neither `/clear` nor `/compact` fires
  UserPromptSubmit, so the file never reads "thinking" and every working Clear
  or Compact was reported as "never started a turn". `/clear` deleted the old
  sid's files about 0.9s after Enter and a new sid appeared idle; `/compact`
  left the file idle until SessionStart rewrote it about 10s later with
  `turn_start` and `last_seed` null.
- Decided: key the landing check on what was typed (`SessionReplier.Landing`):
  Clear = the pre-send file is gone (15s), Compact = the file changed from its
  pre-send contents to that SessionStart shape (180s, since compaction is a
  model call), anything else = thinking/tool (4s). No baseline means not
  observed. The Swift path was unit-tested on the recorded shapes, not
  re-run end to end through the app's button.
- Fixed: push/pull/merge ran on the status probe's 8s timeout and were
  terminated on expiry; a merge could be killed after GitHub had merged. They
  now get 120s, and the timeout message says the action may have partly run.

### 2026-09-29 (five review fixes: usage chain, banners, probe, AppleScript)
- A read-only bug hunt over FeedWatcher / app / GitProbe found five defects;
  each was re-read against its callers before fixing.
- Fixed: `pollUsage` heads the 5h/7d chain but was never cleared, so turning
  polling off, a 401, or a missing Keychain token froze the last polled number
  over live statusLine values. It is now cleared on stop and on auth expiry, and
  a missing token reports as expired instead of returning silently. Reasoned,
  not observed (toggling it needs the UI).
- Fixed: `notifiedDone` started empty, so a relaunch with notify-on-done on
  bannered every session already finished. The first scan now only seeds it.
  Reasoned: the preference is off here and was left off.
- Fixed: `updateUsageCache` stamped `savedAt` with the scan time every 2s, so
  hours-old numbers read as fresh and overwrote newer poll snapshots. It now
  uses the session's `updated` and never goes backwards. Observed: after
  `run.sh` the snapshot carried the launch poll's fractional stamp, then an
  integer session epoch 21s old, not a scan-time stamp.
- Fixed: GitProbe read its pipe buffers even when the reader threads had not
  finished (a grandchild holding the pipe), returning a partial answer as whole.
  Now nil, which the card renders as unknown.
- Fixed: folder names went raw into AppleScript string literals. Observed with
  osacompile: `a"b` and `end\` fail raw and compile escaped; `plain-app`
  compiles both ways. (The first run of that check compiled an empty file and
  passed everything: the snippet lacked `import Foundation`.)
- Full suite 249/0, run beside the live app.

### 2026-09-29 (window 5h/7d unified; test host exempt from single-instance)
- Decided: the window's overview strip reads `feed.usageFiveHourPct` /
  `usageSevenDayPct` (poll -> freshest session -> cached snapshot), the same
  chain as the menu bar, instead of its own freshest-session pick. Observed
  after `run.sh`: strip `45% of 5h · 47% of 7d`, matching the cached snapshot
  (45/47). The fallback leg (no live session carrying rate limits) is reasoned
  from the shared chain, not observed.
- Fixed: `-only-testing` runs failed at bootstrap ("test runner exited with
  code 0 before establishing connection", exit 65) whenever the installed app
  was running: the test host is a second copy, and the single-instance guard
  `exit(0)`s it. The guard now skips when `XCTestConfigurationFilePath` is set.
  Pair observed beside live pid 40771: with the fix, two single-test runs exit
  0 and the live app survives; with it reverted, exit 65 with that error. Full
  suite 249/0. Something relaunches the app ~4s after `killall` (parent
  launchd, no LaunchAgent or ~/bin script found); source unidentified. It did
  not recur at 15:03: after the full suite's `killall` the app stayed down
  over a minute. BTM shows the login item disabled, and nothing in hooks or
  ~/bin opens the app, so a sibling `run.sh` is the likelier cause (unconfirmed).

### 2026-09-29 (unreadable-remote rendering observed, seeded)
- Observed: the Git card's "couldn't tell" path. A throwaway repo on branch
  `feature`, upstream `origin/feature`, origin `file:///nonexistent/...`
  (`ls-remote` exit 128; `gh pr view` exit 1, "no known GitHub host"), plus a
  fake feed session with that cwd. The card read `remote unknown`, `pr unknown`
  and kept all five actions on screen greyed, each reason printed underneath
  (push: "The remote couldn't be read, so there is nothing to compare
  against."). Screenshot 14:54. The real repo's card in the same window read
  `in sync` / `none` / "no actions available", the settled control.
- Cleanup observed: deleting the fake feed file dropped the row on the next
  rescan (14:54:29 capture).
- Found: the gh failure here was not a network one, yet the card says "GitHub
  couldn't be reached". `prFailure` maps every non-"no PR" stderr to `.unknown`,
  so a non-GitHub remote reads as an outage forever. Harmless on this machine
  (every remote is GitHub); noted, not fixed.

