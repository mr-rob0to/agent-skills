bats_require_minimum_version 1.5.0  # run --separate-stderr

load helpers/setup

# ship-env reads a setting from two places: the operator's own directory,
# ${XDG_CONFIG_HOME:-$HOME/.config}/ship, then config/ beside the script. Every
# test runs a copy of the script from a folder of its own, under the fake HOME
# that setup() makes, so an answer never comes from this machine's settings or
# from the real folder's bundled files.
skill_copy() {  # prints the copied folder
  local c="$TEST_HOME/skill"
  mkdir -p "$c/config"
  cp "$SKILL_DIR/ship-env" "$c/ship-env"
  printf 'bundled template\n' > "$c/PULL_REQUEST_TEMPLATE.md"
  printf 'bundled reviewer command\n' > "$c/config/reviewer"
  printf 'agent:bundled-security-reviewer\n' > "$c/config/security-reviewer"
  echo "$c"
}

# The operator's own directory, where ship-env looks first.
ovr() {  # prints the directory, made
  mkdir -p "$HOME/.config/ship"
  echo "$HOME/.config/ship"
}

env_at() {  # $1 copied folder, $2.. arguments
  local c="$1"; shift
  "$c/ship-env" "$@"
}

# The probe reads three things off the host: PATH, the user's agent directory
# and the project directory the gate runs in. Every test that reaches it builds
# all three, so the answer is the one the test asked for and never the machine's
# own codex install or the operator's own agents. Run against the real host,
# these tests would pass here and say nothing about anywhere else.
host() {  # $1.. any of: codex claude user-agent project-agent
  STUB="$TEST_HOME/host/bin"; PROJECT="$TEST_HOME/host/project"
  mkdir -p "$STUB" "$HOME/.claude/agents" "$PROJECT/.claude/agents" "$PROJECT/sub"
  [ -d "$PROJECT/.git" ] || git init -q -b main "$PROJECT"
  local w
  for w in "$@"; do
    case "$w" in
      codex | claude) printf '#!/bin/sh\nexit 0\n' > "$STUB/$w"; chmod +x "$STUB/$w" ;;
      user-agent)     : > "$HOME/.claude/agents/security-reviewer.md" ;;
      project-agent)  : > "$PROJECT/.claude/agents/security-reviewer.md" ;;
      *) echo "host: unknown ingredient $w"; return 1 ;;
    esac
  done
}

# $STUB first and never an empty field: an empty PATH entry means the working
# directory, which would let a stray file there answer the probe.
on_host() {  # $1 copied folder, $2.. arguments
  local c="$1"; shift
  ( cd "${PROJECT_CWD:-$PROJECT}" && env PATH="$STUB:/usr/bin:/bin" \
      CLAUDE_CONFIG_DIR="$HOME/.claude" "$c/ship-env" "$@" )
}

# The claude command line the probe falls back to, in one place, so a test that
# asserts it cannot drift from the one ship-env prints.
claude_line='claude -p --safe-mode --disallowedTools WebFetch,WebSearch --model claude-fable-5-1 --effort high --permission-mode plan'
codex_line='codex exec -m gpt-5.6-sol --sandbox read-only -c project_doc_max_bytes=0'

# A copy whose bundled defaults are auto, so the probe is reached the way a
# fresh install reaches it.
auto_copy() {  # prints the copied folder
  local c; c="$(skill_copy)"
  printf 'auto\n' > "$c/config/reviewer"
  printf 'auto\n' > "$c/config/security-reviewer"
  echo "$c"
}

@test "an override supplies both reviewers" {
  c="$(skill_copy)"
  o="$(ovr)"
  printf 'configured reviewer command\n' > "$o/reviewer"
  printf 'agent:configured-security-reviewer\n' > "$o/security-reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "configured reviewer command" ]
  run --separate-stderr env_at "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:configured-security-reviewer" ]
}

