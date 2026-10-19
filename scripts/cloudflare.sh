#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Cloudflare API automation (DNS management)
# ============================================================================

CF_API_BASE="https://api.cloudflare.com/client/v4"

verify_cloudflare_token() {
    local token="$1"
    log_info "Verifying Cloudflare API token..."
    local resp
    resp="$(curl -s4 -X GET "${CF_API_BASE}/user/tokens/verify" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"

    local is_valid
    is_valid="$(python3 -c "
import sys, json
try:
    d = json.loads('''$resp''')
    print('true' if d.get('success') and d.get('result', {}).get('status') == 'active' else 'false')
except Exception:
    print('false')
")"

    if [[ "$is_valid" != "true" ]]; then
        log_error "Cloudflare API token verification failed. Please check the token permissions."
        return 1
    fi

    log_success "Cloudflare API token is active and valid."
    return 0
}

get_zone_id() {
    local token="$1"
    local domain="$2"

    local resp
    resp="$(curl -s4 -X GET "${CF_API_BASE}/zones?name=${domain}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"

    local zone_id
    zone_id="$(python3 -c "
import sys, json
try:
    d = json.loads('''$resp''')
    zones = d.get('result', [])
    if zones:
        print(zones[0]['id'])
    else:
        print('')
except Exception:
    print('')
")"

    if [[ -z "$zone_id" ]]; then
        log_error "Could not find Zone ID for domain: ${domain}. Ensure the domain exists in your Cloudflare account."
        return 1
    fi

    echo "$zone_id"
    return 0
}

setup_cloudflare_dns() {
    local token="$1"
    local zone_id="$2"
    local full_domain="$3"
    local server_ip="$4"

    log_step "Setting up Cloudflare DNS for ${full_domain} -> ${server_ip}"

    # Check if record already exists
    local check_resp
    check_resp="$(curl -s4 -X GET "${CF_API_BASE}/zones/${zone_id}/dns_records?type=A&name=${full_domain}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json")"

    local record_id
    record_id="$(python3 -c "
import sys, json
try:
    d = json.loads('''$check_resp''')
    records = d.get('result', [])
    if records:
        print(records[0]['id'])
    else:
        print('')
except Exception:
    print('')
")"

    local payload
    payload="$(python3 -c "
import json
print(json.dumps({
    'type': 'A',
    'name': '$full_domain',
    'content': '$server_ip',
    'ttl': 1,
    'proxied': True,
    'comment': 'Managed by 3xui-cloudflare-provisioner'
}))
")"

    local result_resp
    if [[ -n "$record_id" ]]; then
        log_info "Updating existing DNS A record (${record_id})..."
        result_resp="$(curl -s4 -X PUT "${CF_API_BASE}/zones/${zone_id}/dns_records/${record_id}" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$payload")"
    else
        log_info "Creating new proxied DNS A record..."
        result_resp="$(curl -s4 -X POST "${CF_API_BASE}/zones/${zone_id}/dns_records" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$payload")"
    fi

    local success
    success="$(python3 -c "
import sys, json
try:
    d = json.loads('''$result_resp''')
    print('true' if d.get('success') else 'false')
except Exception:
    print('false')
")"

    if [[ "$success" != "true" ]]; then
        log_error "Failed to configure DNS record in Cloudflare: ${result_resp}"
        return 1
    fi

    log_success "Cloudflare DNS configured: ${full_domain} -> ${server_ip} (CDN Proxied ☁️)"
    return 0
}
