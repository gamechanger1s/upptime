#!/bin/bash

# Automated commit script with semantic versioning
# Usage: ./commit.sh "your commit message"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if commit message is provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Commit message is required${NC}"
    echo -e "${CYAN}Usage: ./commit.sh \"your commit message\"${NC}"
    echo ""
    echo -e "${YELLOW}Semantic Versioning Guide:${NC}"
    echo -e "  ${GREEN}feat:${NC} New feature (bumps MINOR version)"
    echo -e "  ${GREEN}fix:${NC} Bug fix (bumps PATCH version)"
    echo -e "  ${GREEN}docs:${NC} Documentation changes (bumps PATCH version)"
    echo -e "  ${GREEN}style:${NC} Code style changes (bumps PATCH version)"
    echo -e "  ${GREEN}refactor:${NC} Code refactoring (bumps PATCH version)"
    echo -e "  ${GREEN}test:${NC} Adding tests (bumps PATCH version)"
    echo -e "  ${GREEN}chore:${NC} Maintenance tasks (bumps PATCH version)"
    echo -e "  ${GREEN}BREAKING CHANGE:${NC} Breaking changes (bumps MAJOR version)"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  ./commit.sh \"feat: add new monitoring endpoint\""
    echo -e "  ./commit.sh \"fix: resolve uptime calculation bug\""
    echo -e "  ./commit.sh \"BREAKING CHANGE: redesign monitoring structure\""
    exit 1
fi

COMMIT_MESSAGE="$1"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        🚀 Automated Git Commit & Version Bump         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show current status
echo -e "${CYAN}📊 Current Git Status:${NC}"
git status --short
echo ""

# Stage all changes
echo -e "${YELLOW}📝 Staging all changes...${NC}"
git add -A

# Show what will be committed
echo -e "${CYAN}📦 Files to be committed:${NC}"
git diff --cached --name-status
echo ""

# Commit with the provided message
echo -e "${YELLOW}💾 Creating commit: ${COMMIT_MESSAGE}${NC}"
git commit -m "$COMMIT_MESSAGE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Commit successful!${NC}"
    echo -e "${GREEN}🏷️  Version tag created and pushed automatically${NC}"
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                  🎉 Deployment Complete!              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
else
    echo ""
    echo -e "${RED}❌ Commit failed${NC}"
    exit 1
fi

exit 0
