#!/usr/bin/env bash
# Created by Diego Castro - https://github.com/codieg0
# For PPE Support team
# Pulls the safelist/blocklist for all active users of a Proofpoint Essentials
#
# Usage:
#   ./users_sender_lists.sh [-d|--domain DOMAIN] [-s|--stack STACK] [-u|--username USER]
#   ./users_sender_lists.sh DOMAIN STACK
#
# Examples:
#   ./get_safe_block_lists.sh -d test.com -s eu1
#   ./get_safe_block_lists.sh test.com eu1
#
# Anything not supplied on the command line is prompted for interactively.
# Password is always prompted for (never accepted as an argument).
#
# Requires: curl, jq

set -euo pipefail

username=""
domain=""
stack=""

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [-d|--domain DOMAIN] [-s|--stack STACK] [-u|--username USER]
       $(basename "$0") DOMAIN STACK
 
  -d, --domain    Organization/domain to query
  -s, --stack     Essentials stack (e.g. us1, eu1)
  -u, --username  Essentials API username
  -h, --help      Show this help
EOF
}
 
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain) domain="$2"; shift 2 ;;
    -s|--stack) stack="$2"; shift 2 ;;
    -u|--username) username="$2"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    --) shift; positional+=("$@"); break ;;
    -*)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
    *) positional+=("$1"); shift ;;
  esac
done
 
# Positional fallback: DOMAIN STACK
if [[ -z "$domain" && ${#positional[@]} -ge 1 ]]; then domain="${positional[0]}"; fi
if [[ -z "$stack"  && ${#positional[@]} -ge 2 ]]; then stack="${positional[1]}"; fi
 
# --- Styling --------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4); CYAN=$(tput setaf 6)
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
fi
 
info()    { printf '%s➜%s %s\n' "$BLUE" "$RESET" "$1"; }
success() { printf '%s✔%s %s\n' "$GREEN" "$RESET" "$1"; }
warn()    { printf '%s⚠%s %s\n' "$YELLOW" "$RESET" "$1"; }
error()   { printf '%s✘%s %s\n' "$RED" "$RESET" "$1" >&2; }
rule()    { printf '%s%s%s\n' "$DIM" "──────────────────────────────────────────" "$RESET"; }
 
trap 'error "Something went wrong (line $LINENO). Aborting."' ERR
 
printf '\n%s%s Proofpoint Essentials — Safelist/Blocklist Export %s\n' "$BOLD" "$CYAN" "$RESET"
rule
 
# --- Dependency checks ------------------------------------------------------
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "'$cmd' is required but not installed."
    exit 1
  fi
done
 
# --- Prompts (only for whatever wasn't passed in) ----------------------
printf '%sEssentials API details:%s\n\n' "$BOLD" "$RESET"
 
if [[ -n "$username" ]]; then
  printf '%s  Username:%s %s\n' "$CYAN" "$RESET" "$username"
else
  read -r -p "$(printf '%s  Username:%s ' "$CYAN" "$RESET")" username
fi
 
read -r -s -p "$(printf '%s  Password:%s ' "$CYAN" "$RESET")" password
echo
 
if [[ -n "$domain" ]]; then
  printf '%s  Domain:  %s %s\n' "$CYAN" "$RESET" "$domain"
else
  read -r -p "$(printf '%s  Domain:  %s ' "$CYAN" "$RESET")" domain
fi
 
if [[ -n "$stack" ]]; then
  printf '%s  Stack:   %s %s\n' "$CYAN" "$RESET" "$stack"
else
  read -r -p "$(printf '%s  Stack:   %s ' "$CYAN" "$RESET")" stack
fi
echo
 
if [[ -z "$username" || -z "$password" || -z "$domain" || -z "$stack" ]]; then
  error "All fields are required."
  exit 1
fi
 
output_file="users_sender_lists-${domain}-${stack}.csv"
tmp_response="$(mktemp)"
trap 'rm -f "$tmp_response"' EXIT
 
rule
info "Contacting ${BOLD}${stack}.proofpointessentials.com${RESET} for org ${BOLD}${domain}${RESET}..."
 
http_code=$(curl -s -o "$tmp_response" -w "%{http_code}" \
  "https://${stack}.proofpointessentials.com/api/v1/orgs/${domain}/users" \
  -H "X-User: ${username}" \
  -H "X-Password: ${password}")
 
if [[ "$http_code" != "200" ]]; then
  error "API request failed with HTTP status $http_code"
  echo
  cat "$tmp_response" >&2 2>/dev/null || true
  exit 1
fi
 
success "Received response (HTTP $http_code)"
info "Parsing users and writing CSV..."
 
jq -r '
  ["First Name", "Last Name", "Email Address", "Type", "Safelist", "Blocklist"],
  (.users[]
    | select(.is_active == true)
    | [
        .firstname,
        .surname,
        .primary_email,
        .type,
        (.white_list_senders | join("; ")),
        (.black_list_senders | join("; "))
      ]
  ) | @csv
' "$tmp_response" > "$output_file"
 
row_count=$(($(wc -l < "$output_file") - 1))
 
rule
success "Done — ${BOLD}${row_count}${RESET}${GREEN} active user(s) exported${RESET}"
printf '%s  ↳ %s%s\n\n' "$DIM" "$output_file" "$RESET"
 