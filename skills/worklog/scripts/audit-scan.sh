#!/usr/bin/env bash
# audit-scan.sh <vault> - compute the twelve /worklog audit checks; emit JSON findings to stdout.
# Read-only. Scans the vault in bash so the model never loads People/Programs bodies.
# Checks mirror the definitions in references/audit.md exactly.
set -euo pipefail

VAULT="${1:?usage: audit-scan.sh <vault-path>}"
[ -d "$VAULT" ] || { echo "audit-scan: vault dir not found: $VAULT" >&2; exit 2; }
cd "$VAULT"

# The 4 most recent weekly files (YYYY-WNN.md) across Worklogs + Archive.
# Use while-read loop instead of mapfile for bash 3.2 compatibility (macOS default bash).
RECENT_BN=()
while IFS= read -r b; do
  RECENT_BN+=("$b")
done < <(
  { ls Worklogs 2>/dev/null; ls Archive 2>/dev/null; } \
    | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -u -r | head -4
)
RECENT=()
for b in "${RECENT_BN[@]:-}"; do
  [ -n "$b" ] || continue
  [ -f "Worklogs/$b" ] && RECENT+=("Worklogs/$b")
  [ -f "Archive/$b" ]  && RECENT+=("Archive/$b")
done
BACKLOG="Worklogs/Backlog.md"
ACTIVE_BN="$(ls Worklogs 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -r | head -1 || true)"
ACTIVE="${ACTIVE_BN:+Worklogs/${ACTIVE_BN}}"

emit_array(){ jq -s '.'; }

stale_people(){
  shopt -s nullglob
  # Build sorted list of ALL weekly files (Worklogs + Archive) for last_seen lookup.
  ALL_WEEKLY=()
  while IFS= read -r b; do ALL_WEEKLY+=("$b"); done < <(
    { ls Worklogs 2>/dev/null; ls Archive 2>/dev/null; } \
      | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort -u | sort
  )
  for f in People/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" "$BACKLOG" 2>/dev/null; then
      # Find last_seen: highest WNN weekly file (basename without .md, sorted desc)
      # among ALL weekly files in which [[<name appears.
      last_seen="never"
      for b in "${ALL_WEEKLY[@]:-}"; do
        [ -n "$b" ] || continue
        found_in=""
        [ -f "Worklogs/$b" ] && grep -Fq "[[$name" "Worklogs/$b" 2>/dev/null && found_in="$b"
        [ -f "Archive/$b"  ] && grep -Fq "[[$name" "Archive/$b"  2>/dev/null && found_in="$b"
        if [ -n "$found_in" ]; then
          # basename without .md = week label e.g. 2026-W19
          last_seen="${found_in%.md}"
        fi
      done
      # ALL_WEEKLY is sorted ascending, so last iteration that matched is the highest week
      jq -cn --arg file "$f" --arg last_seen "$last_seen" '{file:$file, last_seen:$last_seen}'
    fi
  done | emit_array
}

