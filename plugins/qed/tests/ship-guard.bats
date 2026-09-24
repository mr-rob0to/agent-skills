bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

# The guard is not on PATH: it lives beside SKILL.md, so it travels with the
# skill folder, and /ship finds it by path.
guard() { "$SKILL_DIR/ship-guard" "$@"; }

# A repository with two commits, so a test can move HEAD backwards.
new_repo() {  # $1 branch; prints the path
  local d="$TEST_HOME/repo"
  git init -q -b "$1" "$d"
  git -C "$d" commit -q --allow-empty -m one
  git -C "$d" commit -q --allow-empty -m two
  echo "$d"
}

state_file() { echo "$(git rev-parse --absolute-git-dir)/ship-guard/$1"; }
short() { git rev-parse --short HEAD; }

full_gate() {
  guard open && guard record checks && guard record review && guard record security
}

@test "open writes the branch and a zero fix count inside the git directory" {
  cd "$(new_repo main)"
  run --separate-stderr guard open
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  f="$(state_file main)"
  [ -f "$f" ]
  grep -qx 'version=2' "$f"
  grep -qx 'branch=main' "$f"
  grep -qx 'fix_passes=0' "$f"
  # No mode stated is the careful mode, and the reason says so rather than
  # leaving a reader to guess why the gate ran three phases.
  grep -qx 'review_mode=separate' "$f"
  grep -qx 'review_reason=no classification was recorded' "$f"
  # The state is untracked and invisible to the repository being shipped.
  [ -z "$(git status --porcelain)" ]
}

@test "a clean gate records three phases and lets the push through" {
  cd "$(new_repo main)"
  run guard open
  [ "$status" -eq 0 ]
  run guard record checks
  [ "$status" -eq 0 ]
  run guard check checks
  [ "$status" -eq 0 ]
  run guard record review
  [ "$status" -eq 0 ]
  run guard check review
  [ "$status" -eq 0 ]
  run guard record security
  [ "$status" -eq 0 ]
  run guard check security
  [ "$status" -eq 0 ]
  run guard push-ok
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

@test "push-ok refuses a commit that landed after the gate ran" {
  cd "$(new_repo main)"
  full_gate
  gated="$(short)"
  git commit -q --allow-empty -m "late fix"
  head="$(short)"
  run guard push-ok
  [ "$status" -eq 2 ]
  # Every phase is stale here; the first one reported is the earliest.
  [[ "$output" == "finding: the checks covered $gated, not HEAD $head; open a fix pass and record every phase again"* ]]
}

@test "push-ok names the review when the review is the stale one" {
  cd "$(new_repo main)"
  full_gate
  reviewed="$(short)"
  git commit -q --allow-empty -m "late fix"
  head="$(git rev-parse HEAD)"
  # Only a hand-edited file can single the review out: a legal flow can no
  # longer move checks and security past it without a fix pass clearing it too.
  f="$(state_file main)"
  sed -i.bak -e "s/^checks=.*/checks=$head/" -e "s/^security=.*/security=$head/" "$f"
  rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the review covered $reviewed, not HEAD $(short); open a fix pass and record every phase again"* ]]
}

@test "push-ok refuses when the security pass was never recorded" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  guard record review
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no security recorded for main; the gate did not run in order"* ]]
}

@test "check refuses a HEAD that does not descend from the recorded phase" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  recorded="$(short)"
  git commit -q --amend --allow-empty -m "rewritten"
  head="$(short)"
  run guard check checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: HEAD $head does not descend from the checks commit $recorded; open the gate again"* ]]
}

@test "record applies the same descent test as check" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  recorded="$(short)"
  git commit -q --amend --allow-empty -m "rewritten"
  head="$(short)"
  run guard record review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: HEAD $head does not descend from the checks commit $recorded; open the gate again"* ]]
}

@test "record refuses a phase whose predecessor was never recorded" {
  cd "$(new_repo main)"
  guard open
  run guard record review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no checks recorded for main; the gate did not run in order"* ]]
  guard record checks
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no review recorded for main; the gate did not run in order"* ]]
}

