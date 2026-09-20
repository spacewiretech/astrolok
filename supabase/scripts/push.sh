#!/usr/bin/env bash
#
# Drive `notification-dispatch` by hand: send a test push, count who would get a campaign, or
# kick off a dispatch run without waiting for pg_cron.
#
# All three actions need the cron secret, which is `reconcile_secret` in the `app_config` table:
#
#   Supabase dashboard → SQL editor → select value from app_config where key = 'reconcile_secret';
#
# Export it once per shell (leading space keeps it out of your history):
#
#    export CRON_SECRET='…'
#
# Usage:
#   ./push.sh send <user_id> [campaign]    Send one push to one account. Default campaign: kundali_ready
#   ./push.sh dry [campaign]               How many people would get it right now? Sends nothing.
#   ./push.sh run                          Run the scheduled dispatch now (respects every flag and rule).
#
# Examples:
#   ./push.sh send d53877e5-33d0-4fad-bb13-45328e23ee3b
#   ./push.sh send d53877e5-33d0-4fad-bb13-45328e23ee3b winback_paid
#   ./push.sh dry                          # every scheduled campaign
#   ./push.sh dry dormant
#
# `send` ignores the campaign flags, quiet hours, the daily cap and eligibility — but the account
# still needs an authorized device on a live session at build >= notif_min_app_build, or you get
# back `no_token`. Copy and language are resolved for real, from that account.

set -euo pipefail

PROJECT_URL="${SUPABASE_URL:-https://qktgingrvecpetrofimy.supabase.co}"
ENDPOINT="$PROJECT_URL/functions/v1/notification-dispatch"

CAMPAIGNS="mid_cancel billing_issue kundali_ready kundali_ready_lapsed kundali_halfway \
kundali_not_opened palm_no_face reading_no_chat trial_no_reading paywall_abandoned \
onboarding_incomplete post_charge_no_return winback_paid dormant"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

[ $# -ge 1 ] || usage
[ -n "${CRON_SECRET:-}" ] || die "CRON_SECRET is not set. See the header of this script."

check_campaign() {
  case " $CAMPAIGNS " in
    *" $1 "*) ;;
    *) die "unknown campaign '$1'. One of:$(printf '\n  %s' $CAMPAIGNS)" ;;
  esac
}

post() {
  local body="$1" code
  local out; out="$(mktemp)"
  code="$(curl -sS -X POST "$ENDPOINT" \
    -H 'Content-Type: application/json' \
    -H "x-cron-secret: $CRON_SECRET" \
    -d "$body" \
    -w '%{http_code}' -o "$out")"

  if command -v jq >/dev/null 2>&1; then jq . < "$out" 2>/dev/null || cat "$out"; else cat "$out"; fi
  echo
  rm -f "$out"

  case "$code" in
    200|202) ;;
    403) die "403 — the cron secret is wrong. Check app_config.reconcile_secret." ;;
    *)   die "HTTP $code" ;;
  esac
}

case "$1" in
  send)
    [ $# -ge 2 ] || die "usage: $0 send <user_id> [campaign]"
    user_id="$2"
    campaign="${3:-kundali_ready}"
    printf '%s' "$user_id" | grep -Eqi '^[0-9a-f-]{36}$' || die "'$user_id' is not a uuid"
    check_campaign "$campaign"
    echo "→ sending '$campaign' to $user_id"
    post "$(printf '{"action":"send_test","user_id":"%s","campaign":"%s"}' "$user_id" "$campaign")"
    echo "status 'sent' means FCM accepted it. 'no_token' means that account has no eligible device."
    ;;

  dry)
    if [ $# -ge 2 ]; then
      check_campaign "$2"
      echo "→ counting candidates for '$2'"
      post "$(printf '{"action":"dry_run","campaign":"%s"}' "$2")"
    else
      echo "→ counting candidates for every scheduled campaign"
      post '{"action":"dry_run"}'
    fi
    echo "'inline' means the campaign is not cron-driven (mid_cancel, billing_issue)."
    ;;

  run)
    echo "→ running the scheduled dispatch now"
    post '{}'
    echo "202 accepted — it enqueues and sends in the background. Watch the function logs."
    ;;

  -h|--help|help) usage 0 ;;
  *) die "unknown action '$1'. Try: send, dry, run" ;;
esac
