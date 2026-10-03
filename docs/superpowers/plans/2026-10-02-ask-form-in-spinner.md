# Ask Form In Spinner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `AskUserQuestion` box a session raises (one question, several questions, multi-select) can be answered from the spinner's session row, and the generic "Run AskUserQuestion? Allow / Deny" card never appears.

**Architecture:** `ask.sh` gains a third path. A single-select question keeps today's non-waiting path (the terminal draws its box, a card click types the digit). A *form* (more than one question, or any multi-select) blocks in the `PreToolUse` hook, but only while the session's terminal is not the frontmost app; the app draws every question, and the hook returns `permissionDecision: "allow"` with `updatedInput.answers`, so the terminal box never opens. The `PermissionRequest` path stops handling `AskUserQuestion` at all.

**Tech Stack:** POSIX `sh` + `jq` (the hook), Swift 6 / SwiftUI (the app), XCTest (`claude spinnerTests/claude_spinnerTests.swift`), tmux (the live probe).

**Spec:** none was written. The design is the section below; its evidence is `STATUS.md:53-59` and `STATUS-ARCHIVE.md` entries `2026-09-04 (answer from the notification)`, `2026-09-04 (runtime verification)` and `2026-09-30 (Job Search dashboard, ...)`.

## Design

What is known, and how:

| Fact | Evidence |
|---|---|
| A `PreToolUse` hook on `AskUserQuestion` can answer the call by printing `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"questions":[...],"answers":{"<question text>":"<option label>"}}}}` | Proven live 2026-09-04, single-select (`STATUS.md:53-59`). The code that did it is in git: `git show 7c5c4b7^:"claude spinner/Scripts/ask.sh"`, lines 118-125. |
| Questions were made non-blocking on 2026-09-30 so the terminal box draws at once | `STATUS-ARCHIVE.md`, "Decided: questions no longer block". This plan keeps that for single-select. |
| `PermissionRequest` fires for `AskUserQuestion`, and `ask.sh permission` (matcher `""`) turns it into an Allow/Deny card whenever the terminal is not frontmost | Seen 2026-10-02 in the app: card "Permission needed / Run AskUserQuestion?". `~/.claude/settings.json` registers `ask.sh permission` on `PermissionRequest` with an empty matcher. |
| While that Allow/Deny card waits, the terminal box is not drawn | `ask.sh` comment: "A PermissionRequest hook holds the terminal prompt until it returns". So today a single-select question's digit card and the Allow/Deny card fight. |
| A multi-select answer is the chosen labels joined with `", "` | **Not proven.** Inferred from the tool result text Claude Code shows the model (`"..."="Label one, Label two"`). Task 1 proves or refutes it before any code is written. |

Decisions:

- Single-select questions: unchanged (non-waiting ask, digit typed into the pane).
- Forms block only when the terminal is not frontmost, the same guard the permission path already uses. At the terminal you get the terminal box immediately, as now.
- An incomplete answer never decides the call. The hook prints nothing and the terminal box opens.
- "Answer in terminal" on the form card writes `passthrough`, which the hook already treats as a timeout.

Out of scope (each is its own plan if wanted):

- Replacing `ConversationCard` with a purpose-built "apply card" for Job Search sessions. The form card already draws above it in `PinnedProjectDetail.run(_:underStep:)`.
- A multi-select question answered with nothing ticked, and the "Other" free-text answer. Both stay terminal-only: use "Answer in terminal".
- Answering forms from a notification banner. A banner has one tap; the form gets "Open session" only.

## Global Constraints

- No emoji anywhere (code, comments, commit messages, docs). Status marks are `[ok]`, `[x]`, `[!]`.
- `ask.sh` must never exit 2 (that reads as a deny on `PreToolUse`). Every fallback prints nothing and exits 0.
- The hook source of truth is `claude spinner/Scripts/ask.sh`. `~/.claude/spinnerfeed/ask.sh` is an installed copy, tracked in the separate `~/.claude` git repo; it must be byte-identical (`cmp`) after every install step.
- Before any `xcodebuild`: load the `ios-build` skill, and check `gh run list --limit 1` is not `in_progress` (a local test run kills the self-hosted CI runner's test host, `CLAUDE.md` "Test").
- Test command shape (unit target only):
  ```bash
  killall "claude spinner" 2>/dev/null
  set -o pipefail
  xcodebuild -scheme "claude spinner" test -only-testing:"claude spinnerTests/claude_spinnerTests/<testName>" | { command -v xcbeautify >/dev/null && xcbeautify || cat; }
  ```
- Any layout change updates `docs/WIREFRAMES.md` in the same commit and ends in a look at the running app (`./run.sh`), not only a green suite.
- tmux: address panes by pane id (`%N`), never by session name.
- Commits: new commits only, imperative subject, reasoning in the body, trailer `Co-Authored-By: Claude <noreply@anthropic.com>`, explicit pathspec (`git commit -- <paths>`). Never `--no-verify`.
- Match the surrounding comment style: comments explain why, not what.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `claude spinner/Scripts/ask.sh` | modify | Decide per call: skip, hand over without waiting, or wait for the app and print the decision. |
| `claude spinner/AskInbox.swift` | modify | Decode asks, hold the pure form logic (`AskForm`), write answers. |
| `claude spinner/WindowContentView.swift` | modify (`AskCard`, new `AskFormCard` beside it) | Draw a pending ask. No new file: the project keeps its cards in this file and a new file would need a project-file edit. |
| `claude spinnerTests/claude_spinnerTests.swift` | modify | Hook tests run the real script against stubbed `pgrep` / `lsappinfo`; pure tests cover `AskForm` and decoding. |
| `docs/WIREFRAMES.md` | modify | Text wireframe of the form card. |
| `STATUS.md`, `TASKS.md` | modify | Decision log entry, task ticks. |
| `~/.claude/spinnerfeed/ask.sh` | install copy (other repo) | The hook Claude Code actually runs. |

---

### Task 1: Prove the multi-question, multi-select answer format (no repo change)

**Files:**
- Create (scratch, deleted at the end): `$TMPDIR/askprobe/.claude/settings.json`, `$TMPDIR/askprobe/answer.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the fact Tasks 3-5 rest on. `AskForm.separator` in Task 4 is `", "` only if this task passes.

- [ ] **Step 1: Build the scratch project**

```bash
P="$TMPDIR/askprobe"; rm -rf "$P"; mkdir -p "$P/.claude"
cat > "$P/answer.sh" <<'EOF'
#!/bin/sh
# Answers every question: the first option, or the first two joined by ", " when multiSelect.
jq -c '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
  updatedInput: {questions: .tool_input.questions,
    answers: (.tool_input.questions | map({key: .question,
      value: (if (.multiSelect // false) then (.options[0:2] | map(.label) | join(", "))
              else .options[0].label end)}) | from_entries)}}}'
