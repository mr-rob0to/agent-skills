# agent-skills

Skills for coding agents, grouped into plugins by purpose. Each skill is a
self-contained folder, a `SKILL.md` with its helpers beside it, so the same
folder works in Claude Code, in Codex, and in any harness that reads skill
folders.

| Plugin | Purpose | Skills |
|---|---|---|
| [`qed`](plugins/qed/README.md) | Software delivery | `ship` |
| [`worktree-setup`](plugins/worktree-setup/README.md) | Worktree sessions | none; a `SessionStart` hook |

## Install

Pick your harness. Each path installs the `qed` plugin, whose one skill today is
`ship`.

**Claude Code**

```bash
claude plugin marketplace add mr-rob0to/agent-skills
claude plugin install qed@mr-rob0to
```

Then type `/qed:ship`. Bare `/ship` also works unless the repository you are in
defines a skill of that name.

**Codex**

```bash
codex plugin marketplace add mr-rob0to/agent-skills
codex plugin add qed@mr-rob0to
```

Then type `$qed:ship`. Bare `$ship` also works unless another installed skill
is named `ship`.

**`worktree-setup`** installs the same way, in either harness:
`claude plugin install worktree-setup@mr-rob0to` or
`codex plugin add worktree-setup@mr-rob0to`. Codex asks you to trust its hook
once. It has no skill to copy into other harnesses.

**Any other harness**

```bash
npx skills add mr-rob0to/agent-skills --skill ship
```

Or copy the folder from a clone of this repository:
`cp -R plugins/qed/skills/ship ~/.agents/skills/ship`. Copy the whole folder:
the gate runs the helpers beside its `SKILL.md` and nothing else.

The Claude Code and Codex installs are tested. The `npx skills` install is not.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `make check` runs everything CI runs.

## License

MIT. See [LICENSE](LICENSE).
