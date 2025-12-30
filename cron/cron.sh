# Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.
#
# This software is proprietary and confidential.
# Unauthorized copying of this file, via any medium, is strictly prohibited.
# 
# For license information, see the LICENSE.txt file in the root directory of
# this project.
# --------------------------------------------------------------------------

#!/bin/bash

# cron.sh - Script to handle log rotation and cleanup for FileAgo services
# This script should only run as a cron job

# Check if script is running as cron
# In cron, the parent process is typically 'cron' or 'crond'
parent_process=$(ps -o comm= -p $PPID)
if [[ "$parent_process" != "cron" && "$parent_process" != "crond" ]]; then
    # Additional check: if running in a terminal with specific environment variable
    if [[ -t 1 && -z "$FORCE_CRON" ]]; then
        echo "Error: This script should only be run as a cron job"
        echo "To run manually for testing, set FORCE_CRON=1"
        exit 1
    fi
fi

# Check if required commands are available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Error: docker is not installed"
    exit 1
fi

# Get container information directly from docker-compose.yml
containers=$(docker compose -f ../docker-compose.yml ps --format json)

# Process nginx container
nginx_container=$(echo "$containers" | jq -r '(if type=="array" then .[] else . end) | select(.Service == "nginx") | .Name')
if [ -n "$nginx_container" ]; then
    # Check if nginx container is running
    nginx_status=$(echo "$containers" | jq -r '(if type=="array" then .[] else . end) | select(.Service == "nginx") | .State')
    if [ "$nginx_status" == "running" ]; then
        echo "Running logrotate for nginx container: $nginx_container"
        docker exec "$nginx_container" /usr/sbin/logrotate /etc/logrotate.d/nginx
    fi
fi

# Process lool container
lool_container=$(echo "$containers" | jq -r '(if type=="array" then .[] else . end) | select(.Service == "lool") | .Name')
if [ -n "$lool_container" ]; then
    # Check if lool container is running
    lool_status=$(echo "$containers" | jq -r '(if type=="array" then .[] else . end) | select(.Service == "lool") | .State')
    if [ "$lool_status" == "running" ]; then
        echo "Cleaning temporary files for lool container: $lool_container"
        # Remove all *.tmp files from /tmp directory
        docker exec "$lool_container" sh -c 'rm -rf /tmp/*.tmp'
    fi
fi

# Process db container
db_container=$(echo "$containers" | jq -r '(if type=="array" then .[] else . end) | select(.Service == "db") | .Name')
if [ -n "$db_container" ]; then
    # Check if db container is running
    db_status=$(echo "$containers" | jq -r '(if type=="array" then .[] else . end) | select(.Service == "db") | .State')
    if [ "$db_status" == "running" ]; then
        echo "Cleaning up log files for db container: $db_container"
        # Remove all *.log.* files from /var/lib/neo4j/logs/
        docker exec "$db_container" sh -c 'rm -f /var/lib/neo4j/logs/*.log.*'
        # Remove all *.csv.* files from /var/lib/neo4j/metrics/
        docker exec "$db_container" sh -c 'rm -f /var/lib/neo4j/metrics/*.csv.*'
        # Copy and execute backup script
        docker cp ./db_backup.sh "$db_container":/tmp/
        docker exec "$db_container" /bin/bash /tmp/db_backup.sh
    fi
fi

echo "Cron job completed successfully!"