EOF
chmod +x "$P/answer.sh"
cat > "$P/.claude/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"AskUserQuestion","hooks":[{"type":"command","command":"$P/answer.sh"}]}]}}
EOF
```

- [ ] **Step 2: Check the scratch hook on its own (known-good and known-bad input)**

```bash
echo '{"tool_input":{"questions":[{"question":"Pick a color?","options":[{"label":"Red"},{"label":"Green"}]},{"question":"Pick toppings?","multiSelect":true,"options":[{"label":"Ham"},{"label":"Olives"},{"label":"Corn"}]}]}}' | "$TMPDIR/askprobe/answer.sh" | jq -c '.hookSpecificOutput.updatedInput.answers'
echo 'not json' | "$TMPDIR/askprobe/answer.sh"; echo "exit=$?"
```

Expected: first command prints `{"Pick a color?":"Red","Pick toppings?":"Ham, Olives"}`. Second prints a `jq: error` line and a non-zero `exit=`.

- [ ] **Step 3: Run a real session against it**

Keep the terminal you run this from frontmost, so the installed `ask.sh permission` stays out of the way.

```bash
tmux new-session -d -s askprobe -c "$TMPDIR/askprobe" \
  "claude 'Call the AskUserQuestion tool exactly once with two questions. Question 1: \"Pick a color?\", header \"Color\", single-select, options Red and Green. Question 2: \"Pick toppings?\", header \"Toppings\", multiSelect true, options Ham, Olives and Corn. Then reply with the tool result you received, verbatim, inside a code block, and nothing else.'"
PANE=$(tmux list-panes -t askprobe -F '#{pane_id}' | head -1)
sleep 25; tmux capture-pane -p -t "$PANE" | tail -40
```

If the capture shows a "trust this folder" prompt, accept it with `tmux send-keys -t "$PANE" Enter`, wait 25 seconds and capture again.

- [ ] **Step 4: Read the result (go / no-go)**

Pass, all three:
1. No question box was drawn in the pane (no numbered options list).
2. The reply's code block contains `"Pick a color?"="Red"`.
3. It contains `"Pick toppings?"="Ham, Olives"`.

If 1 fails (a box appeared), a hook cannot answer a multi-question call: **stop, do not start Task 3, 4 or 5**, do Task 2 only, and report the capture. If 2 passes and 3 differs, record the exact text shown and stop for a decision on the separator.

- [ ] **Step 5: Clean up and record**

```bash
tmux kill-session -t askprobe
rm -rf "$TMPDIR/askprobe"
```

Append to `STATUS.md` under a `### 2026-10-02` decision-log heading (create it if absent), using the capture as the evidence:

```markdown
- Verified: a PreToolUse hook answers a two-question AskUserQuestion call, one of them
  multiSelect, with `updatedInput.answers` keyed on the question text. The multi-select
  value is the labels joined with ", ". No terminal box was drawn. (scratch probe, tmux capture)
```

```bash
git commit -m "docs(status): record the multi-question answer probe

A hook answering AskUserQuestion was proven on 2026-09-04 for one
single-select question only. The form path in ask.sh needs the same for
several questions and for multiSelect, so it was probed before any code.

Co-Authored-By: Claude <noreply@anthropic.com>" -- STATUS.md
```

---

### Task 2: `ask.sh permission` leaves `AskUserQuestion` alone

**Files:**
- Modify: `claude spinner/Scripts/ask.sh:44-55` (the `else` branch of the mode test)
- Test: `claude spinnerTests/claude_spinnerTests.swift` (add after `testAskScriptLeavesThePermissionToAFrontmostTerminal`, which ends at line 2585)
- Install: `~/.claude/spinnerfeed/ask.sh`

**Interfaces:**
- Consumes: nothing from Task 1 (this task is safe to ship even if Task 1 fails).
- Produces: `ask.sh permission` exits 0 with empty stdout and no ask file when stdin's `.tool_name` is `AskUserQuestion`.

- [ ] **Step 1: Write the failing test**

```swift
    /// The Allow/Deny card for a question, removed. Run both ways with the
    /// terminal behind: AskUserQuestion must exit at once with no ask file, and
    /// Bash must still reach the wait, or this is a guard that always exits.
    func testAskScriptLeavesAQuestionsPermissionToTheQuestionHook() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        for (tool, expectAsk) in [("AskUserQuestion", false), ("Bash", true)] {
            try withTempDir { home in
                let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
                let bin = home.appendingPathComponent("bin")
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                let stubs = ["pgrep": "#!/bin/sh\nexit 0\n",
                             "lsappinfo": "#!/bin/sh\n[ \"$1\" = front ] && echo ASN:0x0-0x1 && exit 0\n"
                                 + "echo '    bundleID=\"com.example.other\"'\n"]
                for (name, body) in stubs {
                    let url = bin.appendingPathComponent(name)
                    try Data(body.utf8).write(to: url)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
                let hook = Process()
                hook.executableURL = URL(fileURLWithPath: "/bin/sh")
                hook.arguments = [script.path, "permission"]
                hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin:/opt/homebrew/bin",
                                    "SPINNER_ASK_TIMEOUT": "30", "__CFBundleIdentifier": "com.example.term"]
                let stdin = Pipe()
                let out = Pipe()
                hook.standardInput = stdin
                hook.standardOutput = out
                try hook.run()
                stdin.fileHandleForWriting.write(Data(
                    #"{"session_id":"sid","tool_name":"\#(tool)","tool_input":{"questions":[{"question":"q","options":[{"label":"a"}]}]}}"#.utf8))
                try stdin.fileHandleForWriting.close()

                func askFiles() -> [String] {
                    ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                        .filter { $0.hasSuffix(".ask.json") }
                }
                let deadline = Date().addingTimeInterval(5)
                if expectAsk {
                    while askFiles().isEmpty && Date() < deadline { usleep(50_000) }
                    XCTAssertEqual(askFiles().count, 1, "any other tool must still be handed to the app")
                    hook.terminate()
                } else {
                    while hook.isRunning && Date() < deadline { usleep(50_000) }
                    XCTAssertFalse(hook.isRunning, "a question's permission must not wait for the app")
                    XCTAssertEqual(askFiles(), [])
                    if hook.isRunning { hook.terminate() }
                    XCTAssertEqual(out.fileHandleForReading.readDataToEndOfFile(), Data(),
                                   "printing a decision here would answer the permission")
                }
                hook.waitUntilExit()
            }
        }
    }
```

