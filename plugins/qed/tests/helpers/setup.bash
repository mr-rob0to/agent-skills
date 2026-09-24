# Sourced by every bats file via `load helpers/setup`.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL_DIR="$PLUGIN_DIR/skills/ship"

setup() {
  # A directory of the test's own, which bats removes after the run. Physical
  # path: git prints paths resolved through symlinks (/private/var on macOS).
  TEST_HOME="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  # A home of the test's own, so nothing here reads this machine's settings:
  # not the operator's ship config, and not their git config.
  mkdir -p "$TEST_HOME/home"
  export HOME="$TEST_HOME/home"
  unset XDG_CONFIG_HOME
  # Throwaway repos need an identity; never depend on the machine's git config.
  export GIT_AUTHOR_NAME=qed-test GIT_AUTHOR_EMAIL=qed-test@example.invalid
  export GIT_COMMITTER_NAME=qed-test GIT_COMMITTER_EMAIL=qed-test@example.invalid
}

# A bare `! cmd` can never fail a bats test: bash ignores errexit for a command
# whose return value is being inverted. An assertion that something is absent
# goes through this instead, so that the inversion happens inside a function
# and the call itself is an ordinary command that can fail.
refute() { ! "$@"; }
