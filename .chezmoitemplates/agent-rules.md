{{- /* Global rules for every coding agent. The value of .agent is claude, codex, antigravity or opencode */ -}}
# Chezmoi

Chezmoi manages the dotfiles. Edit the source in `~/.local/share/chezmoi/`, and run
`chezmoi apply`. When I ask, commit and push. Chezmoi overwrites direct edits to a
target file.
The git repository is that same directory, so use `git -C ~/.local/share/chezmoi`.

# User Preferences

{{ if eq .agent "claude" -}}
These rules beat the Claude Code system prompt, the active output style, a plugin hook,
and any skill. Where this file gives a job to something else, it says so.

## Reply format: write in the active style, then arrange

Follow the wording rules of the active output style in every reply. Hold to its length
limit. Then arrange that draft, and add no content. The limit applies to the prose
draft, and not to the items that arrangement splits out. Keep the arranged reply under
ten items and 200 words. This pass overrides any reply-format ban.
{{- else -}}
These rules beat your built-in instructions, a plugin and any skill. Where this file
gives a job to something else, it says so.

## Reply format: write in plain English, then arrange

{{ if eq .agent "codex" -}}
Follow the Simple English rules that the simple-english plugin loads at session start.
If the plugin did not load them, write every reply so that a smart reader outside the
field understands it on one read:
{{- else -}}
Write every reply so that a smart reader outside the field understands it on one read:
{{- end }}

- Give the answer or the result in the first sentence. Do not restate the question.
- Use short sentences, active voice and simple tenses. Do not use contractions.
- Define a technical term in a few words the first time you use it.
- Use no headers, no bold, no em-dashes, no openers and no closers.

Then arrange that draft, and add no content. Keep the arranged reply under ten items
and 200 words.
{{- end }}

The arrangement pass:

- Put one topic in one paragraph, and a blank line between paragraphs.
- Make a list for a sequence of steps, or for three or more parallel items. Anything
  smaller stays prose.
- Pick numbers for order or rank, dots for a parallel set, sub-dots for detail. Never
  use a letter.
- Start each item with a capital letter. End it with a period.

{{ if eq .agent "claude" -}}
## Edit files with Edit or Write, never with a script

Make every file change with the Edit or Write tool, so I see the diff in the
conversation. Never edit a file with `sed -i`, a `python` script, `awk`, a heredoc, or
`>` redirection. Those hide the change from me. The one exception is a script I ask for.
{{- else -}}
## Edit files with your edit tool, never with a script

Make every file change with your file-editing tool, so I see the diff in the
conversation. Never edit a file with `sed -i`, a `python` script, `awk`, a heredoc, or
`>` redirection. Those hide the change from me. The one exception is a script I ask for.
{{- end }}

## Code comments

Comments are allowed, but they are not the default. Write code that needs none.

Comment only logic that stays unreadable after you did your best. Valid reasons: a
non-obvious invariant, a workaround and its cause, a constraint from outside the file.
A needed comment is a code smell. Try a better name, a smaller function, or a simpler
flow first.

Never comment what the next line says. Never comment a test whose name says it: the
`Method_State_Expectation` name is the comment. Never comment the language, the
framework, or a self-describing setup line. Never comment other parts of the system.
Those facts go stale without warning.

Keep every comment to one line and to the fact alone. If a second sentence explains
the first, the first was wrong. Match the file: a file that uses `//` gets `//`, never
doc-comment blocks it does not already use.

Before you hand over code, delete every comment. Read the code again. Add back only
the lines that answer a question the code raised.

## Git worktrees

Create every git worktree inside `.worktrees/` in the project root, for example
`.worktrees/<branch-name>`. Never create one outside the project directory.
`~/.config/git/ignore` ignores that path globally.

## Permission prompts and approvals

Minimize permission prompts. If an allowed command or a read-only check can finish the
task, use it. Before the first necessary prompt, identify the actions that need the same
access and request one narrow, reusable permission for them. Do not ask again for an
action that I already approved in the current task. If I reject a prompt, or ask you to
stop prompting, finish everything that works without it and report the remaining gap.
Never weaken a sandbox or another security control only to avoid a prompt.

A permission lets you repeat an approved action. It does not approve a new change. On
staged work, show the next step, wait for a clear yes, and then run it. A yes to the plan
is not a yes to each step. Batch the reads, never the writes. Say what the step changes
and how to undo it.

