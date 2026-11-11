#!/usr/bin/env bash
# auto-sync.sh <vault> get | can-sync | set <on|off> <setup|first-run|user>
# Reads and writes the Auto Sync preference note, Preferences/Auto Sync.md.
# get: prints on | off | unset | invalid. invalid also warns on stderr. Exit 0.
#   unset: no note, or no auto_sync line in its frontmatter.
# can-sync: exit 0 when the vault is the top level of a git work tree with an origin remote.
#   Otherwise exit 1 and print "not a git repo" or "no backup remote" to stdout. A vault folder
#   nested inside another repo is "not a git repo".
# set: creates the note from the spec template, or rewrites the auto_sync line and appends a
#   "- <date>: set to <value> via <source>." line. Writes a temp file, then mv over the note.
#   Exit 2 on a bad argument. bash 3.2; coreutils + git + awk.
set -uo pipefail

usage() { echo "auto-sync: usage: auto-sync.sh <vault> get | can-sync | set <on|off> <setup|first-run|user>" >&2; exit 2; }

[ "$#" -ge 2 ] || usage
VAULT="$1"; CMD="$2"; shift 2
NOTE="$VAULT/Preferences/Auto Sync.md"

# First frontmatter block only. Prints the auto_sync line, or nothing when absent.
note_line() {
  awk '
    { sub(/\r$/, "") }
    NR==1 && $0!="---" { exit }
    NR==1 { infm=1; next }
    infm && $0=="---" { exit }
    infm && /^auto_sync:/ { print; exit }
  ' "$NOTE"
}

cmd_get() {
  [ -f "$NOTE" ] || { echo unset; return 0; }
  LINE="$(note_line)"
  [ -n "$LINE" ] || { echo unset; return 0; }
  # Drop a trailing " # comment", the surrounding space, and one pair of quotes. CR is stripped in note_line.
  VAL="$(printf '%s' "${LINE#auto_sync:}" | awk '{ sub(/ # .*/, ""); $1=$1; print }')"
  case "$VAL" in \"*\"|\'*\') VAL="${VAL#?}"; VAL="${VAL%?}" ;; esac
  case "$VAL" in
    on|off) echo "$VAL" ;;
    *) echo invalid
       echo "auto-sync: Preferences/Auto Sync.md has auto_sync: $VAL; treating as off" >&2 ;;
  esac
  return 0
}

cmd_can_sync() {
  # The vault must be the work tree's top level. Compare physical paths: on macOS /tmp is a symlink.
  TOP="$(git -C "$VAULT" rev-parse --show-toplevel 2>/dev/null)" || TOP=""
  PHYS="$(cd "$VAULT" 2>/dev/null && pwd -P)" || PHYS=""
  [ -n "$TOP" ] && [ "$TOP" = "$PHYS" ] || { echo "not a git repo"; return 1; }
  git -C "$VAULT" remote get-url origin >/dev/null 2>&1 || { echo "no backup remote"; return 1; }
  return 0
}

template() { # the spec's note template; $VALUE, $TODAY and $SRC are set by cmd_set
  printf '%s\n' '---' 'type: preference' 'applies-to: [workflow, sync]' \
    "auto_sync: $VALUE" '---' '' '# Auto Sync' '' \
    'When on, every /worklog command that writes the vault ends with a commit and push to the' \
    'backup repo, and prints one line saying so. Set `auto_sync: off` to go back to manual' \
    '`/worklog sync`.' \
    "Chosen on $TODAY via $SRC."
}

cmd_set() {
  VALUE="${1:-}"; SRC="${2:-}"
  case "$VALUE" in on|off) ;; *) usage ;; esac
  case "$SRC" in setup|first-run|user) ;; *) usage ;; esac
  TODAY="$(date +%Y-%m-%d)"
  mkdir -p "$VAULT/Preferences" || { echo "auto-sync: cannot create $VAULT/Preferences" >&2; exit 1; }
  TMP="$(mktemp "$VAULT/Preferences/.auto-sync.XXXXXX")" || exit 1
  trap 'rm -f "$TMP"' EXIT
  if [ -f "$NOTE" ]; then
    awk -v v="$VALUE" -v s="$SRC" -v d="$TODAY" '
      NR==1 && $0!="---" { print "---"; print "auto_sync: " v; print "---"; done=1 }
      NR==1 && $0=="---" { infm=1; print; next }
      infm && $0=="---" { if (!done) { print "auto_sync: " v; done=1 } infm=0; print; next }
      infm && /^auto_sync:/ { if (!done) { print "auto_sync: " v; done=1 } next }
      { print }
      END {
        if (NR==0) { print "---"; print "auto_sync: " v; print "---" }
        print "- " d ": set to " v " via " s "."
      }
    ' "$NOTE" > "$TMP" || exit 1
  else
    template > "$TMP" || exit 1
  fi
  mv "$TMP" "$NOTE" || exit 1
  trap - EXIT
  return 0
}

case "$CMD" in
  get)      cmd_get; exit $? ;;
  can-sync) cmd_can_sync; exit $? ;;
  set)      cmd_set "$@"; exit $? ;;
  *)        usage ;;
esac
