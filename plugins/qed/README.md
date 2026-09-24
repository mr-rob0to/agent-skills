# qed

Skills for software delivery. One so far: `ship`.

The name comes from Q.E.D., short for the Latin *quod erat demonstrandum*,
"which was to be shown". Mathematicians write it at the end of a proof. These
skills work the same way: a change is done when it has been shown to work, not
when someone says it does.

To install, see [Install](../../README.md#install) in the repository's README.

## ship

`ship` takes a finished branch through a pre-merge gate and stops at the first
thing that is wrong. In order, it:

1. Finds the branch the pull request should target, and stops if the
   repository's own signals disagree.
2. Decides whether the branch gets one combined review, or separate correctness
   and security reviews. Anything touching sign-in or permissions, secrets,
   migrations, stored data, concurrency, or the order of deploys gets separate
   reviews.
3. Runs the project's own checks.
4. Sends the diff to a fresh, read-only reviewer that does not load the
   repository's own instruction files. When the branch needs it, a second
   reviewer does a security pass.
5. Records which commit each check and review saw. If a commit lands after them,
   the push is refused until they run again.
6. Pushes without overwriting commits it has not seen, and opens or updates the
   pull request from the repository's own template. The body ends with a hidden
   note naming the commit each check and review saw.
7. Watches CI until it is green.

It never merges. That stays with you.

### Running it

- Claude Code: `/qed:ship`.
- Codex: `$qed:ship`.
- Anywhere else: ask the agent to follow the installed `SKILL.md`. It needs to
  know which folder that file is in; if it cannot tell, the gate stops and says
  how to set it.

The gate needs bash, `git`, `jq`, the GitHub CLI `gh` signed in, and a reviewer
on your `PATH`: `codex`, or failing that `claude`.

### Choosing the reviewers

Out of the box both reviewers are set to `auto`:

- **Code review:** `codex` when it is on your `PATH`, otherwise Claude Code in
  plan mode, which can read the code but not change it.
- **Security review:** `codex` only, with the model this gate was tested
  against. Without `codex`, a branch that needs a security review stops rather
  than running a reviewer nobody has tested.

To choose your own, write a command line into a file:

- `~/.config/ship/reviewer` for the code review.
- `~/.config/ship/security-reviewer` for the security review.

When `XDG_CONFIG_HOME` is set, the files go in `$XDG_CONFIG_HOME/ship/`
instead. The gate adds the review prompt to the end of your command as one
argument. Lines starting with `#` are notes. The bundled files in
`skills/ship/config/` explain each choice. Copy one and edit the copy: an update
replaces the bundled files, never yours.

In Claude Code only, `security-reviewer` may say `agent:<name>` to use one of
your agents. Any other harness stops the gate on that value.

### What the gate does not cover

- It does not merge, and it does not settle design questions. It stops and asks.
- It reads the diff, not the running app. Run the app yourself.
- A reviewer you name yourself is not isolated for you. `auto` tells the
  reviewer to ignore the reviewed repository's own instruction files; your own
  command line gets no such treatment.
- The reviewer still reads the code, and the code can contain text written to
  steer it. Skipping instruction files does not stop that.
- It trusts your machine. Anyone who can edit your config files or the installed
  skill can change what the gate does.
- A repository you open can define its own `ship` skill and take the bare
  `/ship` name. `/qed:ship` always means this one.
- It works with GitHub only. The pull request and the CI watch go through `gh`.
- Token counts for a review come only from `codex`. Any other reviewer's are
  reported as `unknown`.
