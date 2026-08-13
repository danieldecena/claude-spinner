# Audit — 2026-08-12

Read-only pass over the repo. Every claim below was checked against `git ls-files`,
`git check-ignore` or the file itself — not inferred from the docs.

## Blockers

- (none) — nothing here stops further work.

## Risks

- [x] `STATUS.md:15` claimed "CI: 57 unit tests green" under `## Confirmed working`,
  which is present-tense state, so it read as current and was wrong. Now 67.
  *Not* touched: the `61/61` at `STATUS.md:140` is inside the dated 2026-07-18
  decision-log entry and was true when written — a log records what happened, not what
  is true now.
- [ ] `graphify-out/` has 24 tracked files (164K) of generated output. Every regeneration
  is a diff, and nothing asserts it still matches the source it describes, so it can go
  stale silently while looking authoritative. Either untrack it (`graphify update .`
  rebuilds it on demand) or accept the churn deliberately.
- [x] The app requires **macOS 27** (`MACOSX_DEPLOYMENT_TARGET = 27.0`) — a hard floor
  stated only in passing in `HANDOFF.md`. Now in `CLAUDE.md` under Build & run,
  alongside a warning not to glob `DerivedData/claude_spinner-*`: two such directories
  exist, and a stale one was launched during verification on 2026-08-12.

## Notes

- **No root `README.md` and no `LICENSE`.** `reset-notifier/` has its own README; the app
  itself has none. The fresh-machine path exists in code (`SetupInstaller` writes the
  scripts and merges hooks into `~/.claude/settings.json`) but is written down nowhere as
  a sequence. Only worth fixing if this repo is ever read by someone other than its author.
- **No Swift lint/format config.** The style is consistent and hand-maintained; adding
  SwiftLint to a solo project with 2.8k lines would be tooling for its own sake. Listed so
  the absence is a decision rather than an oversight.
- **Stray files on disk are all correctly ignored** — `GEMINI.md` (an agy-spinner artifact
  referencing `~/.agy/spinnerfeed/`, not this app) and `claude spinner/.ruff_cache/` via
  `~/.gitignore_global`, `buildServer.json` via `.gitignore:8`. The working tree is clean;
  they are clutter, not risk. `.superpowers/` is untracked too — it is *not* committed
  task artifacts.
- **`.wolf/` is 11 tracked files against 1.6M on disk** — the tracked part is the frozen
  reference kept deliberately (STATUS.md, 2026-07-21); the rest is untracked runtime cruft
  that can be deleted whenever the space is wanted.
- **Credentials are clean.** The OAuth token is read from the keychain at call time
  (`security find-generic-password -s "Claude Code-credentials"`), never persisted, never
  logged. `reset-notifier/check-reset.sh` uses the same path with a `NO_API=1` test
  override. No key, token or endpoint secret anywhere in the tree, including `Scripts/*.sh`
  and the launchd plist (which uses a `__HOME__` placeholder).
- **CI is honest about its constraints.** `.github/workflows/swift.yml` runs a real
  `xcodebuild test` on a self-hosted macOS runner — GitHub-hosted runners cannot open an
  Xcode 27 format 110 project — and `killall`s the app first, without which the
  single-instance guard `exit(0)`s the test host.
- **UI target excluded from the scheme on purpose** (XCUITest cannot launch a menu-bar
  accessory app), matching CI. 2 UI test functions exist but never run.
- **One hand-verification is outstanding**, carried in `TASKS.md`: `windowWillClose`
  restoring `.accessory` with a *placed* status item. Not scriptable — see the 2026-08-12
  decision-log entry for why.
