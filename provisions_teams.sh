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

# GLOBAL CONSTANTS & ENVIRONMENT SETTINGS
readonly LOG_FILE="/var/log/provisions_teams/provisions_teams.log"
readonly GROUPNAME_REGEX='^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$'
CLEANUP_MODE=false

# HELPER FUNCTIONS (Logging, Notification, Diagnostics)
log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] - $*" | tee -a "$LOG_FILE" >&2
}

# Parse arguments BEFORE provisional parameter checks
while [ "$#" -gt 0 ]; do
	case "$1" in
		--cleanup)
			CLEANUP_MODE=true
			shift
			;;
		*)
			# Capture any invalid flags
			if [ "$1" == -* ]; then
				log_error "Invalid option: $1"
				log_error "Usage: provisions_teams.sh [--cleanup] <team_name> [team_name_2 ...]"
				exit 1
			fi
			break
			;;
	esac
done

# Interactive prompt to user
confirm_action() {
	while true; do
		read -rp "Are you sure you want to proceed with this operation? (y/yes/n/no): " response
		
		# Normalize input to lowercase to handle y/yes/n/no/Y/YES/N/NO all at once
		local clean_response="${response,,}"

		if [[ "$clean_response" =~ ^(y|yes)$ ]]; then
			log_info "Confirmation received. Proceeding..."
			break # Exit the loop and continue script execution
		elif [[ "$clean_response" =~ ^(n|no)$ ]]; then
			log_error "Operation canceled by user."
			exit 1 # Abort the script immediately
		else
			# Invalid input: log error and let the loop prompt again
			log_error "Invalid input: '$response'. Please enter y, yes, n, or no."
			echo "" # Adds a clean empty line for terminal readability
		fi
	done
}



# Dynamic Cleanup
execute_cleanup() {
	log_info "Cleanup mode enabled. Removing provisioned resources..."
	shopt -s nullglob
	local targets=(/data/teams/*)
	echo "${targets[@]}"
	sleep 1
	for team_path in "${targets[@]}"; do
		# Extract the basename (team name) from the path string
		local team_name=$(basename "$team_path")
		log_info "Removing resources for team: $team_name"
		sleep 1
		if grep -q "^$team_name:" /etc/group; then
			groupdel "$team_name"
			log_info "Team $team_name have been removed."
			sleep 1
		else
			log_info "Team $team_name does not exist. Skipping cleanup for it..."
			sleep 1
		fi
	done
	sleep 1
	log_info "Removing the root directory for created groups"
	rm -rf "/data/teams"
	sleep 2
	log_info "Cleanup completed successfully."
	exit 0
}

# Create log directory if it doesn't exist
mkdir -p /var/log/provisions_teams



# Check for atleast one positional parameters if no cleanup mode is enabled
if [ "$CLEANUP_MODE" = false ] && [ "$#" -lt 1 ]; then
	log_error "USAGE: provisions_teams.sh <team_name> [team_name_2 ...]"
	log_error "Error: Please provide one or more team names"
	exit 2
fi

main() {
	# Check for administrative access first
	if [ "$EUID" -ne 0 ]; then
		log_error "Error: This script must be run as root or with sudo."
		exit 3
	fi

	# Trigger the prompt before any destructive action
	if [ "$CLEANUP_MODE" = true ]; then
		confirm_action

		# If team arguments were passed along with --cleanup, notify log of test execution
		if [ "$#" -gt 0 ]; then
			log_info "STARTING TEST RUN: Provisioning will occur followed by immediate destruction."
			sleep 1
		fi
	fi

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
		elif [ ! "$team_name" =~ GROUPNAME_REGEX ]; then
			log_error "$team_name contains forbidden characters or is too long."
			sleep 0.5
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

	# Cleanup after execution of script
	if [ "$CLEANUP_MODE" = true ]; then
		if [ "$#" -gt 0 ]; then
			log_info "Test provisioning phase complete. Transitioning to immediate teardown..."
			sleep 1
		fi
		execute_cleanup
	fi

}

main "$@"