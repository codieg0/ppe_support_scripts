#!/usr/bin/env bash
# DOne by Diego Castro - https://github.com/codieg0
# For PPE Support team
# org_sender_lists.sh
# Pulls the Allow/Block sender lists for a Proofpoint Essentials tenant

set -euo pipefail

# Defining colors
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

info()  { printf '%s➜%s %s\n'  "$CYAN"  "$RESET" "$1"; }
ok()    { printf '%s✔%s %s\n'  "$GREEN" "$RESET" "$1"; }
warn()  { printf '%s⚠%s %s\n'  "$YELLOW" "$RESET" "$1"; }
fail()  { printf '%s✘%s %s\n'  "$RED"   "$RESET" "$1" >&2; exit 1; }

trap 'fail "Unexpected error on line $LINENO. Aborting."' ERR

banner() {
    local title="Proofpoint Essentials  |  Sender List Export"
    local pad=1
    local width=$(( ${#title} + pad * 2 ))
    local h_line
    h_line=$(printf '%.0s─' $(seq 1 "$width"))

    printf '\n%s%s┌%s┐%s\n'   "$BOLD" "$BLUE" "$h_line" "$RESET"
    printf '%s%s│%*s%s%*s│%s\n' "$BOLD" "$BLUE" "$pad" "" "$title" "$pad" "" "$RESET"
    printf '%s%s└%s┘%s\n\n'   "$BOLD" "$BLUE" "$h_line" "$RESET"
}

# Dependency checks
check_deps() {
    local missing=()
    for cmd in curl jq; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        fail "Missing required tool(s): ${missing[*]}. Please install and re-run."
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [-u username] [-d domain] [-s stack]

  -u  Username (skips the prompt)
  -d  Domain / org (skips the prompt)
  -s  Stack, e.g. us1, eu1 (skips the prompt)
  -h  Show this help

Password is always prompted interactively and is never accepted as a
command-line flag, so it can't leak into shell history or 'ps'.
EOF
}

username=""
domain=""
stack=""

parse_args() {
    while getopts ":u:d:s:h" opt; do
        case "$opt" in
            u) username="$OPTARG" ;;
            d) domain="$OPTARG" ;;
            s) stack="$OPTARG" ;;
            h) usage; exit 0 ;;
            :) fail "Option -$OPTARG requires an argument." ;;
            \?) fail "Unknown option: -$OPTARG (use -h for help)." ;;
        esac
    done
}

# Asking user (only for whatever wasn't already supplied via flags)
prompt_info() {
    if [[ -z "$username" ]]; then
        read -rep "$(printf '%sUsername:%s ' "$BOLD" "$RESET")" username
    fi
    [[ -n "$username" ]] || fail "Username cannot be empty."

    read -rsp "$(printf '%sPassword:%s ' "$BOLD" "$RESET")" password
    echo
    [[ -n "$password" ]] || fail "Password cannot be empty."

    if [[ -z "$domain" ]]; then
        read -rep "$(printf '%sDomain:%s ' "$BOLD" "$RESET")" domain
    fi
    [[ -n "$domain" ]] || fail "Domain cannot be empty."

    if [[ -z "$stack" ]]; then
        read -rep "$(printf '%sStack (e.g. us1, eu1):%s ' "$BOLD" "$RESET")" stack
    fi
    [[ -n "$stack" ]] || fail "Stack cannot be empty."
}

# API call
fetch_and_write() {
    local url="https://${stack}.proofpointessentials.com/api/v1/orgs/${domain}/sender-lists"
    local outfile="${OUTPUT_DIR:-.}/org_sender_list-${domain}-${stack}.csv"
    local tmp_body http_code

    info "Contacting ${DIM}${url}${RESET}"

    tmp_body="$(mktemp)"
    trap 'rm -f "$tmp_body"; trap - RETURN' RETURN

    http_code=$(curl -s -o "$tmp_body" -w '%{http_code}' \
        --connect-timeout 10 --max-time 30 \
        "$url" \
        -H "X-User: ${username}" \
        -H "X-Password: ${password}") || fail "Network request failed (curl error). Check stack/connectivity."

    # never let credentials linger in memory longer than needed
    unset password

    if [[ "$http_code" != "200" ]]; then
        fail "API returned HTTP ${http_code}. Check username, password, domain, and stack. Response: $(cat "$tmp_body" | head -c 300)"
    fi

    if ! jq -e . >/dev/null 2>&1 <"$tmp_body"; then
        fail "Response was not valid JSON. The stack or domain may be incorrect."
    fi

    if ! jq -e '(.allow_list // .block_list) != null' >/dev/null 2>&1 <"$tmp_body"; then
        warn "Response JSON did not contain 'allow_list' or 'block_list' keys — writing an empty CSV with headers only."
    fi

    jq -r '
        (.allow_list // []) as $A
        | (.block_list // []) as $B
        | ["Allow","Block"],
          ( [range(0; ([$A|length, $B|length] | max))][]
            | [ ($A[.] // ""), ($B[.] // "") ] )
        | @csv
    ' "$tmp_body" > "$outfile"

    local rows
    rows=$(($(wc -l < "$outfile") - 1))
    ok "Saved ${BOLD}${rows}${RESET} row(s) to ${BOLD}${outfile}${RESET}"
}

main() {
    banner
    check_deps
    parse_args "$@"
    prompt_info
    fetch_and_write
    printf '\n%sDone.%s\n' "$GREEN$BOLD" "$RESET"
}

main "$@"