@test "check refuses a phase that was never recorded" {
  cd "$(new_repo main)"
  guard open
  run guard check review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no review recorded for main; the gate did not run in order"* ]]
}

@test "record and check refuse an unknown phase" {
  cd "$(new_repo main)"
  guard open
  run guard record pr
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown phase 'pr' (checks, review, security)"* ]]
  run guard check pr
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown phase 'pr' (checks, review, security)"* ]]
}

@test "every verb but open refuses when the gate was never opened" {
  cd "$(new_repo main)"
  for args in "record checks" "check checks" "fix-pass" "push-ok"; do
    # shellcheck disable=SC2086
    run guard $args
    [ "$status" -eq 2 ]
    [[ "$output" == "finding: no guard file for main; the gate was never opened"* ]]
  done
}

@test "a guard file naming another branch is refused, not trusted" {
  cd "$(new_repo main)"
  guard open
  f="$(state_file main)"
  # The file is untracked and world-writable by anything running as this
  # account, so a file that names another branch is a refusal, not a record.
  sed -i.bak 's/^branch=main$/branch=other/' "$f" && rm -f "$f.bak"
  run guard record checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file names other, not main; open the gate again"* ]]
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file names other, not main; open the gate again"* ]]
}

@test "a renamed branch has no gate of its own" {
  cd "$(new_repo main)"
  full_gate
  git branch -m main renamed
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no guard file for renamed; the gate was never opened"* ]]
}

@test "a detached HEAD is a finding" {
  cd "$(new_repo main)"
  git checkout -q --detach HEAD
  run guard open
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: /ship guard needs a branch; HEAD is detached"* ]]
}

@test "outside a git repository is a finding" {
  cd "$TEST_HOME"
  run guard open
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: /ship guard must run inside a git repository"* ]]
}

@test "a fix pass clears every phase, so each one is recorded again" {
  cd "$(new_repo main)"
  full_gate
  run guard fix-pass
  [ "$status" -eq 0 ]
  [[ "$output" == "fix pass 1 of 3" ]]
  f="$(state_file main)"
  refute grep -q '^checks=' "$f"
  refute grep -q '^review=' "$f"
  refute grep -q '^security=' "$f"
  grep -qx 'fix_passes=1' "$f"
}

@test "a fix pass reaches a push, which is the whole point of clearing the phases" {
  cd "$(new_repo main)"
  full_gate
  guard fix-pass
  git commit -q --allow-empty -m "the fix"
  guard record checks
  guard record review
  guard record security
  run guard push-ok
  [ "$status" -eq 0 ]
}

@test "fix-pass takes no argument" {
  cd "$(new_repo main)"
  guard open
  run guard fix-pass security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: ship-guard open [combined|separate <reason>] | record <phase> | check <phase> | fix-pass | attest | push-ok"* ]]
}

@test "the fourth fix pass is refused" {
  cd "$(new_repo main)"
  guard open
  run guard fix-pass
  [[ "$output" == "fix pass 1 of 3" ]]
  run guard fix-pass
  [[ "$output" == "fix pass 2 of 3" ]]
  run guard fix-pass
  [[ "$output" == "fix pass 3 of 3" ]]
  run guard fix-pass
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: three fix passes already; revert to the minimal fix and stop"* ]]
}

@test "opening the gate again starts the fix count over" {
  cd "$(new_repo main)"
  guard open
  guard fix-pass
  guard fix-pass
  guard fix-pass
  guard open
  run guard fix-pass
  [ "$status" -eq 0 ]
  [[ "$output" == "fix pass 1 of 3" ]]
}

@test "the guard works from a subdirectory" {
  repo="$(new_repo main)"
  mkdir -p "$repo/deep/inside"
  cd "$repo/deep/inside"
  run guard open
  [ "$status" -eq 0 ]
  run guard record checks
  [ "$status" -eq 0 ]
  [ -f "$repo/.git/ship-guard/main" ]
}

