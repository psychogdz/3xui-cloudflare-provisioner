#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Summary and Credentials Dashboard
# ============================================================================

print_and_save_summary() {
    local server_ip="$1"
    local full_domain="$2"

    local cdn_port="${INBOUND_CDN_PORT:-443}"
    local grpc_port="${INBOUND_GRPC_PORT:-8443}"
    local reality_port="${INBOUND_REALITY_PORT:-2053}"
    local panel_port="${PANEL_PORT:-2053}"
    local base_path="${PANEL_BASE_PATH}"

    # Assembled VLESS URIs
    LINK_CDN_DOMAIN="vless://${CLIENT_UUID}@${full_domain}:${cdn_port}?encryption=none&host=${full_domain}&path=%2Fws&security=tls&sni=${full_domain}&type=ws#CF-CDN-Domain"
    LINK_CDN_CLEAN_IP="vless://${CLIENT_UUID}@104.21.71.170:${cdn_port}?encryption=none&host=${full_domain}&path=%2Fws&security=tls&sni=${full_domain}&type=ws#CF-CDN-CleanIP"
    LINK_GRPC_DOMAIN="vless://${CLIENT_UUID}@${full_domain}:${grpc_port}?encryption=none&security=tls&serviceName=grpc-service&sni=${full_domain}&type=grpc#CF-CDN-gRPC"
    LINK_REALITY="vless://${CLIENT_UUID}@${server_ip}:${reality_port}?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&security=reality&sid=${REALITY_SHORT_ID}&sni=${REALITY_SNI}&spx=%2F&type=tcp#Reality-Direct"

    PANEL_URL_IP="http://${server_ip}:${panel_port}${base_path}"
    PANEL_URL_DOMAIN="http://${full_domain}:${panel_port}${base_path}"

    # Format file output
    cat <<EOF > "$INFO_FILE"
================================================================================
                    3X-UI CLOUDFLARE PROVISIONER SUMMARY
================================================================================
Deployment Date: $(date '+%Y-%m-%d %H:%M:%S UTC')
Server IP:       ${server_ip}
Domain:          ${full_domain}

--------------------------------------------------------------------------------
1. 3X-UI MANAGEMENT PANEL
--------------------------------------------------------------------------------
Panel URL (IP):     ${PANEL_URL_IP}
Panel URL (Domain): ${PANEL_URL_DOMAIN}
Username:           ${PANEL_USERNAME}
Password:           ${PANEL_PASSWORD}
Port:               ${panel_port}
Base Path:          ${base_path}

--------------------------------------------------------------------------------
2. SUBSCRIPTION LINKS (Import in Happ, v2rayN, Streisand, etc.)
--------------------------------------------------------------------------------
Subscription (Domain): ${SUB_URL_DOMAIN}
Subscription (IP):     ${SUB_URL_IP}

--------------------------------------------------------------------------------
3. DIRECT VLESS CONFIGURATION LINKS
--------------------------------------------------------------------------------
[1] Cloudflare CDN VLESS-WebSocket (Recommended for Iran):
${LINK_CDN_DOMAIN}

[2] Cloudflare CDN VLESS-WebSocket (Using Tested Clean Anycast IP):
${LINK_CDN_CLEAN_IP}

[3] Cloudflare CDN VLESS-gRPC (Low Latency):
${LINK_GRPC_DOMAIN}

[4] Direct VLESS-Reality Vision:
${LINK_REALITY}

================================================================================
All configuration details saved securely to: ${INFO_FILE}
================================================================================
EOF

    chmod 600 "$INFO_FILE" 2>/dev/null || true

    # Print to terminal with colors
    printf "\n"
    printf "${BOLD}${GREEN}================================================================================${NC}\n"
    printf "${BOLD}${GREEN}              🎉 3X-UI CLOUDFLARE PROVISIONING COMPLETE! 🎉                     ${NC}\n"
    printf "${BOLD}${GREEN}================================================================================${NC}\n"
    printf "\n"
    printf "${BOLD}${CYAN}▶ PANEL ACCESS CREDENTIALS:${NC}\n"
    printf "  ${BOLD}Panel URL:${NC}       ${YELLOW}%s${NC}\n" "$PANEL_URL_IP"
    printf "  ${BOLD}Username:${NC}        ${YELLOW}%s${NC}\n" "$PANEL_USERNAME"
    printf "  ${BOLD}Password:${NC}        ${YELLOW}%s${NC}\n" "$PANEL_PASSWORD"
    printf "\n"
    printf "${BOLD}${CYAN}▶ SUBSCRIPTION URL:${NC}\n"
    printf "  ${GREEN}%s${NC}\n" "$SUB_URL_DOMAIN"
    printf "\n"
    printf "${BOLD}${CYAN}▶ READY-TO-USE VLESS CONFIGS (Copy & Paste into Happ / v2rayN):${NC}\n"
    printf "  ${BOLD}1. Cloudflare CDN VLESS-WS (Domain-based):${NC}\n"
    printf "     ${MAGENTA}%s${NC}\n\n" "$LINK_CDN_DOMAIN"
    printf "  ${BOLD}2. Cloudflare CDN VLESS-WS (Clean IP - Ultra Fast Connection):${NC}\n"
    printf "     ${MAGENTA}%s${NC}\n\n" "$LINK_CDN_CLEAN_IP"
    printf "  ${BOLD}3. Direct VLESS-Reality (Fallback):${NC}\n"
    printf "     ${MAGENTA}%s${NC}\n\n" "$LINK_REALITY"
    printf "${BOLD}${GREEN}================================================================================${NC}\n"
    printf " Credentials & configs saved to: ${BOLD}%s${NC} (chmod 600)\n" "$INFO_FILE"
    printf "${BOLD}${GREEN}================================================================================${NC}\n"
    printf "\n"
}