@test "with no override, both reviewers come from the bundled config" {
  c="$(skill_copy)"
  [ ! -d "$HOME/.config/ship" ]
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "bundled reviewer command" ]
  run --separate-stderr env_at "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:bundled-security-reviewer" ]
}

@test "XDG_CONFIG_HOME moves the override directory, and HOME's is not read" {
  c="$(skill_copy)"
  o="$(ovr)"
  printf 'home reviewer command\n' > "$o/reviewer"
  mkdir -p "$TEST_HOME/xdg/ship"
  printf 'xdg reviewer command\n' > "$TEST_HOME/xdg/ship/reviewer"
  XDG_CONFIG_HOME="$TEST_HOME/xdg" run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "xdg reviewer command" ]
  # An XDG directory with no file for the key falls through to the bundled one,
  # never to the one under HOME.
  rm "$TEST_HOME/xdg/ship/reviewer"
  XDG_CONFIG_HOME="$TEST_HOME/xdg" run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "bundled reviewer command" ]
}

@test "notes and blank lines above the value are skipped" {
  c="$(skill_copy)"
  o="$(ovr)"
  printf '# a note about the reviewer\n\n# another note\nthe value line\n' > "$o/reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "the value line" ]
}

@test "an override of notes alone falls back rather than answering empty" {
  c="$(skill_copy)"
  o="$(ovr)"
  printf '# the operator commented the value out\n\n' > "$o/reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "bundled reviewer command" ]
}

# pwd -P, so a folder installed as a link reads the real folder's files.
@test "a symlinked skill folder answers from the real folder" {
  c="$(skill_copy)"
  ln -s "$c" "$TEST_HOME/linked"
  run --separate-stderr "$TEST_HOME/linked/ship-env" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "bundled reviewer command" ]
  run --separate-stderr "$TEST_HOME/linked/ship-env" pr-template-fallback
  [ "$status" -eq 0 ]
  [ "$output" = "$c/PULL_REQUEST_TEMPLATE.md" ]
}

@test "an unknown key is a finding that names the keys there are" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" models
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: unknown key 'models' (reviewer, security-reviewer, review-mode, pr-template, pr-template-fallback, usage)" ]
  # --root was a key in an earlier copy of this gate. It has no use here, so it is gone.
  run --separate-stderr env_at "$c" --root
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == "finding: unknown key '--root' "* ]]
}

@test "a copy with no config folder and no override is a finding naming both files" {
  c="$(skill_copy)"
  rm -r "$c/config"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no value for reviewer in $HOME/.config/ship/reviewer or $c/config/reviewer" ]
}

@test "a key with no value in either file is a finding naming both" {
  c="$(skill_copy)"
  : > "$c/config/reviewer"
  o="$(ovr)"
  : > "$o/reviewer"
  run --separate-stderr env_at "$c" reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no value for reviewer in $o/reviewer or $c/config/reviewer" ]
}

@test "no command at all is a finding, not an empty answer" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

@test "an argument after a key is a finding" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" reviewer extra
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

# The shipped defaults are what a fresh install runs on, so the test that reads
# them must not read an override instead. A copy carrying the real config/ and
# no override is the only way to ask that question.
@test "a fresh copy with no override resolves both keys from the bundled defaults" {
  c="$TEST_HOME/fresh"
  mkdir -p "$c"
  cp "$SKILL_DIR/ship-env" "$c/ship-env"
  cp -R "$SKILL_DIR/config" "$c/config"
  [ ! -d "$HOME/.config/ship" ]
  host codex user-agent
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
}

@test "auto picks codex for the code review when codex is on this host" {
  c="$(auto_copy)"
  host codex claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
}

@test "auto picks claude for the code review when codex is not on this host" {
  c="$(auto_copy)"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
}

@test "auto with no reviewer on the host stops the gate and names the file" {
  c="$(auto_copy)"
  host
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no code reviewer on this host: neither codex nor claude is on PATH; put a command line in $HOME/.config/ship/reviewer" ]
}

