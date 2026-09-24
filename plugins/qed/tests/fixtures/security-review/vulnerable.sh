#!/usr/bin/env bash
# FIXTURE. Never executed, never sourced, never installed. It exists so that the
# security reviewer the ship gate chooses can be qualified against a diff whose
# answers are known: two reachable defects, both planted, both Critical.
#
# Shipping it as a file rather than a string keeps the qualification repeatable:
# the same bytes go to every reviewer that is ever qualified, and a later run can
# be compared with expected.md line by line.
set -u

archive_root=/var/lib/qed-fixture/archives

# Planted defect 1: shell injection. $1 arrives from the caller and is placed
# inside a string that is handed to a shell, so a name of `x; rm -rf /` runs.
fetch_archive() {  # $1 archive name
  local name="$1"
  eval "tar -xzf $archive_root/$name.tar.gz -C /tmp/unpack"
}

# Planted defect 2: path traversal. The name is joined to the root with no check
# that the result stays under it, so `../../../../etc/shadow` reads that file.
show_archive_note() {  # $1 archive name
  local name="$1"
  cat "$archive_root/$name/NOTE.txt"
}

fetch_archive "$1"
show_archive_note "$1"
