#!/usr/bin/env bash
# By Diego Castro - started this to learn Bash - have some basics...
# Improved by Claude
# For our PPE Support team
# PPE Domain Search

# Add your creds within the quotation marks
username=""
password=""

# Defining colors
# Colors from - https://unix.stackexchange.com/questions/124407/what-color-codes-can-i-use-in-my-bash-ps1-prompt
bold_red='\e[1;31m'
bold_green='\e[1;32m'
bold_cyan='\e[1;36m'
bold_yellow='\e[1;33m'
dark_gray='\e[1;30m'
ul_red='\e[4;31m'
endc='\e[0m'
 
# Always resolve DNS against Google's public resolver rather than whatever
# resolver is configured on the local machine, so results are consistent
# regardless of who runs this or what network they're on.
dns_server="8.8.8.8"
 
if [[ $# -ne 1 ]];then
    echo -e "Usage: stacks ${ul_red}domain.tld${endc}"
    exit 1
fi
 
# Declaring stacks array
stacks=("eu1" "us1" "us2" "us3" "us4" "us5" "usg1" "usg2")
 
# --- Boxed console output helpers --------------------------------------------
# Mirrors the .ps1 version's boxed output (Write-BoxTop/Write-BoxLine/etc) so
# results read as a bordered card instead of loose lines.
 
box_width=92
 
# Word-wraps $1 to width $2, printing one (plain, uncolored) line per output
# line. Long unbroken "words" (e.g. a long SPF/DMARC string) are hard-wrapped
# since they can't be split on spaces.
wrap_text() {
    local text=$1 width=$2
 
    if [[ -z "$text" ]]; then
        printf '\n'
        return
    fi
    if (( ${#text} <= width )); then
        printf '%s\n' "$text"
        return
    fi
 
    local -a words=($text)
    local current="" word candidate remaining
    for word in "${words[@]}"; do
        if (( ${#word} > width )); then
            [[ -n "$current" ]] && { printf '%s\n' "$current"; current=""; }
            remaining=$word
            while (( ${#remaining} > width )); do
                printf '%s\n' "${remaining:0:width}"
                remaining=${remaining:width}
            done
            current=$remaining
            continue
        fi
 
        candidate=$([[ -n "$current" ]] && echo "$current $word" || echo "$word")
        if (( ${#candidate} > width )) && [[ -n "$current" ]]; then
            printf '%s\n' "$current"
            current=$word
        else
            current=$candidate
        fi
    done
    [[ -n "$current" ]] && printf '%s\n' "$current"
}
 
box_top() {
    local title=$1
    if [[ -n "$title" ]]; then
        local text=" $title "
        local dashes=$(( box_width + 1 - ${#text} ))
        (( dashes < 1 )) && dashes=1
        printf "${dark_gray}┌─%s%s┐${endc}\n" "$text" "$(printf -- '─%.0s' $(seq 1 "$dashes"))"
    else
        printf "${dark_gray}┌%s┐${endc}\n" "$(printf -- '─%.0s' $(seq 1 $((box_width + 2))))"
    fi
}
 
box_divider() {
    printf "${dark_gray}├%s┤${endc}\n" "$(printf -- '─%.0s' $(seq 1 $((box_width + 2))))"
}
 
box_bottom() {
    printf "${dark_gray}└%s┘${endc}\n" "$(printf -- '─%.0s' $(seq 1 $((box_width + 2))))"
}
 
# A plain (unlabeled) line inside the box, optionally colored.
box_line() {
    local text=$1 color=${2:-} pad line
    while IFS= read -r line; do
        pad=$(( box_width - ${#line} ))
        (( pad < 0 )) && pad=0
        printf "${dark_gray}│ ${endc}"
        if [[ -n "$color" ]]; then printf "%b%s${endc}" "$color" "$line"; else printf "%s" "$line"; fi
        printf '%*s' "$pad" ""
        printf "${dark_gray} │${endc}\n"
    done < <(wrap_text "$text" "$box_width")
}
 
# A "Label: value" line inside the box; the value wraps and continuation
# lines are indented under it, matching the .ps1's Write-BoxLabelValue.
box_label_value() {
    local label=$1 value=$2 label_color=${3:-$bold_cyan} value_color=${4:-} pad line first=1
    local prefix_len=$(( ${#label} + 1 ))
    local avail=$(( box_width - prefix_len ))
    (( avail < 10 )) && avail=10
 
    while IFS= read -r line; do
        printf "${dark_gray}│ ${endc}"
        if (( first )); then
            printf "%b%s ${endc}" "$label_color" "$label"
            first=0
        else
            printf '%*s' "$prefix_len" ""
        fi
        if [[ -n "$value_color" ]]; then printf "%b%s${endc}" "$value_color" "$line"; else printf "%s" "$line"; fi
        pad=$(( box_width - prefix_len - ${#line} ))
        (( pad < 0 )) && pad=0
        printf '%*s' "$pad" ""
        printf "${dark_gray} │${endc}\n"
    done < <(wrap_text "$value" "$avail")
}
 
# --- DNS / RDAP lookups -------------------------------------------------------
# These run regardless of whether a stack/org match is found, so you always
# get MX/SPF/DMARC/age visibility on the domain that was searched.
 
# +timeout/+tries bound each query to ~2s instead of dig's default (5s x 3
# tries = up to 15s per query) — without this, a slow or filtered path to
# 8.8.8.8 (common on corporate networks/VPNs) makes every lookup crawl.
dig_opts=(+time=2 +tries=1)
 
mx_lookup() {
    local domain=$1
    dig "${dig_opts[@]}" +short @"${dns_server}" "${domain}" MX 2>/dev/null | sort -n
}
 
spf_lookup() {
    local domain=$1
    dig "${dig_opts[@]}" +short @"${dns_server}" "${domain}" TXT 2>/dev/null | tr -d '"' | grep -i '^v=spf1' | head -n1
}
 
dmarc_lookup() {
    local domain=$1
    dig "${dig_opts[@]}" +short @"${dns_server}" "_dmarc.${domain}" TXT 2>/dev/null | tr -d '"' | grep -i '^v=DMARC1' | head -n1
}
 
# RDAP is the structured, HTTPS-based successor to WHOIS. rdap.org resolves
# the right registry automatically for the TLD, so this works across TLDs
# without per-registry WHOIS parsing.
age_lookup() {
    local domain=$1
    local resp created=""
 
    # rdap.org 302-redirects to the actual registry's RDAP server, so -L is
    # required or the response body comes back empty. -4 avoids the slow
    # AAAA-then-A fallback some networks hit when IPv6 routing is broken.
    resp=$(curl -4 -sL --connect-timeout 5 --max-time 8 "https://rdap.org/domain/${domain}" 2>/dev/null)
    [[ -z "$resp" ]] && return
 
    if command -v jq >/dev/null 2>&1; then
        created=$(printf '%s' "$resp" | jq -r '(.events // [])[] | select(.eventAction=="registration") | .eventDate' 2>/dev/null | head -n1)
    fi
 
    if [[ -z "$created" ]]; then
        # No jq (or it found nothing) — fall back to plain Bash regex, since
        # the "eventAction" and "eventDate" keys can appear in either order.
        if [[ $resp =~ \"eventAction\":\"registration\"[^}]*\"eventDate\":\"([^\"]+)\" ]]; then
            created="${BASH_REMATCH[1]}"
        elif [[ $resp =~ \"eventDate\":\"([^\"]+)\"[^}]*\"eventAction\":\"registration\" ]]; then
            created="${BASH_REMATCH[1]}"
        fi
    fi
 
    printf '%s' "$created"
}
 
# Days between an RDAP registration timestamp (e.g. 1997-09-15T00:00:00Z) and
# now. Tries GNU date first, then falls back to BSD/macOS date syntax.
days_since() {
    local iso_date=$1
    local now_epoch created_epoch
 
    now_epoch=$(date +%s)
    created_epoch=$(date -d "$iso_date" +%s 2>/dev/null)
    if [[ -z "$created_epoch" ]]; then
        created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_date%Z}" +%s 2>/dev/null)
    fi
    [[ -z "$created_epoch" ]] && return
 
    echo $(( (now_epoch - created_epoch) / 86400 ))
}
 
# --- Field label helpers (mirroring the .ps1's Get-DeploymentTypeLabel /
# Get-PackageLabel) ------------------------------------------------------------
 
deployment_type_label() {
    local method=$1
    case "$method" in
        "") echo "Unknown" ;;
        mx_record) echo "MX Deployment" ;;
        api) echo "API Deployment" ;;
        journal) echo "Journal Deployment" ;;
        bcc) echo "BCC Deployment" ;;
        inline) echo "Inline Deployment" ;;
        *) echo "$method" ;;
    esac
}
 
package_label() {
    local pkg=$1
    if [[ -z "$pkg" ]]; then
        echo "Unknown"
        return
    fi
    # Titlecase and de-underscore so raw API values like "advanced_bundle"
    # read as "Advanced Bundle".
    pkg=${pkg//_/ }
    local out="" word
    for word in $pkg; do
        [[ -n "$word" ]] && out+="${word^} "
    done
    echo "${out% }"
}
 
# --- Boxed section builders ---------------------------------------------------
 
# One box per matched stack, mirroring the .ps1's per-result box.
build_stack_box() {
    local stack=$1 eid=$2 name=$3 primary_domain=$4 deployment_type=$5 package=$6 is_active=$7 url=$8
    local title=$stack
    [[ -n "$name" ]] && title="${stack} — ${name}"
 
    box_top "$title"
    box_label_value "EID:" "$eid"
    box_label_value "Stack:" "$stack"
    [[ -n "$name" ]] && box_label_value "Name:" "$name"
    [[ -n "$primary_domain" ]] && box_label_value "Primary Domain:" "$primary_domain"
    box_label_value "Deployment Type:" "$deployment_type"
    box_label_value "Package:" "$package"
    if [[ "$is_active" == "true" ]]; then
        box_label_value "Active:" "Yes" "$bold_cyan" "$bold_green"
    else
        box_label_value "Active:" "No" "$bold_cyan" "$bold_red"
    fi
    box_label_value "URL:" "$url" "$bold_cyan" "$bold_green"
    box_bottom
}
 
# One combined box for MX/SPF/DMARC/Domain Age, mirroring the .ps1's
# "DNS & Domain Info" box.
print_dns_and_age_info() {
    local domain=$1 mxfile=$2 spffile=$3 dmarcfile=$4 agefile=$5
    local mx_records spf_record dmarc_record created days years
 
    mx_records=$(cat "$mxfile" 2>/dev/null)
    spf_record=$(cat "$spffile" 2>/dev/null)
    dmarc_record=$(cat "$dmarcfile" 2>/dev/null)
    created=$(cat "$agefile" 2>/dev/null)
 
    box_top "DNS & Domain Info — ${domain}"
 
    box_line "MX Records:" "$bold_cyan"
    if [[ -z "$mx_records" ]]; then
        box_line "  None found" "$bold_yellow"
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] && box_line "  $line"
        done <<< "$mx_records"
    fi
 
    box_divider
    box_line "SPF Record:" "$bold_cyan"
    if [[ -z "$spf_record" ]]; then
        box_line "  None found" "$bold_yellow"
    else
        box_line "  $spf_record"
    fi
 
    box_divider
    box_line "DMARC Record:" "$bold_cyan"
    if [[ -z "$dmarc_record" ]]; then
        box_line "  None found" "$bold_yellow"
    else
        box_line "  $dmarc_record"
    fi
 
    box_divider
    box_line "Domain Age:" "$bold_cyan"
    if [[ -z "$created" ]]; then
        box_line "  Unknown (RDAP lookup failed or no registration data)" "$bold_yellow"
    else
        days=$(days_since "$created")
        if [[ -z "$days" ]]; then
            box_line "  Unknown (could not parse registration date: $created)" "$bold_yellow"
        else
            years=$(( days / 365 ))
            box_line "  Registered ${created%%T*} (~${years} years, ${days} days)"
        fi
    fi
 
    box_bottom
}
 
domain_info() {
    local domain=$1
 
    local mxfile spffile dmarcfile resultfile domainsfile agefile
    mxfile=$(mktemp)
    spffile=$(mktemp)
    dmarcfile=$(mktemp)
    resultfile=$(mktemp)
    domainsfile=$(mktemp)
    agefile=$(mktemp)
 
    # Kick off the DNS + RDAP/age lookups in the background so they run
    # fully in parallel with the stack queries below, instead of waiting for
    # the stack queries to finish first (that serial hand-off — wait for all
    # 8 stacks, *then* start the RDAP call — was what made some domains feel
    # slow). Each writes to its own file and we explicitly wait on its PID
    # later instead of relying on a single blanket "wait".
    mx_lookup "$domain" > "$mxfile" 2>/dev/null &
    local mx_pid=$!
    spf_lookup "$domain" > "$spffile" 2>/dev/null &
    local spf_pid=$!
    dmarc_lookup "$domain" > "$dmarcfile" 2>/dev/null &
    local dmarc_pid=$!
    age_lookup "$domain" > "$agefile" 2>/dev/null &
    local age_pid=$!
 
    local pids=()
    for location in "${stacks[@]}"; do
        (
            response=$(curl -4 -s \
                --connect-timeout 3 \
                --max-time 5 \
                -X GET \
                -H "X-User: ${username}" \
                -H "X-Password: ${password}" \
                "https://${location}.proofpointessentials.com/api/v1/orgs/${domain}")
 
            # Fast Bash regex parsing (no grep/cut)
            if [[ $response =~ \"eid\":([0-9]+) ]]; then
                eid="${BASH_REMATCH[1]}"
                url="https://${location}.proofpointessentials.com/i/${eid}/dashboard"
 
                name=""
                [[ $response =~ \"name\":\"([^\"]*)\" ]] && name="${BASH_REMATCH[1]}"
 
                primary_domain=""
                [[ $response =~ \"primary_domain\":\"([^\"]*)\" ]] && primary_domain="${BASH_REMATCH[1]}"
 
                deployment_method=""
                [[ $response =~ \"deployment_method\":\"([^\"]*)\" ]] && deployment_method="${BASH_REMATCH[1]}"
                deployment_type=$(deployment_type_label "$deployment_method")
 
                licensing_package=""
                [[ $response =~ \"licensing_package\":\"([^\"]*)\" ]] && licensing_package="${BASH_REMATCH[1]}"
                package=$(package_label "$licensing_package")
 
                is_active="false"
                [[ $response =~ \"is_active\":(true|false) ]] && is_active="${BASH_REMATCH[1]}"
 
                # Build the whole box as one string and write it with a single
                # append so parallel stacks' boxes don't interleave line by line.
                block=$(build_stack_box "${location^^}" "$eid" "$name" "$primary_domain" "$deployment_type" "$package" "$is_active" "$url")
                printf '%s\n\n' "$block" >> "$resultfile"
 
                # Capture the account's confirmed primary domain (can differ
                # from what was typed, e.g. a searched alias/secondary domain)
                # so the age lookup below checks the real domain.
                [[ -n "$primary_domain" ]] && printf "%s\n" "$primary_domain" >> "$domainsfile"
            fi
        ) &
        pids+=("$!")
    done
 
    # Wait for every stack query to finish before deciding whether a match
    # was found.
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done
 
    if [[ -s "$resultfile" ]]; then
        cat "$resultfile"
    else
        printf "${bold_red}Domain not found${endc}\n\n"
    fi
 
    # Now wait for the DNS + age lookups, all of which have been running in
    # parallel with the stack queries since the start.
    wait "$mx_pid" "$spf_pid" "$dmarc_pid" "$age_pid" 2>/dev/null
 
    # The age lookup above used the typed domain. If a matched stack reports
    # a different confirmed primary domain (e.g. an alias/secondary domain
    # was searched), re-run the age lookup just for that one case — this is
    # the only path that adds extra wait time, and only when it actually
    # differs.
    local age_domain
    age_domain=$(head -n1 "$domainsfile" 2>/dev/null)
    if [[ -n "$age_domain" && "${age_domain,,}" != "${domain,,}" ]]; then
        age_lookup "$age_domain" > "$agefile" 2>/dev/null
    else
        age_domain=$domain
    fi
 
    print_dns_and_age_info "$domain" "$mxfile" "$spffile" "$dmarcfile" "$agefile"
    echo ""
 
    rm -f "$mxfile" "$spffile" "$dmarcfile" "$resultfile" "$domainsfile" "$agefile"
}
 
domain_info "$1"