@test "a linked worktree keeps its own guard file, and a slash in the branch is encoded" {
  repo="$(new_repo main)"
  git -C "$repo" worktree add -q -b feat/x "$repo/wt" >/dev/null
  cd "$repo"
  guard open
  guard record checks
  cd "$repo/wt"
  run guard open
  [ "$status" -eq 0 ]
  # Two gates, two files, neither inside the other's git directory.
  [ -f "$repo/.git/ship-guard/main" ]
  [ -f "$repo/.git/worktrees/wt/ship-guard/feat%2Fx" ]
  # The linked worktree's gate is its own: it has no phase recorded yet.
  run guard check checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no checks recorded for feat/x; the gate did not run in order"* ]]
}

@test "an unknown verb prints the usage line" {
  cd "$(new_repo main)"
  run guard verify
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: ship-guard open [combined|separate <reason>] | record <phase> | check <phase> | fix-pass | attest | push-ok"* ]]
}

@test "push-ok refuses a guard file counting more fix passes than the gate allows" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  # Same reason as the branch check: the file is untracked, so what it claims
  # about itself is checked rather than believed.
  sed -i.bak 's/^fix_passes=0$/fix_passes=9/' "$f" && rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file counts 9 fix passes, more than three; revert to the minimal fix and stop"* ]]
}

@test "record refuses to move a phase to a new commit without a fix pass" {
  cd "$(new_repo main)"
  full_gate
  recorded="$(short)"
  git commit -q --allow-empty -m "one more small fix"
  # The refusal push-ok prints says "record it again". Doing literally that is
  # how the gate gets walked past, so record has to refuse it.
  run guard record review
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: review is already recorded at $recorded; recording a new commit needs a fix pass"* ]]
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: security is already recorded at $recorded; recording a new commit needs a fix pass"* ]]
}

@test "record at the commit already recorded is allowed, so a repeated call is not a trap" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  run guard record checks
  [ "$status" -eq 0 ]
}

@test "push-ok refuses when the checks are older than the commit going out" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  checked="$(short)"
  git commit -q --allow-empty -m "committed after the suite ran"
  head="$(short)"
  guard record review
  guard record security
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the checks covered $checked, not HEAD $head; open a fix pass and record every phase again"* ]]
}

@test "a fix count that is not a number is a finding, not a fresh gate" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  sed -i.bak 's/^fix_passes=0$/fix_passes=three/' "$f" && rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file's fix count is not a number; open the gate again"* ]]
  run guard fix-pass
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file's fix count is not a number; open the gate again"* ]]
}

@test "attest lets no unchecked phase value into the attestation" {
  cd "$(new_repo main)"
  full_gate
  head_sha="$(git rev-parse HEAD)"
  f="$(state_file main)"

  # Two planted values, because one is not enough to tell the two checks apart.
  # A single "not-a-sha" is caught by the length check and by the hex check, so
  # deleting either one on its own left the test green. That was a finding: the
  # assertion never reached the check it was written for.
  #
  # 40 characters, several of them not hex. Only the hex check sees this. The
  # length is asserted here so a later edit cannot quietly make it 39 and hand
  # the catch back to the length check.
  bad="zzzzzzzz--> injected zzzzzzzzzzzzzzzzzzz"
  [ "${#bad}" -eq 40 ]
  sed -i.bak "s|^review=.*|review=$bad|" "$f" && rm -f "$f.bak"
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the review commit is not a commit id: "* ]]
  [[ "$output" != *"ship-attestation"* ]]

  # Valid hex, 39 characters. Only the length check sees this.
  short="${head_sha%?}"
  sed -i.bak "s|^review=.*|review=$short|" "$f" && rm -f "$f.bak"
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the review commit is not a commit id: $short"* ]]
  [[ "$output" != *"ship-attestation"* ]]

  # Restored: one attestation comment, and the value in it is the checked one.
  sed -i.bak "s|^review=.*|review=$head_sha|" "$f" && rm -f "$f.bak"
  run guard attest
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '-->' <<< "$output")" -eq 1 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  [ "$(jq -r '.steps[] | select(.step == "review") | .sha' <<< "$json")" = "$head_sha" ]
}

