#!/bin/bash
# Fail2ban Login Banner
# Compact status display for SSH login
# Add to ~/.bashrc or /etc/profile.d/

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Only run if fail2ban is active
if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
    return 0 2>/dev/null || exit 0
fi

# Get jail list
JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*Jail list://' | tr ',' '\n' | sed 's/^[ \t]*//' | grep -v '^$')

if [ -z "$JAILS" ]; then
    return 0 2>/dev/null || exit 0
fi

# Count totals
TOTAL_BANNED=0
TOTAL_FAILED=0
JAILS_WITH_BANS=""

while IFS= read -r jail; do
    [ -z "$jail" ] && continue

    STATUS=$(sudo fail2ban-client status "$jail" 2>/dev/null)
    BANNED=$(echo "$STATUS" | grep "Currently banned:" | awk '{print $NF}')
    FAILED=$(echo "$STATUS" | grep "Currently failed:" | awk '{print $NF}')

    # Validate numeric values
    BANNED=$(echo "$BANNED" | grep -E '^[0-9]+$' || echo "0")
    FAILED=$(echo "$FAILED" | grep -E '^[0-9]+$' || echo "0")

    TOTAL_BANNED=$((TOTAL_BANNED + BANNED))
    TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

    if [ "$BANNED" -gt 0 ]; then
        JAILS_WITH_BANS="$JAILS_WITH_BANS$jail($BANNED) "
    fi
done <<< "$JAILS"

# Only show if there's activity
if [ "$TOTAL_BANNED" -gt 0 ] || [ "$TOTAL_FAILED" -gt 0 ]; then
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Fail2ban Status${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"

    if [ "$TOTAL_BANNED" -gt 0 ]; then
        echo -e "  ${RED}⚠ ${TOTAL_BANNED} IP(s) currently banned${NC}"
        echo -e "  ${YELLOW}└─ Jails: ${JAILS_WITH_BANS}${NC}"
    fi

    if [ "$TOTAL_FAILED" -gt 0 ]; then
        echo -e "  ${YELLOW}● ${TOTAL_FAILED} failed attempt(s) detected${NC}"
    fi

    echo -e "  ${CYAN}Run:${NC} sudo fail2ban-status.sh --verbose"
    echo ""
fi
