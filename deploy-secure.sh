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

# Check required variables are set (read directly to avoid UID readonly issue)
# Using sed to handle values containing '=' (like base64)
ASSETS_DIR=$(sed -n 's/^ASSETS_DIR=//p' .env)
ENV_UID=$(sed -n 's/^UID=//p' .env)
ENV_GID=$(sed -n 's/^GID=//p' .env)

if [ -z "$ASSETS_DIR" ] || [ "$ASSETS_DIR" = "/absolute/path/to/assets" ]; then
    echo -e "${RED}Error: ASSETS_DIR not configured in .env${NC}"
    echo -e "${YELLOW}Edit .env and set ASSETS_DIR to your assets directory path${NC}"
    exit 1
fi

if [ -z "$ENV_UID" ] || [ "$ENV_UID" = "YOUR_UID" ]; then
    echo -e "${RED}Error: UID not configured in .env${NC}"
    echo -e "${YELLOW}Run 'id -u' and set UID in .env${NC}"
    exit 1
fi

if [ -z "$ENV_GID" ] || [ "$ENV_GID" = "YOUR_GID" ]; then
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
        SECRET=$(sed -n 's/^ASSETS_SIGNING_SECRET=//p' .env)
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

# Verify the secret was stored correctly
STORED_SECRET=$(sed -n 's/^ASSETS_SIGNING_SECRET=//p' .env)
if [ "$SECRET" != "$STORED_SECRET" ]; then
    echo -e "${RED}ERROR: Secret mismatch!${NC}"
    echo -e "Expected: ${SECRET}"
    echo -e "Stored:   ${STORED_SECRET}"
    echo -e "${RED}Please check .env file manually${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Secret verified in .env${NC}"

echo ""
echo -e "${YELLOW}Secret (save this for client configuration):${NC}"
echo -e "${GREEN}${SECRET}${NC}"
echo ""

# Reload ASSETS_DIR in case it changed (avoid source due to UID readonly issue)
ASSETS_DIR=$(sed -n 's/^ASSETS_DIR=//p' .env)

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

# Run health checks
./check.sh

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