@test "a fix count with a leading zero is a finding, so attest cannot print bad JSON" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  # 00 is digits, and every caller that does arithmetic on it reads it as zero.
  # attest prints it into the JSON unquoted, where it is not a number at all, so
  # the attestation would stop parsing while the gate reported success.
  sed -i.bak 's/^fix_passes=0$/fix_passes=00/' "$f" && rm -f "$f.bak"
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file's fix count has a leading zero: 00; open the gate again"* ]]
  run guard push-ok
  [ "$status" -eq 2 ]
  run guard fix-pass
  [ "$status" -eq 2 ]
  # A plain zero is the count open writes, and it stays valid.
  sed -i.bak 's/^fix_passes=00$/fix_passes=0/' "$f" && rm -f "$f.bak"
  run guard attest
  [ "$status" -eq 0 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  run jq -e . <<< "$json"
  [ "$status" -eq 0 ]
}

@test "record and push-ok refuse a fix that was never committed" {
  cd "$(new_repo main)"
  guard open
  guard record checks
  guard record review
  echo "the fix" > tracked.txt
  git add tracked.txt
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worktree has uncommitted changes; the push would not carry them"* ]]
  git commit -q -m "the fix"
  guard open && guard record checks && guard record review && guard record security
  echo "forgotten" >> tracked.txt
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the worktree has uncommitted changes; the push would not carry them"* ]]
}

@test "untracked files do not block the gate, because ship worktrees carry env files" {
  cd "$(new_repo main)"
  full_gate
  echo "SECRET=x" > .env
  run guard push-ok
  [ "$status" -eq 0 ]
}

@test "a git status that fails is a stop, not a clean worktree" {
  cd "$(new_repo main)"
  guard open
  # Every other guard here turns a git error into a refusal. This one used to
  # throw the error away and read the empty output as a clean tree.
  printf 'garbage' > .git/index
  run guard record checks
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: git status failed; cannot prove the worktree is clean"* ]]
}

@test "the moved-phase refusal does not name the one command that resets the count" {
  cd "$(new_repo main)"
  full_gate
  git commit -q --allow-empty -m "one more small fix"
  run guard record review
  [ "$status" -eq 2 ]
  # Naming open here would hand back the dodge this refusal exists to close:
  # open zeroes the fix count and clears every phase.
  [[ "$output" != *"open the gate"* ]]
}

@test "a missing fix count is a finding, the same as an unreadable one" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  # open always writes the line and no verb removes it, so an absent count has
  # the same provenance as a garbled one.
  grep -v '^fix_passes=' "$f" > "$f.next" && mv "$f.next" "$f"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file has no fix count; open the gate again"* ]]
}

# The attestation is derived from the guard file, so it lives with the one thing
# that knows that file's format. Building the JSON in prose would put the format
# in two places and let them drift.
@test "attest carries the head, the fix count and the three phases" {
  cd "$(new_repo main)"
  full_gate
  head_sha="$(git rev-parse HEAD)"
  run --separate-stderr guard attest
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" == '<!-- ship-attestation:v1 '* ]]
  [[ "$output" == *' -->' ]]
  json="${output#<!-- ship-attestation:v1 }"
  json="${json% -->}"
  run jq -e . <<< "$json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .head_sha <<< "$json")" = "$head_sha" ]
  [ "$(jq -r .fix_passes <<< "$json")" = 0 ]
  [ "$(jq -r '.steps | length' <<< "$json")" = 3 ]
  [ "$(jq -r '[.steps[].step] | join(",")' <<< "$json")" = "checks,review,security" ]
  for p in checks review security; do
    [ "$(jq -r --arg p "$p" '.steps[] | select(.step == $p) | .sha' <<< "$json")" = "$head_sha" ]
    [ "$(jq -r --arg p "$p" '.steps[] | select(.step == $p) | .status' <<< "$json")" = completed ]
  done
  # Step 8 writes it before pr and ci have happened, so it never claims them.
  [ "$(jq -r '[.steps[].step] | index("pr")' <<< "$json")" = null ]
  [ "$(jq -r '[.steps[].step] | index("ci")' <<< "$json")" = null ]
}

