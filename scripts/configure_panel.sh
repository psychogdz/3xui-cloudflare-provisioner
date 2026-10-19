#!/usr/bin/env bash
# ============================================================================
# 3xui-cloudflare-provisioner - Direct Database Panel Provisioning
# ============================================================================

XUI_DB_PATH="/etc/x-ui/x-ui.db"

configure_panel_database() {
    local full_domain="$1"

    log_step "Configuring 3X-UI panel settings and credentials"

    if [[ ! -f "$XUI_DB_PATH" ]]; then
        # Try alternate path if /etc/x-ui doesn't have it
        if [[ -f "/usr/local/x-ui/x-ui.db" ]]; then
            XUI_DB_PATH="/usr/local/x-ui/x-ui.db"
        else
            log_error "Could not find x-ui.db database file."
            return 1
        fi
    fi

    # Generate dynamic random credentials if not explicitly set
    PANEL_USERNAME="${PANEL_USERNAME:-admin_$(random_lowercase 5)}"
    PANEL_PASSWORD="${PANEL_PASSWORD:-$(random_alphanumeric 24)}"
    PANEL_PORT="${PANEL_PORT:-2053}"
    PANEL_BASE_PATH="${PANEL_BASE_PATH:-/xui_$(random_lowercase 8)/}"
    SUB_PATH="${SUB_PATH:-/sub_$(random_lowercase 8)/}"
    PANEL_SECRET="$(random_alphanumeric 32)"

    # Format base path with leading and trailing slashes
    [[ "$PANEL_BASE_PATH" != /* ]] && PANEL_BASE_PATH="/${PANEL_BASE_PATH}"
    [[ "$PANEL_BASE_PATH" != */ ]] && PANEL_BASE_PATH="${PANEL_BASE_PATH}/"
    [[ "$SUB_PATH" != /* ]] && SUB_PATH="/${SUB_PATH}"
    [[ "$SUB_PATH" != */ ]] && SUB_PATH="${SUB_PATH}/"

    log_info "Generated Panel Username: ${PANEL_USERNAME}"
    log_info "Generated Panel Port: ${PANEL_PORT}"
    log_info "Generated Panel Base Path: ${PANEL_BASE_PATH}"

    # Backup database
    cp "$XUI_DB_PATH" "${XUI_DB_PATH}.bak"

    # Use official x-ui CLI for bcrypt password hashing and resetting 2FA
    local xui_bin=""
    for b in "/usr/local/x-ui/x-ui" "/usr/bin/x-ui"; do
        if [[ -x "$b" ]]; then
            xui_bin="$b"
            break
        fi
    done

    if [[ -n "$xui_bin" ]]; then
        log_info "Configuring panel credentials and resetting 2FA via official x-ui CLI..."
        "$xui_bin" setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" >/dev/null 2>&1 || true
        "$xui_bin" setting -resetTwoFactor >/dev/null 2>&1 || true
    fi

    # Direct SQLite updates via Python for custom paths and HTTPS subscription server
    python3 -c "
import sqlite3

db_path = '$XUI_DB_PATH'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Ensure 2FA is completely disabled in settings
c.execute(\"UPDATE settings SET value='false' WHERE key='twoFactorEnable'\")
c.execute(\"UPDATE settings SET value='' WHERE key='twoFactorToken'\")

# Update panel settings and enable HTTPS on subscription server
settings_map = {
    'webPort': '$PANEL_PORT',
    'webBasePath': '$PANEL_BASE_PATH',
    'secret': '$PANEL_SECRET',
    'subEnable': 'true',
    'subPort': '${SUB_PORT:-2096}',
    'subPath': '$SUB_PATH',
    'subDomain': '$full_domain',
    'subCertFile': '/etc/ssl/v2ray/cert.crt',
    'subKeyFile': '/etc/ssl/v2ray/cert.key'
}

for k, v in settings_map.items():
    c.execute(\"SELECT count(*) FROM settings WHERE key=?\", (k,))
    if c.fetchone()[0] > 0:
        c.execute(\"UPDATE settings SET value=? WHERE key=?\", (v, k))
    else:
        c.execute(\"INSERT INTO settings (key, value) VALUES (?, ?)\", (k, v))

conn.commit()
conn.close()
"

    chmod 600 "$XUI_DB_PATH"
    log_success "Database credentials and paths updated."
    return 0
}