orphan_programs(){
  shopt -s nullglob
  for f in Programs/*.md; do
    name="$(basename "$f" .md)"
    if ! grep -Fq "[[$name" "${RECENT[@]:-/dev/null}" 2>/dev/null; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

empty_stubs(){
  shopt -s nullglob
  for f in People/*.md Programs/*.md; do
    bullets="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm<2{next} /^[[:space:]]*-[[:space:]]/{n++} END{print n+0}' "$f")"
    if [ "${bullets:-0}" -eq 0 ]; then
      jq -cn --arg file "$f" '{file:$file}'
    fi
  done | emit_array
}

frontmatter_gaps(){
  shopt -s nullglob
  for f in Worklogs/[0-9]*-W*.md Archive/[0-9]*-W*.md; do
    [ -f "$f" ] || continue
    fm="$(awk 'BEGIN{n=0} /^---$/{n++; next} n==1{print} n>=2{exit}' "$f")"
    missing="$(for k in programs people tags item-count done-count; do
                 printf '%s\n' "$fm" | grep -Eq "^${k}:" || echo "$k"
               done | jq -R . | jq -s '.')"
    if [ "$(printf '%s' "$missing" | jq 'length')" -gt 0 ]; then
      jq -cn --arg file "$f" --argjson missing "$missing" '{file:$file, missing:$missing}'
    fi
  done | emit_array
}

missing_links(){
  shopt -s nullglob
  local pfile
  pfile="$(mktemp)"
  { ls People 2>/dev/null; ls Programs 2>/dev/null; } | sed 's/\.md$//' | sort -u > "$pfile"
  for f in "${RECENT[@]:-}"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    grep -nFf "$pfile" "$f" 2>/dev/null | while IFS=: read -r ln rest; do
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$rest" in *"[[$name"*) continue ;; esac
        case "$rest" in
          *"$name"*)
            jq -cn --arg file "$f" --argjson line "$ln" --arg text "$name" \
               '{file:$file, line:$line, text:$text, suggest:("[[" + $text + "]]")}'
          ;;
        esac
      done < "$pfile"
    done
  done | emit_array
  rm -f "$pfile"
}

stuck_items(){
  [ -n "${ACTIVE:-}" ] && [ -f "$ACTIVE" ] || { echo '[]'; return; }
  shopt -s nullglob
  # Sorted ascending list of archive basenames (e.g. 2026-W14.md, 2026-W15.md, ...)
  ARCH=()
  while IFS= read -r a; do ARCH+=("$a"); done < <(ls Archive 2>/dev/null | grep -E '^[0-9]{4}-W[0-9]{2}\.md$' | sort)
  ARCH_LEN="${#ARCH[@]}"
  norm(){ printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9 ' | tr -s ' '; }
  while IFS= read -r line; do
    title="${line#*In Progress - }"
    nt="$(norm "$title")"
    [ -n "$nt" ] || continue
    prefix20="$(printf '%s' "$nt" | cut -c1-20)"

    # --- Step 1: Collect indices of matching archives ---
    match_indices=""
    since_week=""
    i=0
    while [ "$i" -lt "$ARCH_LEN" ]; do
      a="${ARCH[$i]}"
      roll="$(grep -oE 'rolled forward to [^(]*\(([^)]*)\)' "Archive/$a" 2>/dev/null | sed 's/.*(\(.*\))/\1/' || true)"
      if [ -n "$roll" ] && printf '%s' "$(norm "$roll")" | grep -qF "$prefix20"; then
        match_indices="${match_indices} $i"
        # earliest matching archive week (ascending sort => first match)
        if [ -z "$since_week" ]; then since_week="${a%.md}"; fi
      fi
      i=$((i+1))
    done

    # Need at least 2 matches for any consecutiveness check
    match_count=$(printf '%s' "$match_indices" | wc -w | tr -d ' ')
    [ "$match_count" -ge 2 ] || continue

    # --- Step 2: Require at least two ADJACENT (consecutive) matching indices ---
    consecutive=0
    prev=-99
    for idx in $match_indices; do
      if [ "$((idx - prev))" -eq 1 ]; then consecutive=1; break; fi
      prev="$idx"
    done
    [ "$consecutive" -eq 1 ] || continue

    # --- Step 3: Extract item block from active week, check for (Mon D) dated sub-item ---
    # Capture lines from the item's header up to (but not including) the next P0/P1/P2 header.
    item_block="$(awk -v tgt="$title" '
      BEGIN{found=0}
      /^- \*\*P[012]\*\* ⏳ In Progress - /{
        if(found){exit}
        if(index($0, tgt)>0){found=1; print; next}
      }
      found{print}
    ' "$ACTIVE" 2>/dev/null)"
    # Regex for (Mon D) or (Mon DD): e.g. (May 14), (Jun 4)
    if printf '%s' "$item_block" | grep -qE '\([A-Z][a-z][a-z] [0-9]{1,2}\)'; then
      continue  # has dated progress - not stuck
    fi

    # --- Step 4: Emit {title, since, last_dated:null} ---
    jq -cn --arg title "$title" --arg since "$since_week" \
       '{title:$title, since:$since, last_dated:null}'
  done < <(grep -E '^- \*\*P[012]\*\* ⏳ In Progress - ' "$ACTIVE" 2>/dev/null) | emit_array
}

oversized_notes(){
  shopt -s nullglob
  limit="${WORKLOG_COMPACT_LINES:-250}"
  # Threads are per-item history logs; being long is their job. 250 lines is a People-note
  # threshold and would report every Thread on the day it is created. 400 is where a Thread
  # stops being scannable and starts wanting a fold.
  tlimit="${WORKLOG_THREAD_LINES:-400}"
  for f in People/*.md Programs/*.md Threads/*.md; do
    n="$(awk 'END{print NR}' "$f")"
    case "$f" in Threads/*) lim="$tlimit" ;; *) lim="$limit" ;; esac
    [ "$n" -gt "$lim" ] || continue
    c="$(awk 'BEGIN{fm=0}
              /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
              fm==1 && /^compacted:/{ s=$0; sub(/^compacted:[[:space:]]*/,"",s)
                                      gsub(/[[:space:]]+$/,"",s)
                                      gsub(/^["'\'']|["'\'']$/,"",s)
                                      print s; exit }' "$f")"
    if [ -n "$c" ]; then
      jq -cn --arg file "$f" --argjson lines "$n" --arg compacted "$c" \
         '{file:$file, lines:$lines, compacted:$compacted}'
    else
      jq -cn --arg file "$f" --argjson lines "$n" '{file:$file, lines:$lines, compacted:null}'
    fi
  done | emit_array
}

