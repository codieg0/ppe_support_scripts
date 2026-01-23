#!/bin/bash

# To do:
# Need to figure how to fiter by type of user
# Reuse code

creds_domain() {
  read -rep "Username: " username
  read -rep "Password: " password
  echo
  read -rep "Enter domain: " domain
  read -rep "Enter stack: " stack 
}

menu(){
  cat <<'USERS'

[1] End Users
[2] Silent Users
[3] Organizational Admins
[4] Channel Admins
[5] Functional Accounts
[6] All Users Except Functional Accounts
[7] All Users

USERS
}

users_endpoint() {
  curl -s -X GET \
  -H "X-User: $username" \
  -H "X-Password: $password" \
  https://"$stack".proofpointessentials.com/api/v1/orgs/"$domain"/users
}

general_jq() {

	local users_type="$1"

	users_endpoint | jq -r --arg user "$users_type" '["First Name", "Last Name", "Email Address", "Type"], 
   	(.users[] | select(.is_active == true and .type == $user) | 
   	[.firstname, .surname, .primary_email, .type]) | @tsv' | column -t -s $'\t'
}

end_user() {
	echo
	creds_domain
	echo

	general_jq "end_user"
}

silent_user() {
	echo
	creds_domain
	echo

	general_jq "silent_user"
}

org_admin() {
	echo
	creds_domain
	echo

	general_jq "organization_admin"
}

channel_admin() {
	echo
	creds_domain
	echo

	general_jq "channel_admin"
}

funct_acc() {
	echo
	creds_domain
	echo

	general_jq "functional_account"
}

all() {
	echo
	creds_domain
	echo
	
	users_endpoint | jq -r '["First Name", "Last Name", "Email Address", "Type"], 
   	(.users[] | select(.is_active == true) | 
   	[.firstname, .surname, .primary_email, .type]) | @tsv' | column -t -s $'\t'
}

all_no_functs(){
	echo
	creds_domain
	echo
	
	users_endpoint | jq -r '["First Name", "Last Name", "Email Address", "Type"], 
   	(.users[] | select(.is_active == true and .type != "functional_account") | 
   	[.firstname, .surname, .primary_email, .type]) | @tsv' | column -t -s $'\t'
}

while true;do
  menu
  read -rep "➤ Select an option [1 – 7 | q = quit]: " option

  case $option in
  	1)
  	  end_user
  	  ;;

  	2)
  	  silent_user
  	  ;;	

    3) 
      org_admin
      ;; 

    4)
      channel_admin
      ;;

    5)
	    funct_acc
      ;; 

	6)
	    all_no_functs
	    ;;

	7)
	    all
	    ;;

    q|Q)
      echo
      echo "Bye 👋"
      exit 0
      ;;

    *)
      echo
      echo "Invalid option. Please try again."

  esac
done