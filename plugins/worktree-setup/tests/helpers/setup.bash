# Sourced by every bats file via `load helpers/setup`.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/session-start"

setup() {
  # A directory of the test's own, which bats removes after the run. Physical
  # path: git prints paths resolved through symlinks (/private/var on macOS).
  TEST_HOME="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  # A home of the test's own, so nothing here reads this machine's git config.
  mkdir -p "$TEST_HOME/home"
  export HOME="$TEST_HOME/home"
  unset XDG_CONFIG_HOME WORKTREE_MAIN WORKTREE_PATH WORKTREE_BRANCH
  # Throwaway repos need an identity; never depend on the machine's git config.
  export GIT_AUTHOR_NAME=wt-test GIT_AUTHOR_EMAIL=wt-test@example.invalid
  export GIT_COMMITTER_NAME=wt-test GIT_COMMITTER_EMAIL=wt-test@example.invalid
}

# A bare `! cmd` can never fail a bats test: bash ignores errexit for a command
# whose return value is being inverted. An assertion that something is absent
# goes through this instead.
refute() { ! "$@"; }
