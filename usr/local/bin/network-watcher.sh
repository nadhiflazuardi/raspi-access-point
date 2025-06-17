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

ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE

    # --- wlan0 ---
    if [[ "$line" == *"wlan0"* ]]; then
        IS_AP_MODE=$(systemctl is-active hostapd)

        if [[ "$line" == *"state DOWN"* && "$LAST_WLAN0_STATE" != "DOWN" ]]; then
            LAST_WLAN0_STATE="DOWN"

            # Check eth0 too
            local eth_status=$(get_interface_status eth0)
            if [[ "$eth_status" == "down" ]]; then
                if acquire_lock; then
                    echo "[$(date)] wlan0 DISCONNECTED and eth0 is also down. Turning on access point..." >> $LOG_FILE
                    /usr/local/bin/start-raspi-ap
                    release_lock
                fi
            else
                echo "[$(date)] wlan0 down, but eth0 is up. No need to turn on AP." >> $LOG_FILE
            fi

        elif [[ "$line" == *"state UP"* && "$LAST_WLAN0_STATE" != "UP" ]]; then
            LAST_WLAN0_STATE="UP"
            
            if [[ "$IS_AP_MODE" == "active" ]]; then
                echo "[$(date)] wlan0 is UP but AP is active, skipping shutdown to avoid loop" >> $LOG_FILE
            else
                if acquire_lock; then
                    echo "[$(date)] wlan0 CONNECTED! Shutting down access point..." >> $LOG_FILE
                    /usr/local/bin/stop-raspi-ap
                    release_lock
                fi
            fi
        fi
    fi

    # --- eth0 ---
    if [[ "$line" == *"eth0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_ETH0_STATE" != "DOWN" ]]; then
            LAST_ETH0_STATE="DOWN"

            local wlan_status=$(get_interface_status wlan0)
            if [[ "$wlan_status" == "down" ]]; then
                if acquire_lock; then
                    echo "[$(date)] eth0 DISCONNECTED and wlan0 is also down. Turning on access point..." >> $LOG_FILE
                    /usr/local/bin/start-raspi-ap
                    release_lock
                fi
            else
                echo "[$(date)] eth0 down, but wlan0 is up. No need to turn on AP." >> $LOG_FILE
            fi

        elif [[ "$line" == *"state UP"* && "$LAST_ETH0_STATE" != "UP" ]]; then
            LAST_ETH0_STATE="UP"

            if acquire_lock; then
                echo "[$(date)] eth0 CONNECTED! Shutting down access point..." >> $LOG_FILE
                /usr/local/bin/stop-raspi-ap
                release_lock
            fi
        fi
    fi
done
