#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Subscription service validation
# ============================================================================

start_and_verify_service() {
    local server_ip="$1"
    local full_domain="$2"

    log_step "Starting 3X-UI service and validating inbounds"

    systemctl daemon-reload 2>/dev/null || true
    systemctl restart x-ui
    sleep 3

    if ! systemctl is-active --quiet x-ui; then
        log_error "3X-UI service failed to start. Checking journal logs..."
        journalctl -u x-ui -n 20 --no-pager
        return 1
    fi

    log_success "3X-UI service is active and running."

    local sub_port="${SUB_PORT:-2096}"
    local sub_path="${SUB_PATH:-/sub/}"
    [[ "$sub_path" != /* ]] && sub_path="/${sub_path}"
    [[ "$sub_path" != */ ]] && sub_path="${sub_path}/"

    # Assemble Subscription URLs (HTTPS over Cloudflare port 2096)
    SUB_URL_DOMAIN="https://${full_domain}:${sub_port}${sub_path}${CLIENT_SUB_ID}"
    SUB_URL_IP="https://${server_ip}:${sub_port}${sub_path}${CLIENT_SUB_ID}"

    log_info "Testing local subscription endpoint..."
    local check_sub
    check_sub="$(curl -k -s4m 5 "https://127.0.0.1:${sub_port}${sub_path}${CLIENT_SUB_ID}" \
        -H "Host: ${full_domain}" \
        -A "Happ/3.0" 2>/dev/null || true)"

    if [[ -n "$check_sub" ]]; then
        log_success "Subscription endpoint responded successfully."
    else
        log_warn "Subscription endpoint check had warnings. Client can still use direct VLESS links."
    fi

    return 0
}
