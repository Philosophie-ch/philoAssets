#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== PhiloAssets Secure Deployment ===${NC}"
echo ""

# Check if .env exists, create from example if not
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo -e "${YELLOW}Creating .env from .env.example...${NC}"
        cp .env.example .env
        echo -e "${GREEN}✓ .env created${NC}"
        echo ""
        echo -e "${YELLOW}Please edit .env now and set:${NC}"
        echo "  - ASSETS_DIR (absolute path to assets directory)"
        echo "  - UID (your user ID, run 'id -u' to find it)"
        echo "  - GID (your group ID, run 'id -g' to find it)"
        echo ""
        read -p "Press Enter when done editing .env... "
    else
        echo -e "${RED}Error: .env.example not found${NC}"
        exit 1
    fi
fi

# Check required variables are set
source .env
if [ -z "$ASSETS_DIR" ] || [ "$ASSETS_DIR" = "/absolute/path/to/assets" ]; then
    echo -e "${RED}Error: ASSETS_DIR not configured in .env${NC}"
    echo -e "${YELLOW}Edit .env and set ASSETS_DIR to your assets directory path${NC}"
    exit 1
fi

if [ -z "$UID" ] || [ "$UID" = "YOUR_UID" ]; then
    echo -e "${RED}Error: UID not configured in .env${NC}"
    echo -e "${YELLOW}Run 'id -u' and set UID in .env${NC}"
    exit 1
fi

if [ -z "$GID" ] || [ "$GID" = "YOUR_GID" ]; then
    echo -e "${RED}Error: GID not configured in .env${NC}"
    echo -e "${YELLOW}Run 'id -g' and set GID in .env${NC}"
    exit 1
fi

if [ ! -d "$ASSETS_DIR" ]; then
    echo -e "${RED}Error: ASSETS_DIR does not exist: ${ASSETS_DIR}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ .env configured (ASSETS_DIR=${ASSETS_DIR})${NC}"

# Create filebrowser database if it doesn't exist
if [ ! -f filebrowser/database.db ]; then
    echo -e "${YELLOW}Creating filebrowser/database.db...${NC}"
    mkdir -p filebrowser
    touch filebrowser/database.db
    echo -e "${GREEN}✓ filebrowser/database.db created${NC}"
else
    echo -e "${GREEN}✓ filebrowser/database.db exists${NC}"
fi

# Check if ASSETS_SIGNING_SECRET is already set
if grep -q "^ASSETS_SIGNING_SECRET=" .env && ! grep -q "^ASSETS_SIGNING_SECRET=$" .env && ! grep -q "^ASSETS_SIGNING_SECRET=your-secret-here" .env; then
    echo -e "${YELLOW}ASSETS_SIGNING_SECRET already set in .env${NC}"
    read -p "Do you want to generate a new secret? (y/N): " regenerate
    if [ "$regenerate" != "y" ] && [ "$regenerate" != "Y" ]; then
        echo "Keeping existing secret"
        SECRET=$(grep "^ASSETS_SIGNING_SECRET=" .env | cut -d'=' -f2)
    else
        SECRET=$(openssl rand -base64 32)
        # Update existing secret
        sed -i "s|^ASSETS_SIGNING_SECRET=.*|ASSETS_SIGNING_SECRET=${SECRET}|" .env
        echo -e "${GREEN}New secret generated and saved to .env${NC}"
    fi
else
    # Generate new secret
    SECRET=$(openssl rand -base64 32)

    # Check if the line exists but is empty/placeholder
    if grep -q "^ASSETS_SIGNING_SECRET=" .env; then
        sed -i "s|^ASSETS_SIGNING_SECRET=.*|ASSETS_SIGNING_SECRET=${SECRET}|" .env
    else
        echo "" >> .env
        echo "# Signing secret for secure URLs" >> .env
        echo "ASSETS_SIGNING_SECRET=${SECRET}" >> .env
    fi
    echo -e "${GREEN}Secret generated and saved to .env${NC}"
fi

echo ""
echo -e "${YELLOW}Secret (save this for client configuration):${NC}"
echo -e "${GREEN}${SECRET}${NC}"
echo ""

