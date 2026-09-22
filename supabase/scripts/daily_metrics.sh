#!/usr/bin/env bash
#
# Yesterday's marketing numbers, in the order the sheet's columns are in, ready to paste.
#
# The same counts the 09:00 cron job would push — signups, trials started, subscriptions renewed,
# and that last one split into its ₹499 and ₹299 halves — but printed here instead of posted, for
# as long as the Apps Script half is not up. The two halves need not sum to the total: a payment
# with no subscription row behind it counts in the total and in neither half.
#
# It calls `public.daily_marketing_metrics` rather than re-deriving the counts, so this and the
# automatic push can never drift apart: change the definition once, in the migration, and both
# follow.
#
# Runs one read-only query against the linked project through the Management API, so it needs the
# CLI logged in and linked — the same `supabase login` / `supabase link` that `db push` uses.
# Nothing here writes, to the database or to the sheet.
#
# Usage:
#   ./daily_metrics.sh                          # yesterday
#   ./daily_metrics.sh 2026-09-20               # one particular day
#   ./daily_metrics.sh 2026-09-15 2026-09-21    # an inclusive range, oldest first
#
# Flags:
#   --copy    put the rows on the clipboard instead of explaining them
#   --tsv     bare tab-separated rows, no header, no chatter — safe to pipe
#   --csv     comma-separated, with a header row
#
# Paste into the sheet by selecting the cell under `Date` and hitting paste: a tab-separated row
# spreads across the six columns on its own, and a range pastes as that many rows.
#
# "Yesterday" is a calendar day in Asia/Kolkata and is worked out by the database, not by this
# machine — so a laptop on the wrong timezone, or on a plane, still gets the day the numbers
# will be quoted as. Every count is bounded the same way, which is why a signup at 11pm IST on
# the 21st belongs to the 21st and not to the 22nd.
#
# Re-running for a day you already pasted is fine: the query only reads. The numbers for a very
# recent day can still move — Cashfree's recurring batches and their webhook retries settle
# overnight, and the hourly reconcile revises renewals upward — which is why the automatic push
# waits until 09:00 rather than running at midnight. Asking before about 6am IST is asking early.

set -euo pipefail

FORMAT=table
COPY=no
FROM=
TO=

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --copy) COPY=yes; shift ;;
    --tsv)  FORMAT=tsv; shift ;;
    --csv)  FORMAT=csv; shift ;;
    -h|--help|help) usage 0 ;;
    -*) die "unknown flag '$1'. Try: --copy, --tsv, --csv" ;;
    *)
      if   [ -z "$FROM" ]; then FROM="$1"
      elif [ -z "$TO"   ]; then TO="$1"
      else die "at most two dates, got a third: '$1'"
      fi
      shift ;;
  esac
done

# Both dates land inside SQL below, so neither may be anything but a plain ISO date. The database
# still has to agree it is a real one — 2026-02-31 matches this and is caught there.
for d in "$FROM" "$TO"; do
  [ -z "$d" ] || printf '%s' "$d" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
    || die "dates must look like 2026-09-21, got '$d'"
done

if [ -n "$FROM" ] && [ -n "$TO" ] && [ "$FROM" \> "$TO" ]; then
  die "the range runs backwards: $FROM is after $TO"
fi

command -v supabase >/dev/null 2>&1 || die "the supabase CLI is not on PATH"
command -v jq        >/dev/null 2>&1 || die "jq is not on PATH"

# No argument means yesterday IST, computed by the database for the reason in the header. One date
# means that day alone. `generate_series` covers all three cases, so there is only one query.
if [ -z "$FROM" ]; then
  FIRST="(now() at time zone 'Asia/Kolkata')::date - 1"
  LAST="$FIRST"
  WHEN="yesterday"
else
  FIRST="'$FROM'::date"
  LAST="${TO:+'$TO'::date}"
  LAST="${LAST:-$FIRST}"
  WHEN="${TO:+$FROM to $TO}"
  WHEN="${WHEN:-$FROM}"
fi

SQL="
select to_char(m.report_date, 'YYYY-MM-DD') as report_date,
       m.signups,
       m.trials,
       m.renewals,
       m.renewals_499,
       m.renewals_299
  from generate_series($FIRST, $LAST, interval '1 day') d
  cross join lateral public.daily_marketing_metrics(d::date) m
 order by m.report_date;
"

out="$(mktemp)"
trap 'rm -f "$out" "$out.err"' EXIT

# `--workdir` is what lets this be run from any directory — a bare `--linked` resolves the project
# ref by walking up from wherever you happen to be. The project directory is the repo root, two
# levels above this script.
WORKDIR="$(cd "$(dirname "$0")/../.." && pwd)"
REF="$(cat "$WORKDIR/supabase/.temp/project-ref" 2>/dev/null || echo '<ref>')"

# `--output-format json` is not optional: left to itself the CLI draws an ASCII table for a person
# and emits JSON only when it thinks it is talking to an agent, so a script that does not ask would
# work for whoever wrote it and break for everyone else. Progress chatter goes to stderr, while a
# failure is reported on *stdout*, which is why the message is read back out of the rows file.
supabase --workdir "$WORKDIR" --output-format json db query --linked "$SQL" > "$out" 2>"$out.err" || {
  { jq -re '.error.message' < "$out" 2>/dev/null || cat "$out" "$out.err"; } | sed 's/^/  /' >&2
  die "the query did not run. If that says you are not linked or not logged in: supabase login, then supabase link --project-ref $REF"
}

rows="$(jq -c 'if type == "array" then . else .rows end' < "$out" 2>/dev/null)" || rows=
[ -n "$rows" ] && [ "$rows" != "null" ] || {
  sed 's/^/  /' "$out" | head -5 >&2
  die "could not read the CLI's answer as rows. Check 'supabase --output-format json db query' by hand."
}
n="$(printf '%s' "$rows" | jq 'length')"
[ "$n" -gt 0 ] || die "no rows came back for $WHEN, which should not happen — the query returns one row per day asked for."

tsv() { printf '%s' "$rows" | jq -r '.[] | [.report_date,.signups,.trials,.renewals,.renewals_499,.renewals_299] | @tsv'; }

if [ "$COPY" = yes ]; then
  command -v pbcopy >/dev/null 2>&1 || die "--copy needs pbcopy, which is macOS only. Use --tsv and pipe it yourself."
  tsv | pbcopy
  printf '\033[32m✓\033[0m %s row(s) for %s on the clipboard. Click the cell under \033[1mDate\033[0m and paste.\n' "$n" "$WHEN"
  exit 0
fi

case "$FORMAT" in
  tsv) tsv ;;
  csv)
    printf '%s' "$rows" | jq -r '
      (["Date","Signups","Trials","Subscription Renewed","Renewed 499","Renewed 299"] | @csv),
      (.[] | [.report_date,.signups,.trials,.renewals,.renewals_499,.renewals_299] | @csv)'
    ;;
  table)
    {
      printf 'Date\tSignups\tTrials\tSubscription Renewed\tRenewed 499\tRenewed 299\n'
      tsv
    } | column -t -s $'\t'
    printf '\n\033[2mPaste-ready:\033[0m\n'
    tsv
    printf '\n\033[2m--copy puts those rows straight on the clipboard.\033[0m\n'
    ;;
esac
