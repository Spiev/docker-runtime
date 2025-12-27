#!/bin/bash
# Fail2ban Status Overview
# Shows status of all jails in a compact format
# Usage: ./fail2ban-status.sh [--verbose]

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

VERBOSE=false
if [[ "$1" == "--verbose" || "$1" == "-v" ]]; then
    VERBOSE=true
fi

# Check if fail2ban is running
if ! systemctl is-active --quiet fail2ban; then
    echo -e "${RED}✗ fail2ban is not running${NC}"
    exit 1
fi

# Header
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}  Fail2ban Status Overview${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get list of all jails
JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' '\n' | sed 's/^[ \t]*//' | grep -v '^$')

if [ -z "$JAILS" ]; then
    echo -e "${YELLOW}No jails configured${NC}"
    exit 0
fi

# Track totals
TOTAL_JAILS=0
TOTAL_BANNED=0
TOTAL_FAILED=0

# Function to get jail info
get_jail_info() {
    local jail=$1
    local status=$(sudo fail2ban-client status "$jail" 2>/dev/null)

    local currently_failed=$(echo "$status" | grep "Currently failed:" | awk '{print $4}')
    local currently_banned=$(echo "$status" | grep "Currently banned:" | awk '{print $4}')
    local total_failed=$(echo "$status" | grep "Total failed:" | awk '{print $4}')
    local total_banned=$(echo "$status" | grep "Total banned:" | awk '{print $4}')

    # Default to 0 if empty
    currently_failed=${currently_failed:-0}
    currently_banned=${currently_banned:-0}
    total_failed=${total_failed:-0}
    total_banned=${total_banned:-0}

    echo "$currently_banned|$currently_failed|$total_banned|$total_failed"
}

# Print table header
printf "%-25s %8s %8s %10s %10s\n" "JAIL" "BANNED" "FAILED" "TOTAL BAN" "TOTAL FAIL"
echo "─────────────────────────────────────────────────────────────────"

# Process each jail
while IFS= read -r jail; do
    [ -z "$jail" ] && continue

    TOTAL_JAILS=$((TOTAL_JAILS + 1))

    INFO=$(get_jail_info "$jail")
    IFS='|' read -r curr_banned curr_failed tot_banned tot_failed <<< "$INFO"

    TOTAL_BANNED=$((TOTAL_BANNED + curr_banned))
    TOTAL_FAILED=$((TOTAL_FAILED + curr_failed))

    # Color code based on activity
    if [ "$curr_banned" -gt 0 ]; then
        COLOR=$RED
        SYMBOL="⚠"
    elif [ "$curr_failed" -gt 0 ]; then
        COLOR=$YELLOW
        SYMBOL="●"
    else
        COLOR=$GREEN
        SYMBOL="✓"
    fi

    printf "${COLOR}%-2s${NC} %-22s %8s %8s %10s %10s\n" \
        "$SYMBOL" "$jail" "$curr_banned" "$curr_failed" "$tot_banned" "$tot_failed"

    # Show banned IPs in verbose mode
    if $VERBOSE && [ "$curr_banned" -gt 0 ]; then
        BANNED_IPS=$(sudo fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list:" | sed 's/.*Banned IP list://')
        if [ -n "$BANNED_IPS" ]; then
            echo "   └─ Banned IPs:$BANNED_IPS"
        fi
    fi
done <<< "$JAILS"

# Summary line
echo "─────────────────────────────────────────────────────────────────"
printf "${BOLD}%-25s %8s %8s${NC}\n" "TOTAL ($TOTAL_JAILS jails)" "$TOTAL_BANNED" "$TOTAL_FAILED"

echo ""

# Status indicator
if [ "$TOTAL_BANNED" -gt 0 ]; then
    echo -e "${RED}⚠ $TOTAL_BANNED IP(s) currently banned${NC}"
elif [ "$TOTAL_FAILED" -gt 0 ]; then
    echo -e "${YELLOW}● $TOTAL_FAILED failed attempt(s) detected${NC}"
else
    echo -e "${GREEN}✓ All quiet - no suspicious activity${NC}"
fi

# Recent bans (last 5)
if $VERBOSE; then
    echo ""
    echo -e "${BOLD}Recent ban activity (last 5):${NC}"
    sudo grep "Ban " /var/log/fail2ban.log 2>/dev/null | tail -n 5 | sed 's/^/  /' || echo "  No recent bans"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Exit code based on banned IPs
if [ "$TOTAL_BANNED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