# Load ASSETS_DIR from .env
source .env

# Check robots.txt
if [ -f "${ASSETS_DIR}/robots.txt" ]; then
    echo -e "${GREEN}✓ robots.txt exists${NC}"
else
    echo -e "${YELLOW}Creating robots.txt...${NC}"
    echo -e "User-agent: *\nDisallow: /" > "${ASSETS_DIR}/robots.txt"
    echo -e "${GREEN}✓ robots.txt created${NC}"
fi

# Check nginx template
if [ -f "nginx-static/default.conf.template" ]; then
    echo -e "${GREEN}✓ nginx template exists${NC}"
else
    echo -e "${RED}Error: nginx-static/default.conf.template not found${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Stopping containers...${NC}"
docker compose down

echo ""
echo -e "${YELLOW}Starting containers...${NC}"
docker compose up -d

echo ""
echo -e "${YELLOW}Waiting for nginx to start...${NC}"
sleep 3

# Test signed URL generation and validation
echo ""
echo -e "${YELLOW}=== Testing Signed URLs ===${NC}"

# Test file path (use robots.txt since we know it exists)
TEST_PATH="/robots.txt"
EXPIRES=$(($(date +%s) + 3600))  # 1 hour from now

# Generate hash (same algorithm as nginx secure_link)
# Format: MD5(expires + uri + " " + secret) -> base64url
HASH_INPUT="${EXPIRES}${TEST_PATH} ${SECRET}"
HASH=$(echo -n "${HASH_INPUT}" | openssl md5 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')

echo "Test path: ${TEST_PATH}"
echo "Expires: ${EXPIRES}"
echo "Hash: ${HASH}"
echo ""

# Test against nginx-static directly (internal network)
echo -e "${YELLOW}Testing against nginx-static container...${NC}"

# Test 1: Valid signed URL
echo -n "1. Valid signed URL: "
RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}?md5=${HASH}&expires=${EXPIRES}" 2>/dev/null || echo "error")
if [ "$RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓ 200 OK${NC}"
else
    echo -e "${RED}✗ Got ${RESPONSE} (expected 200)${NC}"
fi

# Test 2: Missing signature (should be 403)
echo -n "2. Missing signature: "
RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}" 2>/dev/null || echo "error")
if [ "$RESPONSE" = "403" ]; then
    echo -e "${GREEN}✓ 403 Forbidden${NC}"
else
    echo -e "${RED}✗ Got ${RESPONSE} (expected 403)${NC}"
fi

# Test 3: Invalid signature (should be 403)
echo -n "3. Invalid signature: "
RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}?md5=invalid&expires=${EXPIRES}" 2>/dev/null || echo "error")
if [ "$RESPONSE" = "403" ]; then
    echo -e "${GREEN}✓ 403 Forbidden${NC}"
else
    echo -e "${RED}✗ Got ${RESPONSE} (expected 403)${NC}"
fi

# Test 4: Expired signature (should be 410)
echo -n "4. Expired signature: "
EXPIRED=$(($(date +%s) - 86400))  # 24 hours ago
HASH_EXPIRED_INPUT="${EXPIRED}${TEST_PATH} ${SECRET}"
HASH_EXPIRED=$(echo -n "${HASH_EXPIRED_INPUT}" | openssl md5 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')
RESPONSE=$(docker exec nginx-static curl -s -o /dev/null -w "%{http_code}" "http://localhost${TEST_PATH}?md5=${HASH_EXPIRED}&expires=${EXPIRED}" 2>/dev/null || echo "error")
if [ "$RESPONSE" = "410" ]; then
    echo -e "${GREEN}✓ 410 Gone${NC}"
else
    echo -e "${RED}✗ Got ${RESPONSE} (expected 410)${NC}"
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Save this secret for client application configuration:"
echo -e "   ${GREEN}ASSETS_SIGNING_SECRET=${SECRET}${NC}"
echo ""
echo "2. Configure client applications to generate signed URLs using this secret"
echo ""
echo "3. (Optional) Purge CDN cache if using a CDN"
echo ""
echo -e "${YELLOW}WARNING:${NC} All direct asset URLs now return 403."
echo "Client applications must generate signed URLs to access assets."
