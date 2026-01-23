#!/bin/bash
# Created by Diego Castro.
# Purpose: SMTP Authentication testing tool fo PPE support.

# To Do
# 1. Improve detection of attachment type
# 2. Consider adding command-line arguments. For now, interactive mode is sufficient for testing.
#    An .env file can be used to store the username and password, but the interactive `read` prompts
#    would need to be removed or made optional.
# Might need a .md file? Think its simple enough. Will see.

# Anyway nice way to learn Bash

# If something breaks, script stops
set -Eeuo pipefail
# For attachments so it wont mess up if contains spaces
IFS=$'\n\t'

port="587"

menu() {
cat <<'OPTIONS'

[1] Check SMTP Auth credentials.
[2] Send email WITHOUT attachment.
[3] Send email WITH attachment.
[4] Send spam email.
[5] Send virus email.
[6] Send email with the data from .eml.
[7] Send email with custom header.
[q] To quit. 👋

OPTIONS
}

email_info() {
    read -rep "Sender: " sender
    read -rep "Recipient: " rcpt
    read -rep "Subject: " subject
    read -rep "Body: " body
}

email_info_virus_spam() {
    read -rep "Sender: " sender
    read -rep "Recipient: " rcpt
    read -rep "Subject: " subject
}

email_info_content() {
    read -rep "Sender: " sender
    read -rep "Recipient: " rcpt
}

smtp_auth_info() {
    read -rep "Username: " username
    read -rep "Password: " passwd
    read -rep "Server: " server
}

location_attachment() {
    read -rep "attachment path (/home/user/Downloads/attachment): " attachment
}

location_data() {
    read -rep "Email path (/home/user/Downloads/eml): " data
}

send_email() {
    
    swaks \
    -f "$sender" \
    -t "$rcpt" \
    -s "$server" \
    -p "$port" \
    --tls \
    -a LOGIN \
    -au "$username" \
    -ap "$passwd" \
    --header "Subject: $subject" \
    --body "$body" \
    "$@"
}

send_email_data_content() {
    swaks \
    -f "$sender" \
    -t "$rcpt" \
    -s "$server" \
    -p "$port" \
    --tls \
    -a LOGIN \
    -au "$username" \
    -ap "$passwd" \
    "$@"
}

send_email_attachment() {
    location_attachment
    

    mime_type=$(file -b --mime-type "${attachment}")

    echo "Detected attachment type: $mime_type"

    send_email --attach "@$attachment" --attach-type "$mime_type"
    echo
}

send_spam() {
    body="XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X"
    send_email
}

send_virus() {
    body='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
    send_email
}

send_email_data() {
    email_info_content
    smtp_auth_info
    location_data
    send_email_data_content -d "@$data"
    echo
}

custom_header() {
    email_info
    smtp_auth_info
    ead -rep "Customer header: " header

    send_email --add-header "$header"
}

smtp_auth_creds() {
    smtp_auth_info
    
    local output

    if output=$(swaks \
        -s "$server" \
        -p "$port" \
        --tls \
        -a PLAIN \
        -au "$username" \
        -ap "$passwd" \
        --quit-after AUTH \
        --silent \
        2>&1
    ); then
        echo
        echo "SMTP credentials are valid"
    else
        echo
        echo "SMTP authentication failed"
    fi
}

while true; do
    menu

    read -rep "➤ Select an option [1 – 6 | q = quit]: " option
    echo

    case "$option" in
    1) 
        echo "Checking SMTP Auth credentials."
        echo
        smtp_auth_creds
        ;;

    2) 
        echo "Sending email."
        echo
        email_info
        smtp_auth_info
        send_email
        ;;

    3) 
        echo "Sending email with attachment."
        echo
        email_info
        smtp_auth_info
        send_email_attachment
        ;;

    4) 
        echo "Sending spam email."
        email_info_virus_spam
        smtp_auth_info
        send_spam
        ;;

    5) 
        echo "Sending virus email."
        email_info_virus_spam
        smtp_auth_info
        send_virus
        ;;

    6) 
        echo "Sending email with same data as eml."
        echo
        send_email_data
        ;;

    7)
        echo "Sending email with customer header"
        custom_header
        ;;

    q|Q) 
        echo
        echo "Bye 👋"
        echo
        exit 0
        ;;

    *) 
        echo
        echo "Invalid option, try again."
        echo
        ;;
  esac
done
