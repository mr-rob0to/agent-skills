bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

# Every test builds its own repo under the fake HOME: a main checkout with one
# commit and, where the test needs one, a linked worktree beside it. The hook
# is fed the JSON a harness sends on SessionStart, with cwd set to the place
# the session started.

# A root Makefile whose worktree-setup target behaves as the contract asks:
# it writes a marker only when the marker is missing, so a second run changes
# nothing, and it records the env the hook passed. $2: the target's exit status.
makefile() {  # $1 dir, $2 exit status (default 0)
  local s="${2:-0}"
  printf 'worktree-setup:\n\t@[ -e "$(CURDIR)/marker" ] || echo ran >> "$(CURDIR)/marker"\n\t@printf "%%s|%%s|%%s\\n" "$$WORKTREE_MAIN" "$$WORKTREE_PATH" "$$WORKTREE_BRANCH" > "$(CURDIR)/env"\n\t@exit %s\n' "$s" > "$1/Makefile"
}

repo() {  # $1: with-makefile | bare. Prints nothing; sets MAIN.
  MAIN="$TEST_HOME/repo"
  git init -q -b main "$MAIN"
  [ "$1" = with-makefile ] && makefile "$MAIN"
  git -C "$MAIN" add -A && git -C "$MAIN" commit -q --allow-empty -m init
}

worktree() {  # $1 branch name, or "detached". Sets WT.
  WT="$TEST_HOME/wt"
  if [ "$1" = detached ]; then
    git -C "$MAIN" worktree add -q --detach "$WT"
  else
    git -C "$MAIN" worktree add -q -b "$1" "$WT"
  fi
}

hook() {  # $1 cwd to send (empty: send no cwd); runs from $PWD
  if [ -n "$1" ]; then
    run --separate-stderr bash -c 'printf "{\"session_id\": \"x\", \"cwd\" :  \"%s\", \"source\": \"startup\"}" "$1" | "$2"' _ "$1" "$HOOK"
  else
    run --separate-stderr bash -c 'printf "{\"session_id\": \"x\", \"source\": \"startup\"}" | "$1"' _ "$HOOK"
  fi
}

@test "1: plain checkout prints the none line and runs nothing" {
  repo with-makefile
  cd "$TEST_HOME"
  hook "$MAIN"
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: none. Plain checkout at $MAIN. Feature work needs a worktree session; base-branch work stays here." ]
  refute [ -e "$MAIN/marker" ]
  # Outside any repo the hook says nothing at all.
  mkdir -p "$TEST_HOME/plain"
  hook "$TEST_HOME/plain"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "2: worktree with a target runs it with the env" {
  repo with-makefile
  worktree feat/x
  cd "$TEST_HOME"
  hook "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: $WT on feat/x. Setup: ran make worktree-setup. Name the branch for the task before the first commit." ]
  [ "$(cat "$WT/marker")" = ran ]
  [ "$(cat "$WT/env")" = "$MAIN|$WT|feat/x" ]
  [ -f "$(git -C "$WT" rev-parse --absolute-git-dir)/worktree-setup.log" ]
}

@test "3: second run leaves one marker line" {
  repo with-makefile
  worktree feat/x
  cd "$TEST_HOME"
  hook "$WT"
  first="$output"
  hook "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  [ "$(wc -l < "$WT/marker" | tr -d ' ')" -eq 1 ]
}

@test "4: no Makefile prints none declared" {
  repo bare
  worktree feat/x
  cd "$TEST_HOME"
  hook "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: $WT on feat/x. Setup: none declared. Name the branch for the task before the first commit." ]
}

@test "5: failing target prints FAILED and exits 0" {
  repo bare
  worktree feat/x
  makefile "$WT" 3
  cd "$TEST_HOME"
  hook "$WT"
  [ "$status" -eq 0 ]
  log="$(git -C "$WT" rev-parse --absolute-git-dir)/worktree-setup.log"
  [ "$output" = "Worktree: $WT on feat/x. Setup: FAILED, see $log. Name the branch for the task before the first commit." ]
}

@test "6: detached HEAD is named and the branch env is empty" {
  repo with-makefile
  worktree detached
  cd "$TEST_HOME"
  hook "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: $WT on detached HEAD. Setup: ran make worktree-setup. Name the branch for the task before the first commit." ]
  [ "$(cat "$WT/env")" = "$MAIN|$WT|" ]
}

@test "7: no cwd on stdin falls back to PWD" {
  repo bare
  worktree feat/x
  cd "$WT"
  hook ""
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: $WT on feat/x. Setup: none declared. Name the branch for the task before the first commit." ]
}

@test "8: stdin cwd wins over PWD" {
  repo with-makefile
  worktree feat/x
  cd "$MAIN"
  hook "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: $WT on feat/x. Setup: ran make worktree-setup. Name the branch for the task before the first commit." ]
  [ -f "$WT/marker" ]
  refute [ -e "$MAIN/marker" ]
}

@test "9: a session in a subdirectory still finds the root Makefile" {
  repo with-makefile
  worktree feat/x
  mkdir -p "$WT/sub/dir"
  cd "$TEST_HOME"
  hook "$WT/sub/dir"
  [ "$status" -eq 0 ]
  [ "$output" = "Worktree: $WT on feat/x. Setup: ran make worktree-setup. Name the branch for the task before the first commit." ]
  [ -f "$WT/marker" ]
}