@test "attest reports the fix count it was given" {
  cd "$(new_repo main)"
  full_gate
  guard fix-pass > /dev/null
  guard record checks && guard record review && guard record security
  run guard attest
  [ "$status" -eq 0 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  [ "$(jq -r .fix_passes <<< "$json")" = 1 ]
}

@test "attest refuses each phase that was never recorded" {
  cd "$(new_repo main)"
  guard open
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no checks recorded for main; the gate did not run in order"* ]]
  guard record checks
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no review recorded for main; the gate did not run in order"* ]]
  guard record review
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no security recorded for main; the gate did not run in order"* ]]
}

@test "attest refuses a phase whose value is not a commit id" {
  cd "$(new_repo main)"
  for bad in deadbeef "$(git rev-parse HEAD)x" "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"; do
    full_gate
    f="$(state_file main)"
    # The file is untracked and anything running as this account can write it,
    # so what it says about itself is checked before it reaches the pull request.
    { grep -v '^review=' "$f"; echo "review=$bad"; } > "$f.next" && mv "$f.next" "$f"
    run guard attest
    [ "$status" -eq 2 ]
    [[ "$output" == "finding: the review commit is not a commit id: $bad"* ]] \
      || { echo "wrong refusal for '$bad': $output"; return 1; }
    [[ "$output" != *ship-attestation* ]]
  done
}

@test "attest takes no arguments and needs a gate that was opened" {
  cd "$(new_repo main)"
  full_gate
  run guard attest extra
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: usage: ship-guard "* ]]
  [[ "$output" == *attest* ]]
  rm "$(state_file main)"
  run guard attest
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no guard file for main; the gate was never opened"* ]]
}

# ---- review modes ----------------------------------------------------------
# A combined gate is one reviewer instead of two, so everything below is about
# the ways a gate could end up claiming that without having earned it.

combined_gate() {
  guard open combined "nothing sensitive in the diff" \
    && guard record checks && guard record review
}

@test "open records the mode and reason it was given" {
  cd "$(new_repo main)"
  run --separate-stderr guard open combined "no auth, no migration, no money"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  f="$(state_file main)"
  grep -qx 'review_mode=combined' "$f"
  grep -qx 'review_reason=no auth, no migration, no money' "$f"
}

@test "an unknown review mode is refused, and nothing is opened" {
  cd "$(new_repo main)"
  run guard open quick "faster"
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: unknown review mode 'quick' (combined, separate)"* ]]
  [ ! -e "$(state_file main)" ]
}

@test "a mode with no reason is refused: a combined gate states why it is combined" {
  cd "$(new_repo main)"
  run guard open combined
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: a review mode needs a reason"* ]]
  [ ! -e "$(state_file main)" ]
  run guard open separate "   "
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: a review mode needs a reason"* ]]
  [ ! -e "$(state_file main)" ]
}

@test "the reason is flattened to one line, so it cannot forge another key" {
  cd "$(new_repo main)"
  guard open combined "$(printf 'looks fine\nreview_mode=combined')"
  f="$(state_file main)"
  [ "$(grep -c '^review_mode=' "$f")" -eq 1 ]
  [ "$(grep -c '^review_reason=' "$f")" -eq 1 ]
  grep -qx 'review_reason=looks finereview_mode=combined' "$f"
}

@test "a combined gate has no security phase to record or check" {
  cd "$(new_repo main)"
  guard open combined "nothing sensitive"
  guard record checks
  guard record review
  run guard record security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: this gate is a combined review; it has no security phase"* ]]
  run guard check security
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: this gate is a combined review; it has no security phase"* ]]
}

@test "a combined gate pushes on two phases; a separate one still needs three" {
  cd "$(new_repo main)"
  combined_gate
  run guard push-ok
  [ "$status" -eq 0 ]

  d="$TEST_HOME/repo2"
  git init -q -b other "$d"
  git -C "$d" commit -q --allow-empty -m one
  cd "$d"
  guard open separate "touches auth"
  guard record checks
  guard record review
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: no security recorded for other; the gate did not run in order"* ]]
}

@test "a combined gate's attestation names its mode and carries two steps" {
  cd "$(new_repo main)"
  combined_gate
  head_sha="$(git rev-parse HEAD)"
  run guard attest
  [ "$status" -eq 0 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  run jq -e . <<< "$json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .review_mode <<< "$json")" = combined ]
  [ "$(jq -r .review_reason <<< "$json")" = "nothing sensitive in the diff" ]
  [ "$(jq -r '[.steps[].step] | join(",")' <<< "$json")" = "checks,review" ]
  [ "$(jq -r '.steps[] | select(.step == "review") | .sha' <<< "$json")" = "$head_sha" ]
}

@test "a separate gate's attestation names its mode and still carries three steps" {
  cd "$(new_repo main)"
  full_gate
  run guard attest
  [ "$status" -eq 0 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  [ "$(jq -r .review_mode <<< "$json")" = separate ]
  [ "$(jq -r '[.steps[].step] | join(",")' <<< "$json")" = "checks,review,security" ]
}

@test "a reason holding a quote still leaves the attestation parseable" {
  cd "$(new_repo main)"
  guard open combined 'the "whole" branch is prose and one script'
  guard record checks && guard record review
  run guard attest
  [ "$status" -eq 0 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  run jq -e . <<< "$json"
  [ "$status" -eq 0 ]
}

@test "a fix pass on a combined gate clears its two phases and reaches a push" {
  cd "$(new_repo main)"
  combined_gate
  guard fix-pass
  f="$(state_file main)"
  refute grep -q '^checks=' "$f"
  refute grep -q '^review=' "$f"
  # The mode survives a fix pass: a fix does not reclassify the branch.
  grep -qx 'review_mode=combined' "$f"
  git commit -q --allow-empty -m "the fix"
  guard record checks && guard record review
  run guard push-ok
  [ "$status" -eq 0 ]
}

@test "a guard file with a mode nothing can read is refused, not read as combined" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  { grep -v '^review_mode=' "$f"; echo "review_mode=quick"; } > "$f.next" && mv "$f.next" "$f"
  for args in "record checks" "check checks" "push-ok" "attest" "fix-pass"; do
    # shellcheck disable=SC2086
    run guard $args
    [ "$status" -eq 2 ]
    [[ "$output" == "finding: the guard file's review mode is not a mode: quick; open the gate again"* ]]
  done
}

# A gate opened by the previous version of this file has no mode line at all.
# Reading that as combined would retire a security pass that did run, so it
# reads as what it was.
@test "a guard file from before review modes is read as separate" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  { grep -v '^review_mode=' "$f" | grep -v '^review_reason=' | sed 's/^version=2$/version=1/'; } \
    > "$f.next" && mv "$f.next" "$f"
  run guard push-ok
  [ "$status" -eq 0 ]
  run guard attest
  [ "$status" -eq 0 ]
  json="${output#<!-- ship-attestation:v1 }"; json="${json% -->}"
  [ "$(jq -r .review_mode <<< "$json")" = separate ]
  [ "$(jq -r '[.steps[].step] | join(",")' <<< "$json")" = "checks,review,security" ]
}

@test "a version this file does not know is refused rather than guessed at" {
  cd "$(new_repo main)"
  full_gate
  f="$(state_file main)"
  sed -i.bak 's/^version=2$/version=9/' "$f" && rm -f "$f.bak"
  run guard push-ok
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: the guard file's version is 9, which this gate cannot read; open the gate again"* ]]
}

@test "open takes at most a mode and a reason" {
  cd "$(new_repo main)"
  run guard open combined
  [ "$status" -eq 2 ]
  [[ "$output" == "finding: a review mode needs a reason"* ]]
}
