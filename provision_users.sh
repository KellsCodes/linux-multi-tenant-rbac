#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =========================================================================
# Script Name:		provision_users.sh
# Description:		This script provisions user accounts on specified servers.
# Author:			Ifeanyi Nworji (DevOps Engineer)
# Version:			1.0
# License:			MIT
# =========================================================================

# CLEANUP_MODE=false
DELETE_USER_MODE=false
MODIFY_USER_MODE=false
CREATE_USER_MODE=false
SCRIPT_NAME='provision_users.sh'
FLAG=''

readonly LOG_FILE="/var/log/provision_users/provision_user.log"
readonly USERNAME_REGEX='^[a-z_][a-z0-9_-]{0,31}$'
readonly GROUPNAME_REGEX='^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$'
mkdir -p /var/log/provision_users

log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] - $*" | tee -a "$LOG_FILE" >&2
}

create_group() {
	log_info "Group '$1' not found. Provisioning group via teams script..."
	sleep 1
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

	if "$SCRIPT_DIR/provisions_teams.sh" "$1"; then
		log_info "Successfully created group: $1"
		sleep 1
	else
		log_error "Failed to execute provisions_teams.sh for group: $1"
		sleep 1
		log_error "Exiting the program..."
		sleep 1
		exit 8
	fi
}

# check user input for multiple flags
for args in "$@"; do
	# Check the flags
	case "$args" in
		--delete=*|--group=*|--modify=*)
		if [[ -z "$FLAG" ]]; then
			FLAG="$args"
			case "$args" in
				--delete=*) DELETE_USER_MODE=true ;;
				--group=*)  CREATE_USER_MODE=true ;;
				--modify=*)  MODIFY_USER_MODE=true ;;
			esac
		else
			log_error "USAGE: $SCRIPT_NAME <username> --group=<group_name> || $SCRIPT_NAME --delete=<username> || $SCRIPT_NAME --modify=<username> name=<new_username> group=<new_group> drop=<old_group>"
			log_info "Use one or more options for modifying user."
			exit 1
		fi
		;;
	esac
done

