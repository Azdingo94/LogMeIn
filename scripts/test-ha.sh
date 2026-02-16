#!/bin/bash
# ============================================
# LogMeIn - High Availability Test Script
# Tests failover, recovery, and resilience
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
STACK_NAME=${1:-logmein}
MANAGER_IP="192.168.56.10"

log() { echo -e "${BLUE}[TEST]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "============================================"
echo "  LogMeIn - High Availability Tests"
echo "============================================"
echo ""

# ============================================
# Test 1: Verify Swarm cluster health
# ============================================
log "Test 1: Swarm cluster health"
NODE_COUNT=$(docker node ls --format "{{.Status}}" | grep -c "Ready")
if [ "$NODE_COUNT" -ge 3 ]; then
    pass "Swarm cluster has $NODE_COUNT ready nodes (expected >= 3)"
else
    fail "Swarm cluster has only $NODE_COUNT ready nodes (expected >= 3)"
fi

# ============================================
# Test 2: Verify all services are running
# ============================================
log "Test 2: Service status"
SERVICES=$(docker stack services ${STACK_NAME} --format "{{.Name}} {{.Replicas}}")
ALL_OK=true
while IFS= read -r line; do
    SERVICE_NAME=$(echo "$line" | awk '{print $1}')
    REPLICAS=$(echo "$line" | awk '{print $2}')
    CURRENT=$(echo "$REPLICAS" | cut -d'/' -f1)
    TARGET=$(echo "$REPLICAS" | cut -d'/' -f2)
    if [ "$CURRENT" = "$TARGET" ]; then
        pass "Service $SERVICE_NAME: $REPLICAS"
    else
        fail "Service $SERVICE_NAME: $REPLICAS (not all replicas ready)"
        ALL_OK=false
    fi
done <<< "$SERVICES"

# ============================================
# Test 3: Health endpoint accessibility
# ============================================
log "Test 3: Health endpoint"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${MANAGER_IP}/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    pass "Health endpoint returns 200 OK"
else
    fail "Health endpoint returns $HTTP_CODE (expected 200)"
fi

# ============================================
# Test 4: API functionality
# ============================================
log "Test 4: API - Add a log entry"
RESPONSE=$(curl -s -X POST http://${MANAGER_IP}/logs \
    -H "Content-Type: application/json" \
    -d '{"level":"info","message":"HA test log","service":"ha-test"}' 2>/dev/null || echo '{"error":"connection failed"}')

if echo "$RESPONSE" | grep -q '"success": true\|"success":true'; then
    pass "POST /logs successful"
else
    fail "POST /logs failed: $RESPONSE"
fi

# ============================================
# Test 5: Simulate backend container failure
# ============================================
log "Test 5: Backend container failure & recovery"
BACKEND_TASK=$(docker service ps ${STACK_NAME}_backend --format "{{.ID}}" --filter "desired-state=running" | head -1)

if [ -n "$BACKEND_TASK" ]; then
    log "Killing backend task: $BACKEND_TASK"
    docker kill $(docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' $BACKEND_TASK) 2>/dev/null || true

    log "Waiting 30s for Swarm to recover..."
    sleep 30

    # Check if service recovered
    RUNNING=$(docker service ls --filter "name=${STACK_NAME}_backend" --format "{{.Replicas}}")
    CURRENT=$(echo "$RUNNING" | cut -d'/' -f1)
    TARGET=$(echo "$RUNNING" | cut -d'/' -f2)

    if [ "$CURRENT" = "$TARGET" ]; then
        pass "Backend service recovered after container kill ($RUNNING)"
    else
        fail "Backend service did not fully recover ($RUNNING)"
    fi
else
    warn "Could not find backend task to kill"
fi

# ============================================
# Test 6: Check service distribution across nodes
# ============================================
log "Test 6: Service distribution across nodes"
NODES_USED=$(docker service ps ${STACK_NAME}_backend --format "{{.Node}}" --filter "desired-state=running" | sort -u | wc -l)
if [ "$NODES_USED" -ge 2 ]; then
    pass "Backend replicas distributed across $NODES_USED nodes"
else
    warn "Backend replicas only on $NODES_USED node(s) - consider adding more replicas"
fi

# ============================================
# Test 7: Rolling update test
# ============================================
log "Test 7: Rolling update (scale up then down)"
docker service scale ${STACK_NAME}_backend=4 --detach 2>/dev/null
sleep 15

RUNNING=$(docker service ls --filter "name=${STACK_NAME}_backend" --format "{{.Replicas}}")
log "After scale up: $RUNNING"

docker service scale ${STACK_NAME}_backend=3 --detach 2>/dev/null
sleep 10

RUNNING=$(docker service ls --filter "name=${STACK_NAME}_backend" --format "{{.Replicas}}")
if echo "$RUNNING" | grep -q "3/3"; then
    pass "Scaling up and down successful ($RUNNING)"
else
    warn "Scaling result: $RUNNING (may need more time)"
fi

# ============================================
# Test 8: Database persistence
# ============================================
log "Test 8: Database persistence after API test"
STATS=$(curl -s http://${MANAGER_IP}/stats 2>/dev/null)
if echo "$STATS" | grep -q '"total_logs"'; then
    TOTAL=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['total_logs'])" 2>/dev/null || echo "0")
    if [ "$TOTAL" -gt 0 ]; then
        pass "Database has $TOTAL logs (data persisted)"
    else
        warn "Database is empty (0 logs)"
    fi
else
    fail "Could not retrieve stats from API"
fi

# ============================================
# Results Summary
# ============================================
echo ""
echo "============================================"
echo "  Test Results"
echo "============================================"
echo -e "  ${GREEN}PASSED: $PASS${NC}"
echo -e "  ${RED}FAILED: $FAIL${NC}"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
