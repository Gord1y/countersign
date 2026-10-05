# Allow and deny rules

Countersign's own rules decide a request before any panel is queued. This page is why they are
evaluated the way they are. The user-facing description is in
[configuration](../configuration.md#allow-and-deny-rules); the code is `ApprovalRule`,
`RuleEvaluator` and the `rules` reader in `ConfigFileParser`.

## Evaluation order

`RuleEvaluator.decide` takes a permission request, the parsed rules and the home folder, and answers
allow, deny with a message, or nothing. Only permission requests are decided; questions, plans and
context checkpoints always reach a person.

1. A rule is in scope when every field it sets matches. A rule with a `command` is in scope only for
   a shell command, because there is nothing to match the pattern against otherwise.
2. The first in-scope deny rule that applies wins. A deny rule without a `command` applies
   outright; with one, it applies when any segment of the command matches.
3. An in-scope allow rule without a `command` allows outright.
4. For a shell command, the remaining allow rules must cover every segment: each segment has to
   match the `command` of at least one in-scope allow rule.
5. Anything else is no decision, and the panel shows as it does without rules.

The indexes in a decision are positions in the parsed array, after dropped entries are removed, so
the log line and the Settings list agree.

Settings ▸ Rules shows that parsed array and removes from it; see "Rules" in
[settings.md](settings.md#rules).

## Deny on any segment, allow on every segment

A compound command runs all its parts, so the two answers need opposite quantifiers. Blocking
`rm` must catch `ls && rm -rf x`; letting `ls` through must not let `ls && rm -rf x` through. Deny
is checked first for the same reason: a block is the answer the user wrote a rule to be sure of, and
it must not depend on rule order or on an allow rule that happens to match too.

## An unsplittable command is never decided

`ShellCommandSegments.split` returns nothing for a command it cannot split safely: one with a `$`
outside single quotes, a backtick, a parenthesis, a brace, a `#` that starts a word, or an output
redirection to anything but `/dev/null` or another descriptor. For those,
neither an allow nor a deny rule with a `command` decides: an allow would let an unseen `$(rm x)`
through, and a deny that quietly fails to apply is no better than none. The panel is the safety
net, so the person sees the whole command. Rules without a `command` do not look at the command and
still apply.

The splitter refuses every `$` rather than following each shell's expansion rules, because those
rules are where 0.2.0's first splitter was bypassed. Each of these passed an allow rule for
`git log` while the shell ran a second command:

- `git log # '⏎rm -rf x⏎#'`: the shell reads `# '` as a comment and runs line 2, while a splitter
  that does not know comments sees one quoted string.
- `git log $'\'' ; rm -rf x⏎'`: inside `$'…'`, `\'` is an escaped quote, so bash and the splitter
  disagree about where the quote ends.
- `git log "${(e)${:-\$(rm -rf x)}}"`: zsh's `(e)` flag runs a command substitution from inside
  double quotes.

A variable in a command therefore always gets a panel. A `$` escaped with a backslash or inside
single quotes is literal, and a `#` inside a word, as in a URL's fragment, is not a comment, so
both still split.

An output redirection writes a file the rule never named: an allow rule for `ls` would otherwise
let `ls > ~/.zshrc` through. Only `/dev/null` and a copy onto another descriptor, such as `2>&1`
and `>&2`, write nothing new, so those still split, with or without a descriptor number or a
blank before the target. Anything else after `>`, `>>`, `>|`, `&>` or `&>>` is refused, the
target included when it is quoted. A descriptor copy has to end its word, because `>&1x` writes a
file named `1x`. An input redirection `<` only reads and still splits, while `<>` also opens the
file for writing and is refused.

## One pattern language

The `command` field uses `CommandPattern`, the same matcher as Cursor's command allowlist: a prefix
on a word boundary, or `base:argsGlob`. Someone who knows one list knows the other, the Cursor
allowlist and the rules are matched by one piece of code, and a fix to the matcher applies to both.

## The tool glob

`tool` matches `ApprovalRequest.toolName` as the host reports it, which differs per agent (`Bash`,
`Shell`, `run_command`, `apply_patch`, `mcp__github__create_issue`). The only wildcard is `*`, over
the whole name and case-sensitively, so `mcp__github__*` covers a server's tools without a regex
language to get wrong.

## The project parent test

A rule's `project` covers its folder and everything under it, because an agent's working directory
is often a subfolder of the repository. The test compares path components, not prefixes: `/a/b`
is a parent of `/a/b/c` but not of `/a/bc`. A leading `~` is expanded against the home folder passed
in, so tests do not depend on the machine. The request's `cwd` is used as the host gave it, with no
symlink resolution.

## Where the hook applies rules

`HookRunner.run` calls `RuleEvaluator.decide` once, right after the `start host=…` log line:

1. A deny answers immediately, before the sandboxed-command skip, the not-asked-about skip and
   everything else. Deny wins over every skip because a rule that says never should hold whatever
   Countersign would otherwise have done with the request.
2. An allow answers after those two skips and before Cursor's allowlist check and the panel. Allow
   never overrides a skip: a sandboxed Cursor command or a tool Countersign does not ask about
   stays exactly as it is without Countersign, and is not turned into an explicit allow.
3. No match carries on as before.

Rules are off while paused (the hook exits before it parses), for test panels and for context
checkpoints (neither reaches this code). The answers are logged as `rule: allowed by rules[<i>]`
or `rule: denied by rules[<i>]`, then `outcome: allow` or `outcome: deny`, and recorded in the
decision history as `allowedByRule` and `deniedByRule`. See "Answered by a rule" in
[answers.md](answers.md) for what each host receives.

## Always allow

Codex has no "Always allow" of its own, so Approve ▾ offers one that saves rules to `config.json`
(`AlwaysAllowOffer`, `RuleFileWriter`). Claude Code keeps its own suggestions and gets no such row.
Cursor and Antigravity get none either: both ignore an `allow` from a hook and decide by their own
settings (`Host.honorsHookAllow` is false; see "Approve is not enough yet" for each in
[hosts.md](hosts.md)), so a saved allow rule would only hide Countersign's panel while the agent
asked again, which is not what "Always allow" says. Measured for Cursor on 2026-10-04 with Cursor
3.22.12 in Allowlist mode: the rule was saved, the hook printed `{"permission":"allow"}`, and
Cursor showed its own prompt.

- **Offered** on Codex permission panels only, never for a test panel or a context checkpoint, and
  only when an offer can be built: the working directory must be known.
- **Scope.** Every rule is `allow`, for the request's agent and its project, the working directory
  written with a leading `~` when it is under the home folder (the evaluator expands it, so the
  file stays portable between machines with the same layout).
- **A shell command** is split into segments as the evaluator splits it. One rule is saved per
  distinct segment, in order, each with the segment's exact pattern. A command that can't be split,
  or has a segment with no exact pattern, gets no offer. The evaluator needs every segment of a
  compound command matched by an allow rule, so saving them all is what makes the same command
  pass next time.
- **Anything else** (an MCP call, `apply_patch`, a file tool) saves one rule with the request's
  `tool` name and no `command`.
- **Writing.** `PreferenceEdit.addRules` appends each rule to the top-level `rules` array, creating
  it when absent and skipping a rule equal to one already there, so choosing the same row twice
  saves it once. Keys are written in the order `decision`, `agent`, `project`, `tool`, `command`,
  `message`. `RuleFileWriter.add` creates the folder, backs up the existing file and writes
  atomically, so the hook and Settings can share it.

### The exact pattern

The pattern must match the approved segment and the same segment followed by more arguments, and
never anything broader. `CommandPattern.exact(forSegment:)` builds it from the trimmed segment:

- Without a `:`, the segment itself. A prefix pattern ends on a word boundary, so `git push origin
  main` also covers `git push origin main --force`. A `*` in such a segment stays literal.
- With a `:` but no `*`, and no `:` in the first word, `<first word>:<rest>`. In the pattern
  language the first `:` splits a base command from an argument glob, so saving
  `git push origin main:main` as is would be read as the base `git push origin main` and the glob
  `main`, which matches nothing useful. Writing the first word as the base and the rest as the glob
  keeps the colon in the arguments, and with no `*` the arguments must equal the rest exactly.
- Otherwise, no pattern, and no offer: a `:` with a `*` in the segment, or a `:` in the first word,
  can't be expressed without becoming broader or different.

## Why rules are top-level only

Rules are about what to do with a request, not about how an agent is configured, and the same rule
must be able to name any agent through its `agent` field. Putting them under `hosts.<agent>` would
split one ordered list into four, make the order that decides which rule wins ambiguous across
them, and leave no place for a rule that applies to all agents.
