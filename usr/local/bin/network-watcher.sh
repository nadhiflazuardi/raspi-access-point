#!/bin/bash

CONFIG_FILE="/etc/raspi-ap/config.conf"
LOG_FILE="/var/log/netlink.log"
LOCK_FILE="/tmp/raspi-ap.lock"

LAST_WLAN0_STATE=""
LAST_ETH_STATE=""

# Dynamically detect Ethernet interface (eth0, end0, enx...)
get_eth_interface() {
    ip -o link show | awk -F': ' '{print $2}' | grep -E '^e(n|th|nx)[0-9]*$' | head -n1
}

ETH_IFACE=$(get_eth_interface)

if [ -z "$ETH_IFACE" ]; then
    echo "[ERR] Could not detect Ethernet interface." >> $LOG_FILE
    exit 1
fi

get_interface_status() {
    local iface="$1"
    ip link show "$iface" | grep -q "state UP" && echo "up" || echo "down"
}

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        echo "[$(date)] Lock file exists, skipping action" >> $LOG_FILE
        return 1
    fi
    touch "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

handle_wlan0_down() {
    LAST_WLAN0_STATE="DOWN"

    local eth_status=$(get_interface_status "$ETH_IFACE")
    if [[ "$eth_status" != "down" ]]; then
        echo "[$(date)] wlan0 down, but $ETH_IFACE is up. No need to turn on AP." >> $LOG_FILE
        return
    fi

    acquire_lock || return
    echo "[$(date)] wlan0 DISCONNECTED and $ETH_IFACE is also down. Turning on access point..." >> $LOG_FILE
    /usr/local/bin/start-raspi-ap
    release_lock
}

handle_wlan0_up() {
    LAST_WLAN0_STATE="UP"
    IS_AP_MODE=$(systemctl is-active hostapd)

    if [[ "$IS_AP_MODE" == "active" ]]; then
        echo "[$(date)] wlan0 is UP but AP is active, skipping shutdown to avoid loop" >> $LOG_FILE
        return
    fi

    acquire_lock || return
    echo "[$(date)] wlan0 CONNECTED! Shutting down access point..." >> $LOG_FILE
    /usr/local/bin/stop-raspi-ap
    release_lock
}

handle_eth_down() {
    LAST_ETH_STATE="DOWN"

    local wlan_status=$(get_interface_status wlan0)
    if [[ "$wlan_status" != "down" ]]; then
        echo "[$(date)] $ETH_IFACE down, but wlan0 is up. No need to turn on AP." >> $LOG_FILE
        return
    fi

    acquire_lock || return
    echo "[$(date)] $ETH_IFACE DISCONNECTED and wlan0 is also down. Turning on access point..." >> $LOG_FILE
    /usr/local/bin/start-raspi-ap
    release_lock
}

handle_eth_up() {
    LAST_ETH_STATE="UP"

    acquire_lock || return
    echo "[$(date)] $ETH_IFACE CONNECTED! Shutting down access point..." >> $LOG_FILE
    /usr/local/bin/stop-raspi-ap
    release_lock
}

ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE

    # --- wlan0 ---
    if [[ "$line" == *"wlan0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_WLAN0_STATE" != "DOWN" ]]; then
            handle_wlan0_down
        elif [[ "$line" == *"state UP"* && "$LAST_WLAN0_STATE" != "UP" ]]; then
            handle_wlan0_up
        fi
    fi

    # --- eth ---
    if [[ "$line" == *"$ETH_IFACE"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_ETH_STATE" != "DOWN" ]]; then
            handle_eth_down
        elif [[ "$line" == *"state UP"* && "$LAST_ETH_STATE" != "UP" ]]; then
            handle_eth_up
        fi
    fi
done
