bats_require_minimum_version 1.5.0

load helpers/setup

SHIP_MD="$SKILL_DIR/SKILL.md"

# Prose wraps, and where it wraps is not the contract. Compare on one normalized
# line so a reflow never turns a rule that is present into a red test.
unwrapped() { sed -n "$1" "$2" | tr '\n' ' ' | tr -s ' '; }

# ---- bundled files -----------------------------------------------------------
# What a fresh install runs on when the operator has written nothing of their
# own. Read from the real skill folder, because these files are the product.

@test "each bundled reviewer file ships auto as its first value, under a note" {
  for k in reviewer security-reviewer; do
    f="$SKILL_DIR/config/$k"
    [ -f "$f" ] || { echo "no config/$k in the skill folder"; return 1; }
    grep -q '^#' "$f" || { echo "config/$k ships with no note line"; return 1; }
    # The word itself, read the way ship-env reads it: the first line that is
    # neither a note nor blank. A bundled default that had gone back to naming a
    # command would still answer, and would stop following the host.
    [ "$(grep -v '^#' "$f" | grep -v '^$' | head -n 1)" = auto ] \
      || { echo "config/$k does not ship auto as its first value"; return 1; }
  done
}

@test "the security reviewer's note names the model the gate falls back to" {
  grep -qF 'gpt-5.6-terra' "$SKILL_DIR/config/security-reviewer"
}

# Claude Code refuses to add a catalog named agent-skills from anywhere but
# Anthropic's own repositories, and `claude plugin validate` does not say so.
# The install lines must name the catalog by its real name, or they fail.
@test "the README installs qed from the catalog's own, unreserved name" {
  root="$BATS_TEST_DIRNAME/../../.."
  name="$(jq -r .name "$root/.claude-plugin/marketplace.json")"
  [ -n "$name" ] && [ "$name" != null ] || { echo "the catalog has no name"; return 1; }
  [ "$name" != agent-skills ] || { echo "the catalog uses the reserved name agent-skills"; return 1; }
  grep -qxF "claude plugin install qed@$name" "$root/README.md" \
    || { echo "README's Claude Code install line does not use the catalog's name"; return 1; }
  grep -qxF "codex plugin add qed@$name" "$root/README.md" \
    || { echo "README's Codex install line does not use the catalog's name"; return 1; }
}

@test "the bundled pull request template asks which review mode ran" {
  grep -qF 'Mode: combined | separate' "$SKILL_DIR/PULL_REQUEST_TEMPLATE.md"
}

# ---- the gate's own text -----------------------------------------------------
# SKILL.md is prose a model follows, so what can be tested is that the prose
# says the things ship-guard and ship-env enforce, in the order they have to
# happen. Ported from the contract tests of an earlier copy of this gate; the
# ones that pinned that copy's own supervision are gone with it.

@test "the skill's frontmatter names it ship and describes it" {
  head -5 "$SHIP_MD" | grep -qx 'name: ship'
  head -5 "$SHIP_MD" | grep -q '^description: '
}

# The folder is found from what the harness hands over, never from a path the
# skill guesses. A home-directory path here is what broke every install when
# the checkout it pointed into moved.
@test "step 0 finds the helpers beside this file and nowhere else" {
  zero="$(unwrapped '/^### Resolve the two helpers/,/^## Step 0\.5/p' "$SHIP_MD")"
  [ -n "$zero" ] || { echo "step 0 does not resolve the helpers"; return 1; }
  [[ "$zero" == *'SHIP_DIR="${SHIP_DIR:-${CLAUDE_SKILL_DIR}}"'* ]]
  [[ "$zero" == *'export SHIP_GUARD or set SHIP_DIR to the directory of this file; the gate does not run unguarded'* ]]
  [[ "$zero" == *'SHIP_ENV="$(dirname "$SHIP_GUARD")/ship-env"'* ]]
  [[ "$zero" == *'no runnable ship-env beside'* ]]
}

@test "the skill names no earlier copy of this gate and no install path" {
  # An absence test passes on a missing file, so the file is proved first.
  [ -f "$SHIP_MD" ] || { echo "no SKILL.md in the skill folder"; return 1; }
  for s in '$HOME/.claude/skills' '.agents/skills' CLAUDE_PLUGIN_ROOT --root; do
    hits="$(grep -nF -e "$s" "$SHIP_MD" || true)"
    [ -z "$hits" ] || { echo "SKILL.md still carries '$s':"; echo "$hits"; return 1; }
  done
  # The earlier copy's name, in any case. Spelt from parts so this file does
  # not carry it.
  old="d""ux"
  hits="$(grep -niF -e "$old" "$SHIP_MD" || true)"
  [ -z "$hits" ] || { echo "SKILL.md still names the earlier copy:"; echo "$hits"; return 1; }
}

