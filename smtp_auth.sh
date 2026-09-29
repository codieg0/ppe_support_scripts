#!/usr/bin/env bash
# Created by Diego Castro - https://github.com/codieg0
# SMTP Authentication testing tool fo PPE support.

# To Do
# 1. Improve detection of attachment type
# 2. Consider adding command-line arguments. For now, interactive mode is sufficient for testing.
# Anyway nice way to learn Bash
# Done mostly by myself. Improved it using Claude.

# If something breaks, script stops
set -Eeuo pipefail
# For attachments so it wont mess up if contains spaces
IFS=$'\n\t'

# Colors/styling — disabled automatically when output isn't a real terminal
# (e.g. piped or redirected) or the terminal doesn't support them.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
    CYAN=$(tput setaf 6); YELLOW=$(tput setaf 3); GREEN=$(tput setaf 2); RED=$(tput setaf 1)
else
    BOLD=""; DIM=""; RESET=""; CYAN=""; YELLOW=""; GREEN=""; RED=""
fi

port="587"
custom_headers=()

# Clear sensitive vars whenever the script exits
cleanup() {
    unset username passwd
}
trap cleanup EXIT

# Ctrl+C / kill should actually close the script instead of just
# returning to the read prompt
on_interrupt() {
    echo
    echo "${CYAN}Interrupted, bye 👋${RESET}"
    exit 130
}
trap on_interrupt INT TERM

# Preflight: make sure required tools exist before we ever get to the menu
require_bin() {
    command -v "$1" >/dev/null 2>&1 || { echo "${RED}Error: '$1' is required but not installed.${RESET}"; exit 1; }
}
require_bin swaks
require_bin file

