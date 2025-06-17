#!/bin/bash

CONFIG_FILE="/etc/raspi-ap/config.conf"
LOG_FILE="/var/log/netlink.log"
LOCK_FILE="/tmp/raspi-ap.lock"

LAST_WLAN0_STATE=""
LAST_ETH0_STATE=""

get_interface_status() {
    local iface="$1"
    ip link show "$iface" | grep -q "state UP" && echo "up" || echo "down"
}

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        echo "[$(date)] Lock file exists, skipping action" >> $LOG_FILE
        return 1 # Lock file exists, skip action
    fi

    touch "$LOCK_FILE"
    return 0 # Lock file created successfully
}

release_lock() {
    rm -f "$LOCK_FILE"
}

handle_wlan0_down() {
    LAST_WLAN0_STATE="DOWN"
    
    local eth_status=$(get_interface_status eth0)
    if [[ "$eth_status" != "down" ]]; then
        echo "[$(date)] wlan0 down, but eth0 is up. No need to turn on AP." >> $LOG_FILE
        return
    fi
    
    acquire_lock || return
    echo "[$(date)] wlan0 DISCONNECTED and eth0 is also down. Turning on access point..." >> $LOG_FILE
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

handle_eth0_down() {
    LAST_ETH0_STATE="DOWN"
    
    local wlan_status=$(get_interface_status wlan0)
    if [[ "$wlan_status" != "down" ]]; then
        echo "[$(date)] eth0 down, but wlan0 is up. No need to turn on AP." >> $LOG_FILE
        return
    fi
    
    acquire_lock || return
    echo "[$(date)] eth0 DISCONNECTED and wlan0 is also down. Turning on access point..." >> $LOG_FILE
    /usr/local/bin/start-raspi-ap
    release_lock
}

handle_eth0_up() {
    LAST_ETH0_STATE="UP"
    
    acquire_lock || return
    echo "[$(date)] eth0 CONNECTED! Shutting down access point..." >> $LOG_FILE
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

    # --- eth0 ---
    if [[ "$line" == *"eth0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_ETH0_STATE" != "DOWN" ]]; then
            handle_eth0_down
        elif [[ "$line" == *"state UP"* && "$LAST_ETH0_STATE" != "UP" ]]; then
            handle_eth0_up
        fi
    fi
done