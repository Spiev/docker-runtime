#!/bin/bash
# Fail2ban Test Script
# Tests if fail2ban is actively monitoring and banning IPs

set -e

echo "=========================================="
echo "Fail2ban Configuration Test"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if fail2ban is running
echo -n "1. Checking if fail2ban is running... "
if systemctl is-active --quiet fail2ban; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo "Start with: sudo systemctl start fail2ban"
    exit 1
fi
echo ""

# Check jail status
echo "2. Active jails:"
sudo fail2ban-client status | grep "Jail list" | sed 's/.*Jail list://' | tr ',' '\n' | sed 's/^[ \t]*/   - /'
echo ""

# Test filters against logs
LOGFILE="/home/stefan/docker/proxy/nginx/logs/access.log"

if [ ! -f "$LOGFILE" ]; then
    echo -e "${RED}Error: Log file not found: $LOGFILE${NC}"
    exit 1
fi

echo "3. Testing filters against existing logs:"
echo ""

# Test auth-failed filter
echo "   Testing: nginx-auth-failed.conf"
MATCHES=$(sudo fail2ban-regex "$LOGFILE" /etc/fail2ban/filter.d/nginx-auth-failed.conf 2>/dev/null | grep "Total matched:" | awk '{print $3}')
if [ -n "$MATCHES" ] && [ "$MATCHES" -gt 0 ]; then
    echo -e "   ${GREEN}✓ $MATCHES matches found${NC}"
else
    echo -e "   ${YELLOW}⚠ No matches (no failed logins in logs)${NC}"
fi

# Test rate-limit filter
echo "   Testing: nginx-rate-limit-abuse.conf"
MATCHES=$(sudo fail2ban-regex "$LOGFILE" /etc/fail2ban/filter.d/nginx-rate-limit-abuse.conf 2>/dev/null | grep "Total matched:" | awk '{print $3}')
if [ -n "$MATCHES" ] && [ "$MATCHES" -gt 0 ]; then
    echo -e "   ${GREEN}✓ $MATCHES matches found${NC}"
else
    echo -e "   ${YELLOW}⚠ No matches (no rate limiting triggered)${NC}"
fi

# Test scanning filter
echo "   Testing: nginx-forbidden-scan.conf"
MATCHES=$(sudo fail2ban-regex "$LOGFILE" /etc/fail2ban/filter.d/nginx-forbidden-scan.conf 2>/dev/null | grep "Total matched:" | awk '{print $3}')
if [ -n "$MATCHES" ] && [ "$MATCHES" -gt 0 ]; then
    echo -e "   ${GREEN}✓ $MATCHES matches found${NC}"
else
    echo -e "   ${YELLOW}⚠ No matches (no scanning attempts in logs)${NC}"
fi
echo ""

# Check currently banned IPs
echo "4. Currently banned IPs:"
BANNED=$(sudo fail2ban-client banned 2>/dev/null)
if [ -n "$BANNED" ]; then
    echo "$BANNED" | while read ip; do
        echo "   - $ip"
    done
else
    echo -e "   ${YELLOW}No IPs currently banned${NC}"
fi
echo ""

# Show recent fail2ban activity
echo "5. Recent fail2ban activity (last 10 lines):"
sudo tail -n 10 /var/log/fail2ban.log | sed 's/^/   /'
echo ""

# Summary
echo "=========================================="
echo "Test completed!"
echo ""
echo "To manually test fail2ban:"
echo "1. Try wrong password 5+ times on one of your services"
echo "2. Check: sudo fail2ban-client status immich-auth"
echo "3. Your IP should appear in 'Currently banned'"
echo ""
echo "To unban yourself:"
echo "sudo fail2ban-client unban YOUR_IP"
echo "=========================================="
