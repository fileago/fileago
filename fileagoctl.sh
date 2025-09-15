# Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.
#
# This software is proprietary and confidential.
# Unauthorized copying of this file, via any medium, is strictly prohibited.
#
# For license information, see the LICENSE.txt file in the root directory of
# this project. 
# --------------------------------------------------------------------------

#!/bin/bash

# fileagoctl.sh - Script to manage FileAgo services using docker-compose

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure script is run from its own directory
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [[ "$SCRIPT_DIR" != "$(pwd)" ]]; then
    echo -e "${RED}Error: Script must be run from its own directory. Please change to: $SCRIPT_DIR${NC}"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Function to print usage
usage() {
    echo "Usage: $0 {up|start|stop|restart|status|logs|installcron|removecron}"
    echo "  up          - Build and start all enabled services (first run)"
    echo "  start       - Start all enabled services"
    echo "  stop        - Stop all services"
    echo "  restart     - Restart all enabled services"
    echo "  status      - Show status of services"
    echo "  logs        - Show logs of services (tail)"
    echo "  installcron - Install cron job file in /etc/cron.d/"
    echo "  removecron  - Remove cron job file from /etc/cron.d/"
    exit 1
}

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: docker-compose is not installed${NC}"
    exit 1
fi

# Check if settings.env exists
if [ ! -f "settings.env" ]; then
    echo -e "${RED}Error: settings.env file not found.${NC}"
    exit 1
fi

# Function to read settings from settings.env
read_settings() {
    # Reset variables
    ICAP_ENABLED=false
    PDFVIEWER_ENABLED=false
    CHAT_ENABLED=false
    CAD_ENABLED=false
    SSO_ENABLED=false
    
    # Read settings.env file
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ $line =~ ^#.*$ ]] || [[ -z $line ]]; then
            continue
        fi
        
        # Parse key=value pairs
        if [[ $line =~ ^([A-Z_]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            case $key in
                ICAP_ENABLED)
                    ICAP_ENABLED=$value
                    ;;
                PDFVIEWER_ENABLED)
                    PDFVIEWER_ENABLED=$value
                    ;;
                CHAT_ENABLED)
                    CHAT_ENABLED=$value
                    ;;
                CAD_ENABLED)
                    CAD_ENABLED=$value
                    ;;
                SSO_ENABLED)
                    SSO_ENABLED=$value
                    ;;
            esac
        fi
    done < "settings.env"
}

# Function to build docker-compose command
build_compose_command() {
    local action=$1
    local compose_files="-f docker-compose.yml"
    
    # Add additional compose files based on enabled services
    if [[ "$ICAP_ENABLED" == "true" ]]; then
        if [ -f "docker-compose.icap.yml" ]; then
            compose_files="$compose_files -f docker-compose.icap.yml"
        else
            echo -e "${YELLOW}Warning: docker-compose.icap.yml not found${NC}"
        fi
    fi
    
    if [[ "$PDFVIEWER_ENABLED" == "true" ]]; then
        if [ -f "docker-compose.pdfviewer.yml" ]; then
            compose_files="$compose_files -f docker-compose.pdfviewer.yml"
        else
            echo -e "${YELLOW}Warning: docker-compose.pdfviewer.yml not found${NC}"
        fi
    fi
    
    if [[ "$CHAT_ENABLED" == "true" ]]; then
        if [ -f "docker-compose.chat.yml" ]; then
            compose_files="$compose_files -f docker-compose.chat.yml"
        else
            echo -e "${YELLOW}Warning: docker-compose.chat.yml not found${NC}"
        fi
    fi
    
    if [[ "$CAD_ENABLED" == "true" ]]; then
        if [ -f "docker-compose.cad.yml" ]; then
            compose_files="$compose_files -f docker-compose.cad.yml"
        else
            echo -e "${YELLOW}Warning: docker-compose.cad.yml not found${NC}"
        fi
    fi

    if [[ "$SSO_ENABLED" == "true" ]]; then
        if [ -f "docker-compose.sso.yml" ]; then
            compose_files="$compose_files -f docker-compose.sso.yml"
        else
            echo -e "${YELLOW}Warning: docker-compose.sso.yml not found${NC}"
        fi
    fi
    
    echo "docker-compose $compose_files $action"
}

