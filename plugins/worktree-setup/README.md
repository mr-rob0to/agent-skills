# worktree-setup

A `SessionStart` hook for Claude Code and Codex. When a session starts, it
tells the agent where it is: the plain checkout, or a linked worktree on a
named branch or a detached HEAD. In a linked worktree, it also runs the
repository's own setup, if the repository declares one.

The plugin knows nothing about any repository. Each repository says what its
worktrees need through one Makefile target.

## What the agent sees

One line, added to the session's context:

```
Worktree: none. Plain checkout at <path>. Feature work needs a worktree session; base-branch work stays here.
Worktree: <path> on <branch>|detached HEAD. Setup: ran make worktree-setup|none declared|FAILED, see <log>. Name the branch for the task before the first commit.
```

Outside a git repository it prints nothing.

## The repository contract

**Detection.** The root `Makefile` of the worktree has a line that starts with
the literal text `worktree-setup:`. Nothing else is looked for.

**How it runs.** `make worktree-setup`, with the working directory set to the
worktree's root, these variables set, and output written to
`<git-dir>/worktree-setup.log`:

| Variable | Value |
|---|---|
| `WORKTREE_MAIN` | the main checkout's path |
| `WORKTREE_PATH` | this worktree's root |
| `WORKTREE_BRANCH` | the current branch, empty on a detached HEAD |

The target should derive the same values from git when the variables are unset,
so it also works when run by hand.

**What the target must guarantee.**

- Run twice, it changes nothing the second time.
- Run twice at once, it is safe (for example, a `mkdir` lock that the second
  run sees and exits 0 on).
- Nothing to do is exit 0.

**Failure.** A non-zero exit is reported in the line as `Setup: FAILED, see
<log>`. The hook itself always exits 0, so the session starts and the agent
reads why.

**Example.**

```make
worktree-setup:
	@[ -e .env ] || cp "$${WORKTREE_MAIN:-$$(dirname "$$(git rev-parse --path-format=absolute --git-common-dir)")}/.env" .env
	@[ -d node_modules ] || npm ci
	@echo "worktree ready"
```

## Hook

`SessionStart`, matcher `startup|resume`, timeout 300 seconds. The session's
directory comes from the `cwd` field the harness sends on stdin, falling back to
the hook's own working directory. A session started in a subdirectory still
finds the worktree's root `Makefile`.

In Codex, a plugin hook runs only after you trust it once; until then it is
skipped without a message.