# The security pass is qualified work, and what was qualified is Codex Sol
# against the fixtures under tests/fixtures/security-review. An agent the
# operator happens to have defined has not been qualified for this, so it is not
# probed: automatic means Sol, and a preference is stated in the override file
# or not at all.
@test "auto picks Codex Sol for the security pass even where an agent is defined" {
  c="$(auto_copy)"
  host codex claude user-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
  [ "$output" != "agent:security-reviewer" ]
  [ "$output" != "$claude_line" ]
  # The definition really is where a probe for agents would read it, so this is
  # not passing because nothing was written.
  [ -f "$HOME/.claude/agents/security-reviewer.md" ]
}

# The project the gate runs in is the repository whose diff is being audited, and
# Claude Code would prefer a definition committed there over the operator's own.
# A branch that could put one in the probe's path would be appointing and writing
# the agent that reviews it, which is the whole of the security pass handed to
# the change under review.
@test "a security-reviewer definition committed to the project is not the agent" {
  c="$(auto_copy)"
  host codex claude project-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
  [ "$output" != "agent:security-reviewer" ]
  # The file really is where the gate would run, so the test is asking the
  # question it means to ask and not passing because nothing was written.
  [ -f "$PROJECT/.claude/agents/security-reviewer.md" ]
}

# A stated agent: value is not probed, and it is still dispatched by name into
# the worktree, so the refusal has to cover it too.
@test "a stated agent value is refused when the project defines that agent" {
  c="$(auto_copy)"
  o="$(ovr)"
  printf 'agent:security-reviewer\n' > "$o/security-reviewer"
  host claude user-agent project-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"the repository being reviewed defines an agent called security-reviewer"* ]]
  [[ "$stderr" == *"$o/security-reviewer"* ]]
}

# The probe never returns an agent, so the worst a repository defining one can
# do to an automatic run is nothing. Both definitions present, and the answer is
# Sol.
@test "the probe cannot be made to return an agent by defining one" {
  c="$(auto_copy)"
  host codex claude user-agent project-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
  [ -f "$HOME/.claude/agents/security-reviewer.md" ]
  [ -f "$PROJECT/.claude/agents/security-reviewer.md" ]
}

# The refusal is about a name collision, not about the project having a .claude
# directory. A project agent by some other name is nobody's business here.
@test "a project agent of another name does not refuse the gate" {
  c="$(auto_copy)"
  o="$(ovr)"
  printf 'agent:security-reviewer\n' > "$o/security-reviewer"
  host codex claude user-agent
  : > "$PROJECT/.claude/agents/some-other-agent.md"
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:security-reviewer" ]
}

# Nothing pins the directory the gate calls from, so a refusal anchored on it
# would miss a definition at the repository root, which is the ordinary place to
# put one and the whole case this check exists for.
@test "the refusal finds a root definition when the gate is called from a subdirectory" {
  c="$(auto_copy)"
  o="$(ovr)"
  printf 'agent:security-reviewer\n' > "$o/security-reviewer"
  host codex claude user-agent project-agent
  PROJECT_CWD="$PROJECT/sub"
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"the repository being reviewed defines an agent called security-reviewer"* ]]
  # The definition really is at the root and not in the directory called from,
  # so the test cannot pass by finding it under $PWD.
  [ -f "$PROJECT/.claude/agents/security-reviewer.md" ]
  [ ! -f "$PROJECT/sub/.claude/agents/security-reviewer.md" ]
}

# Both reviewer commands run inside the repository they read, and neither may
# take its instructions from it, or the change under review writes part of its
# own reviewer's brief. One test each: host() adds to the machine it is building
# rather than replacing it, so asking both questions in one test asks the first
# one twice.
@test "the codex reviewer does not read the reviewed repository's instructions" {
  c="$(auto_copy)"
  host codex
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  case "$output" in
    *" -c project_doc_max_bytes=0"*) ;;
    *) echo "the codex reviewer loads the project's own instructions: $output"; return 1 ;;
  esac
}

