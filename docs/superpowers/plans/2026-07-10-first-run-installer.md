# First-run one-click installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Install hooks" button to the app's "Setup needed" state that writes the feed scripts and safely merges the spinnerfeed hooks + statusLine into `~/.claude/settings.json`, so a fresh install works without manual config editing.

**Architecture:** Vendor the two shell scripts into the app bundle (auto-included via the Xcode synchronized group). A new `SetupInstaller` enum copies them to `~/.claude` and merges hook entries into `settings.json` (backup first, atomic write). A pure `mergeSpinnerHooks(into:)` function holds the settings logic and is unit-tested. The UI adds a button wired to the installer, using a small `ObservableObject` for state (the codebase avoids `@State`).

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation (`JSONSerialization`), XCTest.

## Global Constraints

- Never clobber existing `settings.json` config: back it up to `settings.json.backup-<epoch>` before writing, and merge (append-only) — never replace arrays.
- Idempotent: re-running adds only missing hook events; never duplicates an `emit.sh` entry; never overwrites an existing `statusLine`.
- Atomic writes: write to a temp file in the same directory, then `replaceItemAt`.
- Home base must match `FeedWatcher`: `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")`. The app is not sandboxed.
- Do NOT use `@State`; mirror the existing `HoverState: ObservableObject` + `@StateObject` pattern.
- Build/test with real Xcode: `xcodebuild ... -scheme "claude spinner"`. Quit any running app copy first (`killall "claude spinner"`) — the single-instance guard would kill the unit-test host.
- Hook entry command path: `~/.claude/spinnerfeed/emit.sh <Event>`. statusLine command: `bash ~/.claude/statusline-command.sh`.

---

### Task 1: Vendor the feed scripts into the app bundle

The scripts exist only in the developer's live `~/.claude`; the app must carry them. The app folder `claude spinner/` is an Xcode synchronized root group, so files placed under it are auto-included — a `.sh` lands in `Contents/Resources/` with no `project.pbxproj` edit (verified empirically).

**Files:**
- Create: `claude spinner/Scripts/emit.sh` (copied from `~/.claude/spinnerfeed/emit.sh`)
- Create: `claude spinner/Scripts/statusline-command.sh` (copied from `~/.claude/statusline-command.sh`)

**Interfaces:**
- Produces: bundle resources reachable via `Bundle.main.url(forResource: "emit", withExtension: "sh")` and `forResource: "statusline-command"`.

- [ ] **Step 1: Copy the live scripts into the repo**

```bash
cd "/Users/home/Developer/claude-spinner"
mkdir -p "claude spinner/Scripts"
cp ~/.claude/spinnerfeed/emit.sh "claude spinner/Scripts/emit.sh"
cp ~/.claude/statusline-command.sh "claude spinner/Scripts/statusline-command.sh"
chmod +x "claude spinner/Scripts/"*.sh
```

- [ ] **Step 2: Build and verify both scripts bundle into Resources**

```bash
killall "claude spinner" 2>/dev/null || true
xcodebuild -scheme "claude spinner" -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2
APP=$(xcodebuild -scheme "claude spinner" -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
find "$APP/Contents/Resources" -name "emit.sh" -o -name "statusline-command.sh"
```

Expected: `** BUILD SUCCEEDED **` and both files listed under `Contents/Resources/`.

- [ ] **Step 3: Commit**

```bash
git add "claude spinner/Scripts/emit.sh" "claude spinner/Scripts/statusline-command.sh"
git commit -m "Vendor emit.sh and statusline-command.sh into the app bundle"
```

---

### Task 2: SetupInstaller with a pure, tested merge function

**Files:**
- Create: `claude spinner/SetupInstaller.swift`
- Test: `claude spinnerTests/claude_spinnerTests.swift` (append tests)