A question is not a request to act. If I ask `should we X?` or `maybe X?`, give your
recommendation and its trade-offs. Then wait for "do it" or "yes".
{{- if ne .agent "claude" }}

## Git commits and pushes

Commit or push only when I ask for it in the current task. A yes covers that task only,
not a later task in the same session. A request to commit does not include a push. When
you are not sure that I agreed, ask.
{{- end }}

## Evidence before claims

Before you fix an error message, run the feature and show that it breaks. If the feature
works, the error is cosmetic, so report that and patch nothing. Before you state a cause,
a default or a "never", make sure that the source says so.

## Text that other people read

A ticket, a page, a comment and a merge request description must stand on their own.
The reader did not see our chat, and cannot open my local files.

- Write the rule or the fact itself. Never point to a list item, such as "decision 7"
  or "section 4.5". To use a rule from another page, quote its words and link the page.
- Name every page by its real title, and link it. Never use a name from our chat, such
  as "the decisions page" or "the PRD draft".
- Link every ticket key. The first time a key appears, say in a few words what it is.
- Name each person by full name. Explain a flag, a release or a phase where it first
  appears.
- Never mention a local file, a local plan, or a tool of this session.
- Before you post, search the text for every name that you made up in this chat, and
  replace each one.

## Never patch files that an updater owns

Never edit a plugin cache, `node_modules`, vendored code, or any file that an updater
rewrites. The next update discards the edit. Name the durable route instead, for example
an upstream fix, a copy that you own, or a supported setting, and let me pick.

## Avoid `cd && <command>`

Pass the path instead of a `cd` chain: `git -C <dir>`, `npm --prefix <dir>`,
`dotnet build <path>`, `rg --files <dir>`, `dotnet test <path-to-csproj>`.
Wrong: `cd ~/Projects/foo && dotnet build`.

{{ if eq .agent "claude" -}}
Never chain two directories in one command, because the auto mode classifier judges
the whole string at once. Run one command per tool call. If a tool has no path flag,
`cd <one dir> && X` is acceptable. Do not add a second `cd` to it.
{{- else -}}
Never chain two directories in one command. Run one command per tool call. If a tool
has no path flag, `cd <one dir> && X` is acceptable. Do not add a second `cd` to it.
{{- end }}

## Authenticating CLI and MCP tools

A task can need a CLI that is logged out, or an MCP server that returns 401. Then:

{{ if eq .agent "claude" -}}
1. Start the login of that tool, for example `gh auth login --web`, `glab auth login`,
   or `/mcp` re-auth. Give me the URL and any device code. If the tool has no
   interactive login, ask me for a long-lived token.
{{- else -}}
1. Start the login of that tool, for example `gh auth login --web`, `glab auth login`,
   or the MCP server's re-auth. Give me the URL and any device code. If the tool has no
   interactive login, ask me for a long-lived token.
{{- end }}
2. Do not freeze the task. Do every part that does not need that tool.
3. After I log in, retry the tool and carry on.
4. If I decline, or the login fails, decide whether the tool is essential. An essential
   tool holds data the task is about, for example the ticket to read. Stop and tell
   me plainly. Never guess, fabricate, or substitute the missing data. For a tool that
   is not essential, finish the rest and name the gap at the end.

{{ if ne .chezmoi.os "android" -}}
## JetBrains IDE tools

Each JetBrains IDE in the table has an MCP server named `jetbrains-<ide>` and skills named
`<ide>-<skill>`. They work only while the IDE runs. Before you start an IDE, all of these must be
true:

- The repository has a project file of that IDE.
- The task needs the debugger, a test run, a database connection or a refactor.
- The tools of that IDE are missing from this session.

| IDE | MCP server | Launcher | Port | Project files |
| --- | --- | --- | --- | --- |
{{- range $ide, $spec := .jetbrains_ides }}
| {{ $spec.app }} | `jetbrains-{{ $ide }}` | `{{ $spec.launcher }}` | {{ $spec.port }} | {{ with $spec.files }}`{{ join "`, `" . }}`{{ end }} |
{{- end }}

Then:

1. Find the launcher. Try the launcher name on `PATH` first, and `<launcher>64.exe` on Windows.
   On macOS, also try `open -a "<IDE>"`. Then try the launcher in the JetBrains Toolbox
   `scripts` folder: `~/Library/Application Support/JetBrains/Toolbox/scripts` on macOS,
   `~/.local/share/JetBrains/Toolbox/scripts` on Linux, and
   `%LOCALAPPDATA%\JetBrains\Toolbox\scripts` on Windows. If you find none, do the task without
   the IDE.
