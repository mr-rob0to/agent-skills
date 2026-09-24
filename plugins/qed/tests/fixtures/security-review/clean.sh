#!/usr/bin/env bash
# FIXTURE. Never executed, never sourced, never installed. The counterpart to
# vulnerable.sh: the same two jobs done safely, so a reviewer that reports an
# Important or Critical finding here is inventing one.
set -u

archive_root=/var/lib/qed-fixture/archives

# The name is checked against a whitelist of the characters an archive name may
# hold, so nothing that reaches the command line can be read as shell syntax or
# as a path, and tar is given the name as one argument rather than through a
# shell.
valid_name() {  # $1 candidate
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    .|..|.*) return 1 ;;
    *) return 0 ;;
  esac
}

fetch_archive() {  # $1 archive name
  local name="$1"
  valid_name "$name" || { printf 'finding: bad archive name\n' >&2; return 2; }
  tar -xzf "$archive_root/$name.tar.gz" -C /tmp/unpack
}

show_archive_note() {  # $1 archive name
  local name="$1"
  valid_name "$name" || { printf 'finding: bad archive name\n' >&2; return 2; }
  cat "$archive_root/$name/NOTE.txt"
}

fetch_archive "$1"
show_archive_note "$1"