# Row helpers pad based on the PLAIN (uncolored) text length, so color codes
# never throw off the box alignment.
menu_title_row() {
    local text="$1" w="$2"
    local plain=" ${text}"
    local pad=$(( w - ${#plain} ))
    (( pad < 0 )) && pad=0
    printf '%s│%s %s%s%s%*s%s│%s\n' "$CYAN" "$RESET" "$BOLD" "$text" "$RESET" "$pad" "" "$CYAN" "$RESET"
}

menu_item_row() {
    local key="$1" label="$2" w="$3" color="${4:-$YELLOW}"
    local plain="  ${key}  ${label}"
    local pad=$(( w - ${#plain} ))
    (( pad < 0 )) && pad=0
    printf '%s│%s  %s%s%s  %s%*s%s│%s\n' "$CYAN" "$RESET" "$color" "$key" "$RESET" "$label" "$pad" "" "$CYAN" "$RESET"
}

menu() {
    local w=52
    local line; line=$(printf '─%.0s' $(seq 1 "$w"))

    echo
    printf '%s┌%s┐%s\n' "$CYAN" "$line" "$RESET"
    menu_title_row "Proofpoint Essentials — SMTP Auth Tester" "$w"
    printf '%s├%s┤%s\n' "$CYAN" "$line" "$RESET"
    menu_item_row "1" "Check SMTP Auth credentials" "$w"
    menu_item_row "2" "Send email WITHOUT attachment" "$w"
    menu_item_row "3" "Send email WITH attachment" "$w"
    menu_item_row "4" "Send spam email" "$w"
    menu_item_row "5" "Send virus email" "$w"
    menu_item_row "6" "Send email with the data from .eml" "$w"
    printf '%s├%s┤%s\n' "$CYAN" "$line" "$RESET"
    menu_item_row "q" "Quit" "$w" "$RED"
    printf '%s└%s┘%s\n' "$CYAN" "$line" "$RESET"
    echo
}

# Prints a bold, colored section header before each action runs.
step_header() {
    echo "${BOLD}${CYAN}▸ $1${RESET}"
    echo
}

ask_custom_headers() {
    custom_headers=()
    local header
    echo "${DIM}Add custom header(s)? Format 'Name: Value', blank line to finish.${RESET}"
    while true; do
        read -rep "Header (blank to skip/finish): " header
        [[ -z "$header" ]] && break
        if [[ "$header" != *:* ]]; then
            echo "${RED}Invalid format, expected 'Name: Value'.${RESET}"
            continue
        fi
        custom_headers+=(--header "$header")
    done
}

email_info() {
    read -rep "Sender: " sender
    read -rep "Recipient: " rcpt
    read -rep "Subject: " subject
    read -rep "Body: " body
    ask_custom_headers
}

email_info_virus_spam() {
    read -rep "Sender: " sender
    read -rep "Recipient: " rcpt
    read -rep "Subject: " subject
    ask_custom_headers
}

email_info_content() {
    read -rep "Sender: " sender
    read -rep "Recipient: " rcpt
    ask_custom_headers
}

select_server() {
    local choice
    while true; do
        echo "${BOLD}Select PPE server:${RESET}"
        echo "  ${YELLOW}[1]${RESET} US  (outbound-us1.ppe-hosted.com)"
        echo "  ${YELLOW}[2]${RESET} EU  (outbound-eu1.ppe-hosted.com)"
        read -rep "Choice [1-2]: " choice
        case "$choice" in
        1) server="outbound-us1.ppe-hosted.com"; break ;;
        2) server="outbound-eu1.ppe-hosted.com"; break ;;
        *) echo "${RED}Invalid choice, try again.${RESET}" ;;
        esac
    done
}

smtp_auth_info() {
    read -rep "Username: " username
    read -rep "Password: " passwd
    select_server
}

location_attachment() {
    while true; do
        read -rep "attachment path (/home/user/Downloads/attachment): " attachment
        [[ -f "$attachment" ]] && break
        echo "${RED}File not found: $attachment${RESET}"
    done
}

location_data() {
    while true; do
        read -rep "Email path (/home/user/Downloads/eml): " data
        [[ -f "$data" ]] && break
        echo "${RED}File not found: $data${RESET}"
    done
}

# Wrap swaks so a failed send/auth just returns to the menu instead of
# killing the whole script (we're running under set -e).
run_swaks() {
    if swaks "$@"; then
        return 0
    else
        echo "${RED}swaks command failed (see output above).${RESET}"
        return 1
    fi
}

send_email() {
    run_swaks \
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
    "${custom_headers[@]+"${custom_headers[@]}"}" \
    "$@" || true
}

send_email_data_content() {
    run_swaks \
    -f "$sender" \
    -t "$rcpt" \
    -s "$server" \
    -p "$port" \
    --tls \
    -a LOGIN \
    -au "$username" \
    -ap "$passwd" \
    "${custom_headers[@]+"${custom_headers[@]}"}" \
    "$@" || true
}

send_email_attachment() {
    location_attachment

    mime_type=$(file -b --mime-type "${attachment}")

    echo "${DIM}Detected attachment type: $mime_type${RESET}"

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
        2>&1
    ); then
        echo
        echo "$output" | grep -E '~> AUTH|<~.*(23[0-9]|53[0-9])' || true
        echo
        echo "${GREEN}✔ SMTP credentials are valid${RESET}"
    else
        echo
        echo "$output" | grep -E '~> AUTH|<~.*(23[0-9]|53[0-9])' || true
        echo
        echo "${RED}✘ SMTP authentication failed${RESET}"
    fi
}

while true; do
    menu

    read -rep "🐙 ${BOLD}Select an option${RESET} [1 – 6 | q = quit]: " option
    echo

    case "${option,,}" in
    1)
        step_header "Checking SMTP Auth credentials"
        smtp_auth_creds
        ;;
    2)
        step_header "Sending email"
        email_info
        smtp_auth_info
        send_email
        ;;
    3)
        step_header "Sending email with attachment"
        email_info
        smtp_auth_info
        send_email_attachment
        ;;
    4)
        step_header "Sending spam email"
        email_info_virus_spam
        smtp_auth_info
        send_spam
        ;;
    5)
        step_header "Sending virus email"
        email_info_virus_spam
        smtp_auth_info
        send_virus
        ;;
    6)
        step_header "Sending email with same data as eml"
        send_email_data
        ;;
    q)
        echo
        echo "${CYAN}Bye 👋${RESET}"
        echo
        exit 0
        ;;
    *)
        echo
        echo "${RED}Invalid option, try again.${RESET}"
        echo
        ;;
  esac
done