**Interfaces:**
- Produces:
  - `enum SetupInstaller`
  - `static func mergeSpinnerHooks(into settings: [String: Any]) -> [String: Any]`
  - `static func install() -> Result<Void, Error>`
  - `static let hookEvents: [String]`
  - `enum SetupError: Error { case malformedSettings, missingBundledScript }`

- [ ] **Step 1: Write the failing tests for the pure merge**

Append to `claude spinnerTests/claude_spinnerTests.swift`:

```swift
    // MARK: - SetupInstaller.mergeSpinnerHooks (settings.json merge)

    /// Casts the emit.sh command out of a merged settings dict for one event.
    private func emitCommands(_ settings: [String: Any], _ event: String) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
            .filter { $0.contains("emit.sh") }
    }

    func testMergeAddsAllHookEventsToEmptySettings() {
        let merged = SetupInstaller.mergeSpinnerHooks(into: [:])
        for event in SetupInstaller.hookEvents {
            XCTAssertEqual(emitCommands(merged, event), ["~/.claude/spinnerfeed/emit.sh \(event)"],
                           "expected one emit.sh entry for \(event)")
        }
        let statusLine = merged["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "bash ~/.claude/statusline-command.sh")
    }

    func testMergeIsIdempotent() {
        let once = SetupInstaller.mergeSpinnerHooks(into: [:])
        let twice = SetupInstaller.mergeSpinnerHooks(into: once)
        for event in SetupInstaller.hookEvents {
            XCTAssertEqual(emitCommands(twice, event).count, 1, "\(event) must not duplicate")
        }
    }

    func testMergePreservesExistingStatusLineAndOtherKeys() {
        let existing: [String: Any] = [
            "model": "opus",
            "statusLine": ["type": "command", "command": "my-custom-statusline"],
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(merged["model"] as? String, "opus")
        let statusLine = merged["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLine?["command"] as? String, "my-custom-statusline") // untouched
        XCTAssertEqual(emitCommands(merged, "SessionStart").count, 1)             // still wired
    }

    func testMergeOnlyAddsMissingEvents() {
        // SessionStart already wired by hand; the rest are missing.
        let existing: [String: Any] = [
            "hooks": ["SessionStart": [
                ["matcher": "", "hooks": [["type": "command",
                  "command": "~/.claude/spinnerfeed/emit.sh SessionStart"]]]
            ]]
        ]
        let merged = SetupInstaller.mergeSpinnerHooks(into: existing)
        XCTAssertEqual(emitCommands(merged, "SessionStart").count, 1)  // not duplicated
        XCTAssertEqual(emitCommands(merged, "Stop").count, 1)          // added
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
killall "claude spinner" 2>/dev/null || true
xcodebuild test -project "claude spinner.xcodeproj" -scheme "claude spinner" \
  -destination 'platform=macOS' -only-testing:"claude spinnerTests" CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -iE "error:|cannot find 'SetupInstaller'|\*\* TEST"
```

Expected: FAIL — "cannot find 'SetupInstaller' in scope".

- [ ] **Step 3: Implement SetupInstaller**

Create `claude spinner/SetupInstaller.swift`:

```swift
import Foundation

/// Writes the feed plumbing on first run: copies the bundled scripts into
/// ~/.claude and merges the spinnerfeed hooks + statusLine into settings.json
/// without clobbering existing config (backup + append-only merge, atomic write).
enum SetupInstaller {
    enum SetupError: LocalizedError {
        case malformedSettings
        case missingBundledScript
        var errorDescription: String? {
            switch self {
            case .malformedSettings:
                return "settings.json isn't valid JSON — fix it, or add the hooks by hand."
            case .missingBundledScript:
                return "The bundled feed scripts are missing from the app."
            }
        }
    }

    /// Every Claude Code lifecycle event the feed listens on.
    static let hookEvents = [
        "SessionStart", "PreToolUse", "PostToolUse",
        "UserPromptSubmit", "Notification", "SessionEnd", "Stop",
    ]

    static let emitCommandPath = "~/.claude/spinnerfeed/emit.sh"

    /// Append-only merge of the spinnerfeed hooks + statusLine. Pure, no I/O.
    static func mergeSpinnerHooks(into settings: [String: Any]) -> [String: Any] {
        var out = settings
        var hooks = (out["hooks"] as? [String: Any]) ?? [:]
        for event in hookEvents {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            let alreadyWired = groups.contains { group in
                let entries = (group["hooks"] as? [[String: Any]]) ?? []
                return entries.contains { ($0["command"] as? String)?.contains("emit.sh") == true }
            }
            if !alreadyWired {
                groups.append([
                    "matcher": "",
                    "hooks": [["type": "command", "command": "\(emitCommandPath) \(event)"]],
                ])
                hooks[event] = groups
            }
        }
        out["hooks"] = hooks
        if out["statusLine"] == nil {
            out["statusLine"] = ["type": "command", "command": "bash ~/.claude/statusline-command.sh"]
        }
        return out
    }

    /// Copy the scripts and merge settings.json. Safe to re-run.
    static func install() -> Result<Void, Error> {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        let feedDir = claudeDir.appendingPathComponent("spinnerfeed", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: feedDir, withIntermediateDirectories: true)

            guard let emitSrc = Bundle.main.url(forResource: "emit", withExtension: "sh"),
                  let statusSrc = Bundle.main.url(forResource: "statusline-command", withExtension: "sh")
            else { return .failure(SetupError.missingBundledScript) }

            try copyExecutable(from: emitSrc, to: feedDir.appendingPathComponent("emit.sh"))
            try copyExecutable(from: statusSrc, to: claudeDir.appendingPathComponent("statusline-command.sh"))

            let settingsURL = claudeDir.appendingPathComponent("settings.json")
            var current: [String: Any] = [:]
            if fm.fileExists(atPath: settingsURL.path) {
                let data = try Data(contentsOf: settingsURL)
                let stamp = Int(Date().timeIntervalSince1970)
                try data.write(to: claudeDir.appendingPathComponent("settings.json.backup-\(stamp)"))
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return .failure(SetupError.malformedSettings) }
                current = parsed
            }
            let merged = mergeSpinnerHooks(into: current)
            let out = try JSONSerialization.data(withJSONObject: merged,
                                                 options: [.prettyPrinted, .sortedKeys])
            try writeAtomically(out, to: settingsURL)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func copyExecutable(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.copyItem(at: src, to: dst)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
    }

    private static func writeAtomically(_ data: Data, to dst: URL) throws {
        let tmp = dst.deletingLastPathComponent()
            .appendingPathComponent(".\(dst.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        if FileManager.default.fileExists(atPath: dst.path) {
            _ = try FileManager.default.replaceItemAt(dst, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: dst)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
killall "claude spinner" 2>/dev/null || true
xcodebuild test -project "claude spinner.xcodeproj" -scheme "claude spinner" \
  -destination 'platform=macOS' -only-testing:"claude spinnerTests" CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -iE "Test Suite 'claude_spinnerTests'|Executed [0-9]+ test|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`, 31 tests executed (27 existing + 4 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add "claude spinner/SetupInstaller.swift" "claude spinnerTests/claude_spinnerTests.swift"
git commit -m "Add SetupInstaller with a tested settings.json merge"
```

---

### Task 3: Wire the Install button into the UI

**Files:**
- Modify: `claude spinner/FeedWatcher.swift` (make setup state recomputable/published)
- Modify: `claude spinner/MenuContentView.swift:17-36` (Setup-needed block)

**Interfaces:**
- Consumes: `SetupInstaller.install()` from Task 2.
- Produces: `FeedWatcher.refreshSetupState()`; `InstallState: ObservableObject`.

- [ ] **Step 1: Make `isSetupInstalled` recomputable in FeedWatcher**

In `claude spinner/FeedWatcher.swift`, replace the `lazy var` (around line 709):

```swift
    private(set) lazy var isSetupInstalled: Bool = Self.checkSetupInstalled(dir: dir)
```

with a published stored property + refresh method:

```swift
    @Published private(set) var isSetupInstalled: Bool = false

    /// Re-check whether the feed plumbing is installed and publish the result.
    /// Called after the one-click installer runs so the panel updates in place.
    func refreshSetupState() {
        isSetupInstalled = Self.checkSetupInstalled(dir: dir)
    }
```

Then set the initial value once in `init` — add this line right after the `dir = ...` / `createDirectory` lines (near line 508):

```swift
        isSetupInstalled = Self.checkSetupInstalled(dir: dir)
```

- [ ] **Step 2: Add the InstallState object and Install button**

In `claude spinner/MenuContentView.swift`, add a state object property to `MenuContentView` (next to `@ObservedObject var feed`):

```swift
    @StateObject private var install = InstallState()
```

Replace the Setup-needed `else` block (lines 23-36) with:

```swift
                } else {
                    // Nothing will ever appear until the hooks are wired up — offer a
                    // one-click install instead of a silent empty panel.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setup needed")
                            .font(.claudeMono(11)).fontWeight(.semibold)
                            .foregroundStyle(Color.usageTint(95))
                        Text("The feed hooks aren't installed, so no sessions can show.")
                            .font(.claudeMono(10)).foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = install.message {
                            Text(message)
                                .font(.claudeMono(10)).foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(install.installing ? "Installing…" : "Install hooks") {
                            install.installing = true
                            install.message = nil
                            DispatchQueue.global(qos: .userInitiated).async {
                                let result = SetupInstaller.install()
                                DispatchQueue.main.async {
                                    install.installing = false
                                    switch result {
                                    case .success:
                                        feed.refreshSetupState()
                                        install.message = "Installed — restart your Claude Code sessions to start the feed."
                                    case .failure(let error):
                                        install.message = "Couldn't install: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                        .font(.claudeMono(10))
                        .disabled(install.installing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 12)
                }
```

Add the `InstallState` class near `HoverState` (around line 573):

```swift
/// Drives the one-click installer button in the Setup-needed panel. A small
/// ObservableObject rather than @State, matching HoverState (the codebase avoids
/// @State so the swiftc dev-loop build keeps working).
class InstallState: ObservableObject {
    @Published var installing = false
    @Published var message: String?
}
```

- [ ] **Step 3: Build to verify it compiles**

```bash
killall "claude spinner" 2>/dev/null || true
xcodebuild -scheme "claude spinner" -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Re-run unit tests (nothing regressed)**

```bash
xcodebuild test -project "claude spinner.xcodeproj" -scheme "claude spinner" \
  -destination 'platform=macOS' -only-testing:"claude spinnerTests" CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -iE "Executed [0-9]+ test|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`, 31 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add "claude spinner/FeedWatcher.swift" "claude spinner/MenuContentView.swift"
git commit -m "Add one-click Install hooks button to the Setup-needed panel"
```

---

### Task 4: End-to-end verification against a scratch config

Prove the button actually installs against a settings.json that isn't the developer's real one. Uses a throwaway `~/.claude` by pointing `HOME` at a scratch dir for a manual `install()` exercise via a tiny harness, then restores.

**Files:** none modified (verification only).

- [ ] **Step 1: Build a standalone harness that runs install() against a scratch HOME**

```bash
cd "/Users/home/Developer/claude-spinner"
SCRATCH=$(mktemp -d)/home
mkdir -p "$SCRATCH/.claude"
printf '{\n  "model": "opus"\n}\n' > "$SCRATCH/.claude/settings.json"
SD="$(mktemp -d)"
sed 's/@main//' "claude spinner/claude_spinnerApp.swift" > "$SD/App_nomain.swift"
cat > "$SD/harness.swift" <<'SWIFT'
import Foundation
@main struct H {
    static func main() {
        switch SetupInstaller.install() {
        case .success: print("INSTALL OK")
        case .failure(let e): print("INSTALL FAIL: \(e)"); exit(1)
        }
    }
}
SWIFT
HOME="$SCRATCH" xcrun --sdk macosx swiftc \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macosx14.0 \
  "$SD/App_nomain.swift" "claude spinner/FeedWatcher.swift" "claude spinner/MenuContentView.swift" \
  "claude spinner/SetupInstaller.swift" "$SD/harness.swift" -o "$SD/harness" 2>&1 | tail -5
```

Note: the harness copies scripts from `Bundle.main` — a bare swiftc binary has no resource bundle, so `install()` returns `.missingBundledScript`. To exercise the file/merge path, this step verifies compilation + the merge; the real script-copy path is verified by the app run below.

Expected: compiles cleanly.

- [ ] **Step 2: Verify the merge against the scratch settings via the harness merge path**

Instead of the app-bundle copy, assert the merge directly (append to harness `main` before install, or reuse the unit tests already covering merge). Since Task 2 unit-tests the merge exhaustively, this step is satisfied by those passing — skip the harness merge re-assertion.

- [ ] **Step 3: Real app verification — install against a moved-aside real config**

```bash
cd "/Users/home/Developer/claude-spinner"
# Move the real feed plumbing aside so the app shows "Setup needed".
mv ~/.claude/spinnerfeed/emit.sh ~/.claude/spinnerfeed/emit.sh.aside 2>/dev/null || true
cp ~/.claude/settings.json ~/.claude/settings.json.preinstall
bash run.sh 2>&1 | tail -2   # rebuild + relaunch; panel should read "Setup needed"
```

Then click **Install hooks** in the panel and confirm:

```bash
ls -l ~/.claude/spinnerfeed/emit.sh ~/.claude/statusline-command.sh   # both present, 0755
ls ~/.claude/settings.json.backup-*                                    # a backup was made
grep -c "emit.sh" ~/.claude/settings.json                              # >= 7
```

Expected: scripts present and executable, a backup exists, settings references `emit.sh`, and the panel flips from "Setup needed" to "No active sessions".

- [ ] **Step 4: Restore the developer's real config**

```bash
# The installer rewrote settings.json (sorted+pretty). Restore the pre-install copy.
mv ~/.claude/settings.json.preinstall ~/.claude/settings.json
rm -f ~/.claude/spinnerfeed/emit.sh.aside
# Remove test backups created during verification (keep none):
rm -f ~/.claude/settings.json.backup-*
bash run.sh 2>&1 | tail -1
```

Expected: real config restored; app back to normal.

- [ ] **Step 5: Commit the plan completion note (docs only, if any)**

No code change in this task. If a `STATUS.md`/`TASKS.md` update is warranted, commit it here.

---

## Self-Review

**Spec coverage:**
- Ship scripts (spec §1) → Task 1. ✓
- SetupInstaller + pure merge (spec §2) → Task 2. ✓
- UI Install button + recomputable setup state (spec §3) → Task 3. ✓
- Format tradeoff (spec §4) → merge uses `.sortedKeys, .prettyPrinted`; backup made in `install()`. ✓
- Error handling (spec §5) → `SetupError.malformedSettings` (abort before write) + `.missingBundledScript`; copy/write errors surface via `Result`. ✓
- Testing (spec) → Task 2 tests empty/idempotent/partial/preserve-statusLine; Task 4 end-to-end. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. Task 4 Step 2 intentionally defers to Task 2's tests (documented reason), not a placeholder.

**Type consistency:** `mergeSpinnerHooks(into:) -> [String: Any]`, `install() -> Result<Void, Error>`, `hookEvents`, `SetupError`, `refreshSetupState()`, `InstallState.installing/.message` — names match across tasks.
