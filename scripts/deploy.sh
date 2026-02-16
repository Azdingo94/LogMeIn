#!/bin/bash
# ============================================
# LogMeIn - Deployment Script
# Deploy the application stack to Docker Swarm
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

STACK_NAME=${1:-logmein}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE=${2:-${PROJECT_ROOT}/docker-stack.yml}

# ============================================
# Pre-deployment checks
# ============================================
log "Starting deployment of stack: ${STACK_NAME}"

# Check if we're on a Swarm manager
if ! docker node ls > /dev/null 2>&1; then
    error "This node is not a Swarm manager. Run this script on the manager node."
fi

log "Swarm cluster status:"
docker node ls

# ============================================
# Create secrets if they don't exist
# ============================================
log "Checking Docker secrets..."
if ! docker secret inspect db_password > /dev/null 2>&1; then
    log "Creating db_password secret..."
    echo "logs_password" | docker secret create db_password -
    log "Secret created."
else
    log "Secret db_password already exists."
fi

# ============================================
# Build and tag images (if building locally)
# ============================================
if [ "${BUILD_LOCAL:-false}" = "true" ]; then
    log "Building Docker images locally..."
    export GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-logmein}
    export TAG=${TAG:-latest}
    docker build -t ghcr.io/${GITHUB_REPOSITORY}/backend:${TAG} ${PROJECT_ROOT}/backend/
    docker build -t ghcr.io/${GITHUB_REPOSITORY}/frontend:${TAG} ${PROJECT_ROOT}/frontend/
    log "Images built and tagged for: ghcr.io/${GITHUB_REPOSITORY}"
fi

# ============================================
# Deploy the stack
# ============================================
log "Deploying stack ${STACK_NAME}..."
docker stack deploy -c ${COMPOSE_FILE} ${STACK_NAME}

# ============================================
# Wait for services to be ready
# ============================================
log "Waiting for services to start..."
sleep 10

MAX_RETRIES=30
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    RUNNING=$(docker service ls --filter "name=${STACK_NAME}" --format "{{.Replicas}}" | grep -c "0/" || true)
    if [ "$RUNNING" -eq 0 ]; then
        log "All services are running!"
        break
    fi
    RETRY=$((RETRY + 1))
    echo -ne "${BLUE}[DEPLOY]${NC} Waiting for services... ($RETRY/$MAX_RETRIES)\r"
    sleep 5
done

if [ $RETRY -ge $MAX_RETRIES ]; then
    warn "Some services may not have started correctly."
fi

# ============================================
# Display deployment status
# ============================================
echo ""
log "========================================="
log "Deployment Status"
log "========================================="
docker stack services ${STACK_NAME}
echo ""
log "Stack ${STACK_NAME} deployed successfully!"
log "Frontend: http://192.168.56.10"
log "Backend API: http://192.168.56.10:5000"
log "Health check: http://192.168.56.10/health"