@test "the claude reviewer does not read the reviewed repository's instructions" {
  c="$(auto_copy)"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  # Named, so this cannot pass on the codex line, which answers the same
  # question with a different flag.
  case "$output" in
    claude\ *" --safe-mode "*) ;;
    *) echo "the claude reviewer loads the project's own instructions: $output"; return 1 ;;
  esac
}

# A list-taking flag last would swallow the prompt the gate appends as one
# argument, and the run would end asking for a prompt it was given.
@test "the claude fallback ends on a flag that takes no list" {
  c="$(auto_copy)"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  case "$output" in
    *--disallowedTools*--permission-mode*) ;;
    *) echo "a list-taking flag is last in: $output"; return 1 ;;
  esac
}

@test "auto picks Codex Sol for the security pass, never the claude line" {
  c="$(auto_copy)"
  host codex claude
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_line" ]
  # claude is on this host and is not the answer. There is no automatic Claude
  # security reviewer: what was qualified is Sol.
  [ "$output" != "$claude_line" ]
}

# A host without codex has nothing qualified to run, so it stops rather than
# quietly running something else. claude is deliberately present: falling back
# to it is exactly what must not happen.
@test "auto with no codex on the host stops the security pass and names the file" {
  c="$(auto_copy)"
  host claude user-agent
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no security reviewer on this host: codex is not on PATH; put a command line in $HOME/.config/ship/security-reviewer" ]
}

# The probe exists to answer where nobody has said what they want. A stated
# value is the whole reason the gate is configurable, and a probe that could
# overrule it would take the operator's reviewer away on a machine that happens
# to have another one.
@test "a stated value is never probed, whatever the host has" {
  c="$(auto_copy)"
  o="$(ovr)"
  printf 'my own reviewer command\n' > "$o/reviewer"
  printf 'agent:my-own-security-reviewer\n' > "$o/security-reviewer"
  host codex claude user-agent
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "my own reviewer command" ]
  run --separate-stderr on_host "$c" security-reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "agent:my-own-security-reviewer" ]
}

# An operator who copies the bundled file to start their own copies the auto in
# it, and that copy has to reach the probe as well.
@test "an auto in the override reaches the probe like the bundled file" {
  c="$(auto_copy)"
  o="$(ovr)"
  printf '# a note copied from the bundled file\nauto\n' > "$o/reviewer"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
}

# Commenting the value out asks for the bundled default back, and the bundled
# default is the probe. Emptying both files is still a finding, above.
@test "an override of notes alone over a bundled auto still reaches the probe" {
  c="$(auto_copy)"
  o="$(ovr)"
  printf '# the operator commented the value out\n\n' > "$o/reviewer"
  host claude
  run --separate-stderr on_host "$c" reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "$claude_line" ]
}

# ---- pr-template -----------------------------------------------------------
# GitHub reads a pull request template from the repository root, from docs/, and
# from .github/, in any letter case, with any extension, and as a folder of
# several. The lookup lists all of them, one repo-relative path per line, and
# prints nothing for a repository that has none.

a_repo() {  # $1 name; prints the path
  local d="$TEST_HOME/$1"
  mkdir -p "$d"
  git init -q -b main "$d"
  echo "$d"
}

@test "pr-template gives back the template's path, one per line" {
  c="$(skill_copy)"
  r="$(a_repo withtemplate)"
  mkdir -p "$r/docs"
  : > "$r/docs/pull_request_template.md"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ "$output" = "docs/pull_request_template.md" ]
}

