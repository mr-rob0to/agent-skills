# The ship gate, installed and run end to end

This is a recording, not a test the suite runs. Nothing in `make check` can
prove the gate works once it is installed as a plugin: the skill is prose an
agent follows, and the part most likely to break is the seam between that prose
and the helpers beside it in a folder they were never tested from.

So the plugin was installed from the public repository in Claude Code and in
Codex, `npx skills` was asked to list what it would install, and the gate was
run once by a real Claude Code session against a real remote and real CI. This file is what they printed. Run on 2026-09-23.

Paths are redacted. `~` is the home directory, `<tmp>` the scratch directory,
`<account>` the GitHub account and `<throwaway>` the repository that was
created for the run and deleted after it.

## Install, Claude Code

```
$ claude plugin marketplace add <account>/agent-skills
✔ Successfully added marketplace: <account> (declared in user settings)
$ claude plugin install qed@<account>
✔ Successfully installed plugin: qed@<account> (scope: user)
$ claude plugin details qed
qed 0.1.0
  Source: qed@<account>
Component inventory
  Skills (1)  ship
```

The first attempt used the catalog's original name and failed. Claude Code
keeps that name for Anthropic's own catalog:

```
$ claude plugin marketplace add <account>/agent-skills
✘ Failed to add marketplace: The name 'agent-skills' is reserved for official
  Anthropic marketplaces. Only repositories from 'github.com/anthropics/' can use this name.
```

The catalog was renamed after the GitHub owner. A contract test now fails if it
goes back.

## Install, Codex

```
$ codex plugin marketplace add <account>/agent-skills
Added marketplace `<account>` from https://github.com/<account>/agent-skills.git.
$ codex plugin add qed@<account>
Added plugin `qed` from marketplace `<account>`.
Installed plugin root: ~/.codex/plugins/cache/<account>/qed/0.1.0
```

Codex read the `.claude-plugin` catalog as it is; no Codex manifest was needed.
A fresh `codex exec` listed the skill as `qed:ship`, backed by
`~/.codex/plugins/cache/<account>/qed/0.1.0/skills/ship/SKILL.md`, and a message
starting `$qed:ship` loaded it: asked for the first heading of the skill it had
been given, it answered `# Ship`.

## Discovery, any other harness

```
$ npx skills add <account>/agent-skills --list
⚠ Skipped <tmp>/plugins/qed/skills/ship/SKILL.md — YAML parse error: Nested
  mappings are not allowed in compact mappings at line 2, column 14
└  No valid skills found.
```

The skill's `description` held a `: `, which a strict YAML parser rejects.
Claude Code and Codex read it anyway. The description was reworded and a
contract test now checks the header. Against a local clone with the fix:

```
$ npx skills add <local clone> --list
◇  Found 1 skill
│    ship
```

This proves the skill is found. It was not installed this way.

## The gate, run by Claude Code from the installed plugin

A headless Claude Code session was started in a clone of `<throwaway>` with
`/qed:ship` and the classification `combined`. The branch `one-line-change`
added one line to `README.md`. The throwaway held a `Makefile` whose `check`
target greps the README, and a workflow that runs it.

### Step 0. The base, then the helpers beside the skill

```
$ gh repo view --json defaultBranchRef,nameWithOwner
{"defaultBranchRef":{"name":"main"},"nameWithOwner":"<account>/<throwaway>"}
$ git fetch origin main && git merge-base --is-ancestor origin/main HEAD && echo OK
OK
```

Claude Code wrote the installed skill's own folder into the block:

```
SHIP_DIR="~/.claude/plugins/cache/<account>/qed/0.1.0/skills/ship"
```

### Steps 1 to 5. Classify, open, checks

```
MODE=combined
check passed
REVIEWER=codex exec -m gpt-5.6-sol --sandbox read-only -c project_doc_max_bytes=0
```

The reviewer came from the bundled `config/reviewer`: this machine had no
`~/.config/ship/reviewer`.

### Step 6. The review, first attempt

```
Reading additional input from stdin...
Command did not complete within its 600s timeout and was moved to the background
[killed]
```

The block handed `codex exec` the shell's open input, and Codex waits for its
input to end before it starts. In a Claude Code shell it never ends. The session
was resumed and the block rerun with `< /dev/null`; the skill's block now says
that itself, and a contract test fails if it goes back.

### Step 6. The review, rerun

```
HEAD=fd0f526299e0cd1d0954a2446cad3f45532d840e
## Findings
No findings.
usage: input=22478 output=676 cache_read=62848 cache_write=0
```

### Step 8. The template, the push, the pull request

```
TEMPLATES:
FALLBACK:
~/.claude/plugins/cache/<account>/qed/0.1.0/skills/ship/PULL_REQUEST_TEMPLATE.md
```

The repository had no template of its own, so the bundled one was filled in.
The push ran the anchored sequence:

```
"$SHIP_GUARD" push-ok || exit 2
BRANCH="$(git symbolic-ref --short HEAD)"
git fetch --prune origin
REMOTE="$(git rev-parse --verify --quiet "refs/remotes/origin/$BRANCH")"
[ -z "$REMOTE" ] || git merge-base --is-ancestor "$REMOTE" HEAD || exit 2
git push --force-with-lease="refs/heads/$BRANCH:$REMOTE" origin "HEAD:refs/heads/$BRANCH"
[ "$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)" = "$(git rev-parse HEAD)" ]
```

```
To https://github.com/<account>/<throwaway>.git
 * [new branch]      HEAD -> one-line-change
PUSHED
https://github.com/<account>/<throwaway>/pull/1
<!-- ship-attestation:v1 {"head_sha":"fd0f526299e0cd1d0954a2446cad3f45532d840e","fix_passes":0,"review_mode":"combined",...} -->
```

### Step 9. CI

```
{"conclusion":"success","event":"pull_request","headSha":"fd0f526299e0cd1d0954a2446cad3f45532d840e"}
```

Nothing was merged. `<throwaway>` was deleted after the run.

## What the run found

- The catalog's original name is reserved in Claude Code. Renamed.
- The skill header was not strict YAML, so `npx skills` skipped the skill. Reworded.
- The review block left Codex waiting for input that never ends. Closed.
