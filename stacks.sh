#!/bin/bash
# Created by Diego Castro.
# Purpose: SMTP Authentication testing tool for the PPE support team.

# To avoid re-entering your credentials, you can create an .env file and store them there.
# Be sure to comment out the username and password when using this method.

# Added a menu - no need but just wanted to practice from previous project.
menu() {
    cat <<'OPTIONS'

[1] Check domain.
[q] To quit. 👋

OPTIONS
}

help() {
    cat<<'HELPSECTION'

Usage:

    [1] ./stacks.sh
        Prompts for credentials and allows you to select an option

    [2] ./stacks.sh domain.tld
        Prompts only for the domain name

HELPSECTION
}

args_domain=$1

case "$1" in
    -h|--help)
        help
        exit 0
        ;;
esac

#Declaring stacks array
stacks=("eu1" "us1" "us2" "us3" "us4" "us5" "usg1" "usg2")

user_info() {
    read -rep "Username: " username
    read -rep "Password: " password
    echo
}

domain_info() {
    local domain=$1

    for location in "${stacks[@]}"; do
        response=$(curl -s \
            -X GET \
            -H "X-User: ${username}" \
            -H "X-Password: ${password}" \
            "https://${location}.proofpointessentials.com/api/v1/orgs/${domain}")

        eid=$(echo "$response" | grep -o '"eid":[0-9]*' | cut -d':' -f2)

        url="https://${location}.proofpointessentials.com/i/${eid}/dashboard"

        if [[ -n "$eid" ]]; then
            printf "Location: %s\nEID: %s\nURL: %s\n\n" \
            "${location^^}" "$eid" "$url"
        fi
    done
}

if [[ -n "$args_domain" ]]; then
    echo
    user_info
    domain_info "$args_domain"
    exit 0
fi

while true;do
    menu

    read -rep "➤ Select an option: " option
    echo

    case $option in
    1)  
        user_info
        read -rep "Domain: " domain
        echo;domain_info "$domain"
        ;;

    q|Q) 
        echo "Bye 👋."
        exit 0
        ;;

    *)
        echo "Invalid option. Try again."
        ;;
    esac
done