# Function to execute docker-compose command
execute_compose() {
    local cmd=$1
    echo -e "${GREEN}Executing: $cmd${NC}"
    eval $cmd
}

# Make the script executable
chmod +x "$0" 2>/dev/null || echo -e "${YELLOW}Note: Could not make script executable, please run 'chmod +x fileagoctl.sh' manually${NC}"

# Main script logic
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1

# Read settings from settings.env
read_settings

case $COMMAND in
    up)
        echo -e "${YELLOW}!!! Warning: Recreating an existing environment could undo custom changes. !!!${NC}"
        echo -e "${GREEN}But it is totally fine if you are running this for the first time.${NC}"
        echo -e ""
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Operation cancelled.${NC}"
            exit 0
        fi
        COMPOSE_CMD=$(build_compose_command "up -d")
        execute_compose "$COMPOSE_CMD"
        ;;
    start)
        COMPOSE_CMD=$(build_compose_command "start")
        execute_compose "$COMPOSE_CMD"
        ;;
    stop)
        COMPOSE_CMD=$(build_compose_command "stop")
        execute_compose "$COMPOSE_CMD"
        ;;
    restart)
        COMPOSE_CMD=$(build_compose_command "restart")
        execute_compose "$COMPOSE_CMD"
        ;;
    ps)
        COMPOSE_CMD=$(build_compose_command "ps")
        execute_compose "$COMPOSE_CMD"
        ;;
    status)
        COMPOSE_CMD=$(build_compose_command "ps")
        execute_compose "$COMPOSE_CMD"
        ;;
    logs)
        COMPOSE_CMD=$(build_compose_command "logs --tail 1 --follow")
        execute_compose "$COMPOSE_CMD"
        ;;
    installcron)
        # Check if Docker Compose plugin is installed
        if ! docker compose version &> /dev/null; then
            echo -e "${RED}Error: Docker Compose plugin is not installed${NC}"
            exit 1
        fi

        # Check if jq is installed
        if ! command -v jq &> /dev/null; then
            echo "Error: jq is not installed"
            exit 1
        fi

        # Get current directory path and normalize it
        CURRENT_DIR=$(pwd)
        CRON_NAME=$(echo "$CURRENT_DIR" | sed 's,^/,,; s,/$,,; s,/,_,g')
        CRON_FILE="/etc/cron.d/$CRON_NAME"

        # Check if cron file already exists
        if [ -f "$CRON_FILE" ]; then
            echo -e "${YELLOW}Cron job already exists at $CRON_FILE${NC}"
            exit 0
        fi

        # Get user confirmation
        echo -e "${YELLOW}!!! WARNING: This will create a cron job in /etc/cron.d/ !!!${NC}"
        echo -e "Cron file path: ${GREEN}$CRON_FILE${NC}"
        echo -e "Schedule: ${GREEN}Daily at 1:00 AM${NC}"
        read -p "Proceed with cron job? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Operation cancelled.${NC}"
            exit 0
        fi

        # Create cron file
        echo "0 1 * * * root cd \"$CURRENT_DIR/cron\" && /bin/bash cron.sh" | tee "$CRON_FILE" > /dev/null
        chmod 644 "$CRON_FILE"
        
        echo -e "${GREEN}Cron job installed successfully at $CRON_FILE${NC}"
        exit 0
        ;;
    removecron)
        # Get current directory path and normalize cron file name
        CURRENT_DIR=$(pwd)
        CRON_NAME=$(echo "$CURRENT_DIR" | sed 's,^/,,; s,/$,,; s,/,_,g')
        CRON_FILE="/etc/cron.d/$CRON_NAME"

        # Check if cron file exists
        if [ ! -f "$CRON_FILE" ]; then
            echo -e "${YELLOW}Cron job does not exist at $CRON_FILE${NC}"
            exit 0
        fi

        # Get user confirmation
        echo -e "${YELLOW}!!! WARNING: This will remove cron job from /etc/cron.d/ !!!${NC}"
        echo -e "Cron file path: ${GREEN}$CRON_FILE${NC}"
        read -p "Proceed with removal? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Operation cancelled.${NC}"
            exit 0
        fi

        # Remove cron file
        rm -f "$CRON_FILE"
        echo -e "${GREEN}Cron job removed successfully from $CRON_FILE${NC}"
        exit 0
        ;;
    *)
        usage
        ;;
esac