confirm_action() {
	while true; do
		read -rp "Are you sure you want to delete this user? (y/yes/n/no): " response
		
		# Normalize input to lowercase to handle y/yes/n/no/Y/YES/N/NO all at once
		local clean_response="${response,,}"

		if [[ "$clean_response" =~ ^(y|yes)$ ]]; then
			log_info "Confirmation received. Proceeding..."
			sleep 1
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

main() {
	# Ensure only root user can execute the script
	if [[ "$EUID" -ne 0 ]]; then
		log_error "Error: This script must be run as root or with sudo."
		exit 2
	fi

	if [[ -z "$FLAG" ]]; then
		log_error "USAGE: $SCRIPT_NAME <username> [username_2 ...] --group=<group_name>"
		echo ""
		log_error "USAGE: $SCRIPT_NAME --delete=<username>"
		echo ""
		log_error "USAGE: $SCRIPT_NAME --modify=<username> name=<new_username> group=<new_group> drop=<old_group>"
		echo ""
		log_info "Use one or more options for running the script."
		exit 3;
	fi

	# Delete user
	if [[ "$DELETE_USER_MODE" == "true"  ]]; then
		confirm_action

		local username="${FLAG#*=}"
		if [[ ! "$username" =~ $USERNAME_REGEX ]]; then
			log_error "Invalid linux username."
			exit 4
		fi 
		if grep -q "^$username:" /etc/passwd; then
			killall -u "$username" 2>/dev/null || true
			# tar -czvf "/opt/${username}.tar.gz" "/home/backup/${username}"
			if userdel -r "$username"; then
				sleep 1
				log_info "Successfully removed user: $username"
				sleep 1
				exit 0		
			else
				log_error "Failed to remove user: $username"
				sleep 1
				exit 5
			fi
		else 
			log_error "User $username does not exist."
			sleep 1
			exit 6
		fi
	fi
	
	# Create new user or add user to group if user exists
	if [[ "$CREATE_USER_MODE" == "true" ]]; then
		local group_name="${FLAG#*=}"
		if [[ ! "$group_name" =~ $GROUPNAME_REGEX ]]; then
			log_error "Invalid linux server groupname convention."
			sleep 1
			exit 6
		fi

		local USER_LIST=()
		# get usernames from args
		for username in "$@"; do
			if [[ "$username" == --* ]]; then
				continue
			fi

			if [[ ! "$username" =~ $USERNAME_REGEX ]]; then
				log_error "Invalid linux server username convention: '$username'"
				sleep 1
				exit 7
				# check if username valriable is the actual FLAG on the loop
			elif [[ "$username" =~ "$FLAG" ]]; then
				continue
			elif grep -q "$username" /etc/passwd; then
				log_info "User already exists, moving to the next user"
				sleep 1
				continue
			else
				
				# check if group exists, create group if missing group
				if ! grep -q "^$group_name:" /etc/group; then
					create_group "$group_name"
				fi
				# create user and add user to group
				if useradd -m -g "$group_name" -s /bin/bash "$username"; then
					usermod -aG "$group_name" "$username"
					log_info "Successfully added user '$username' to group '$group_name'"
					sleep 1
				else
					log_error "Failed to create user: $username"
					sleep 1
					exit 9
				fi

			fi
		done
	fi

	# Modify users(change or append groups, change )
	if [[ "$MODIFY_USER_MODE" == "true" ]]; then
		if [[ ! "$1" =~ "$FLAG" ]]; then
			log_error "USAGE: $SCRIPT_NAME --modify=<username> name=<new_username> group=<new_group> drop=<old_group>"
			sleep 1
			log_error "Script arguments are not well structured."
			exit 10
		fi
		local username="${FLAG#*=}"
		log_info "confirming $username is on this server..."
		sleep 1
		# Check if user is present on the server
		if ! grep -q "^$username" /etc/passwd; then
			log_error "$username, not found on this server!"
			sleep 1
			exit 11
		else
			local name=''
			local group=''
			local is_valid="false"
			for key in "${@:2}"; do
				if [[ "$key" =~ ^name= ]]; then
					if [[ ! "${key#*=}" =~ $USERNAME_REGEX ]]; then
						log_error "Invalid username format: '${key#*=}'"
						sleep 1
						exit 12
					else
						name="${key#*=}"
					fi
				fi

				# Check if group is available to add user to new group
				if [[ "$key" =~ ^group= ]]; then
					group="${key#*=}"
					# check if group exists, create group if missing group
					if [[ "${key#*=}" =~ $GROUPNAME_REGEX ]]; then
						if ! grep -q "^$group:" /etc/group; then
							create_group "$group"
						fi
					else
						log_error "Invalid group name format: $group"
						sleep 1
						exit 13
					fi
				fi

				# Check if group name to drop is available
				if [[ "$key" =~ ^drop= ]]; then
					local drop_group="${key#*=}"
					if grep -q "^$drop_group:" /etc/group && id -nG "$name" | grep -qw "$drop_group"; then
						# Remove the user from the current group before appending the new group
						log_info "Removing '$name' from group '$drop_group'"
						sleep 1
					else
						log_info "User is not a member of this group '$drop_group'"
						log_info "Continuing the user modification...."
						sleep 1
						continue
					fi
				fi
			done

			# modify the name and group
			if [[ ! -z "$name" && ! -z "$group" ]]; then
				log_info "Modifying user data..."
				if usermod -l "$name" -c "$name" -d "/home/$name" -G "$group" -m "$username"; then
					log_info "username '$username' changed to $name"
					echo ''
					log_info "$name added to group '$group'"
					sleep 1
					exit 14
				else
					log_error "user modification failed"
					sleep 1
					exit 15
				fi
			elif [[ -z "$name" && ! -z "$group" ]]; then
				log_info "Modifying user group"
				sleep 1
				if usermod -aG "$group" "$username"; then
					log_info "User '$username' added to the group '$group' successfully."
					sleep 1
					exit 16
				else
					log_error "Adding user '$username' to group '$group' is unsuccessful"
					sleep 1
					exit 17
				fi
			elif [[ ! -z "$name" && -z "$group" ]]; then
				log_info "Modifying user login name"
				sleep 1
				if usermod -l "$name" -c "$name" -d "/home/$name" -m "$username"; then
					log_info "User login name is changed successfully."
					sleep 1
					exit 18
				else
					log_error "User modification is unsuccessful."
					sleep 1
					exit 19
				fi
			fi
		fi
	fi
	

		
}

main "$@"

# mkdir -p /var/log/provision_users
#1. get users and the group(1 group per run)
#2. check the formatting of user names and the group, exit if error
#3. add the usernames into USER_LIST
#4. check flags: --delete=<username> for deleting user, --modify=<username> name=<new_username> group=<new_group> drop=<old_group>


# # log_error "Invalid username '$username'. Usernames must start with a letter or underscore, followed by letters, digits, underscores, or hyphens."
# [[ $username =~ $USERNAME_REGEX ]]; then
# 	CLEANED_USER_LIST+=("$username")
# elif [[ $username =~ --delete=([^[:space:]]+) ]]; then
# 	local GROUP_NAME="${BASH_REMATCH[1]}"
# 	echo "$GROUP_NAME"
# 	#if [[ !  =~  ]]
# fi