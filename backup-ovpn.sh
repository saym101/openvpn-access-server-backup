#!/bin/bash

# ==============================================================================
# OpenVPN Access Server — Backup, Restore & Audit Tool
# Method: Official sqlite3 dump (.bak files) as per OpenVPN documentation
# https://openvpn.net/as-docs/tutorials/tutorial--configuration-backup.html
# ==============================================================================

### === CONFIGURATION === ###
BACKUP_DIR="/backups/ovpn"
RSYNC_TARGET="/mnt/vpn-backup/"
OVPN_BASE="/usr/local/openvpn_as"
DB_DIR="${OVPN_BASE}/etc/db"
ETC_DIR="${OVPN_BASE}/etc"
SERVICE="openvpnas"
LOG_DIR="${BACKUP_DIR}/log"
# Separated declaration and assignment to satisfy SC2155
LOG_TIMESTAMP=$(date +%F_%H%M%S)
LOG_FILE="${LOG_DIR}/backup-ovpn-${LOG_TIMESTAMP}.log"
KEEP_ARCHIVES=10
KEEP_LOGS=10

# Email Settings
EMAIL_TO="info@exchample.com"
EMAIL_FROM="info@exchample.com"
SMTP_SERVER="smtp://mail.exchample.com:25"
SMTP_USER="info@exchample.com"
SMTP_PASS="your_pass!"

# List of DB files for backup
DB_FILES=("config.db" "certs.db" "userprop.db" "log.db" "config_local.db" "cluster.db" "notification.db")

# Create directories
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

### === LOGGING & NOTIFICATIONS === ###
log_info() {
    echo "$(date '+%F %T') [INFO] $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "$(date '+%F %T') [WARN] $1" | tee -a "$LOG_FILE" >&2
}

send_email() {
    local status="$1"
    local message="$2"
    local subject
    local current_date
    current_date=$(date +%F)
    subject="OpenVPN Backup Status: $status - $current_date"
    
    local html_body
    html_body="<html><body><h2>OpenVPN AS Report</h2><p><b>Status:</b> ${status}</p><p>${message}</p><p>Time: $(date '+%Y-%m-%d %H:%M:%S')</p></body></html>"

    {
        echo "From: $EMAIL_FROM"; echo "To: $EMAIL_TO"; echo "Subject: $subject"
        echo "MIME-Version: 1.0"; echo "Content-Type: text/html; charset=UTF-8"
        echo ""; echo "$html_body"
    } > /tmp/mail.txt

    curl --url "$SMTP_SERVER" --mail-from "$EMAIL_FROM" --mail-rcpt "$EMAIL_TO" \
         --upload-file /tmp/mail.txt --user "$SMTP_USER:$SMTP_PASS" \
         --silent --show-error --fail >> "$LOG_FILE" 2>&1
    rm -f /tmp/mail.txt
}

### === SERVICE CONTROL === ###
stop_service() {
    log_info "Stopping $SERVICE service..."
    systemctl stop "$SERVICE"
    sleep 3
}

start_service() {
    log_info "Starting $SERVICE service..."
    systemctl start "$SERVICE"
}

### === BACKUP ACTION === ###
archive_data() {
    log_info "Starting backup process..."
    local ts
    ts=$(date +'%Y%m%d-%H%M%S')
    local archive_name="back-openvpn-${ts}.tar.gz"
    local tmp_bak="/tmp/ovpn_bak_${ts}"
    
    mkdir -p "${tmp_bak}/db_dumps" "${tmp_bak}/etc_config"

    stop_service

    # 1. SQL Dumps
    for db in "${DB_FILES[@]}"; do
        if [[ -f "${DB_DIR}/${db}" ]]; then
            sqlite3 "${DB_DIR}/${db}" .dump > "${tmp_bak}/db_dumps/${db}.bak"
            log_info "  Dump created: $db"
        fi
    done

    # 2. Config Files (Excluding DBs and heavy EXE folder)
    rsync -a --exclude='db' --exclude='exe' "${ETC_DIR}/" "${tmp_bak}/etc_config/"
    log_info "  Configuration files copied (excluding /db and /exe)"

    start_service

    # 3. Compress
    tar -czf "${BACKUP_DIR}/${archive_name}" -C "${tmp_bak}" .
    
    # Rotation
    find "$BACKUP_DIR" -maxdepth 1 -name "back-openvpn-*.tar.gz" | sort | head -n -${KEEP_ARCHIVES} | xargs -r rm -f
    find "$LOG_DIR" -maxdepth 1 -name "backup-ovpn-*.log" | sort | head -n -${KEEP_LOGS} | xargs -r rm -f

    # Remote Sync
    if [[ -d "$RSYNC_TARGET" ]]; then
        rsync -av --delete "$BACKUP_DIR/" "$RSYNC_TARGET" >> "$LOG_FILE" 2>&1
        log_info "  Sync to $RSYNC_TARGET completed"
    fi

    log_info "Backup finished: $archive_name"
    send_email "SUCCESS" "Backup created and synced: $archive_name"
    rm -rf "$tmp_bak"
}

