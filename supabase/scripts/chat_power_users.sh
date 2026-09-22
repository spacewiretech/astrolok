#!/usr/bin/env bash
#
# Who talks to Astro the most? Lists the user ids with more than N turns in `chat_messages`.
#
# Runs one read-only aggregate against the linked project through the Management API, so it
# needs the CLI logged in and linked — the same `supabase login` / `supabase link` that
# `db push` uses. Nothing here writes.
#
# Usage:
#   ./chat_power_users.sh [min] [flags]
#
# Flags:
#   --count user|astro|any|threads   What "chats" means. Default: user
#   --days N                         Only count turns from the last N days. Default: all time
#   --ids                            Print bare user ids, one per line — nothing else
#   --csv                            Comma-separated, with a header row
#
# Examples:
#   ./chat_power_users.sh                      # over 50 questions asked, all time, as a table
#   ./chat_power_users.sh 100 --ids            # ids of everyone past 100 questions
#   ./chat_power_users.sh 20 --days 30         # over 20 questions in the last month
#   ./chat_power_users.sh 10 --count threads   # over 10 separate conversations
#
# `--count user` is the default because a user turn is what the product meters: the daily
# allowance in `chat_messages_per_day` counts `role='user'` rows, so "50 chats" read this way
# means 50 questions asked, not 25 exchanges. `any` counts both sides, `astro` the replies.
#
# One caveat on any all-time number: `purge_expired` deletes chat turns over a year old, so
# this counts what is still on disk, not what an account has ever sent.

set -euo pipefail

MIN=50
COUNT=user
DAYS=
FORMAT=table

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '3,29p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --count) [ $# -ge 2 ] || die "--count needs a value"; COUNT="$2"; shift 2 ;;
    --days)  [ $# -ge 2 ] || die "--days needs a value";  DAYS="$2";  shift 2 ;;
    --ids)   FORMAT=ids; shift ;;
    --csv)   FORMAT=csv; shift ;;
    -h|--help|help) usage 0 ;;
    -*) die "unknown flag '$1'. Try: --count, --days, --ids, --csv" ;;
    *)  MIN="$1"; shift ;;
  esac
done

# Both of these are interpolated into SQL below, so neither may be anything but digits.
printf '%s' "$MIN" | grep -Eq '^[0-9]+$' || die "min must be a whole number, got '$MIN'"
[ -z "$DAYS" ] || printf '%s' "$DAYS" | grep -Eq '^[1-9][0-9]*$' || die "--days must be a positive whole number, got '$DAYS'"

case "$COUNT" in
  user)    METRIC="count(*) filter (where role = 'user')"  ; LABEL="questions asked" ;;
  astro)   METRIC="count(*) filter (where role = 'astro')" ; LABEL="replies received" ;;
  any)     METRIC="count(*)"                               ; LABEL="turns either way" ;;
  threads) METRIC="count(distinct thread_id)"              ; LABEL="separate conversations" ;;
  *) die "--count must be one of: user, astro, any, threads" ;;
esac

WINDOW=""
WINDOW_NOTE="all time"
if [ -n "$DAYS" ]; then
  WINDOW="where created_at >= now() - interval '$DAYS days'"
  WINDOW_NOTE="last $DAYS days"
fi

command -v supabase >/dev/null 2>&1 || die "the supabase CLI is not on PATH"
command -v jq        >/dev/null 2>&1 || die "jq is not on PATH"

SQL="
select user_id::text                                as user_id,
       count(*) filter (where role = 'user')        as questions,
       count(*) filter (where role = 'astro')       as replies,
       count(*)                                     as turns,
       count(distinct thread_id)                    as threads,
       to_char(min(created_at) at time zone 'Asia/Kolkata', 'YYYY-MM-DD') as first_day,
       to_char(max(created_at) at time zone 'Asia/Kolkata', 'YYYY-MM-DD') as last_day
  from public.chat_messages
  $WINDOW
 group by user_id
having $METRIC > $MIN
 order by $METRIC desc, max(created_at) desc;
"

[ "$FORMAT" = "ids" ] || printf '\033[2m→ %s > %s, %s\033[0m\n' "$LABEL" "$MIN" "$WINDOW_NOTE" >&2

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

# `--workdir` is what lets this be run from any directory — a bare `--linked` resolves the project
# ref by walking up from wherever you happen to be, so without it the script only works from
# inside the repo. The project directory is the repo root, two levels above this script.
WORKDIR="$(cd "$(dirname "$0")/../.." && pwd)"
REF="$(cat "$WORKDIR/supabase/.temp/project-ref" 2>/dev/null || echo '<ref>')"

# `--output-format json` is not optional. Without it the CLI decides for itself: asked by a person
# at a terminal it draws an ASCII table, and only when it detects an agent does it emit JSON — so a
# script that leaves the choice to the CLI works for whoever wrote it and breaks for everyone else.
#
# Even asked for JSON the answer comes in two shapes, so both are accepted below: a bare array of
# rows, or {"rows": [...]} wrapped in a boundary warning about untrusted content. Either way every
# column is a uuid, an integer or a formatted date.
#
# The two streams stay apart: progress chatter ("Initialising login role...") goes to stderr and
# would break the parse, while a failure is reported on *stdout* as {"_tag":"Error",...} — so the
# message below is read back out of the same file the rows would have been in.
supabase --workdir "$WORKDIR" --output-format json db query --linked "$SQL" > "$out" 2>"$out.err" || {
  { jq -re '.error.message' < "$out" 2>/dev/null || cat "$out" "$out.err"; } | sed 's/^/  /' >&2
  rm -f "$out.err"
  die "the query did not run. If that says you are not linked or not logged in: supabase login, then supabase link --project-ref $REF"
}
rm -f "$out.err"

rows="$(jq -c 'if type == "array" then . else .rows end' < "$out" 2>/dev/null)" || rows=
[ -n "$rows" ] && [ "$rows" != "null" ] || {
  sed 's/^/  /' "$out" | head -5 >&2
  die "could not read the CLI's answer as rows. Check 'supabase --output-format json db query' by hand."
}
n="$(printf '%s' "$rows" | jq 'length')"

case "$FORMAT" in
  ids)
    printf '%s' "$rows" | jq -r '.[].user_id'
    ;;
  csv)
    printf '%s' "$rows" | jq -r '
      (["user_id","questions","replies","turns","threads","first_day","last_day"] | @csv),
      (.[] | [.user_id,.questions,.replies,.turns,.threads,.first_day,.last_day] | @csv)'
    ;;
  table)
    if [ "$n" -eq 0 ]; then
      printf 'no account is past %s %s (%s).\n' "$MIN" "$LABEL" "$WINDOW_NOTE"
    else
      {
        printf 'user_id\tquestions\treplies\tturns\tthreads\tfirst\tlast\n'
        printf '%s' "$rows" | jq -r '.[] | [.user_id,.questions,.replies,.turns,.threads,.first_day,.last_day] | @tsv'
      } | column -t -s $'\t'
      printf '\n\033[2m%s account(s). Add --ids for a bare list, --csv to paste elsewhere.\033[0m\n' "$n"
    fi
    ;;
esac
