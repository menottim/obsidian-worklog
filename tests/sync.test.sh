#!/usr/bin/env bash
# Unit tests for sync.sh. Each case runs against a throwaway vault, a local bare origin and a fake install dir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../skills/worklog/scripts"
FAILS=0
TODAY="$(date +%Y-%m-%d)"
MONTH="$(date +%Y-%m)"

assert_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}
assert_re() { # desc actual ERE
  if printf '%s\n' "$2" | grep -Eq "$3"; then printf 'PASS: %s\n' "$1"
  else printf 'FAIL: %s\n  got:  %s\n  want: /%s/\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
body() { n=0; while [ "$n" -lt "$1" ]; do printf 'line %03d of the note, some padding text\n' "$n"; n=$((n + 1)); done; }

new_case() { # new_case <name>: sets C, V (vault dir with People/Note.md), BARE (empty bare origin), INST (fake install)
  C="$T/$1"; V="$C/vault dir"; BARE="$C/origin.git"; INST="$C/install"
  mkdir -p "$V/People" "$INST/skills/worklog/scripts" "$INST/.claude-plugin"
  body 100 > "$V/People/Note.md"
  printf '# Worklog skill\n' > "$INST/skills/worklog/SKILL.md"
  printf '{"name": "worklog"}\n' > "$INST/.claude-plugin/plugin.json"
  cp "$SCRIPTS"/*.sh "$INST/skills/worklog/scripts/"
  git init -q --bare "$BARE"
}
init_repo() { # git-init V with origin, nothing committed
  git -C "$V" init -q
  git -C "$V" remote add origin "$BARE"
}
init_vault() { # init_repo, commit everything, push it so origin/<branch> exists
  init_repo
  git -C "$V" add -A
  git -C "$V" -c user.name=t -c user.email=t@t commit -qm base
  git -C "$V" push -q origin HEAD
}
edit_note() { # an uncommitted change in the vault, so a sync has something to commit
  printf 'Edited by hand.\n' > "$V/People/Other.md"
}
hand_commit() { # commit one file by hand, so the vault is ahead of origin with a clean tree
  printf 'Added by hand.\n' > "$V/People/Other.md"
  git -C "$V" add -A
  git -C "$V" -c user.name=t -c user.email=t@t commit -qm manual
}
run_sync() { # run_sync [--auto]: sets OUT and RC
  OUT="$(/bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" "test@example.invalid" "$@" 2>"$C/err")"; RC=$?
}
head_of() { git -C "$1" rev-parse -q --verify HEAD 2>/dev/null; }  # empty on an unborn HEAD

# 1. First push: no commits yet, and no Cold/ or Threads/ on disk. Missing allowlisted dirs must not block.
new_case first
init_repo
run_sync
assert_eq "first push exits 0" "$RC" "0"
assert_re "first push prints the success line" "$OUT" '^Synced vault: [0-9a-f]{7,} pushed \([0-9]+ files\)\.$'
assert_eq "bare repo has the first commit" "$(git -C "$BARE" rev-list --count HEAD 2>/dev/null)" "1"
assert_eq "log has sync | vault line" "$(grep -cxF "## [$TODAY] sync | vault" "$V/Logs/$MONTH.md")" "1"
assert_eq "skill copy exists in vault" "$([ -f "$V/.skills/worklog/SKILL.md" ] && echo yes)" "yes"
assert_eq "skill copy is committed" "$(git -C "$BARE" ls-tree -r --name-only HEAD | grep -cx '.skills/worklog/SKILL.md')" "1"

# 2. --auto: prefix, log target and commit subject.
new_case auto
init_repo
run_sync --auto
assert_eq "auto push exits 0" "$RC" "0"
assert_re "auto prints Auto-synced line" "$OUT" '^Auto-synced vault: [0-9a-f]{7,} pushed \([0-9]+ files\)\.$'
assert_eq "auto log target is vault (auto)" "$(grep -cxF "## [$TODAY] sync | vault (auto)" "$V/Logs/$MONTH.md")" "1"
assert_eq "auto commit subject ends with (auto)" "$(git -C "$V" log -1 --format=%s)" "worklog sync $TODAY (auto)"
assert_eq "commit uses the given identity" "$(git -C "$V" log -1 --format='%an <%ae>')" "Test Name <test@example.invalid>"

# 3. Nothing changed after a successful sync: exit 4, no commit, Logs/ untouched.
new_case nothing
init_vault
edit_note
run_sync
assert_eq "first sync after base exits 0" "$RC" "0"
H1="$(head_of "$V")"; LOG1="$(cat "$V/Logs/$MONTH.md")"
run_sync
assert_eq "no change exits 4" "$RC" "4"
assert_eq "no change prints nothing-to-commit" "$OUT" "Sync: nothing to commit."
assert_eq "no change adds no commit" "$(head_of "$V")" "$H1"
assert_eq "no change leaves Logs untouched" "$(cat "$V/Logs/$MONTH.md")" "$LOG1"

# 4. Local commit ahead of origin, clean tree: push only.
new_case ahead
printf 'custom/\n' > "$V/.gitignore"  # present, so sync creates nothing and the commit is the hand commit alone
init_vault
hand_commit
run_sync
assert_eq "ahead commit exits 0" "$RC" "0"
assert_re "ahead commit prints success line" "$OUT" '^Synced vault: [0-9a-f]{7,} pushed \(1 files\)\.$'
assert_eq "bare repo has local HEAD" "$(git -C "$BARE" rev-parse HEAD)" "$(head_of "$V")"

# 5. Shrink check flags an emptied note: exit 1, no commit, no log entry.
new_case shrink
init_vault
: > "$V/People/Note.md"
H1="$(head_of "$V")"
run_sync
assert_eq "shrink flag exits 1" "$RC" "1"
assert_eq "shrink flag prints EMPTY line" "$(printf '%s\n' "$OUT" | grep -cxF 'EMPTY People/Note.md')" "1"
assert_eq "shrink flag adds no commit" "$(head_of "$V")" "$H1"
assert_eq "shrink flag leaves Logs/ absent" "$([ -e "$V/Logs" ] && echo yes || echo no)" "no"
assert_eq "shrink flag leaves Logs diff empty" "$(git -C "$V" diff --stat -- Logs)" ""

# 6. Push failure: origin points at a missing path. The commit stays local.
new_case pushfail
init_vault
edit_note
git -C "$V" remote set-url origin "$C/missing.git"
H1="$(head_of "$V")"
run_sync
assert_eq "push failure exits 3" "$RC" "3"
SHORT="$(git -C "$V" rev-parse --short HEAD)"
assert_eq "push failure prints the git fatal line as the reason" "$OUT" "Synced vault: $SHORT committed locally; push failed: '$C/missing.git' does not appear to be a git repository. The next sync retries."
assert_eq "push failure advances HEAD" "$([ "$(head_of "$V")" != "$H1" ] && echo yes)" "yes"

# 6b. A file staged outside the allowlist is not committed by sync.
new_case scratch
init_vault
edit_note
printf 'scratch\n' > "$V/scratch.txt"
git -C "$V" add scratch.txt
run_sync
assert_eq "scratch case exits 0" "$RC" "0"
assert_eq "staged scratch.txt is not in the commit" "$(git -C "$BARE" ls-tree -r --name-only HEAD | grep -cx 'scratch.txt')" "0"
assert_eq "staged scratch.txt is unstaged and kept on disk" "$(git -C "$V" status --porcelain -- scratch.txt)" "?? scratch.txt"

# 7. WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1 refuses a non-local origin before any push.
new_case refused
init_vault
edit_note
git -C "$V" remote set-url origin "https://example.invalid/x.git"
H1="$(head_of "$V")"
OUT="$(WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1 /bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" "test@example.invalid" 2>"$C/err")"; RC=$?
assert_eq "refused remote exits 3" "$RC" "3"
assert_re "refused remote prints reason" "$OUT" '^Synced vault: [0-9a-f]{7,} committed locally; push failed: non-local remote refused\. The next sync retries\.$'
assert_eq "refused remote keeps the local commit" "$([ "$(head_of "$V")" != "$H1" ] && echo yes)" "yes"

# 8. WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1 still pushes to a local path origin.
new_case localonly
init_vault
hand_commit
OUT="$(WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1 /bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" "test@example.invalid" 2>"$C/err")"; RC=$?
assert_eq "local path with REMOTE_ONLY still exits 0" "$RC" "0"
assert_eq "local path with REMOTE_ONLY reaches origin" "$(git -C "$BARE" rev-parse HEAD)" "$(head_of "$V")"

# 9. No origin: exit 2, no Logs/ entry.
new_case noremote
git init -q "$V"
run_sync
assert_eq "no origin exits 2" "$RC" "2"
assert_eq "no origin prints skipped line" "$OUT" "Sync skipped: no backup remote."
run_sync --auto
assert_eq "no origin with --auto exits 2" "$RC" "2"
assert_eq "no origin with --auto prints skipped line" "$OUT" "Auto-sync skipped: no backup remote."
assert_eq "no origin leaves Logs/ absent" "$([ -e "$V/Logs" ] && echo yes || echo no)" "no"

# 10. Usage: missing args or an unknown flag exit 2.
new_case usage
/bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" >/dev/null 2>&1; RC=$?
assert_eq "three args exit 2" "$RC" "2"
/bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" "test@example.invalid" --bogus >/dev/null 2>&1; RC=$?
assert_eq "unknown flag exits 2" "$RC" "2"

# 11. Vault nested in a parent repo with an origin: sync skips and the parent repo is untouched.
new_case nested
git init -q "$C"
git -C "$C" remote add origin "$BARE"
git -C "$C" -c user.name=t -c user.email=t@t commit -q --allow-empty -m parent
H1="$(head_of "$C")"
run_sync
assert_eq "nested vault exits 2" "$RC" "2"
assert_eq "nested vault prints skipped line" "$OUT" "Sync skipped: not a git repo."
assert_eq "nested vault leaves parent HEAD unchanged" "$(head_of "$C")" "$H1"

# 12. A missing .gitignore is created with the default lines; an existing one is left alone.
DEFAULT_GI="$(printf '%s\n' '.obsidian/plugins/*/data.json' '.obsidian/workspace.json' '.DS_Store' '*.swp' '.env')"
new_case gitignore
init_repo
run_sync
assert_eq "missing .gitignore is created with the default lines" "$(cat "$V/.gitignore" 2>/dev/null)" "$DEFAULT_GI"
new_case gitignore_kept
printf 'custom/\n' > "$V/.gitignore"
init_repo
run_sync
assert_eq "existing .gitignore is left alone" "$(cat "$V/.gitignore")" "custom/"

# 13. Rollover moves a committed week to Archive/ without committing it. The sync commits the move and pushes.
new_case archive
init_repo
mkdir -p "$V/Worklogs"; body 100 > "$V/Worklogs/2026-W40.md"
git -C "$V" add -A; git -C "$V" -c user.name=t -c user.email=t@t commit -qm base; git -C "$V" push -q origin HEAD
mkdir -p "$V/Archive"; mv "$V/Worklogs/2026-W40.md" "$V/Archive/2026-W40.md"
run_sync
assert_eq "archive move exits 0" "$RC" "0"
assert_eq "archive move is pushed" "$(git -C "$BARE" rev-parse HEAD)" "$(head_of "$V")"
assert_eq "archive move commits the Archive copy" "$(git -C "$BARE" ls-tree -r --name-only HEAD | grep -cx 'Archive/2026-W40.md')" "1"
assert_eq "archive move drops the Worklogs copy from the commit" "$(git -C "$BARE" ls-tree -r --name-only HEAD | grep -cx 'Worklogs/2026-W40.md')" "0"

# 14. WORKLOG_SHRINK_CONFIRM passes through sync: a confirmed deletion does not stop it.
new_case confirm
init_vault
rm "$V/People/Note.md"
OUT="$(WORKLOG_SHRINK_CONFIRM='People/Note.md' /bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" "test@example.invalid" 2>"$C/err")"; RC=$?
assert_eq "confirmed deletion exits 0" "$RC" "0"
assert_eq "confirmed deletion is committed" "$(git -C "$BARE" ls-tree -r --name-only HEAD | grep -cx 'People/Note.md')" "0"

# 15. Detached HEAD: exit 2 before anything is written. No commit, no Logs/, no Cold/.
new_case detached
init_vault
git -C "$V" checkout -q --detach
edit_note
H1="$(head_of "$V")"
run_sync
assert_eq "detached HEAD exits 2" "$RC" "2"
assert_eq "detached HEAD prints skipped line" "$OUT" "Sync skipped: detached HEAD."
run_sync --auto
assert_eq "detached HEAD with --auto prints skipped line" "$OUT" "Auto-sync skipped: detached HEAD."
assert_eq "detached HEAD adds no commit" "$(head_of "$V")" "$H1"
assert_eq "detached HEAD writes no Logs/ or Cold/" "$([ -e "$V/Logs" ] || [ -e "$V/Cold" ] && echo yes || echo no)" "no"

# 16. The push guard reads the push URL. A local fetch URL with a non-local pushurl is refused.
new_case pushurl
init_vault
edit_note
git -C "$V" remote set-url --add --push origin "https://example.invalid/x.git"
OUT="$(WORKLOG_SYNC_LOCAL_REMOTE_ONLY=1 /bin/bash "$INST/skills/worklog/scripts/sync.sh" "$V" "$INST" "Test Name" "test@example.invalid" 2>"$C/err")"; RC=$?
assert_eq "non-local pushurl exits 3" "$RC" "3"
assert_re "non-local pushurl prints refusal" "$OUT" 'non-local remote refused'

# 17. A Logs-only change is committed with the sync entry. An otherwise clean vault still exits 4.
new_case logsonly
printf '%s\n' "$DEFAULT_GI" > "$V/.gitignore"
init_vault
mkdir -p "$V/Logs"; printf 'manual log line\n' > "$V/Logs/$MONTH.md"
run_sync
assert_eq "Logs-only change exits 0" "$RC" "0"
assert_eq "Logs-only change leaves a clean status" "$(git -C "$V" status --porcelain)" ""
assert_eq "Logs-only change is in the commit" "$(git -C "$BARE" show "HEAD:Logs/$MONTH.md" | grep -c 'manual log line')" "1"
run_sync
assert_eq "clean vault still exits 4 after a Logs-only sync" "$RC" "4"

# 18. A failed commit restores the month log byte for byte and leaves HEAD unchanged.
new_case logfail
init_vault
edit_note
run_sync
printf 'Second edit.\n' > "$V/People/Second.md"
cp "$V/Logs/$MONTH.md" "$C/log.before"
H1="$(head_of "$V")"
printf '#!/bin/sh\nexit 1\n' > "$V/.git/hooks/pre-commit"; chmod +x "$V/.git/hooks/pre-commit"
run_sync
assert_eq "commit failure exits 2" "$RC" "2"
assert_eq "commit failure keeps the stderr message" "$(cat "$C/err")" "sync: commit failed"
assert_eq "commit failure restores the log byte for byte" "$(cmp -s "$C/log.before" "$V/Logs/$MONTH.md" && echo same)" "same"
assert_eq "commit failure leaves HEAD unchanged" "$(head_of "$V")" "$H1"
assert_eq "commit failure leaves nothing staged" "$(git -C "$V" diff --cached --name-only | grep -c .)" "0"

# 18b. Same failure with no month log yet: the log the sync created is removed. HEAD is unborn here.
new_case logfail_new
init_repo
edit_note
printf '#!/bin/sh\nexit 1\n' > "$V/.git/hooks/pre-commit"; chmod +x "$V/.git/hooks/pre-commit"
run_sync
assert_eq "commit failure on a new month log exits 2" "$RC" "2"
assert_eq "commit failure removes the month log it created" "$([ -e "$V/Logs/$MONTH.md" ] && echo yes || echo no)" "no"
assert_eq "commit failure on an unborn HEAD leaves no commit" "$(head_of "$V")" ""

# 19. A fresh vault gets its .gitignore committed, and the vault status is clean afterwards.
new_case gitignore_commit
init_repo
run_sync
assert_eq "fresh vault .gitignore is in HEAD" "$(git -C "$BARE" show HEAD:.gitignore 2>/dev/null)" "$DEFAULT_GI"
assert_eq "fresh vault status is clean after sync" "$(git -C "$V" status --porcelain)" ""

# 20. A changed .gitignore is committed.
new_case gitignore_edit
printf 'old/\n' > "$V/.gitignore"
init_vault
printf 'custom/\n' > "$V/.gitignore"
run_sync
assert_eq "modified .gitignore exits 0" "$RC" "0"
assert_eq "modified .gitignore is in HEAD" "$(git -C "$BARE" show HEAD:.gitignore 2>/dev/null)" "custom/"

if [ "$FAILS" -gt 0 ]; then printf '\n%d test(s) failed\n' "$FAILS"; exit 1; fi
printf '\nAll tests passed\n'