# Distribution, not findings: 86 distinct team: values across 314 People notes in the
# real vault, of which only 7 resolve exactly. As a per-note dangling-reference list
# that is ~300 findings and useless. The model reads the table and proposes merges.
team_vocabulary(){
  shopt -s nullglob
  [ -d People ] || { echo '[]'; return; }
  tn="$(mktemp)"
  { ls Teams 2>/dev/null || true; } | sed 's/\.md$//' | sort > "$tn"
  TAB="$(printf '\t')"
  # A possibly-empty glob under nullglob leaves grep with NO file operands, and grep
  # with no operands reads stdin and blocks. </dev/null makes the zero-notes case
  # return instead of hanging. Harmless when files exist: grep ignores stdin then.
  grep -h '^team:' People/*.md 2>/dev/null </dev/null \
    | sed -e 's/^team:[[:space:]]*//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | awk '{c[$0]++} END{for(k in c) printf "%d\t%s\n", c[k], k}' \
    | sort -t"$TAB" -k1,1nr -k2,2 \
    | while IFS="$TAB" read -r cnt value; do
        [ -n "$value" ] || continue
        if grep -Fxq "$value" "$tn"; then
          jq -cn --arg v "$value" --argjson n "$cnt" '{value:$v, notes:$n, resolves:"exact"}'
        else
          cand="$(grep -iF "$value" "$tn" | head -1 || true)"
          if [ -n "$cand" ]; then
            jq -cn --arg v "$value" --argjson n "$cnt" --arg c "$cand" \
               '{value:$v, notes:$n, resolves:"substring", candidate:$c}'
          else
            jq -cn --arg v "$value" --argjson n "$cnt" '{value:$v, notes:$n, resolves:"none"}'
          fi
        fi
      done | emit_array
  rm -f "$tn"
}

