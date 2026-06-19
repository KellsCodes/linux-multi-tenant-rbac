#!/bin/bash
set -euo pipefail
IFS=$'\n\t'


# ====================================================================================
# Script Name:		provisions_teams.sh
# Description:		This script provisions the necessary resources for the teams.
# Author:			Ifeanyi Nworji (DevOps Engineer)
# Version:			1.0
# License:			MIT
# =====================================================================================

# Only root can run this script
if [ "$EUID" -ne 0 ]; then
	echo "Error: This script must be run as root or with sudo."
	exit 1
fi

# GLOBAL CONSTANTS & ENVIRONMENT SETTINGS
readonly LOG_FILE="/var/log/provisions_teams/provisions_teams.log"

mkdir -p /var/log/provisions_teams

# HELPER FUNCTIONS (Logging, Notification, Diagnostics)
log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] - $*" | tee -a "$LOG_FILE" >&2
}


# Check for atleast positional parameters
if [ "$#" -lt 1 ]; then
	log_error "USAGE: provisions_teams.sh <team_name> [team_name_2 ...]"
	log_error "Error: Please provide one or more team names"
	exit 2
fi

main() {
	# Iterate over all team names provided as arguments
	for team_name in "$@"; do
		log_info "Provisioning resources for team: $team_name"
		# Check if team(group) already exists
		if grep -q "^$team_name:" /etc/group; then
			sleep 0.5
			log_info "Checking if Team $team_name already exists..."
			sleep 0.5
			log_info "Team $team_name already exists. Skipping it..."
			continue
		else
			log_info "Creating team $team_name."
			sleep 0.5
			path="/data/teams/$team_name"
			# Create the group and the root directory for the group
			groupadd "$team_name"
			mkdir -p "$path"
			# Set permissions for the team directory
			chown root:"$team_name" "$path"
			# Set GroupID Bit for collaborative directory
			chmod 2770 "$path"
			sleep 0.5
			log_info "Team $team_name has been provisioned successfully."
		fi
	done
}

main "$@"