@test "pr-template says nothing for a repo that has none" {
  c="$(skill_copy)"
  r="$(a_repo notemplate)"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "pr-template reports the folder form as the folder form" {
  c="$(skill_copy)"
  r="$(a_repo folderform)"
  mkdir -p "$r/.github/PULL_REQUEST_TEMPLATE"
  : > "$r/.github/PULL_REQUEST_TEMPLATE/one.md"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ "$output" = ".github/PULL_REQUEST_TEMPLATE/" ]
}

# Empty output means "this repo has no template". A lookup that could not look
# must never be read as one, or the gate quietly fills the bundled copy instead.
@test "pr-template on a directory that does not exist is a finding, never an empty answer" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" pr-template "$TEST_HOME/absent"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no such directory: $TEST_HOME/absent" ]
}

@test "pr-template needs exactly one repository" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" pr-template
  [ "$status" -eq 2 ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

# The fixture holds exactly one real match per directory, because glob order
# inside one directory follows the machine's locale: measured on macOS,
# en_US.UTF-8 sorts pull_request_template_old.md before pull_request_template.txt
# and C sorts it after. The near miss therefore sits in .github/, where the
# shorter PULL_REQUEST_TEMPLATE sorts first under both.
@test "pr-template lists every place GitHub reads a template from" {
  c="$(skill_copy)"
  r="$(a_repo everywhere)"
  mkdir -p "$r/docs" "$r/.github/PULL_REQUEST_TEMPLATE"
  echo body > "$r/PULL_REQUEST_TEMPLATE.md"
  echo body > "$r/docs/pull_request_template.txt"
  echo body > "$r/.github/PULL_REQUEST_TEMPLATE/one.md"
  echo body > "$r/.github/pull_request_template_old.md"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "PULL_REQUEST_TEMPLATE.md" ]
  [ "${lines[1]}" = "docs/pull_request_template.txt" ]
  [ "${lines[2]}" = ".github/PULL_REQUEST_TEMPLATE/" ]
  [ "${#lines[@]}" -eq 3 ]
}