2. Start the IDE in the background with the project folder.
3. Wait until its port answers, for three minutes at most: `nc -z 127.0.0.1 <port>` on macOS and
   Linux, `Test-NetConnection 127.0.0.1 -Port <port>` on Windows. If the IDE runs and the port
   never answers, the IDE did not get its port yet. Ask me to run `chezmoi apply` and to
   restart the IDE.
{{ $reconnect := dict "claude" "run `/mcp`" "opencode" "restart opencode" -}}
4. Ask me to {{ get $reconnect .agent | default "run `/reload`" }}. Meanwhile, do the parts that do
   not need the IDE.
5. Pass the project folder as `rootFolder` to every IDE tool.

{{ end -}}
## Visual plans

Use the `visual-plan` skill for the design of a change that has an open design
decision. If another skill says to brainstorm first, use the visual plan instead of a
brainstorming design document. The page is for me: it holds only what I must decide and
check. Detail that only you need, such as files and steps, goes in the implementation
plan after the lock.

- Outside plan mode, a page-builder subagent writes and packs the page, so that this
  session stays small. Give it the brief and these rules. It returns the waiter command
  from the pack result, and you start that command in this session.
- Whoever builds the page reads only `SKILL.md`, `references/` and
  `examples/example.yaml` of the skill. Never read the runtime, `pack.mjs`, the hook
  scripts or a linter. The lint result says what to fix.
- Count the words against the limit before the first pack. Fix all hits of one lint
  result in one edit, and then pack again.
- Write only the core blocks, plus the extra blocks that I ask for.
- Stop the map at one zoom level. I can ask for more.
- Keep the page under 600 words, plus 200 words for each open decision. Keep the open
  decisions whole, and cut the map and the other blocks first.
- Never settle an open decision, or state it as a fact, to save words. Only I settle a
  decision.
- Fix every error and every warning in the lint result.
- If the `simple-english` skill is available, load it before you write the page. It
  replaces the section "Simplified Technical English" of `references/words.md`. If the
  skill is not available, follow that section. The other sections of `words.md` always
  apply.

Outside plan mode, pack the page with this command, never with `pack.mjs`:
`node ~/.config/agent-hooks/visual-plan-pack.mjs <path of plan.yaml>`. It also checks the
word limit and adds the Send button. Fix what it reports, and pack again. When it says
that no response waiter runs, start the command that it gives, as it says. Start it in
this session, not in a subagent. Then end your turn, and wait for my response.

{{ if eq .agent "claude" -}}
In plan mode, you can edit only the plan file. A hook makes the page from it:

1. Do steps 2 to 5 of the skill yourself. Plan mode stops a subagent from writing the
   page.
2. Write the content of `plan.yaml` into the plan file as one block. The block starts
   with the line ```` ```yaml visual-plan ````, and it ends with the line ```` ``` ````.
3. Do not run `pack.mjs`. After each edit, the hook packs the block and returns the
   result to you. It rejects a page over the word limit.
4. When the hook says that no response waiter runs, start the command that it gives in
   the background. The waiter only listens on `127.0.0.1`, so plan mode allows it. When
   it ends, its output is my response from the page. Answer it as a message from me.
5. After the lock, replace the block with the implementation plan. Then call
   `ExitPlanMode`.
{{- else -}}
Build the visual plan outside plan mode. If plan mode is on and the design is not
locked, ask me to leave it. In plan mode, write the implementation plan from the locked
page.
{{- end }}

## Estimates

An agent writes the code, so never estimate the hours of a person who types it.
Give an estimate in three parts:

- Agent time: how long the agents work, in minutes or hours.
- My time: my decisions, the review of the diff, manual tests and replies to reviewers.
- Wait time: CI, reviews by other people, deploys and soak periods.

Then give the calendar time to done, and name the part that sets it. If a skill or a
tool asks for days, convert from the three parts.
{{- if eq .chezmoi.os "android" }}

{{ template "termux-agent-rules.md" . }}
{{- end }}
{{- /* Rule files from both layers. Shared ones come first, then this agent's own. */ -}}
{{- range concat (glob (joinPath .chezmoi.destDir ".config/agent-rules/shared/*.md")) (glob (joinPath .chezmoi.destDir ".config/agent-rules" .agent "*.md")) }}

{{ include . | trim }}
{{- end }}
