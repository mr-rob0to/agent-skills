bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

# ship-attest-check is what a pull request's CI runs to agree the gate covered
# the commit being merged: the one attestation in the body, its head the pull
# request's head, and every phase its mode owes bound to that same commit. It
# also answers whether a pull request is docs-only, which the gate skips.

CHECK="$SKILL_DIR/ship-attest-check"
H=1111111111111111111111111111111111111111
O=2222222222222222222222222222222222222222

att() {  # $1 head, $2 mode, $3 fix passes, $4.. step:sha
  local head="$1" mode="$2" n="$3" steps="" sep="" s; shift 3
  for s in "$@"; do
    steps="$steps$sep{\"step\":\"${s%%:*}\",\"status\":\"completed\",\"sha\":\"${s#*:}\"}"; sep=","
  done
  printf '<!-- ship-attestation:v1 {"head_sha":"%s","fix_passes":%s,"review_mode":"%s","review_reason":"why","steps":[%s]} -->\n' \
    "$head" "$n" "$mode" "$steps"
}

body() {  # $@ attestation lines, wrapped in prose
  { printf '## Summary\n\nA change.\n\n'; printf '%s\n' "$@"; } > "$TEST_HOME/body"
}

verify() { run --separate-stderr "$CHECK" verify "$1" < "$TEST_HOME/body"; }

@test "a combined gate over the head passes" {
  body "$(att $H combined 0 checks:$H review:$H)"
  verify $H
  [ "$status" -eq 0 ]
  [ "$output" = "ok: the combined gate covered $H" ]
}

@test "a separate gate over the head passes" {
  body "$(att $H separate 1 checks:$H review:$H security:$H)"
  verify $H
  [ "$status" -eq 0 ]
  [ "$output" = "ok: the separate gate covered $H" ]
}

@test "a body with no attestation is a finding" {
  body
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the pull request body carries no ship attestation; run the gate" ]
}

@test "an attestation for an older head is a finding naming both commits" {
  body "$(att $O combined 0 checks:$O review:$O)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the attestation covers $O, not the head $H; the gate did not see the commit going out" ]
}

@test "two attestations are a finding, because the first one is stale" {
  body "$(att $O combined 0 checks:$O review:$O)" "$(att $H combined 0 checks:$H review:$H)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the pull request body carries 2 ship attestations; rebuild the body with one" ]
}

@test "a separate gate missing its security pass is a finding" {
  body "$(att $H separate 0 checks:$H review:$H)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the separate gate owes a security phase at $H and the attestation has none" ]
}

@test "a phase bound to an older commit is a finding" {
  body "$(att $H combined 1 checks:$H review:$O)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the review phase covered $O, not the head $H" ]
}

@test "a combined gate that claims a security phase is a finding, not a pass" {
  body "$(att $H combined 0 checks:$H review:$H security:$H)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the attestation records a security phase the combined gate does not run" ]
}

@test "a mode the gate does not have is a finding" {
  body "$(att $H none 0 checks:$H)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the attestation names review mode 'none'; expected combined or separate" ]
}

@test "more than three fix passes is a finding" {
  body "$(att $H combined 4 checks:$H review:$H)"
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the attestation counts 4 fix passes; the gate allows three" ]
}

@test "an attestation that is not JSON is a finding, never a pass" {
  body '<!-- ship-attestation:v1 {"head_sha": -->'
  verify $H
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the ship attestation is not readable JSON" ]
}

@test "a head that is not a commit id is a finding" {
  body "$(att $H combined 0 checks:$H review:$H)"
  verify not-a-sha
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: the head is not a commit id: not-a-sha" ]
}

@test "verify needs exactly one head" {
  body
  run --separate-stderr "$CHECK" verify < "$TEST_HOME/body"
  [ "$status" -eq 2 ]
  [[ "$stderr" == "finding: usage: "* ]]
}

# ---- docs-only ---------------------------------------------------------------
# The gate skips a branch whose every file is prose nothing but a person reads.
# Instruction files and anything a tool consumes are not that, whatever their
# extension.

docs() { run --separate-stderr "$CHECK" docs-only; }

@test "markdown a person reads is docs-only" {
  docs <<< $'README.md\ndocs/plans/a-plan.md\nCHANGELOG.md'
  [ "$status" -eq 0 ]
}

@test "a script among the docs is not docs-only" {
  docs <<< $'README.md\nbin/tool'
  [ "$status" -eq 1 ]
}

@test "agent instruction files are not docs-only" {
  local f
  for f in AGENTS.md CLAUDE.md sub/agents.md skills/ship/SKILL.md .claude/commands/x.md \
           .codex/prompts/x.md .agents/skills/x/notes.md .github/PULL_REQUEST_TEMPLATE.md \
           templates/brief.md; do
    docs <<< "$f"
    [ "$status" -eq 1 ] || { echo "$f read as docs-only"; return 1; }
  done
}

@test "no files at all is a finding, not docs-only" {
  docs < /dev/null
  [ "$status" -eq 2 ]
  [ "$stderr" = "finding: no changed files were given; cannot say the change is docs-only" ]
}

@test "an unknown command is a finding" {
  run --separate-stderr "$CHECK" approve
  [ "$status" -eq 2 ]
  [[ "$stderr" == "finding: usage: "* ]]
}

# ---- against the real guard ----------------------------------------------------
# The format has one owner, ship-guard. An attestation it prints for a gate it
# watched close has to pass here, and one for a commit that landed after it
# has to fail.

@test "the guard's own attestation passes, and fails once a commit lands after it" {
  repo="$TEST_HOME/repo"
  git init -q -b main "$repo"
  ( cd "$repo" && git commit -q --allow-empty -m base && git switch -q -c feature \
      && git commit -q --allow-empty -m change \
      && "$SKILL_DIR/ship-guard" open combined "a test" \
      && "$SKILL_DIR/ship-guard" record checks \
      && "$SKILL_DIR/ship-guard" record review \
      && "$SKILL_DIR/ship-guard" attest ) > "$TEST_HOME/body"
  head="$(git -C "$repo" rev-parse HEAD)"
  verify "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "ok: the combined gate covered $head" ]
  git -C "$repo" commit -q --allow-empty -m "after the gate"
  verify "$(git -C "$repo" rev-parse HEAD)"
  [ "$status" -eq 2 ]
  [[ "$stderr" == "finding: the attestation covers $head, not the head "* ]]
}

# The reusable workflow is the one caller. It has to run this file from the
# checkout it makes, ask about docs-only first, and verify against the pull
# request's own head.
@test "the reusable workflow runs this check against the pull request head" {
  wf="$PLUGIN_DIR/../../.github/workflows/ship-attestation.yml"
  [ -f "$wf" ]
  grep -q 'workflow_call:' "$wf"
  grep -qF 'CHECK: .qed/plugins/qed/skills/ship/ship-attest-check' "$wf"
  grep -qF '| "$CHECK" docs-only; then' "$wf"
  grep -qF '| "$CHECK" verify "$HEAD_SHA"' "$wf"
  grep -qF 'HEAD_SHA: ${{ github.event.pull_request.head.sha }}' "$wf"
  grep -qF 'types: [opened, edited, synchronize, reopened]' "$wf"
}
