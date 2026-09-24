bats_require_minimum_version 1.5.0

load helpers/setup

# A copy of the skill folder, put where Codex and other harnesses look for one,
# has no Claude Code to fill in its directory. It still has to find its own
# helpers, and only its own. Step 0 runs here exactly as the copy's SKILL.md
# carries it. What the helpers do once found is for ship-guard.bats and
# ship-env.bats, not this file.

# A copy under the test's own home, and a shell holding none of the names
# step 0 reads.
fresh_copy() {
  COPY="$HOME/.agents/skills/ship"
  mkdir -p "$HOME/.agents/skills"
  cp -R "$SKILL_DIR" "$COPY"
  unset CLAUDE_SKILL_DIR SHIP_DIR SHIP_GUARD SHIP_ENV
}

# The first bash block under step 0's "Resolve the two helpers", from the copy.
step0_block() {
  sed -n '/^### Resolve the two helpers/,/^## Step 0\.5/p' "$COPY/SKILL.md" | awk '
    /^```bash$/ && !found { inside = 1; next }
    /^```$/ && inside { inside = 0; found = 1; next }
    inside { print }'
}

# Runs the block, then prints where each of the three names landed.
run_step0() {
  block="$(step0_block)"
  [ -n "$block" ] || { echo "step 0 of the copy carries no block"; return 1; }
  run --separate-stderr bash -c "$block"'
printf "%s\n" "$SHIP_DIR" "$SHIP_GUARD" "$SHIP_ENV"'
}

@test "a copy with SHIP_GUARD exported resolves everything inside itself" {
  fresh_copy
  export SHIP_GUARD="$COPY/ship-guard"
  run_step0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$COPY" ]
  [ "${lines[1]}" = "$COPY/ship-guard" ]
  [ "${lines[2]}" = "$COPY/ship-env" ]
  [ -z "$stderr" ]
}

@test "a copy with SHIP_DIR set keeps it and finds both helpers beside it" {
  fresh_copy
  export SHIP_DIR="$COPY"
  run_step0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$COPY" ]
  [ "${lines[1]}" = "$COPY/ship-guard" ]
  [ "${lines[2]}" = "$COPY/ship-env" ]
  [ -z "$stderr" ]
}

@test "a copy with nothing set stops rather than running unguarded" {
  fresh_copy
  run_step0
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: cannot find ship-guard beside this skill; export SHIP_GUARD or set SHIP_DIR to the directory of this file; the gate does not run unguarded" ]
}