# git stores a symlink as a symlink, so GitHub reads no template through one and
# neither does this. Following it would report a template the repo does not have.
@test "pr-template does not follow a symlinked .github" {
  c="$(skill_copy)"
  r="$(a_repo linkedgithub)"
  mkdir -p "$TEST_HOME/elsewhere"
  echo theirs > "$TEST_HOME/elsewhere/pull_request_template.md"
  ln -s "$TEST_HOME/elsewhere" "$r/.github"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A branch can commit a template that is a symlink to a local file such as an
# untracked .env. The gate reads the listed template into the PR body, so
# listing it would publish that file.
@test "pr-template does not list a symlinked template in any place" {
  c="$(skill_copy)"
  r="$(a_repo linkedfile)"
  mkdir -p "$r/docs" "$r/.github" "$TEST_HOME/elsewhere"
  echo secret > "$TEST_HOME/secret"
  ln -s "$TEST_HOME/secret" "$r/PULL_REQUEST_TEMPLATE.md"
  ln -s "$TEST_HOME/secret" "$r/docs/pull_request_template.md"
  ln -s "$TEST_HOME/secret" "$r/.github/pull_request_template.md"
  ln -s "$TEST_HOME/elsewhere" "$r/.github/PULL_REQUEST_TEMPLATE"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A filename is repository content, and this one is printed for the gate to
# read. A newline would print a second line the repo chose the text of; a
# carriage return rewrites the line being read; a C1 control starts an escape
# sequence and is invisible to [[:cntrl:]] under LC_ALL=C. A match is spelt out
# of [A-Za-z0-9._-], so none of them is one.
@test "pr-template does not list a name outside the safe character set" {
  c="$(skill_copy)"
  r="$(a_repo newline)"
  mkdir -p "$r/docs"
  printf 'x' > "$r/docs/$(printf 'pull_request_template.md\nforged')"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  r="$(a_repo carriage)"
  mkdir -p "$r/docs"
  printf 'x' > "$r/docs/$(printf 'pull_request_template.md\rfinding: forged')"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # U+009B, the C1 sequence introducer, as its two UTF-8 bytes. Run under the C
  # locale, where [[:cntrl:]] does not see it.
  r="$(a_repo c1)"
  mkdir -p "$r/docs"
  printf 'x' > "$r/docs/$(printf 'pull_request_template.md\302\233 31m')"
  LC_ALL=C run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A directory named like the file form is not a template to GitHub.
@test "pr-template ignores a directory named like the file form" {
  c="$(skill_copy)"
  r="$(a_repo dirnamed)"
  mkdir -p "$r/docs/PULL_REQUEST_TEMPLATE.md"
  run --separate-stderr env_at "$c" pr-template "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pr-template-fallback names the bundled copy beside the script" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" pr-template-fallback
  [ "$status" -eq 0 ]
  [ "$output" = "$c/PULL_REQUEST_TEMPLATE.md" ]
  [ -f "$output" ]
}

@test "a copy with no bundled template is a finding, not a silent empty path" {
  c="$(skill_copy)"
  rm "$c/PULL_REQUEST_TEMPLATE.md"
  run --separate-stderr env_at "$c" pr-template-fallback
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: no bundled pull request template at $c/PULL_REQUEST_TEMPLATE.md" ]
}

# ---- review-mode -----------------------------------------------------------
# One place decides whether a gate may run one reviewer instead of two. It is
# not a classifier: the gate reads the classification it was given and the
# branch diff and hands in what it found. What lives here is the rule that
# combines the two, so there is one answer to break rather than a paragraph of
# prose to obey.

@test "review-mode says combined only for a combined claim over a clean diff" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" review-mode combined no
  [ "$status" -eq 0 ]
  [ "$output" = combined ]
  [ -z "$stderr" ]
}

@test "review-mode says separate for every other pair" {
  c="$(skill_copy)"
  for pair in "combined yes" "combined unknown" \
              "separate no" "separate yes" "separate unknown" \
              "unknown no" "unknown yes" "unknown unknown"; do
    # shellcheck disable=SC2086
    run env_at "$c" review-mode $pair
    [ "$status" -eq 0 ]
    [ "$output" = separate ] || { echo "'$pair' gave '$output'"; return 1; }
  done
}

@test "review-mode refuses a claim or a verdict it does not know" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" review-mode maybe no
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: review-mode takes combined, separate or unknown, not 'maybe'" ]
  run --separate-stderr env_at "$c" review-mode combined probably
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "finding: review-mode takes yes, no or unknown for the sensitive verdict, not 'probably'" ]
}

@test "review-mode needs both answers, because half of one is not a classification" {
  c="$(skill_copy)"
  for args in "" "combined"; do
    # shellcheck disable=SC2086
    run --separate-stderr env_at "$c" review-mode $args
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    [[ "$stderr" == "finding: usage: ship-env "* ]]
  done
  run --separate-stderr env_at "$c" review-mode combined no extra
  [ "$status" -eq 2 ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}

# ---- usage -----------------------------------------------------------------
# `codex exec --json` ends a run with one turn.completed event, and its usage is
# numbers in fields of their own, apart from the transcript items around it.
# Probed on codex-cli 0.154.0: input counts cached input inside it, output
# counts reasoning inside it, and `exec resume` reports the thread's running
# total under the same thread id.

events() {  # $@ event lines; written where the usage tests read them
  printf '%s\n' "$@" > "$TEST_HOME/events"
}

@test "usage takes cached input out of input and adds no reasoning to output" {
  c="$(skill_copy)"
  events '{"type":"thread.started","thread_id":"t-1"}' '{"type":"turn.started"}' \
    '{"type":"turn.completed","usage":{"input_tokens":55813,"cached_input_tokens":33664,"cache_write_input_tokens":0,"output_tokens":132,"reasoning_output_tokens":40}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "usage: input=22149 output=132 cache_read=33664 cache_write=0" ]
}

@test "usage counts a resumed thread's running total once" {
  c="$(skill_copy)"
  # The probe's own numbers: one run, then exec resume of the same thread.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":28384,"cached_input_tokens":6528,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}' \
    '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":62356,"cached_input_tokens":13568,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "usage: input=48788 output=10 cache_read=13568 cache_write=0" ]
}

@test "usage adds separate runs together" {
  c="$(skill_copy)"
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30,"reasoning_output_tokens":0}}' \
    '{"type":"thread.started","thread_id":"t-2"}' \
    '{"type":"turn.completed","usage":{"input_tokens":2000,"cached_input_tokens":500,"cache_write_input_tokens":0,"output_tokens":70,"reasoning_output_tokens":9}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "usage: input=2100 output=100 cache_read=900 cache_write=0" ]
}

