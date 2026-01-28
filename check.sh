#!/bin/bash
# Comprehensive health check for PhiloAssets
# Run standalone or called from deploy-secure.sh

set -e

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

echo -e "${YELLOW}=== PhiloAssets Health Check ===${NC}"
echo ""

# ============================================
# 1. Environment Configuration
# ============================================
echo -e "${YELLOW}[1/4] Checking environment configuration...${NC}"

# Check .env exists
if [ ! -f .env ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ .env file exists${NC}"

# Check required variables
ASSETS_DIR=$(sed -n 's/^ASSETS_DIR=//p' .env)
ENV_UID=$(sed -n 's/^UID=//p' .env)
ENV_GID=$(sed -n 's/^GID=//p' .env)
SECRET=$(sed -n 's/^ASSETS_SIGNING_SECRET=//p' .env)

if [ -z "$ASSETS_DIR" ] || [ "$ASSETS_DIR" = "/absolute/path/to/assets" ]; then
    echo -e "${RED}✗ ASSETS_DIR not configured${NC}"
    FAILED=1
else
    echo -e "${GREEN}✓ ASSETS_DIR=${ASSETS_DIR}${NC}"
fi

if [ -z "$ENV_UID" ] || [ "$ENV_UID" = "YOUR_UID" ]; then
    echo -e "${RED}✗ UID not configured${NC}"
    FAILED=1
else
    echo -e "${GREEN}✓ UID=${ENV_UID}${NC}"
fi

if [ -z "$ENV_GID" ] || [ "$ENV_GID" = "YOUR_GID" ]; then
    echo -e "${RED}✗ GID not configured${NC}"
    FAILED=1
else
    echo -e "${GREEN}✓ GID=${ENV_GID}${NC}"
fi

if [ -z "$SECRET" ]; then
    echo -e "${RED}✗ ASSETS_SIGNING_SECRET not configured${NC}"
    FAILED=1
else
    echo -e "${GREEN}✓ ASSETS_SIGNING_SECRET is set (${#SECRET} chars)${NC}"
fi

# Check ASSETS_DIR exists
if [ -n "$ASSETS_DIR" ] && [ "$ASSETS_DIR" != "/absolute/path/to/assets" ]; then
    if [ ! -d "$ASSETS_DIR" ]; then
        echo -e "${RED}✗ ASSETS_DIR does not exist: ${ASSETS_DIR}${NC}"
        FAILED=1
    else
        echo -e "${GREEN}✓ ASSETS_DIR exists${NC}"
    fi
fi

echo ""

# ============================================
# 2. Docker Containers
# ============================================
echo -e "${YELLOW}[2/4] Checking Docker containers...${NC}"

for CONTAINER in nginx-static nginx-proxy-manager filebrowser; do
    STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER 2>/dev/null || echo "not found")
    if [ "$STATUS" = "running" ]; then
        echo -e "${GREEN}✓ ${CONTAINER} is running${NC}"
    else
        echo -e "${RED}✗ ${CONTAINER} is ${STATUS}${NC}"
        FAILED=1
    fi
done

echo ""

# ============================================
# 3. Nginx Configuration
# ============================================
echo -e "${YELLOW}[3/4] Checking nginx configuration...${NC}"

# Check if secret is properly injected
NGINX_SECRET=$(docker exec nginx-static cat /etc/nginx/conf.d/default.conf 2>/dev/null | grep -o 'secure_link_md5.*' | sed 's/.*"\$secure_link_expires\$uri //' | sed 's/";//' || echo "")

if [ -z "$NGINX_SECRET" ]; then
    echo -e "${RED}✗ Could not read nginx config${NC}"
    FAILED=1
elif [ "$NGINX_SECRET" != "$SECRET" ]; then
    echo -e "${RED}✗ Secret mismatch between .env and nginx config${NC}"
    echo -e "  .env:  ${SECRET}"
    echo -e "  nginx: ${NGINX_SECRET}"
    FAILED=1
else
    echo -e "${GREEN}✓ Secret correctly injected into nginx${NC}"
fi

echo ""

# ============================================
# 4. Signed URL Tests
# ============================================
echo -e "${YELLOW}[4/4] Testing signed URLs...${NC}"

if [ -z "$SECRET" ]; then
    echo -e "${RED}✗ Cannot test signed URLs without secret${NC}"
    FAILED=1
else
    TEST_PATH="/robots.txt"
    EXPIRES=$(($(date +%s) + 3600))

    # Generate hash
    HASH_INPUT="${EXPIRES}${TEST_PATH} ${SECRET}"
    HASH=$(echo -n "${HASH_INPUT}" | openssl md5 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')

    # Test 1: Valid signed URL
    echo -n "  Valid signed URL: "
    RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}?md5=${HASH}&expires=${EXPIRES}" 2>/dev/null || echo "error")
    if [ "$RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ 200 OK${NC}"
    else
        echo -e "${RED}✗ Got ${RESPONSE} (expected 200)${NC}"
        FAILED=1
    fi

    # Test 2: Missing signature
    echo -n "  Missing signature: "
    RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}" 2>/dev/null || echo "error")
    if [ "$RESPONSE" = "403" ]; then
        echo -e "${GREEN}✓ 403 Forbidden${NC}"
    else
        echo -e "${RED}✗ Got ${RESPONSE} (expected 403)${NC}"
        FAILED=1
    fi

    # Test 3: Invalid signature
    echo -n "  Invalid signature: "
    RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}?md5=invalid&expires=${EXPIRES}" 2>/dev/null || echo "error")
    if [ "$RESPONSE" = "403" ]; then
        echo -e "${GREEN}✓ 403 Forbidden${NC}"
    else
        echo -e "${RED}✗ Got ${RESPONSE} (expected 403)${NC}"
        FAILED=1
    fi

    # Test 4: Expired signature
    echo -n "  Expired signature: "
    EXPIRED=$(($(date +%s) - 86400))
    HASH_EXPIRED_INPUT="${EXPIRED}${TEST_PATH} ${SECRET}"
    HASH_EXPIRED=$(echo -n "${HASH_EXPIRED_INPUT}" | openssl md5 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')
    RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}?md5=${HASH_EXPIRED}&expires=${EXPIRED}" 2>/dev/null || echo "error")
    if [ "$RESPONSE" = "410" ]; then
        echo -e "${GREEN}✓ 410 Gone${NC}"
    else
        echo -e "${RED}✗ Got ${RESPONSE} (expected 410)${NC}"
        FAILED=1
    fi
fi

# ============================================
# Summary
# ============================================
echo ""
if [ "$FAILED" = "1" ]; then
    echo -e "${RED}=== Some checks failed ===${NC}"
    exit 1
else
    echo -e "${GREEN}=== All checks passed ===${NC}"
    exit 0
fi
