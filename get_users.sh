#!/usr/bin/env bash
# Created by Diego Castro - https://github.com/codieg0
# For the Proofpoint Essentials support team
# Done mostly by myself. Improved it using Claude.

# Add your creds within the quotation marks
set -euo pipefail
 
# Credentials are collected interactively (see get_credentials) rather than
# hardcoded here, and the password is read silently.
username=""
password=""
domain=""
stack=""

# Colors/styling — disabled automatically when output isn't a real terminal
# (e.g. piped or redirected) or the terminal doesn't support them.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  CYAN=$(tput setaf 6); YELLOW=$(tput setaf 3); GREEN=$(tput setaf 2); RED=$(tput setaf 1)
else
  BOLD=""; DIM=""; RESET=""; CYAN=""; YELLOW=""; GREEN=""; RED=""
fi

# Tracks the temp file holding auth headers for the in-flight request, so it
# gets removed even if the script is interrupted (e.g. Ctrl-C) mid-request.
CURRENT_HEADER_FILE=""
cleanup() {
  if [[ -n "$CURRENT_HEADER_FILE" && -f "$CURRENT_HEADER_FILE" ]]; then
    rm -f "$CURRENT_HEADER_FILE"
  fi
}
trap cleanup EXIT
 
get_credentials() {
  if [[ -z "$username" ]]; then
    read -rep "Username: " username
  fi
  if [[ -z "$password" ]]; then
    read -rsep "Password: " password
    echo
  fi
 
  while true; do
    read -rep "Enter domain (e.g. example.com): " domain
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] && break
    echo "Invalid domain: use only letters, digits, dots and hyphens." >&2
  done
 
  while true; do
    read -rep "Enter stack (e.g. us1): " stack
    [[ "$stack" =~ ^[A-Za-z0-9]+$ ]] && break
    echo "Invalid stack: use only letters and digits." >&2
  done
}
 

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
 
menu(){
  local w=48
  local line; line=$(printf '─%.0s' $(seq 1 "$w"))
 
  echo
  printf '%s┌%s┐%s\n' "$CYAN" "$line" "$RESET"
  menu_title_row "Proofpoint Essentials — User Export" "$w"
  printf '%s├%s┤%s\n' "$CYAN" "$line" "$RESET"
  menu_item_row "1" "End Users" "$w"
  menu_item_row "2" "Silent Users" "$w"
  menu_item_row "3" "Organizational Admins" "$w"
  menu_item_row "4" "Channel Admins" "$w"
  menu_item_row "5" "Functional Accounts" "$w"
  menu_item_row "6" "All Users Except Functional Accounts" "$w"
  menu_item_row "7" "All Users" "$w"
  printf '%s├%s┤%s\n' "$CYAN" "$line" "$RESET"
  menu_item_row "q" "Quit" "$w" "$RED"
  printf '%s└%s┘%s\n' "$CYAN" "$line" "$RESET"
  echo
}
 
# Sends credentials via a curl config file instead of -H, so they never show
# up as command-line arguments (and therefore never show up in `ps`).
users_endpoint() {
  local header_file
  header_file=$(mktemp) || { echo "${RED}Error: could not create temp file.${RESET}" >&2; return 1; }
  chmod 600 "$header_file"
  CURRENT_HEADER_FILE="$header_file"
 
  {
    printf 'header = "X-User: %s"\n' "$username"
    printf 'header = "X-Password: %s"\n' "$password"
  } > "$header_file"
 
  local response
  if ! response=$(curl -sS -f -K "$header_file" \
        "https://${stack}.proofpointessentials.com/api/v1/orgs/${domain}/users"); then
    rm -f "$header_file"
    CURRENT_HEADER_FILE=""
    echo "${RED}Error: request to the Proofpoint Essentials API failed (check credentials, domain, and stack).${RESET}" >&2
    return 1
  fi
 
  rm -f "$header_file"
  CURRENT_HEADER_FILE=""
  printf '%s' "$response"
}
 
# mode is either a specific user "type" value from the API, or one of the
# special modes "all" / "all_no_functs".
general_jq() {
  local mode="$1"
  local output_file="$2"
  local data
 
  data=$(users_endpoint) || return 1
 
  local filter
  case "$mode" in
    all)
      filter='(.users[] | select(.is_active == true) | [.firstname, .surname, .primary_email, .type])'
      ;;
    all_no_functs)
      filter='(.users[] | select(.is_active == true and .type != "functional_account") | [.firstname, .surname, .primary_email, .type])'
      ;;
    *)
      filter='(.users[] | select(.is_active == true and .type == $user) | [.firstname, .surname, .primary_email, .type])'
      ;;
  esac
 
  if ! printf '%s' "$data" | jq -r --arg user "$mode" \
        "[\"First Name\", \"Last Name\", \"Email Address\", \"Type\"], ${filter} | @csv" \
        > "$output_file"; then
    echo "${RED}Error: failed to parse the API response as JSON.${RESET}" >&2
    rm -f "$output_file"
    return 1
  fi
}
 
# Backs up an existing report instead of silently overwriting it.
protect_existing_file() {
  local path="$1"
  if [[ -e "$path" ]]; then
    local backup="${path%.csv}.bak-$(date +%Y%m%d-%H%M%S).csv"
    mv "$path" "$backup"
    echo "${DIM}Existing '$path' found — backed up to '$backup'.${RESET}"
  fi
}
 
generate_report() {
  local mode="$1"
  local prefix="$2"
 
  echo
  get_credentials
  echo
 
  local output_file="${prefix}-${domain}.csv"
  protect_existing_file "$output_file"
 
  if general_jq "$mode" "$output_file"; then
    echo "${GREEN}✔ Wrote $output_file${RESET}"
  else
    echo "${RED}✘ Failed to generate report; no file written.${RESET}" >&2
  fi
}
 
end_user()      { generate_report "end_user" "end_users"; }
silent_user()   { generate_report "silent_user" "silent_users"; }
org_admin()     { generate_report "organization_admin" "org_admins"; }
channel_admin() { generate_report "channel_admin" "channel_admins"; }
funct_acc()     { generate_report "functional_account" "funct_accounts"; }
all_no_functs() { generate_report "all_no_functs" "all_no_functs"; }
all()           { generate_report "all" "all"; }
 
while true; do
  menu
  read -rep "🐙 ${BOLD}Select an option${RESET} [1 – 7 | q]: " option
 
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
      echo "${CYAN}Bye 👋${RESET}"
      exit 0
      ;;
 
    *)
      echo
      echo "${RED}Invalid option. Please try again.${RESET}"
      ;;
  esac
done