- [ ] **Step 2: Run it and see it fail**

Run the test command from Global Constraints with `<testName>` = `testAskScriptLeavesAQuestionsPermissionToTheQuestionHook`.
Expected: FAIL on the `AskUserQuestion` pass with "a question's permission must not wait for the app". The `Bash` pass succeeds.

- [ ] **Step 3: Implement**

In `claude spinner/Scripts/ask.sh`, the `else` branch currently starts:

```sh
else
    # A PermissionRequest hook holds the terminal prompt until it returns, so
```

Change it to:

```sh
else
    # A question raises a permission request of its own. Answering that one with
    # Allow/Deny is a card that asks nothing, and while it waits the real box is
    # never drawn. The question path owns AskUserQuestion; this one steps aside.
    tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
    [ "$tool" = "AskUserQuestion" ] && exit 0

    # A PermissionRequest hook holds the terminal prompt until it returns, so
```

- [ ] **Step 4: Run the test, then the three neighbouring hook tests**

Run with `<testName>` = each of `testAskScriptLeavesAQuestionsPermissionToTheQuestionHook`, `testAskScriptLeavesThePermissionToAFrontmostTerminal`, `testAskScriptRemovesItsFileWhenStopped`, `testBundledAskScriptKeepsItsFallbacks`.
Expected: all four PASS.

- [ ] **Step 5: Install, and check the copy**

```bash
cp "claude spinner/Scripts/ask.sh" ~/.claude/spinnerfeed/ask.sh
cmp "claude spinner/Scripts/ask.sh" ~/.claude/spinnerfeed/ask.sh && echo "[ok] installed copy matches"
sh -n ~/.claude/spinnerfeed/ask.sh && echo "[ok] parses"
```

Expected: both `[ok]` lines.

- [ ] **Step 6: Commit (two repos)**

```bash
git commit -m "fix(ask): stop turning a question's permission request into Allow/Deny

AskUserQuestion raises a PermissionRequest of its own, and the permission
hook matches every tool, so with the terminal behind the app showed
'Run AskUserQuestion? Allow / Deny' and held the real box back until it
was answered. The question hook owns that tool; the permission hook now
exits for it.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/Scripts/ask.sh" "claude spinnerTests/claude_spinnerTests.swift"

git -C ~/.claude commit -m "fix(spinnerfeed): install ask.sh that leaves AskUserQuestion's permission alone

Copy of claude-spinner's Scripts/ask.sh; see that repo's commit for why.

Co-Authored-By: Claude <noreply@anthropic.com>" -- spinnerfeed/ask.sh
```

---

### Task 3: `ask.sh question` holds a form for the app

**Files:**
- Modify: `claude spinner/Scripts/ask.sh` (whole mode block, the `waits` block, the final output)
- Test: `claude spinnerTests/claude_spinnerTests.swift` (add after the Task 2 test)

**Interfaces:**
- Consumes: Task 1's result (forms can be answered by a hook), Task 2's `ask.sh`.
- Produces, for a form with the terminal behind:
  - ask file `asks/<req>.ask.json` with `"kind":"question"`, `"waits":true`, and the full `questions` array (each question keeps its `multiSelect`);
  - on an answer file `{"behavior":"allow","answers":{<one key per question>}}`: stdout `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"questions":[...],"answers":{...}}}}`, exit 0;
  - on any other answer file (passthrough, deny, fewer answers than questions): empty stdout, exit 0.

- [ ] **Step 1: Write the failing tests**