@test "usage leaves a count codex did not give unknown, never zero" {
  c="$(skill_copy)"
  # A refused model: the run failed and reported no usage at all.
  events '{"type":"thread.started","thread_id":"t-1"}' '{"type":"error","message":"status 400"}' \
    '{"type":"turn.failed","error":{"message":"status 400"}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "usage: input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
  run --separate-stderr env_at "$c" usage < /dev/null
  [ "$output" = "usage: input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
  # One field missing and one that is not a count: those two, and only those.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":55813,"cached_input_tokens":33664,"cache_write_input_tokens":0,"output_tokens":"132"}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$output" = "usage: input=22149 output=unknown cache_read=33664 cache_write=0" ]
  # A run that gave nothing makes the sum of two runs unknown, not the other run alone.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30}}' \
    '{"type":"thread.started","thread_id":"t-2"}' '{"type":"turn.completed","usage":{}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$output" = "usage: input=unknown output=unknown cache_read=unknown cache_write=unknown" ]
}

@test "usage leaves input unknown when a run reports cache writes" {
  c="$(skill_copy)"
  # Every probe reported 0 cache writes, so whether input counts them is not
  # known. Input would be wrong by that much either way; the rest still holds.
  events '{"type":"thread.started","thread_id":"t-1"}' \
    '{"type":"turn.completed","usage":{"input_tokens":55813,"cached_input_tokens":33664,"cache_write_input_tokens":500,"output_tokens":132}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "usage: input=unknown output=132 cache_read=33664 cache_write=500" ]
}

@test "usage counts only a run's own top-level events, never events it printed or said" {
  c="$(skill_copy)"
  # A codex session that runs the gate itself prints each reviewer's events, and
  # the model can repeat them, inside its transcript items. Each review is
  # counted from its own event stream, so here they count for nothing: only the
  # run's own top-level event does.
  reviewers='{"type":"thread.started","thread_id":"t-2"}
{"type":"turn.completed","usage":{"input_tokens":999999,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":999999}}
{"type":"thread.started","thread_id":"t-3"}
{"type":"turn.completed","usage":{"input_tokens":999999,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":999999}}'
  ran="$(jq -cn --arg out "$reviewers" '{type:"item.completed",item:{id:"c",type:"command_execution",aggregated_output:$out}}')"
  said="$(jq -cn --arg text "$reviewers" '{type:"item.completed",item:{id:"m",type:"agent_message",text:$text}}')"
  events '{"type":"thread.started","thread_id":"t-1"}' "$ran" "$said" 'turn.completed "input_tokens":999999' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":400,"cache_write_input_tokens":0,"output_tokens":30}}'
  run --separate-stderr env_at "$c" usage < "$TEST_HOME/events"
  [ "$status" -eq 0 ]
  [ "$output" = "usage: input=600 output=30 cache_read=400 cache_write=0" ]
}

@test "usage takes no argument" {
  c="$(skill_copy)"
  run --separate-stderr env_at "$c" usage extra < /dev/null
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == "finding: usage: ship-env "* ]]
}