# Distribution, not findings. Prototyped as findings first: 23 tags recur in 3+ files in
# the real vault, 21 have no Programs page, and only ~2 of those deserve one -- "strategy",
# "growth", and "leadership" are themes, not programs. ~90% false positive. So emit counts
# and let the model judge which recurring themes deserve promotion.
# Tags (not subgroup headings) are the signal because tags: frontmatter survives archiving
# while archiving rewrites weekly bodies as flat lists, discarding subgroup structure.
recurring_tags(){
  shopt -s nullglob
  min="${WORKLOG_TAG_MIN_FILES:-3}"
  pn="$(mktemp)"; tf="$(mktemp)"
  { ls Programs 2>/dev/null || true; } | sed 's/\.md$//' > "$pn"
  TAB="$(printf '\t')"
  for f in Worklogs/[0-9]*-W*.md Archive/[0-9]*-W*.md; do
    [ -f "$f" ] || continue
    awk '
      BEGIN{fm=0; t=0}
      /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next}
      fm==1 && /^tags:/{t=1; next}
      fm==1 && t && /^[[:space:]]+-[[:space:]]*/{
        s=$0; sub(/^[[:space:]]+-[[:space:]]*/,"",s)
        gsub(/^["'\'']|["'\'']$/,"",s); if(s!="") print s; next }
      fm==1 && t && /^[^[:space:]]/{t=0}
    ' "$f" | sort -u
  done | awk -v min="$min" '{c[$0]++} END{for(k in c) if (c[k]+0 >= min+0) printf "%d\t%s\n", c[k], k}' \
       | sort -t"$TAB" -k1,1nr -k2,2 > "$tf"
  while IFS="$TAB" read -r cnt tag; do
    [ -n "$tag" ] || continue
    has=false
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      norm="$(printf '%s' "$p" | tr 'A-Z' 'a-z' | tr ' ' '-')"
      if [ "$norm" = "$tag" ]; then has=true; break; fi
    done < "$pn"
    jq -cn --arg t "$tag" --argjson f "$cnt" --argjson h "$has" '{tag:$t, files:$f, has_page:$h}'
  done < "$tf" | emit_array
  rm -f "$pn" "$tf"
}

# Gauge, not findings. Measures sub-item mass, NOT top-level item count. "Fold before you
# add" pins item count while routing every new fact into an existing item as a sub-item, so
# item count is the one dimension that structurally cannot see this growth: on 2026-W37.md,
# 151 items whose title lines were 18.6 KB carried 925 KB of sub-items.
# Emits one object or null, never an array - there is one active week.
week_volume(){
  if [ -z "${ACTIVE:-}" ] || [ ! -f "$ACTIVE" ]; then echo 'null'; return; fi
  maxb="${WORKLOG_WEEK_BYTES:-40000}"
  maxs="${WORKLOG_WEEK_KEEP_SUBS:-2}"
  maxitem="${WORKLOG_WEEK_ITEM_BYTES:-6000}"
  TAB="$(printf '\t')"
  # `biggest` is the largest item observed; the shell's thresholds are maxb/maxitem. Keep
  # those names distinct - an earlier version called both of them maxi, which read as a
  # comparison of a value against itself.
  row="$(awk -v maxs="$maxs" '
    BEGIN{fm=0; seen=0}
    /^---[[:space:]]*$/{ if(fm<2){ fm++; next } }
    fm<2{next}
    { seen=1; body += length($0)+1 }
    /^- \*\*P[012]\*\*/{
      if(t!=""){ if(n>maxs) over++; if(b>biggest){ biggest=b; maxt=t } }
      items++; t=$0; b=length($0)+1; n=0; next
    }
    t!=""{ b += length($0)+1
           if($0 ~ /^[[:space:]]+-[[:space:]]/){ subs++; n++ } }
    END{ if(t!=""){ if(n>maxs) over++; if(b>biggest){ biggest=b; maxt=t } }
         # No closing frontmatter delimiter means every line was skipped and the counts
         # below would all be zero - reporting a 900 KB file as empty and under threshold,
         # which is the exact blind spot this gauge exists to close. Say unknown instead.
         if(!seen){ print "unparsed"; exit }
         printf "%d\t%d\t%d\t%d\t%d\t%s\n", body+0, items+0, subs+0, over+0, biggest+0, maxt }
  ' "$ACTIVE")"
  if [ "$row" = "unparsed" ]; then
    jq -cn --arg file "$ACTIVE" \
      '{file:$file, body_bytes:null, items:null, sub_items:null, bytes_per_item:null,
        items_over_sub_cap:null, largest_item_bytes:null, largest_item:null,
        over_threshold:true, note:"frontmatter not parseable; week file body could not be measured"}'
    return
  fi
  IFS="$TAB" read -r body items subs over biggest maxt <<EOF