```swift
    private static let formPayload =
        #"{"session_id":"sid","tool_input":{"questions":[{"question":"Pick a color?","options":[{"label":"Red"},{"label":"Green"}]},{"question":"Pick toppings?","multiSelect":true,"options":[{"label":"Ham"},{"label":"Olives"}]}]}}"#

    /// Runs ask.sh in question mode on the two-question form with `front` as the
    /// frontmost app, feeds it `answer` once its ask file appears, and returns
    /// what it printed. `ask` is the decoded ask file, nil if none was written.
    private func runFormHook(front: String, answer: String?) throws
        -> (stdout: String, status: Int32, ask: AskRequest?, waited: Bool) {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner/Scripts/ask.sh")
        var result: (String, Int32, AskRequest?, Bool) = ("", -1, nil, false)
        try withTempDir { home in
            let asks = home.appendingPathComponent(".claude/spinnerfeed/asks")
            let bin = home.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let stubs = ["pgrep": "#!/bin/sh\nexit 0\n",
                         "lsappinfo": "#!/bin/sh\n[ \"$1\" = front ] && echo ASN:0x0-0x1 && exit 0\n"
                             + "echo '    bundleID=\"\(front)\"'\n"]
            for (name, body) in stubs {
                let url = bin.appendingPathComponent(name)
                try Data(body.utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            let hook = Process()
            hook.executableURL = URL(fileURLWithPath: "/bin/sh")
            hook.arguments = [script.path, "question"]
            hook.environment = ["HOME": home.path, "PATH": "\(bin.path):/usr/bin:/bin:/opt/homebrew/bin",
                                "SPINNER_ASK_TIMEOUT": "30", "__CFBundleIdentifier": "com.example.term"]
            let stdin = Pipe()
            let out = Pipe()
            hook.standardInput = stdin
            hook.standardOutput = out
            try hook.run()
            stdin.fileHandleForWriting.write(Data(Self.formPayload.utf8))
            try stdin.fileHandleForWriting.close()

            func askNames() -> [String] {
                ((try? FileManager.default.contentsOfDirectory(atPath: asks.path)) ?? [])
                    .filter { $0.hasSuffix(".ask.json") }
            }
            var deadline = Date().addingTimeInterval(5)
            while askNames().isEmpty && hook.isRunning && Date() < deadline { usleep(50_000) }
            var ask: AskRequest?
            var waited = false
            if let name = askNames().first {
                ask = try JSONDecoder().decode(AskRequest.self,
                                               from: Data(contentsOf: asks.appendingPathComponent(name)))
                waited = hook.isRunning
                if let answer, let req = ask?.req {
                    try Data(answer.utf8).write(to: asks.appendingPathComponent("\(req).answer.json"))
                }
            }
            deadline = Date().addingTimeInterval(5)
            while hook.isRunning && Date() < deadline { usleep(50_000) }
            if hook.isRunning { hook.terminate() }
            hook.waitUntilExit()
            result = (String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                      hook.terminationStatus, ask, waited)
        }
        return result
    }

    /// At the terminal, a form is the terminal's: no ask file, nothing printed.
    func testAskScriptLeavesAFormToAFrontmostTerminal() throws {
        let run = try runFormHook(front: "com.example.term", answer: nil)
        XCTAssertNil(run.ask)
        XCTAssertEqual(run.stdout, "")
        XCTAssertEqual(run.status, 0)
    }

    /// With the terminal behind, the hook waits on the app and turns a complete
    /// answer into the PreToolUse decision that answers the call.
    func testAskScriptReturnsTheAppsAnswersForAForm() throws {
        let run = try runFormHook(
            front: "com.example.other",
            answer: #"{"behavior":"allow","answers":{"Pick a color?":"Green","Pick toppings?":"Ham, Olives"}}"#)
        XCTAssertTrue(run.waited, "precondition: the hook was still waiting when its ask file appeared")
        XCTAssertEqual(run.ask?.kind, .question)
        XCTAssertEqual(run.ask?.blocking, true)
        XCTAssertEqual(run.ask?.questions?.count, 2)
        XCTAssertEqual(run.status, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any])
        let specific = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(specific["permissionDecision"] as? String, "allow")
        let updated = try XCTUnwrap(specific["updatedInput"] as? [String: Any])
        XCTAssertEqual((updated["questions"] as? [Any])?.count, 2)
        XCTAssertEqual(updated["answers"] as? [String: String],
                       ["Pick a color?": "Green", "Pick toppings?": "Ham, Olives"])
    }

    /// Anything short of one answer per question must not decide the call: the
    /// terminal box is the fallback, and a half-answered form would skip it.
    func testAskScriptPrintsNothingForAnIncompleteOrDeclinedForm() throws {
        for answer in [#"{"behavior":"allow","answers":{"Pick a color?":"Green"}}"#,
                       #"{"behavior":"allow"}"#,
                       #"{"behavior":"passthrough"}"#,
                       #"{"behavior":"deny"}"#] {
            let run = try runFormHook(front: "com.example.other", answer: answer)
            XCTAssertTrue(run.waited, "precondition: the hook reached its wait for \(answer)")
            XCTAssertEqual(run.stdout, "", "printed a decision for \(answer)")
            XCTAssertEqual(run.status, 0)
        }
    }
```

- [ ] **Step 2: Run them and see them fail**

Run with `<testName>` = `testAskScriptReturnsTheAppsAnswersForAForm`, then `testAskScriptPrintsNothingForAnIncompleteOrDeclinedForm`.
Expected: both FAIL at the `run.waited` precondition (today the hook exits at once for a form and writes no ask file). `testAskScriptLeavesAFormToAFrontmostTerminal` already passes; it is the known-good half and must keep passing.

- [ ] **Step 3: Implement the mode block**

In `claude spinner/Scripts/ask.sh`, replace everything from the line `host="${__CFBundleIdentifier:-${TERM_PROGRAM:-}}"` down to the `fi` that closes the mode test (just above `mkdir -p "$dir"`) with:

```sh
host="${__CFBundleIdentifier:-${TERM_PROGRAM:-}}"

# Whether the session's own terminal is the frontmost app. A hook that waits
# holds the terminal's prompt back until it returns, so waiting while you are
# looking at the terminal means the prompt never appears there.
terminal_is_front() {
    [ -n "$host" ] || return 1
    front=$(lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
        | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p')
    [ "$front" = "$host" ]
}

form=false
if [ "$mode" = "question" ]; then
    # One digit picks one option, so a single question never waits: the terminal
    # draws its box and the card types the digit. Several questions at once, or a
    # question that takes several answers, cannot be typed that way. Those wait
    # for the app to send every answer back, but only with the terminal behind.
    shape=$(printf '%s' "$input" | jq -r '
        if (.tool_input.questions | length) < 1 then "none"
        elif (.tool_input.questions | length) > 1 then "form"
        elif (.tool_input.questions[0].multiSelect // false) then "form"
        else "single" end' 2>/dev/null)
    case "$shape" in
        single) ;;
        form) terminal_is_front && exit 0
              form=true ;;
        *) exit 0 ;;
    esac
else
    # A question raises a permission request of its own. Answering that one with
    # Allow/Deny is a card that asks nothing, and while it waits the real box is
    # never drawn. The question path owns AskUserQuestion; this one steps aside.
    tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
    [ "$tool" = "AskUserQuestion" ] && exit 0

    terminal_is_front && exit 0
fi
```

- [ ] **Step 4: Implement the wait and the output**

Still in `ask.sh`, change the condition that picks the non-waiting path. It reads:

```sh
if [ "$mode" = "question" ]; then
    # Nothing waits on a question, so its file outlives this hook on purpose; the
```

Change the first line only:

```sh
if [ "$mode" = "question" ] && [ "$form" = false ]; then
    # Nothing waits on a question, so its file outlives this hook on purpose; the
```

