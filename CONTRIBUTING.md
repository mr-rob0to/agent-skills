# Contributing

Bug reports, questions and patches are welcome. Open an issue first for anything
larger than a bug fix, and wait for a reply before you build it.

## Set up

On macOS:

```bash
brew install bats-core shellcheck jq
```

On Debian or Ubuntu:

```bash
sudo apt-get install -y bats shellcheck jq
```

Then run everything CI runs:

```bash
make check                 # every plugin
make check PLUGIN=qed      # one plugin
make check-bash32          # macOS: the same, under /bin/bash 3.2
```

`make check` also runs `claude plugin validate --strict` over the catalog and
each plugin when Claude Code is installed, and says so when it is not.

## Five rules

The checks enforce all five.

- **bash 3.2.** macOS still ships it, so no `declare -A`, no `${var^^}`, no
  `readarray`. CI runs every plugin's suite under it.
- **shellcheck clean.** Every executable under a plugin's `skills/` is checked
  with `shellcheck -s bash`.
- **Findings, not guesses.** A script that meets a surprise prints
  `finding: <what is wrong and what to change>` to stderr and exits 2.
- **No personal identifiers.** No home-directory paths, account names or private
  project names in tracked files. `make check` builds its list from the machine
  it runs on and never stores it.
- **One plugin per folder.** A plugin is a folder under `plugins/` with its own
  `.claude-plugin/plugin.json`, `skills/` and `tests/`, plus one entry in
  `.claude-plugin/marketplace.json`. Plugins share no code.

## Tests

Write the test first and see it fail. For a guard, break the guarded line once,
watch the test fail, restore it, and paste the failure into the commit message.
A test you have not seen fail is not a guard.

Tests live in `plugins/<name>/tests/`, beside `skills/` rather than inside it,
so a copied skill folder carries no test files.

## Releasing

Raise `version` in the plugin's `.claude-plugin/plugin.json` with every change
to its `skills/`. Claude Code and Codex update an installed plugin only when that
number changes, so a fix merged without it never reaches anyone who installed.