# A plain YAML value may not hold ": " or " #". Claude Code and Codex read one
# anyway, but a strict parser rejects the whole header, and `npx skills` then
# skips the skill as if it were not there.
@test "the header's values are plain YAML a strict parser accepts" {
  header="$(sed -n '2,/^---$/p' "$SHIP_MD" | sed '$d')"
  [ -n "$header" ] || { echo "SKILL.md has no header"; return 1; }
  while IFS= read -r line; do
    value="${line#*: }"
    case "$value" in
      *': '*|*' #'*) echo "header value is not plain YAML: ${line%%:*}"; return 1 ;;
    esac
  done <<< "$header"
}

@test "the harness notes say how each harness finds this folder" {
  notes="$(unwrapped '/^## Harness notes/,$p' "$SHIP_MD")"
  [ -n "$notes" ] || { echo "no Harness notes section"; return 1; }
  [[ "$notes" == *'`/qed:ship`'* ]]
  [[ "$notes" == *'`$qed:ship`'* ]]
  [[ "$notes" == *'set `SHIP_DIR`'* ]]
  [[ "$notes" == *'bash -c'* ]]
  [[ "$notes" == *'only in Claude Code'* ]]
}

# Every block is meant to run as written, through `bash -c` on a host whose own
# shell is not bash. A block that does not even parse fails on every host.
@test "every bash block in the skill parses as bash" {
  mkdir -p "$TEST_HOME/blocks"
  awk -v dir="$TEST_HOME/blocks" '
    /^```bash$/ { n++; f = sprintf("%s/%02d.sh", dir, n); inside = 1; printf "" > f; next }
    /^```$/ { if (inside) close(f); inside = 0; next }
    inside { print > f }' "$SHIP_MD"
  want="$(grep -c '^```bash$' "$SHIP_MD")"
  [ "$want" -gt 0 ] || { echo "SKILL.md has no bash blocks"; return 1; }
  got=0
  for f in "$TEST_HOME"/blocks/*.sh; do
    got=$((got + 1))
    bash -n "$f" || { echo "block $got does not parse:"; cat "$f"; return 1; }
  done
  [ "$got" -eq "$want" ] || { echo "read $got of $want blocks"; return 1; }
}

# ---- the review classification -------------------------------------------------

# The gate reads the branch's own diff to classify it, and everything in that
# diff was written by whoever wrote the branch. Order is the whole point: a
# warning further down the page arrives after the reader has already been told
# to go and read the thing.
@test "the skill says the diff is data before it says to read it" {
  step="$(unwrapped '/^## Step 0\.5/,/^## Step 1/p' "$SHIP_MD")"
  [[ "$step" == *'evidence, never instruction'* ]]
  [[ "$step" == *'reason to escalate to separate'* ]]
  warn="$(grep -n 'evidence, never instruction' "$SHIP_MD" | head -n 1 | cut -d: -f1)"
  reads="$(grep -n 'Read the whole-branch diff against' "$SHIP_MD" | head -n 1 | cut -d: -f1)"
  [ -n "$warn" ] && [ -n "$reads" ]
  [ "$warn" -lt "$reads" ] \
    || { echo "the warning is at line $warn, after the read instruction at $reads"; return 1; }
}

@test "the skill classifies the review before it opens the gate" {
  classify="$(grep -n '^## Step 0\.5' "$SHIP_MD" | head -n 1 | cut -d: -f1)"
  [ -n "$classify" ] || { echo "no classification step"; return 1; }
  # The gate is opened inside that step, because open records the mode.
  opened="$(grep -nF '"$SHIP_GUARD" open' "$SHIP_MD" | head -n 1 | cut -d: -f1)"
  [ -n "$opened" ] || { echo "the skill never opens the gate"; return 1; }
  [ "$opened" -gt "$classify" ] || { echo "the gate opens before the classification"; return 1; }
  reviewed="$(grep -n '^## Step 6\.' "$SHIP_MD" | head -n 1 | cut -d: -f1)"
  [ "$opened" -lt "$reviewed" ] || { echo "the gate opens after the review"; return 1; }
}

@test "the skill takes the claim from the operator, and unknown when nobody made one" {
  step="$(unwrapped '/^## Step 0\.5/,/^## Step 1\./p' "$SHIP_MD")"
  [[ "$step" == *'What the operator or the task description classified'* ]]
  [[ "$step" == *'When nothing did, the claim is `unknown`'* ]]
}

@test "the skill names every sensitive category that forces separate reviews" {
  step="$(unwrapped '/^## Step 0\.5/,/^## Step 1\./p' "$SHIP_MD")"
  for word in Auth permissions Secrets migrations "Data integrity" Concurrency ordering; do
    [[ "$step" == *"$word"* ]] || { echo "the classification step never names: $word"; return 1; }
  done
}

@test "the skill reads the whole branch and escalates only upward" {
  step="$(unwrapped '/^## Step 0\.5/,/^## Step 1\./p' "$SHIP_MD")"
  [[ "$step" == *'whole-branch diff'* ]]
  [[ "$step" == *'Escalation only'* ]]
  [[ "$step" == *'nothing here turns a `separate` classification into a combined gate'* ]]
  # Uncertainty on either side is the careful answer, not a stop.
  [[ "$step" == *'`unknown` on either side means separate'* ]]
}

@test "the skill says operational Markdown is not the docs-only exception" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'Operational instructions are not prose'* ]]
  [[ "$ship" == *'skills, templates'* ]]
}

@test "ship-env owns the rule that turns a claim and a diff into a mode" {
  env="$SKILL_DIR/ship-env"
  [ -x "$env" ]
  [ "$("$env" review-mode combined no)" = combined ]
  [ "$("$env" review-mode combined yes)" = separate ]
  [ "$("$env" review-mode unknown unknown)" = separate ]
  [ "$("$env" review-mode separate no)" = separate ]
  grep -qF '"$SHIP_ENV" review-mode' "$SHIP_MD"
}

@test "step 2 offers a rebase and never performs one unattended" {
  two="$(unwrapped '/^## Step 2\./,/^## Step 3\./p' "$SHIP_MD")"
  [[ "$two" == *'Offer a rebase; do not perform it unattended.'* ]]
}

# ---- the guard -------------------------------------------------------------------

@test "the skill binds every phase to the commit it saw, in order" {
  [ -x "$SKILL_DIR/ship-guard" ]
  prev=0
  for call in open "record checks" "check checks" "record review" \
              "check review" "record security" "check security" push-ok; do
    line="$(grep -nF "\"\$SHIP_GUARD\" $call" "$SHIP_MD" | head -n 1 | cut -d: -f1)"
    [ -n "$line" ] || { echo "the skill never calls the guard: $call"; return 1; }
    [ "$line" -gt "$prev" ] || { echo "guard call '$call' is out of order at line $line"; return 1; }
    prev="$line"
  done
}

@test "the skill guards the push in step 9, not only the one that opens the PR" {
  # A fix pushed while CI is red reaches the remote through step 9. Guarding
  # step 8 alone leaves the whole point of the guard behind.
  ci="$(grep -n '^## Step 9' "$SHIP_MD" | head -n 1 | cut -d: -f1)"
  [ -n "$ci" ]
  last="$(grep -nF '"$SHIP_GUARD" push-ok' "$SHIP_MD" | tail -n 1 | cut -d: -f1)"
  [ -n "$last" ] || { echo "the skill never calls push-ok"; return 1; }
  [ "$last" -gt "$ci" ] || { echo "the last push-ok is at line $last, before step 9 at $ci"; return 1; }
}

@test "the skill stops rather than running unguarded" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'the gate does not run unguarded'* ]]
  [[ "$ship" == *'Guard helper cannot be resolved'* ]]
  [[ "$ship" == *'HEAD moved during the gate'* ]]
  [[ "$ship" == *'push-ok refused'* ]]
  [[ "$ship" == *'the phase names another commit'* ]]
  [[ "$ship" == *'refused for an uncommitted change'* ]]
}

@test "the skill stops on a guard override it cannot run" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'which is not executable'* ]]
  [[ "$ship" == *'set but not runnable is a stop'* ]]
}

@test "the skill says what a fix pass clears and what recording it again asserts" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'A fix pass clears all three'* ]]
  [[ "$ship" == *'The code review is not spared'* ]]
  [[ "$ship" == *'revert to the minimal fix'* ]]
  # The one instruction that keeps the count honest: push-ok's refusal says
  # "record it again", and doing that alone is the way past the whole gate.
  [[ "$ship" == *'Never record a phase again without a fix pass'* ]]
  # open clears every phase and zeroes the count, so it is the same dodge by
  # another route and the skill has to say so where the refusal is read.
  [[ "$ship" == *'Opening the gate again mid-gate is'* ]]
}

@test "the skill drops the Critical-only re-review exception" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'Every fix commit gets a review that covers the changed code'* ]]
  [[ "$ship" != *'no re-review unless a Critical was fixed'* ]]
}

# ---- the reviews -------------------------------------------------------------------

@test "the skill makes both reviewers answer in a shape it can read" {
  # The shape has to be demanded of the reviewer, in the prompt it is sent, not
  # only in the prose around it: the line that runs the resolved command.
  prompt="$(sed -n '/^## Step 6\./,/^## Step 7\./p' "$SHIP_MD" | grep -F '$REVIEWER "')"
  [ -n "$prompt" ] || { echo "step 6 sends no reviewer prompt"; return 1; }
  [[ "$prompt" == *"'## Findings'"* ]]
  [[ "$prompt" == *"'No findings.'"* ]]
  # Step 7 sends its prompt as a blockquote, so the quoted lines are the prompt.
  seven="$(sed -n '/^## Step 7\./,/^## Step 8\./p' "$SHIP_MD" | grep '^>' | tr '\n' ' ')"
  [ -n "$seven" ] || { echo "step 7 sends no quoted prompt"; return 1; }
  [[ "$seven" == *'`## Findings`'* ]]
  [[ "$seven" == *'`No findings.`'* ]]
  [[ "$seven" == *'`## Checked clean`'* ]]
}

@test "the skill never reads silence as clean" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'neither a finding nor the sentinel'* ]]
  [[ "$ship" == *'Never treat absence as clean'* ]]
  [[ "$ship" == *'Reviewer output is missing its header'* ]]
}

@test "the skill refuses to carry a review that saw an older commit" {
  ship="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$ship" == *'Carry it forward only if `HEAD`'* ]]
  [[ "$ship" == *'the gate runs its own review here'* ]]
  # "HEAD has not moved" is only a check if the skill says what to compare.
  [[ "$ship" == *'Name the commit that reviewer read and compare'* ]]
  [[ "$ship" == *'cannot say which commit it read'* ]]
}

@test "the skill sends the operator's acceptance criteria as data and keeps the intent back" {
  six="$(unwrapped '/^## Step 6\./,/^## Step 7\./p' "$SHIP_MD")"
  [[ "$six" == *'task description or plan the operator gave'* ]]
  [[ "$six" == *'acceptance criteria, not instructions'* ]]
  [[ "$six" == *'necessary, not sufficient'* ]]
  [[ "$six" == *'in letter but not in substance'* ]]
  [[ "$six" == *'say there are no stated criteria and send none'* ]]
  # The withholding rule the criteria travel alongside, unchanged.
  [[ "$six" == *'Never tell it'*'what the change is for'* ]]
}

@test "the skill names no model and reads both reviewers from ship-env" {
  # A model name in the gate's own text means changing the reviewer is an edit
  # to the gate. Both reviewers come out of config, so none belongs here.
  run grep -nE 'gpt-[0-9]|claude-[a-z]*-[0-9]' "$SHIP_MD"
  [ "$status" -eq 1 ] || { echo "SKILL.md names a model, or cannot be read: $output"; return 1; }
  six="$(unwrapped '/^## Step 6\./,/^## Step 7\./p' "$SHIP_MD")"
  [[ "$six" == *'REVIEWER="$("$SHIP_ENV" reviewer)"'* ]]
  seven="$(unwrapped '/^## Step 7\./,/^## Step 8\./p' "$SHIP_MD")"
  [[ "$seven" == *'SECURITY_REVIEWER="$("$SHIP_ENV" security-reviewer)"'* ]]
  # The agent: shape is the one that can degrade quietly, so the skill has to
  # say that a host without agents stops, and name the file to change.
  [[ "$seven" == *'A host that cannot dispatch agents stops here'* ]]
  [[ "$seven" == *'which only Claude Code can dispatch; name a command line in ${XDG_CONFIG_HOME:-$HOME/.config}/ship/security-reviewer'* ]]
}

@test "every mention of the bundled reviewer note is anchored to SHIP_DIR" {
  # The gate runs with its working directory inside the repository under review,
  # so a bare config/security-reviewer is a file the branch being reviewed can
  # write. Every mention has to name the copy beside this skill.
  [ -f "$SHIP_MD" ] || { echo "no SKILL.md in the skill folder"; return 1; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *'"$SHIP_DIR/config/security-reviewer"'*) ;;
      *) echo "unanchored mention of the bundled note: $line"; return 1 ;;
    esac
  done <<EOF
$(grep -n 'config/security-reviewer' "$SHIP_MD" || true)
EOF
  # And the mentions are really there, so an empty grep cannot pass this.
  [ "$(grep -c 'config/security-reviewer' "$SHIP_MD")" -ge 2 ]
}

@test "the ship security review is scoped to the declared boundary" {
  grep -q 'declared security boundary' "$SHIP_MD"
}

@test "the skill demands evidence a person can see, or a reason there is none" {
  five="$(unwrapped '/^## Step 5\./,/^## Step 6\./p' "$SHIP_MD")"
  [[ "$five" == *'screenshot'* ]]
  [[ "$five" == *'or one line saying why there is none'* ]]
  # It is a body requirement, not a new stop. Reading it as a stop would hold a
  # branch for a missing picture.
  [[ "$five" == *'not a stop'* ]]
}

# ---- the push and the pull request -----------------------------------------------

# A lease anchored to a value read straight after a fetch matches whatever the
# remote holds, including a commit this branch has never seen. The ancestor test
# is the guard; the lease alone is not.
@test "every push tests the ancestor, anchors the lease, and verifies the remote" {
  # One range per step, spelled out. An alternation in the end pattern is a GNU
  # extension: BSD sed never matches it, and the range runs to the end of file.
  for step in 8 9; do
    case "$step" in
      8) body="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$SHIP_MD")" ;;
      9) body="$(unwrapped '/^## Step 9\./,/^## Stop and report/p' "$SHIP_MD")" ;;
    esac
    [ -n "$body" ] || { echo "step $step is empty"; return 1; }
    # The range has to stop where the step does, or one step's push proves the
    # other's. sed prints the line the range ends on, so the marker checked here
    # is content from inside the next section, not its header.
    case "$step" in
      8) [[ "$body" != *'gh run watch'* ]] || { echo "the step 8 range ran into step 9"; return 1; } ;;
      9) [[ "$body" != *'you are rationalizing'* ]] || { echo "the step 9 range ran into the red flags"; return 1; } ;;
    esac
    [[ "$body" == *'git merge-base --is-ancestor "$REMOTE" HEAD'* ]] \
      || { echo "step $step has no ancestor test"; return 1; }
    [[ "$body" == *'--force-with-lease="refs/heads/$BRANCH:$REMOTE"'* ]] \
      || { echo "step $step does not anchor the lease"; return 1; }
    [[ "$body" == *'git ls-remote origin "refs/heads/$BRANCH"'* ]] \
      || { echo "step $step does not verify the remote after the push"; return 1; }
  done
  # An empty expected value is the same shape for a branch the remote does not
  # have yet, and it refuses if the ref appeared in between.
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$SHIP_MD")"
  [[ "$eight" == *'empty'* ]]
  [[ "$eight" == *'refuses if the ref appeared'* ]]
  # A bare force never comes back.
  flat="$(unwrapped '1,$p' "$SHIP_MD")"
  [[ "$flat" != *'git push --force '* ]]
}

@test "the stop table names the two ways a push can be wrong" {
  table="$(unwrapped '/^## Stop and report/,/^## Red flags/p' "$SHIP_MD")"
  [[ "$table" == *'The remote branch holds commits this branch does not'* ]]
  [[ "$table" == *'The remote head is not the commit that was pushed'* ]]
}

# gh pr create refuses a branch that already has an open pull request, which is
# what a branch shipped again after review feedback has. The lookup keeps it on
# its own pull request, and the edit keeps the title the operator has seen.
@test "step 8 edits the branch's open pull request and opens one only when there is none" {
  grep -qxF 'PR_NUMBER="$(gh pr list --head "$BRANCH" --base "$BASE" --state open --json number --jq '"'"'.[0].number // empty'"'"')"' "$SHIP_MD"
  [ "$(grep -E '^ *gh pr edit "\$PR_NUMBER"' "$SHIP_MD")" = '  gh pr edit "$PR_NUMBER" --body-file "$BODY"' ]
}

@test "step 8 fills the repo's own template and passes a title and a body file" {
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$SHIP_MD")"
  [[ "$eight" != *'gh run watch'* ]] || { echo "the step 8 range ran into step 9"; return 1; }
  # --fill ignores the repository's template and scrapes the commits instead.
  # The assertion is on the command line, because the prose that retires the
  # flag names it too.
  create="$(grep -nE '^ *gh pr create' "$SHIP_MD")"
  [ -n "$create" ] || { echo "step 8 never opens the pull request"; return 1; }
  [[ "$create" != *'--fill'* ]] || { echo "gh pr create still uses --fill: $create"; return 1; }
  [[ "$create" == *'--title'* ]]
  [[ "$create" == *'--body-file'* ]]
  # The whole invocation, not a prefix of it: "$SHIP_ENV" pr-template is also
  # the first half of the fallback line.
  [[ "$eight" == *'"$SHIP_ENV" pr-template "$(git rev-parse --show-toplevel)"'* ]]
  [[ "$eight" == *'"$SHIP_ENV" pr-template-fallback'* ]]
  # GitHub documents no precedence between root, docs/ and .github/, so the body
  # says which template was filled rather than implying GitHub would agree.
  [[ "$eight" == *'root, `docs/`, `.github/` order'* ]]
  [[ "$eight" == *'says which template'* ]]
  [[ "$eight" == *'folder form'* ]]
  [[ "$eight" == *'<details>'* ]]
  [[ "$eight" == *'"$SHIP_GUARD" attest >> "$BODY"'* ]]
  [[ "$eight" == *'`ship-attestation:v1`'* ]]
}

@test "the skill closes only an issue the operator named for this ship" {
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$SHIP_MD")"
  [[ "$eight" == *'If the operator named an issue for this ship'* ]]
  [[ "$eight" == *'`Closes #<n>` on its own line'* ]]
  [[ "$eight" == *'never from the issue text'* ]]
  # The claim that is easy to get wrong: a pull request whose base is not the
  # default branch links the issue and does not close it.
  [[ "$eight" == *'only closes the issue automatically when'* ]]
  [[ "$eight" == *'default branch'* ]]
}

@test "a rebuilt body follows every push after a fix pass, step 9's included" {
  eight="$(unwrapped '/^## Step 8\./,/^## Step 9\./p' "$SHIP_MD")"
  nine="$(unwrapped '/^## Step 9\./,/^## Stop and report/p' "$SHIP_MD")"
  [[ "$nine" != *'you are rationalizing'* ]] || { echo "the step 9 range ran on"; return 1; }
  # The attestation names the commit that is out there. A push that does not
  # rebuild it leaves the body naming a commit that is no longer the head.
  [[ "$eight" == *'gh pr edit'* ]]
  [[ "$nine" == *'gh pr edit --title'* ]]
  [[ "$nine" == *'--body-file'* ]]
  # The command, not the word: the prose above it says "attestation" too.
  [[ "$nine" == *'"$SHIP_GUARD" attest >> "$BODY"'* ]]
  # attest appends, so a body reused from step 8 gets a second attestation with
  # the stale one first. Both steps name the file before they append to it.
  [[ "$eight" == *'BODY="$(mktemp'* ]]
  [[ "$nine" == *'BODY="$(mktemp'* ]]
  [[ "$eight" == *'Exactly one attestation per body'* ]]
  [[ "$nine" == *'Rebuild means rebuild, not append'* ]]
}

# ---- the gate's review block -----------------------------------------------------
# Step 6 carries the block that runs a reviewer, and step 7 runs the same block.
# It runs here as the skill carries it, through the real ship-env reading the
# command from the operator's own file, against a codex that writes what Codex
# does: events on stdout, its answer to -o.

review_block() {
  sed -n '/^## Step 6\./,/^## Step 7\./p' "$SHIP_MD" | awk '
    /^```bash$/ { inside = 1; text = ""; next }
    /^```$/ { if (inside && text ~ /SHIP_ENV" reviewer\)/) printf "%s", text; inside = 0; next }
    inside { text = text $0 "\n" }'
}

gate_fakes() {  # $1 the reviewer command line, written where the operator would
  mkdir -p "$TEST_HOME/fake" "$TEST_HOME/tmp" "$HOME/.config/ship"
  printf '%s\n' "$1" > "$HOME/.config/ship/reviewer"
  cat > "$TEST_HOME/fake/codex" <<'FAKE'
#!/bin/sh
answer=""
while [ "$#" -gt 0 ]; do [ "$1" = -o ] && answer="$2"; shift; done
echo '{"type":"thread.started","thread_id":"t-1"}'
if [ -n "${FAKE_REFUSED:-}" ]; then
  echo '{"type":"error","message":"{\"type\":\"error\",\"status\":400}"}'
  echo '{"type":"turn.failed","error":{"message":"{\"type\":\"error\",\"status\":400}"}}'
  exit 1
fi
# Codex writes its answer with no newline after the last line.
printf '## Findings\nNo findings.' > "$answer"
echo '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30}}'
FAKE
  # The real codex exec reads its input to the end before it starts, and a
  # Claude Code shell hands commands an input that never ends. So this one
  # refuses an input that is a pipe or a socket, the shape that hangs.
  if [ -n "${FAKE_STDIN_CHECK:-}" ]; then
    sed -i.bak '2i\
if [ -p /dev/stdin ] || [ -S /dev/stdin ]; then echo "codex: input left open, waiting for it to end" >&2; exit 3; fi
' "$TEST_HOME/fake/codex" && rm -f "$TEST_HOME/fake/codex.bak"
  fi
  printf '#!/bin/sh\nprintf "## Findings\\nNo findings.\\n"\n' > "$TEST_HOME/fake/other-reviewer"
  chmod +x "$TEST_HOME/fake/codex" "$TEST_HOME/fake/other-reviewer"
}

run_review_block() {
  block="$(review_block)"
  [ -n "$block" ] || { echo "step 6 carries no reviewer block"; return 1; }
  run env SHIP_ENV="$SKILL_DIR/ship-env" BASE=main TMPDIR="$TEST_HOME/tmp" \
    PATH="$TEST_HOME/fake:$PATH" bash -c "$block"
}

@test "the gate prints a codex review's answer, then the usage codex reported for it" {
  gate_fakes 'codex exec -m some-model --sandbox read-only'
  run_review_block
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "## Findings" ]
  [ "${lines[1]}" = "No findings." ]
  [ "${lines[2]}" = "usage: input=600 output=30 cache_read=400 cache_write=0" ]
  [ "${#lines[@]}" -eq 3 ]
  # Nothing of the run is left behind.
  [ -z "$(ls -A "$TEST_HOME/tmp")" ]
}

# The dry run in a real Claude Code session hung here for ten minutes on a
# one-line change: the block left codex holding the shell's open input.
@test "the gate gives the reviewer no input to wait for" {
  FAKE_STDIN_CHECK=1 gate_fakes 'codex exec -m some-model --sandbox read-only'
  block="$(review_block)"
  [ -n "$block" ] || { echo "step 6 carries no reviewer block"; return 1; }
  run bash -c 'echo pending | env SHIP_ENV="$1" BASE=main TMPDIR="$2" PATH="$3" bash -c "$4"' _ \
    "$SKILL_DIR/ship-env" "$TEST_HOME/tmp" "$TEST_HOME/fake:$PATH" "$block"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "## Findings" ]
}

@test "the gate shows a refused review model, leaves its usage unknown and fails" {
  gate_fakes 'codex exec -m some-model --sandbox read-only'
  FAKE_REFUSED=1 run_review_block
  [ "$status" -eq 2 ]
  [[ "$output" != *"## Findings"* ]]
  [[ "$output" == *'reviewer error: {"type":"error","status":400}'* ]]
  [[ "$output" == *"usage: input=unknown output=unknown cache_read=unknown cache_write=unknown"* ]]
  [ "${lines[${#lines[@]}-1]}" = "finding: the reviewer exited 1" ]
  [ -z "$(ls -A "$TEST_HOME/tmp")" ]
}

@test "the gate leaves a reviewer that gives no counts unknown" {
  gate_fakes 'other-reviewer --read-only'
  run_review_block
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "## Findings" ]
  [ "${lines[1]}" = "No findings." ]
  [ "${lines[2]}" = "usage: input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
  [ "${#lines[@]}" -eq 3 ]
  [ -z "$(ls -A "$TEST_HOME/tmp")" ]
}
