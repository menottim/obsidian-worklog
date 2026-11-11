#!/usr/bin/env bash
# Case 32: current-state sections must survive a fold, and a subsection nested
# under a dated entry must not be promoted out of it.
#
# Compaction stops for approval before writing, so a single-turn run produces a
# proposal and touches nothing. That gate is the first thing checked here: a fold
# written before it is shown is unrecoverable in a way the rules exist to prevent.
# The remaining checks read the proposal text, which is softer than reading a
# diff, and is the most this case can observe without a second turn.
. "$(dirname "$0")/_lib.sh"

NOTE="$VAULT/People/Nadia Okafor.md"

[ "$(changed_count)" -eq 0 ]; check "wrote nothing before approval" $?
grep -qiE 'propos|preview|before writing|approve' "$OUT"; check "showed a proposal" $?

# The note is untouched, so the sections are trivially intact - what matters is
# that the proposal does not schedule them for folding.
grep -q '^## Role (HR system, confirmed ' "$NOTE"; check "## Role still present in the note" $?
grep -q '^## 1:1 Doc$' "$NOTE"; check "## 1:1 Doc still present in the note" $?

# The trap: a rule keyed to "the heading has no date" would fold ## Role, whose
# date stamp is what makes it current state.
# The proposal groups these under a heading and lists them on their own lines, so
# match the grouping rather than requiring the keyword on the same line.
grep -qiE 'preserv|unchanged|untouched|current.state|staying in place' "$OUT"
check "proposal has a preserved / current-state grouping" $?
grep -qF '## Role' "$OUT" && grep -qF '## 1:1 Doc' "$OUT"
check "proposal names both current-state sections" $?
# No inverse prose check here. A correct proposal says "## Role and ## 1:1 Doc are
# untouched per the fold rules", which contains both the section names and the
# word fold, and a naive negative match fails it for being right. The positive
# grouping check above plus the untouched file on disk carry this.

! grep -qiE '(promot|extract|lift)[^\n]{0,40}Current Status' "$OUT"
check "does not promote the nested Current Status out of its dated parent" $?
exit $FAILS