(The `else` branch below it, with the two `trap` lines, now also covers a form, which is what removes a form's ask file when the hook is stopped.)

Then replace the last four lines of the file:

```sh
jq -n --arg b "$behavior" \
    '{hookSpecificOutput: {hookEventName: "PermissionRequest",
                           decision: {behavior: $b}}}'
exit 0
```

with:

```sh
if [ "$mode" = "question" ]; then
    # Only one answer per question decides the call. Anything less prints
    # nothing, so the terminal box opens instead of a half-answered form
    # skipping it.
    [ "$behavior" = "allow" ] || exit 0
    printf '%s' "$input" | jq -c --argjson reply "$reply" '
        ($reply.answers // {}) as $a
        | select(($a | type) == "object" and ($a | length) == (.tool_input.questions | length))
        | {hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: {questions: .tool_input.questions, answers: $a}}}' 2>/dev/null
    exit 0
fi

jq -n --arg b "$behavior" \
    '{hookSpecificOutput: {hookEventName: "PermissionRequest",
                           decision: {behavior: $b}}}'
exit 0
```

Also update the header comment (lines 6-9 of the file) so it stays true:

```sh
# Writes ~/.claude/spinnerfeed/asks/<req>.ask.json. A permission then waits for
# the app to write <req>.answer.json and turns that into the hook's decision
# JSON. A single question does not wait: it returns at once so the terminal draws
# its own box, and the app answers by typing the option's digit into that box.
# A form (several questions, or one that takes several answers) waits like a
# permission when the terminal is behind, and returns the app's answers.
```

- [ ] **Step 5: Run the hook tests**

```bash
sh -n "claude spinner/Scripts/ask.sh" && echo "[ok] parses"
```

Then run with `<testName>` = each of: `testAskScriptLeavesAFormToAFrontmostTerminal`, `testAskScriptReturnsTheAppsAnswersForAForm`, `testAskScriptPrintsNothingForAnIncompleteOrDeclinedForm`, `testAskScriptHandsAQuestionOverWithoutWaiting`, `testAskScriptLeavesAQuestionsPermissionToTheQuestionHook`, `testAskScriptLeavesThePermissionToAFrontmostTerminal`, `testAskScriptRemovesItsFileWhenStopped`, `testBundledAskScriptKeepsItsFallbacks`.
Expected: all eight PASS.

- [ ] **Step 6: Commit (do not install yet)**

The installed copy stays at Task 2's version until Task 5: a form that waits with no form card in the app would show only its first question.

```bash
git commit -m "feat(ask): hold a multi-question or multi-select ask for the app

A digit typed into the terminal box can pick one option of one question,
so forms were left to the terminal. With the terminal behind, the question
hook now waits for the app and returns every answer as updatedInput, the
route proven for a single question on 2026-09-04 and for forms by the
2026-10-02 probe. One answer per question or nothing: an incomplete reply
prints no decision and the terminal box opens.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/Scripts/ask.sh" "claude spinnerTests/claude_spinnerTests.swift"
```

---

### Task 4: The form model in `AskInbox.swift`

**Files:**
- Modify: `claude spinner/AskInbox.swift:13-17` (`AskQuestion`), `:106-109` (`AskRequest.question`), `:121-136` (`AskAnswer`), `:351-358` (`write`), `:434-442` (`categories`)
- Test: `claude spinnerTests/claude_spinnerTests.swift` (add after `testDigitIsTheOptionsOneBasedPosition`)

**Interfaces:**
- Consumes: the ask file shape from Task 3.
- Produces:
  - `AskQuestion.multiSelect: Bool?`
  - `AskRequest.isForm: Bool`
  - `AskAnswer.form([String: String])` with `behavior == "allow"`
  - `enum AskForm` with `static let separator: String`, `static func toggle(_ label: String, at index: Int, multi: Bool, in picks: [Int: Set<String>]) -> [Int: Set<String>]`, `static func answers(for questions: [AskQuestion], picks: [Int: Set<String>]) -> [String: String]?`
  - `AskInbox.write(.form(answers), for:in:)` writes `{"behavior":"allow","answers":{...}}`

- [ ] **Step 1: Write the failing tests**

```swift
    // MARK: - Forms: several questions, or several answers to one

    private func makeFormAsk() -> AskRequest {
        let json = """
        {"req":"sid-100-7","kind":"question","session_id":"sid","cwd":"/tmp/proj",
         "created":100,"waits":true,"session_pid":null,
         "questions":[{"question":"Pick a color?","options":[{"label":"Red"},{"label":"Green"}]},
                      {"question":"Pick toppings?","multiSelect":true,
                       "options":[{"label":"Ham"},{"label":"Olives"},{"label":"Corn"}]}]}
        """
        return try! JSONDecoder().decode(AskRequest.self, from: Data(json.utf8))
    }

    /// Both halves: the two shapes that are forms, and the one that is not.
    func testIsFormIsSeveralQuestionsOrAMultiSelect() {
        XCTAssertTrue(makeFormAsk().isForm)
        let oneMulti = try! JSONDecoder().decode(AskRequest.self, from: Data("""
        {"req":"sid-100-7","kind":"question","session_id":"sid","cwd":"/tmp","created":1,"waits":true,
         "questions":[{"question":"q","multiSelect":true,"options":[{"label":"a"}]}]}
        """.utf8))
        XCTAssertTrue(oneMulti.isForm)
        XCTAssertFalse(makeQuestionAsk(waits: false).isForm)
        XCTAssertFalse(makePermissionAsk(toolInput: "{}").isForm)
    }

    /// A single-select question holds one pick; a multi-select toggles each.
    func testToggleReplacesASinglePickAndTogglesAMultiPick() {
        var picks = AskForm.toggle("Red", at: 0, multi: false, in: [:])
        picks = AskForm.toggle("Green", at: 0, multi: false, in: picks)
        XCTAssertEqual(picks[0], ["Green"])
        picks = AskForm.toggle("Olives", at: 1, multi: true, in: picks)
        picks = AskForm.toggle("Ham", at: 1, multi: true, in: picks)
        XCTAssertEqual(picks[1], ["Ham", "Olives"])
        picks = AskForm.toggle("Olives", at: 1, multi: true, in: picks)
        XCTAssertEqual(picks[1], ["Ham"])
        XCTAssertEqual(picks[0], ["Green"], "another question's picks are untouched")
    }

    /// Labels come out in the question's option order, not click order, joined
    /// the way the 2026-10-02 probe showed Claude Code expects.
    func testFormAnswersJoinPicksInOptionOrder() {
        let questions = makeFormAsk().questions ?? []
        let answers = AskForm.answers(for: questions, picks: [0: ["Green"], 1: ["Olives", "Ham"]])
        XCTAssertEqual(answers, ["Pick a color?": "Green", "Pick toppings?": "Ham, Olives"])
    }

    /// No answers until every question has a pick, and a label that is not one
    /// of the question's options does not count as one.
    func testFormAnswersNeedAPickForEveryQuestion() {
        let questions = makeFormAsk().questions ?? []
        XCTAssertNil(AskForm.answers(for: questions, picks: [:]))
        XCTAssertNil(AskForm.answers(for: questions, picks: [0: ["Green"]]))
        XCTAssertNil(AskForm.answers(for: questions, picks: [0: ["Green"], 1: []]))
        XCTAssertNil(AskForm.answers(for: questions, picks: [0: ["Blue"], 1: ["Ham"]]))
        XCTAssertNotNil(AskForm.answers(for: questions, picks: [0: ["Green"], 1: ["Ham"]]))
    }

    /// The file ask.sh reads back: allow, plus every answer.
    func testWriteCarriesAFormsAnswers() throws {
        try withTempDir { dir in
            let ask = makeFormAsk()
            try Data("{}".utf8).write(to: dir.appendingPathComponent("\(ask.req).ask.json"))
            let answers = ["Pick a color?": "Green", "Pick toppings?": "Ham, Olives"]
            XCTAssertTrue(AskInbox.write(.form(answers), for: ask, in: dir))
            let data = try Data(contentsOf: dir.appendingPathComponent("\(ask.req).answer.json"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["behavior"] as? String, "allow")
            XCTAssertEqual(object["answers"] as? [String: String], answers)
        }
    }

    /// A banner button would answer the first question only, and the hook would
    /// then print nothing. A form's banner opens the session; a single
    /// question's banner still carries its options.
    func testAFormsBannerOffersNoOptionButtons() {
        let form = AskInbox.categories(for: [makeFormAsk()])
        XCTAssertEqual(form.first?.actions.map(\.title), ["Open session"])
        let single = AskInbox.categories(for: [makeQuestionAsk(waits: false)])
        XCTAssertEqual(single.first?.actions.map(\.title), ["Alpha", "Beta", "Open session"])
    }
```

- [ ] **Step 2: Run one and see the build fail**

Run with `<testName>` = `testFormAnswersJoinPicksInOptionOrder`.
Expected: build FAILS with "cannot find 'AskForm' in scope" (and `isForm`, `.form`).

- [ ] **Step 3: Implement the model**

In `claude spinner/AskInbox.swift`:

`AskQuestion` (lines 13-17) becomes:

```swift
struct AskQuestion: Decodable, Equatable {
    let question: String
    let header: String?
    let options: [AskOption]?
    /// Absent means one answer, the tool's own default.
    let multiSelect: Bool?
}
```

Replace the `question` property and its comment (lines 106-109) with:

```swift
    /// The one question of a single-select ask. A form carries more, or one
    /// that takes several answers; the card reads `questions` for those.
    var question: AskQuestion? { questions?.first }

    /// Several questions at once, or a question that takes several answers.
    /// `ask.sh` only hands these over when it is waiting for every answer back,
    /// because a digit typed into the terminal box cannot express either.
    var isForm: Bool {
        kind == .question
            && ((questions?.count ?? 0) > 1 || questions?.first?.multiSelect == true)
    }
```

`AskAnswer` (lines 121-136) becomes:

```swift
nonisolated enum AskAnswer: Equatable {
    case option(String)   // a labelled choice for a question ask
    /// Every answer of a form, keyed on the question text.
    case form([String: String])
    case allow
    case deny
    /// Seen and declined — the banner was dismissed, or the user went to the
    /// session instead. Same outcome as a timeout: the terminal prompt takes over.
    case passthrough

    var behavior: String {
        switch self {
        case .option, .form, .allow: return "allow"
        case .deny: return "deny"
        case .passthrough: return "passthrough"
        }
    }
}

/// The picks of a form, and the answers they add up to. Pure, so the rules the
/// card depends on are tested without drawing it.
nonisolated enum AskForm {
    /// How Claude Code writes several labels into one answer (probed 2026-10-02).
    static let separator = ", "

    /// `picks` after a click on `label` in question `index`: a single-select
    /// question keeps only the newest pick, a multi-select toggles it.
    static func toggle(_ label: String, at index: Int, multi: Bool,
                       in picks: [Int: Set<String>]) -> [Int: Set<String>] {
        var next = picks
        var chosen = multi ? (next[index] ?? []) : []
        if chosen.contains(label) { chosen.remove(label) } else { chosen.insert(label) }
        next[index] = chosen
        return next
    }

    /// One answer per question, labels in the question's own option order. Nil
    /// until every question has a pick: `ask.sh` drops a reply with fewer
    /// answers than questions, so sending early would only look like it worked.
    static func answers(for questions: [AskQuestion],
                        picks: [Int: Set<String>]) -> [String: String]? {
        var out: [String: String] = [:]
        for (index, question) in questions.enumerated() {
            let chosen = picks[index] ?? []
            let labels = (question.options ?? []).map(\.label).filter(chosen.contains)
            guard !labels.isEmpty else { return nil }
            out[question.question] = labels.joined(separator: separator)
        }
        return out.count == questions.count ? out : nil
    }
}
```

In `write` (lines 355-358), after the existing `.option` block, add the form case so the payload section reads:

```swift
        var payload: [String: Any] = ["behavior": answer.behavior]
        if case .option(let label) = answer, let question = req.question {
            payload["answers"] = [question.question: label]
        }
        if case .form(let answers) = answer {
            payload["answers"] = answers
        }
```

In `categories(for:)`, the `.question` case (lines 434-442) becomes:

```swift
            case .question:
                // Only two show on a banner; the rest need the notification
                // expanded. Documented behaviour, and the reason the window's
                // detail pane is the surface for anything longer. A form gets
                // none: one tap would answer its first question only.
                actions = req.isForm ? [] : (req.question?.options ?? []).enumerated().map { index, option in
                    UNNotificationAction(identifier: actionID(req: req.req,
                                                              choice: optionChoice(index)),
                                         title: option.label, options: [])
                }
```

- [ ] **Step 4: Run the model tests**

Run with `<testName>` = each of `testIsFormIsSeveralQuestionsOrAMultiSelect`, `testToggleReplacesASinglePickAndTogglesAMultiPick`, `testFormAnswersJoinPicksInOptionOrder`, `testFormAnswersNeedAPickForEveryQuestion`, `testWriteCarriesAFormsAnswers`, `testAFormsBannerOffersNoOptionButtons`, `testDigitIsTheOptionsOneBasedPosition`, `testAskWithoutWaitsFieldIsBlocking`.
Expected: all eight PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(asks): model a form ask and the answers it adds up to

AskRequest only knew its first question, which is all a digit can answer.
A form carries every question; AskForm holds the pick rules (one pick for
single-select, toggles for multi-select, labels joined in option order)
and withholds the answers until each question has one, since ask.sh drops
a short reply. A form's banner loses its option buttons: one tap would
answer the first question and nothing else.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/AskInbox.swift" "claude spinnerTests/claude_spinnerTests.swift"
```

---

### Task 5: The form card, the install, and the live run

**Files:**
- Modify: `claude spinner/WindowContentView.swift:757-851` (`AskCard`; add `AskFormCard` directly after it)
- Modify: `docs/WIREFRAMES.md` (add the form card beside the existing `AskCard` wireframe)
- Modify: `STATUS.md`, `TASKS.md`
- Install: `~/.claude/spinnerfeed/ask.sh`

**Interfaces:**
- Consumes: `AskRequest.isForm`, `AskRequest.questions`, `AskQuestion.multiSelect`, `AskForm.toggle(_:at:multi:in:)`, `AskForm.answers(for:picks:)`, `AskAnswer.form`, `AskAnswer.passthrough`, `AskInbox.shared.answer(_:with:)`, `AskInbox.shared.rescan()`, `AskCard.armDelay`.
- Produces: `struct AskFormCard: View` with `init(ask: AskRequest)`. `AskCard` draws it for a form, so both call sites (`WindowContentView.swift:687` and `PinnedProjectDetail.swift:493`) get it with no change.

- [ ] **Step 1: Route `AskCard` to the form card**

In `claude spinner/WindowContentView.swift`, `AskCard`'s body currently opens:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ask.kind == .permission ? "Permission needed" : (ask.question?.header ?? "Question"))
```

Rename that property to `single` and add a new `body` above it:

```swift
    var body: some View {
        if ask.isForm {
            AskFormCard(ask: ask)
        } else {
            single
        }
    }

    private var single: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ask.kind == .permission ? "Permission needed" : (ask.question?.header ?? "Question"))
```

Nothing else in `AskCard` changes.

- [ ] **Step 2: Add `AskFormCard`**

Directly after `AskCard`'s closing brace (before `// MARK: - Free-text reply`):

```swift
/// A form: every question of the ask, each with its options, sent together.
///
/// The hook is waiting on all the answers at once, so nothing is sent until each
/// question has a pick. "Answer in terminal" hands it back: the hook returns
/// without a decision and Claude Code draws its own box.
struct AskFormCard: View {
    let ask: AskRequest
    @State private var picks: [Int: Set<String>] = [:]
    @State private var outcome: String?
    @State private var armed = false

    private var questions: [AskQuestion] { ask.questions ?? [] }
    private var answers: [String: String]? { AskForm.answers(for: questions, picks: picks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(questions.count == 1 ? (questions[0].header ?? "Question")
                                      : "\(questions.count) questions")
                .font(.ui(11)).foregroundStyle(Color.attention)

            if let outcome {
                Text(outcome).font(.ui(11)).foregroundStyle(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    self.question(question, at: index)
                }
                HStack(spacing: 8) {
                    Button("Send answers") { send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!armed || answers == nil)
                    Button("Answer in terminal") { handBack() }
                        .buttonStyle(.bordered)
                        .disabled(!armed)
                }
            }
        }
        .task(id: ask.req) {
            armed = false
            try? await Task.sleep(for: AskCard.armDelay)
            armed = true
        }
        .padding(12)
        .background(Color.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func question(_ question: AskQuestion, at index: Int) -> some View {
        let multi = question.multiSelect == true
        return VStack(alignment: .leading, spacing: 6) {
            Text(question.question).font(.ui(13)).fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            if multi {
                Text("Pick any that apply").font(.ui(10)).foregroundStyle(Color.label)
            }
            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { _, option in
                let on = picks[index]?.contains(option.label) ?? false
                Button {
                    picks = AskForm.toggle(option.label, at: index, multi: multi, in: picks)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: multi ? (on ? "checkmark.square.fill" : "square")
                                                : (on ? "largecircle.fill.circle" : "circle"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label).font(.ui(11))
                            if let detail = option.description {
                                Text(detail).font(.ui(10))
                                    .foregroundStyle(Color.label)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(!armed)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func send() {
        guard let answers else { return }
        // False means ask.sh already gave up and Claude Code is showing its own
        // box. Say that rather than reporting answers that went nowhere.
        let sent = AskInbox.shared.answer(ask, with: .form(answers))
        outcome = sent
            ? "Answered: " + questions.map { answers[$0.question] ?? "" }.joined(separator: " / ")
            : "expired — answer it in the terminal"
        AskInbox.shared.rescan()
    }

    private func handBack() {
        let sent = AskInbox.shared.answer(ask, with: .passthrough)
        outcome = sent ? "Left for the terminal" : "expired — answer it in the terminal"
        AskInbox.shared.rescan()
    }
}
```

- [ ] **Step 3: Build and run the whole unit suite**

Check `gh run list --limit 1` is not `in_progress`, then:

```bash
killall "claude spinner" 2>/dev/null
set -o pipefail
xcodebuild -scheme "claude spinner" test | { command -v xcbeautify >/dev/null && xcbeautify || cat; }
```

Expected: the suite passes with no failures. A compile error names the line; fix it before going on.

- [ ] **Step 4: Update the wireframe**

Read `docs/WIREFRAMES.md`, find the `AskCard` wireframe, and add this block directly under it:

```text
AskFormCard (WindowContentView.swift) -- drawn by AskCard when ask.isForm
+--------------------------------------------------------------+
| 2 questions                                    ui(11) attention
|                                                               |
| Pick a color?                                  ui(13) semibold|
| [ (o) Red                                                   ] |
| [ ( ) Green                                                 ] |
|                                                    spacing 10 |
| Pick toppings?                                                |
| Pick any that apply                            ui(10) label   |
| [ [x] Ham                                                   ] |
| [ [ ] Olives                                                ] |
|                                                               |
| [ Send answers ]  [ Answer in terminal ]                      |
+--------------------------------------------------------------+
padding 12, corner radius 8, attention 8% fill (same as AskCard).
Send answers is disabled until every question has a pick.
After sending: one line, "Answered: Red / Ham".
```

- [ ] **Step 5: Install the hook and relaunch the app**

```bash
cp "claude spinner/Scripts/ask.sh" ~/.claude/spinnerfeed/ask.sh
cmp "claude spinner/Scripts/ask.sh" ~/.claude/spinnerfeed/ask.sh && echo "[ok] installed copy matches"
./run.sh
pgrep -x "claude spinner" >/dev/null && echo "[ok] app is running"
```

Expected: both `[ok]` lines.

- [ ] **Step 6: Live run, form answered from the app**

Start a session from the app (any pinned project's quick start), then click the spinner window so the terminal is behind it. In that session send:

```text
Call AskUserQuestion once with two questions. Question 1: "Pick a color?", header "Color", options Red and Green. Question 2: "Pick toppings?", header "Toppings", multiSelect true, options Ham, Olives and Corn. Then reply with the tool result verbatim in a code block.
```

Observe, in order:
1. The session's row shows one card headed "2 questions" with both questions. No "Permission needed / Run AskUserQuestion?" card appears.
2. "Send answers" is disabled until both questions have a pick.
3. Pick Green, tick Ham and Corn, click "Send answers". The card reads "Answered: Green / Ham, Corn" and then leaves.
4. The session's reply shows `"Pick a color?"="Green"` and `"Pick toppings?"="Ham, Corn"`, and no question box was drawn in the terminal.
5. `ls ~/.claude/spinnerfeed/asks/` shows no `.ask.json` or `.answer.json` left behind.

Take a screenshot of step 1 for the commit's look.

- [ ] **Step 7: Live run, the two fallbacks**

Repeat the prompt twice more:
- With the terminal frontmost: the terminal draws its own box at once and the app shows no form card.
- With the terminal behind, click "Answer in terminal": the card reads "Left for the terminal" and the terminal box appears within a second.

Then a single-select control, terminal behind: ask for one question with options Red and Green. Expected: the old single card (no "Send answers" button), the terminal box drawn at once, and clicking Green types `2` into it. No Allow/Deny card.

- [ ] **Step 8: Record and commit (two repos)**

In `TASKS.md`, tick the five items this plan added. In `STATUS.md`, under `### 2026-10-02`, append:

```markdown
- Decided: a form ask (several questions, or a multiSelect) waits in the PreToolUse hook
  when the terminal is behind, and the app returns every answer as `updatedInput.answers`.
  Single-select stays non-waiting with the digit. Observed live: "2 questions" card, Green
  plus Ham and Corn sent, session received `"Pick toppings?"="Ham, Corn"`, no terminal box.
- Decided: `ask.sh permission` exits for AskUserQuestion. The Allow/Deny card for a question
  asked nothing and held the real box back.
- Known limits: a multi-select answered with nothing ticked, and "Other" free text, are
  terminal-only ("Answer in terminal").
```

```bash
git commit -m "feat(window): answer a multi-question ask from the session row

AskCard drew one question and typed a digit. A form now draws every
question with radio or checkbox rows, sends all the answers together once
each question has a pick, and can hand the ask back to the terminal.
Looked at in the running app with a live two-question ask.

Co-Authored-By: Claude <noreply@anthropic.com>" -- "claude spinner/WindowContentView.swift" docs/WIREFRAMES.md STATUS.md TASKS.md

git -C ~/.claude commit -m "feat(spinnerfeed): install ask.sh that holds a form ask for the app

Copy of claude-spinner's Scripts/ask.sh; see that repo's commits for why.

Co-Authored-By: Claude <noreply@anthropic.com>" -- spinnerfeed/ask.sh
```

---

## Self-Review

- **Design coverage.** Allow/Deny card removed: Task 2. Forms answered from the app: Tasks 3-5. Single-select unchanged: asserted by `testAskScriptHandsAQuestionOverWithoutWaiting` staying green (Task 3 Step 5) and the control in Task 5 Step 7. Terminal-frontmost fallback: `testAskScriptLeavesAFormToAFrontmostTerminal` and Task 5 Step 7. Incomplete answer never decides: `testAskScriptPrintsNothingForAnIncompleteOrDeclinedForm` and `testFormAnswersNeedAPickForEveryQuestion`. Banner cannot half-answer: `testAFormsBannerOffersNoOptionButtons`. The one unproven fact is Task 1, with a stop condition.
- **Detectors have both inputs.** Each hook test runs a case that must reach the wait beside one that must not (`Bash` beside `AskUserQuestion`; terminal behind beside terminal in front), and `run.waited` is asserted as a precondition so a hook that bailed early cannot pass for "printed nothing".
- **Names used across tasks.** `AskForm.toggle(_:at:multi:in:)`, `AskForm.answers(for:picks:)`, `AskForm.separator`, `AskAnswer.form`, `AskRequest.isForm`, `AskQuestion.multiSelect`, `AskFormCard(ask:)`, `AskCard.armDelay`: defined in Task 4 (or already in the file) and used with the same spelling in Task 5.
- **No placeholders.** Every code step carries its code; every run step carries its command and what it should print.
