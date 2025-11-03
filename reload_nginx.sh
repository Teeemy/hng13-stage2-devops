#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect docker compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo -e "${RED}Error: Neither 'docker-compose' nor 'docker compose' found${NC}"
    exit 1
fi

echo -e "${GREEN}Starting Nginx configuration reload...${NC}"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Load environment variables from .env
echo -e "${YELLOW}Loading environment variables from .env...${NC}"
export $(cat .env | grep -v '^#' | xargs)

# Validate ACTIVE_POOL is set
if [ -z "$ACTIVE_POOL" ]; then
    echo -e "${RED}Error: ACTIVE_POOL not set in .env${NC}"
    exit 1
fi

echo -e "${GREEN}Active pool: ${ACTIVE_POOL}${NC}"

# Check if Nginx container is running
echo -e "${YELLOW}Checking if Nginx container is running...${NC}"
if ! $DOCKER_COMPOSE ps nginx | grep -q "Up"; then
    echo -e "${YELLOW}Nginx container is not running. Starting services...${NC}"
    $DOCKER_COMPOSE up -d
    
    echo -e "${YELLOW}Waiting for services to be healthy...${NC}"
    sleep 10
    
    if $DOCKER_COMPOSE ps nginx | grep -q "Up"; then
        echo -e "${GREEN}✓ Services started successfully${NC}"
        echo -e "${GREEN}✓ Active pool is now: ${ACTIVE_POOL}${NC}"
    else
        echo -e "${RED}✗ Failed to start services${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Reloading Nginx...${NC}"
    $DOCKER_COMPOSE exec nginx nginx -s reload
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Nginx reloaded successfully${NC}"
        echo -e "${GREEN}✓ Active pool is now: ${ACTIVE_POOL}${NC}"
    else
        echo -e "${RED}✗ Failed to reload Nginx${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Reload complete!${NC}\n"

# Optional: Run failover test
if [ "$1" == "--test" ] || [ "$1" == "-t" ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running Failover Test${NC}"
    echo -e "${BLUE}========================================${NC}\n"
    
    NGINX_URL="http://localhost:${NGINX_PORT:-8080}"
    BLUE_URL="http://localhost:${BLUE_PORT:-8081}"
    GREEN_URL="http://localhost:${GREEN_PORT:-8082}"
    NUM_INITIAL_CHECKS=5
    NUM_POST_CHAOS_CHECKS=10
    SLEEP_BETWEEN_CHECKS=0.5
    
    # Function to check pool
    check_pool() {
        local url=$1
        local response=$(curl -s -i "$url/version" 2>/dev/null)
        local status=$(echo "$response" | grep "HTTP" | awk '{print $2}')
        local pool=$(echo "$response" | grep -i "X-App-Pool:" | awk '{print $2}' | tr -d '\r\n ')
        echo "$status|$pool"
    }
    
    # Step 1: Verify active pool
    echo -e "${YELLOW}Step 1: Verifying ${ACTIVE_POOL} pool is active...${NC}"
    success_count=0
    
    for i in $(seq 1 $NUM_INITIAL_CHECKS); do
        result=$(check_pool "$NGINX_URL")
        status=$(echo "$result" | cut -d'|' -f1)
        pool=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$status" != "200" ]; then
            echo -e "${RED}✗ Request $i failed with status $status${NC}"
            exit 1
        fi
        
        if [ "$pool" != "$ACTIVE_POOL" ]; then
            echo -e "${RED}✗ Expected X-App-Pool: ${ACTIVE_POOL}, got: $pool${NC}"
            exit 1
        fi
        
        success_count=$((success_count + 1))
        echo -e "${GREEN}✓ Request $i: Status $status, Pool: $pool${NC}"
        sleep $SLEEP_BETWEEN_CHECKS
    done
    
    echo -e "${GREEN}✓ ${ACTIVE_POOL} pool verified ($success_count/$NUM_INITIAL_CHECKS successful)${NC}\n"
    
    # Step 2: Trigger chaos on active pool
    echo -e "${YELLOW}Step 2: Triggering chaos on ${ACTIVE_POOL} pool...${NC}"
    if [ "$ACTIVE_POOL" == "blue" ]; then
        CHAOS_URL="$BLUE_URL"
        BACKUP_POOL="green"
    else
        CHAOS_URL="$GREEN_URL"
        BACKUP_POOL="blue"
    fi
    
    chaos_response=$(curl -s -w "\n%{http_code}" -X POST "$CHAOS_URL/chaos/start?mode=error" 2>/dev/null)
    chaos_status=$(echo "$chaos_response" | tail -n 1)
    
    if [ "$chaos_status" != "200" ]; then
        echo -e "${RED}✗ Failed to trigger chaos. Status: $chaos_status${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Chaos triggered on ${ACTIVE_POOL} pool${NC}\n"
    
    # Wait for failover
    echo -e "${YELLOW}Waiting for failover to occur...${NC}"
    sleep 2
    
    # Step 3: Verify failover to backup pool
    echo -e "${YELLOW}Step 3: Verifying failover to ${BACKUP_POOL} pool...${NC}"
    backup_count=0
    failover_detected=false
    
    for i in $(seq 1 $NUM_POST_CHAOS_CHECKS); do
        result=$(check_pool "$NGINX_URL")
        status=$(echo "$result" | cut -d'|' -f1)
        pool=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$status" != "200" ]; then
            echo -e "${RED}✗ Request $i failed with status $status${NC}"
            exit 1
        fi
        
        if [ "$pool" == "$BACKUP_POOL" ]; then
            backup_count=$((backup_count + 1))
            failover_detected=true
            echo -e "${GREEN}✓ Request $i: Status $status, Pool: $pool (FAILOVER)${NC}"
        else
            echo -e "${YELLOW}⚠ Request $i: Status $status, Pool: $pool (still on ${ACTIVE_POOL})${NC}"
        fi
        
        sleep $SLEEP_BETWEEN_CHECKS
    done
    
    echo ""
    
    # Validate results
    if [ "$failover_detected" == false ]; then
        echo -e "${RED}✗ FAIL: Failover to ${BACKUP_POOL} pool did not occur${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}✓ SUCCESS: Failover test passed!${NC}"
    echo -e "${GREEN}  - ${ACTIVE_POOL} pool verified initially${NC}"
    echo -e "${GREEN}  - Chaos triggered successfully${NC}"
    echo -e "${GREEN}  - Traffic failed over to ${BACKUP_POOL} ($backup_count/$NUM_POST_CHAOS_CHECKS requests)${NC}"
    echo -e "${GREEN}  - All requests returned 200 status${NC}"
    echo -e "${BLUE}========================================${NC}"
fi