$row
EOF
  # Trigger on bytes, not on the raw sub-item count. Retention deliberately keeps more
  # than WORKLOG_WEEK_KEEP_SUBS on an item carrying open actions or undated lines
  # (threads.md rules 3 and 4), so a strict count check flags its own correct output.
  # items_over_sub_cap stays reported, as information rather than a trigger.
  flag=false
  if [ "$body" -gt "$maxb" ] || [ "$biggest" -gt "$maxitem" ]; then flag=true; fi
  per_item=0
  if [ "$items" -gt 0 ]; then per_item=$(( body / items )); fi
  jq -cn --arg file "$ACTIVE" --arg largest "$maxt" \
         --argjson body "$body" --argjson items "$items" --argjson subs "$subs" \
         --argjson over "$over" --argjson maxi "$biggest" --argjson per "$per_item" \
         --argjson flag "$flag" --argjson lb "$maxb" --argjson ls "$maxs" --argjson li "$maxitem" \
    '{file:$file, body_bytes:$body, items:$items, sub_items:$subs,
      bytes_per_item:$per, items_over_sub_cap:$over,
      largest_item_bytes:$maxi, largest_item:$largest,
      over_threshold:$flag, limits:{body_bytes:$lb, item_bytes:$li, item_sub_items:$ls}}'
}

# cutoff_for <days>: YYYYMMDD of (today - days). WORKLOG_TODAY=YYYY-MM-DD overrides for tests.
# BSD date first (macOS), GNU date fallback.
cutoff_for(){
  local d="$1" t="${WORKLOG_TODAY:-}"
  if [ -n "$t" ]; then
    date -j -f %Y-%m-%d -v-"${d}"d "$t" +%Y%m%d 2>/dev/null || date -d "$t - $d days" +%Y%m%d
  else
    date -j -v-"${d}"d +%Y%m%d 2>/dev/null || date -d "$d days ago" +%Y%m%d
  fi
}

