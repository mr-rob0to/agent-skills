# agent-skills

Skills for coding agents, grouped into plugins by purpose. Each skill is a
self-contained folder, a `SKILL.md` with its helpers beside it, so the same
folder works in Claude Code, in Codex, and in any harness that reads skill
folders.

| Plugin | Purpose | Skills |
|---|---|---|
| [`qed`](plugins/qed/README.md) | Software delivery | `ship` |

## Install

Pick your harness. Each path installs the `qed` plugin, whose one skill today is
`ship`. The catalog is named `mr-rob0to`, not `agent-skills`, because Claude
Code keeps `agent-skills` for Anthropic's own catalog.

**Claude Code**

```bash
claude plugin marketplace add mr-rob0to/agent-skills
claude plugin install qed@mr-rob0to
```

Then type `/qed:ship`. Bare `/ship` also works unless the repository you are in
defines a skill of that name, so instruction files should say `/qed:ship`.

**Codex**

```bash
codex plugin marketplace add mr-rob0to/agent-skills
codex plugin add qed@mr-rob0to
```

Then type `$qed:ship`. Bare `$ship` also works unless another installed skill
is named `ship`.

**Any other harness**

```bash
npx skills add mr-rob0to/agent-skills --skill ship
```

Or copy the folder from a clone of this repository:
`cp -R plugins/qed/skills/ship ~/.agents/skills/ship`. Copy the whole folder:
the gate runs the helpers beside its `SKILL.md` and nothing else.

**Verified on 2026-09-23.** Claude Code and Codex installed the plugin from this
repository. The gate ran end to end from the Claude Code install, and Codex
loaded the skill from `$qed:ship`. For `npx skills`, only discovery was checked:
`--list` finds the skill in a local clone. Installing it that way is untested. The recording is in
[`plugins/qed/tests/harness/ship.md`](plugins/qed/tests/harness/ship.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `make check` runs everything CI runs.

## License

MIT. See [LICENSE](LICENSE).
