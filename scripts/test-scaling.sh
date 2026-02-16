#!/bin/bash
# ============================================
# LogMeIn - Scaling & Load Test Script
# Tests horizontal scaling capabilities
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

STACK_NAME=${1:-logmein}
MANAGER_IP="192.168.56.10"

log() { echo -e "${BLUE}[SCALE]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }

echo ""
echo "============================================"
echo "  LogMeIn - Scaling Tests"
echo "============================================"
echo ""

# ============================================
# Current state
# ============================================
log "Current service status:"
docker stack services ${STACK_NAME}
echo ""

# ============================================
# Scale backend to 5 replicas
# ============================================
log "Scaling backend to 5 replicas..."
docker service scale ${STACK_NAME}_backend=5

log "Waiting 20s for scaling to complete..."
sleep 20

docker service ps ${STACK_NAME}_backend --filter "desired-state=running"
pass "Backend scaled to 5 replicas"

# ============================================
# Load test with concurrent requests
# ============================================
log "Running load test (50 concurrent requests)..."
for i in $(seq 1 50); do
    curl -s -X POST http://${MANAGER_IP}/logs \
        -H "Content-Type: application/json" \
        -d "{\"level\":\"info\",\"message\":\"Load test #$i\",\"service\":\"load-test\"}" \
        -o /dev/null &
done
wait
pass "50 concurrent log entries sent"

# Check results
sleep 5
STATS=$(curl -s http://${MANAGER_IP}/stats 2>/dev/null)
log "Stats after load test: $STATS"

# ============================================
# Scale frontend to 3 replicas
# ============================================
log "Scaling frontend to 3 replicas..."
docker service scale ${STACK_NAME}_frontend=3
sleep 15
pass "Frontend scaled to 3 replicas"

# ============================================
# Scale back to normal
# ============================================
log "Scaling back to default (backend=3, frontend=2)..."
docker service scale ${STACK_NAME}_backend=3 ${STACK_NAME}_frontend=2
sleep 15
pass "Services scaled back to default"

# ============================================
# Final status
# ============================================
echo ""
log "Final service status:"
docker stack services ${STACK_NAME}
echo ""
log "Scaling tests completed!"