### === RESTORE ACTION === ###
restore_data() {
    log_info "Entering restoration mode..."
    mapfile -t backup_list < <(find "$BACKUP_DIR" -name "back-openvpn-*.tar.gz" | sort -r)
    
    if [[ ${#backup_list[@]} -eq 0 ]]; then
        echo "No backups found in $BACKUP_DIR"
        return
    fi

    echo "Available backups:"
    for i in "${!backup_list[@]}"; do
        echo "$i: $(basename "${backup_list[$i]}")"
    done

    read -r -p "Select backup number to restore: " choice
    local selected="${backup_list[$choice]}"
    if [[ -z "$selected" ]]; then echo "Invalid selection"; return; fi

    read -r -p "WARNING: This will overwrite current settings. Proceed? (y/n): " confirm
    [[ "$confirm" != "y" ]] && return

    local tmp_res_ts
    tmp_res_ts=$(date +%s)
    local tmp_res="/tmp/ovpn_res_${tmp_res_ts}"
    mkdir -p "$tmp_res"
    tar -xzf "$selected" -C "$tmp_res"

    stop_service

    # Restore configs
    cp -rp "${tmp_res}/etc_config/"* "${ETC_DIR}/"

    # Restore DBs from dumps
    for bak_file in "${tmp_res}/db_dumps"/*.db.bak; do
        local db_name
        db_name=$(basename "$bak_file" .bak)
        rm -f "${DB_DIR}/${db_name}"
        sqlite3 "${DB_DIR}/${db_name}" < "$bak_file"
        chmod 644 "${DB_DIR}/${db_name}"
        chown root:root "${DB_DIR}/${db_name}"
        log_info "  Restored: $db_name"
    done

    start_service
    log_info "Restoration completed from: $(basename "$selected")"
    rm -rf "$tmp_res"
}

### === AUDIT: USER ACTIVITY === ###
show_activity() {
    local RED='\033[0;31m'
    local YELLOW='\033[1;33m'
    local GREEN='\033[0;32m'
    local NC='\033[0m'

    echo -e "\nUser Activity Report (Sorted by Group & Name):"
    echo "--------------------------------------------------------------------------------"
    printf "%-25s | %-20s | %-15s | %-5s\n" "User" "Last Login" "Status" "Blk"
    echo "--------------------------------------------------------------------------------"

    local last_color=""

    sudo sqlite3 "$DB_DIR/userprop.db" "
    ATTACH DATABASE '$DB_DIR/log.db' AS alog;
    SELECT 
        p.name, 
        COALESCE(datetime(max(l.timestamp), 'unixepoch', 'localtime'), 'Never'),
        CASE 
            WHEN c.value = 'true' THEN 'BLOCKED'
            WHEN l.timestamp IS NULL THEN 'NEW'
            WHEN (strftime('%s','now') - max(l.timestamp)) > 2592000 THEN 'INACTIVE'
            ELSE 'ACTIVE'
        END,
        CASE WHEN c.value = 'true' THEN 'YES' ELSE 'NO' END,
        CASE 
            WHEN c.value = 'true' THEN '1'
            WHEN (strftime('%s','now') - max(l.timestamp)) > 2592000 OR l.timestamp IS NULL THEN '2'
            ELSE '3'
        END
    FROM profile p
    LEFT JOIN config c ON p.id = c.profile_id AND c.name = 'prop_deny'
    LEFT JOIN alog.log l ON p.name = l.username AND l.service='VPN'
    WHERE p.type != 'user_default'
    GROUP BY p.name
    ORDER BY 5 ASC, 1 ASC;" | while IFS='|' read -r name last_login status blocked color; do
        
        if [[ -n "$last_color" && "$last_color" != "$color" ]]; then
            echo ""
        fi
        last_color="$color"

        case $color in
            1) printf '%b' "${RED}" ;;
            2) printf '%b' "${YELLOW}" ;;
            3) printf '%b' "${GREEN}" ;;
        esac

        printf "%-25s | %-20s | %-15s | %-5s%b\n" "$name" "$last_login" "$status" "$blocked" "${NC}"
    done

    echo "--------------------------------------------------------------------------------"
    read -r -p "Press Enter to return to menu..."
}

### === ENTRY POINT === ###
if [[ ! -t 0 ]]; then
    archive_data
    exit 0
fi

while true; do
    echo -e "\n=============================="
    echo " OpenVPN AS Management Tool "
    echo "=============================="
    echo "  1. Backup Now"
    echo "  2. Restore from Backup"
    echo "  3. List Backups"
    echo "  4. Show User Activity"
    echo "  0. Exit"
    echo "------------------------------"
    read -r -p "Action: " choice

    case "$choice" in
        1) archive_data ;;
        2) restore_data ;;
        3) ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found." ;;
        4) show_activity ;;
        0) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done