# Distribution: bytes in dated `##` sections older than the folder's window, plus any non-empty
# `## History` section, plus dated `###` subsections under an undated non-current-state `##`
# container (each counts as a section). Bytes are counted before pins. One awk pass per folder.
# Current-state headings (Role, Context, Current Focus, Current State, Status, OOO, 1:1 Doc,
# Members) are checked first and never move. Dated = heading holding a date: `Mon D[, YYYY]`,
# `Mon D-D`, `Mon D - Mon D`, `Month D YYYY`, `Mon YYYY` (dated the last day of the month),
# or ISO `YYYY-MM-DD`. A year-less date takes the most recent past year. A range is dated by its
# END date, so entries move late, never early. A section runs to the next `## ` or `# `
# heading. Headings inside code fences are ignored. awk runs under LC_ALL=C so lengths are bytes.
# Notes at or over WORKLOG_COLD_MIN_KB movable KB are listed, largest first.
cold_candidates(){
  shopt -s nullglob
  local minb=$(( ${WORKLOG_COLD_MIN_KB:-4} * 1024 )) TAB cut folder days today
  TAB="$(printf '\t')"
  today="$(cutoff_for 0)"
  for folder in People Programs Threads; do
    case "$folder" in
      People)   days="${WORKLOG_COLD_DAYS_PEOPLE:-60}" ;;
      Programs) days="${WORKLOG_COLD_DAYS_PROGRAMS:-60}" ;;
      Threads)  days="${WORKLOG_COLD_DAYS_THREADS:-30}" ;;
    esac
    local files=("$folder"/*.md)
    [ "${#files[@]}" -gt 0 ] || continue
    cut="$(cutoff_for "$days")"
    LC_ALL=C awk -v cut="$cut" -v today="$today" -v minb="$minb" '
      BEGIN{
        n=split("jan feb mar apr may jun jul aug sep oct nov dec",a," ")
        for(i=1;i<=n;i++) MI[a[i]]=i
        n=split("january february march april may june july august september october november december",a," ")
        for(i=1;i<=n;i++) MI[a[i]]=i
        MI["sept"]=9
        split("31 28 31 30 31 30 31 31 30 31 30 31",DM," ")
        ty=int(today/10000); tmd=today%10000
        nx=split("role|context|current focus|current state|status|ooo|1:1 doc|members",EX,"|")
      }
      function flush(){ if(f!=""){ if(mv>=minb) printf "%d\t%d\t%d\t%s\n", mv, tot, cnt, f } }
      # the heading text is the name alone, or the name then "(", "-" or ":" (spaces allowed before);
      # "Role Definition Landed" and "Roleplay" are not current-state headings
      function excl(h,  t,i,r){ t=tolower(h); sub(/^#+ +/,"",t)
        for(i=1;i<=nx;i++){ if(substr(t,1,length(EX[i]))==EX[i]){ r=substr(t,length(EX[i])+1); sub(/^ +/,"",r); if(r==""||r ~ /^[(:-]/) return 1 } }
        return 0 }
      function eom(m,y){ if(m==2 && (y%4==0 && (y%100!=0 || y%400==0))) return 29; return DM[m]+0 }
      # YYYYMMDD of the first date in the heading (range: its end date), 0 if none
      function dkey(h,  s,w,rest,m,d,y,r,em,ed,t,seg,rr,c,p){
        if(match(h,/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)){
          t=substr(h,RSTART,RLENGTH); gsub(/-/,"",t)
          if(substr(t,5,2)+0>=1 && substr(t,5,2)+0<=12 && substr(t,7,2)+0>=1 && substr(t,7,2)+0<=31) return t+0 }
        s=tolower(h)
        while(match(s,/[a-z]+/)){
          w=substr(s,RSTART,RLENGTH); rest=substr(s,RSTART+RLENGTH); s=rest
          if(!(w in MI)) continue
          m=MI[w]
          if(match(rest,/^ +[0-9][0-9][0-9][0-9]([^0-9]|$)/)){
            t=substr(rest,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); return t*10000+m*100+eom(m,t+0) }
          if(!match(rest,/^ +[0-9][0-9]?/)) continue
          d=substr(rest,1,RLENGTH)+0; r=substr(rest,RLENGTH+1)
          if(r ~ /^[0-9]/ || d<1 || d>31) continue
          em=m; ed=d
          if(match(r,/^-[0-9][0-9]?/)){
            t=substr(r,2,RLENGTH-1); rr=substr(r,RLENGTH+1)
            if(substr(rr,1,1) !~ /[0-9:]/ && t+0>=1 && t+0<=31){ ed=t+0; r=rr } }
          else if(match(r,/^ *- *[a-z]+ +[0-9][0-9]?/)){
            seg=substr(r,1,RLENGTH); rr=substr(r,RLENGTH+1); sub(/^ *- */,"",seg); split(seg,p," ")
            if((p[1] in MI) && substr(rr,1,1) !~ /[0-9:]/ && p[2]+0>=1 && p[2]+0<=31){ em=MI[p[1]]; ed=p[2]+0; r=rr } }
          else if(match(r,/^ +- +[0-9][0-9]?/)){
            seg=substr(r,1,RLENGTH); rr=substr(r,RLENGTH+1); c=substr(rr,1,1); sub(/^ +- +/,"",seg)
            if((c==","||c==")"||c=="") && seg+0>=1 && seg+0<=31){ ed=seg+0; r=rr } }
          if(match(r,/^,? +[0-9][0-9][0-9][0-9]([^0-9]|$)/)){
            t=substr(r,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); y=t+0 }
          else { y=ty; if(em*100+ed > tmd) y=ty-1 }
          return y*10000+em*100+ed
        }
        return 0 }
      function close_sec(){ if(sec && !(hist && nb==0)) { mv+=sb; cnt++ } sec=0; sb=0; hist=0; nb=0 }
      FNR==1{ close_sec(); flush(); f=FILENAME; mv=0; tot=0; cnt=0; cont=0; fence=0 }
      { tot += length($0)+1 }
      /^ *(```|~~~)/{ l=$0; sub(/^ +/,"",l); c=substr(l,1,1)
        if(!fence){ fence=1; fch=c } else if(c==fch) fence=0 }
      !fence && /^##? /{
        close_sec(); cont=0
        if($0 ~ /^## /){
          if($0 ~ /^## History[[:space:]]*$/){ sec=1; hist=1; skip=1 }
          else if(excl($0)){ }
          else { k=dkey($0); if(k>0){ if(k<cut+0) sec=1 } else cont=1 }
        }
      }
      !fence && /^### /{ if(cont){ close_sec(); if(!excl($0)){ k=dkey($0); if(k>0 && k<cut+0) sec=1 } } }
      sec{ sb += length($0)+1
        if(skip) skip=0; else if(hist && $0 ~ /[^[:space:]]/) nb++ }
      END{ close_sec(); flush() }
    ' "${files[@]}"
  done | sort -t"$TAB" -k1,1nr -k4,4 \
    | while IFS="$TAB" read -r mv tot cnt f; do
        jq -cn --arg p "$f" --argjson m "$mv" --argjson t "$tot" --argjson c "$cnt" \
          '{path:$p, movable_bytes:$m, total_bytes:$t, sections:$c}'
      done | emit_array
}

# Problems only. (a) [[Cold/...]] link in a warm note's `## Cold storage` section whose
# target file is missing; (b) Cold/ file without a parent: frontmatter key; (c) Cold/ file
# no warm note links to.
cold_integrity(){
  shopt -s nullglob
  local TAB lk cf tg
  TAB="$(printf '\t')"; lk="$(mktemp)"; cf="$(mktemp)"; tg="$(mktemp)"
  # Paths expanded now: locals are gone when a RETURN/EXIT trap fires after the function ends.
  trap "rm -f '$lk' '$cf' '$tg'" EXIT RETURN
  local warm=(People/*.md Programs/*.md Threads/*.md)
  if [ "${#warm[@]}" -gt 0 ]; then
    awk '
      FNR==1{ in_cs=0 }
      /^## /{ in_cs = ($0 ~ /^## Cold storage[[:space:]]*$/); next }
      /^# /{ in_cs=0 }
      in_cs{ s=$0
        while(match(s, /\[\[Cold\/[^]|#]*/)){
          printf "%s\t%s\n", FILENAME, substr(s, RSTART+2, RLENGTH-2)
          s=substr(s, RSTART+RLENGTH) } }
    ' "${warm[@]}" > "$lk"
  fi
  find Cold -type f -name '*.md' 2>/dev/null | sort > "$cf"
  # Targets to a file: `cut | grep -q` SIGPIPEs under pipefail once the list passes the pipe buffer.
  cut -d"$TAB" -f2 "$lk" > "$tg"
  {
    while IFS="$TAB" read -r note tgt; do
      [ -f "$tgt.md" ] || jq -cn --arg p "$note" --arg t "$tgt" '{path:$p, problem:("link target missing: " + $t)}'
    done < "$lk"
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      awk 'BEGIN{fm=0} /^---[[:space:]]*$/{fm++; if(fm>=2) exit; next} fm==1 && /^parent:[[:space:]]*[^[:space:]]/{ok=1} END{exit !ok}' "$c" \
        || jq -cn --arg p "$c" '{path:$p, problem:"no parent: frontmatter key"}'
      grep -Fxq -- "${c%.md}" "$tg" \
        || jq -cn --arg p "$c" '{path:$p, problem:"no warm note links to this file"}'
    done < "$cf"
  } | awk '!seen[$0]++' | emit_array
}

jq -n \
  --argjson week_volume "$(week_volume)" \
  --argjson stale_people "$(stale_people)" \
  --argjson orphan_programs "$(orphan_programs)" \
  --argjson stuck_items "$(stuck_items)" \
  --argjson missing_links "$(missing_links)" \
  --argjson empty_stubs "$(empty_stubs)" \
  --argjson frontmatter_gaps "$(frontmatter_gaps)" \
  --argjson oversized_notes "$(oversized_notes)" \
  --argjson team_vocabulary "$(team_vocabulary)" \
  --argjson recurring_tags "$(recurring_tags)" \
  --argjson cold_candidates "$(cold_candidates)" \
  --argjson cold_integrity "$(cold_integrity)" \
  '{stale_people:$stale_people, orphan_programs:$orphan_programs, stuck_items:$stuck_items, missing_links:$missing_links, empty_stubs:$empty_stubs, frontmatter_gaps:$frontmatter_gaps, oversized_notes:$oversized_notes, team_vocabulary:$team_vocabulary, recurring_tags:$recurring_tags, week_volume:$week_volume, cold_candidates:$cold_candidates, cold_integrity:$cold_integrity}'
