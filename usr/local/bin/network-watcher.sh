#!/bin/bash

CONFIG_FILE="/etc/raspi-ap/config.conf"
LOG_FILE="/var/log/netlink.log"
LOCK_FILE="/tmp/raspi-ap.lock"

LAST_WLAN0_STATE=""
LAST_ETH0_STATE=""

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
            if acquire_lock; then
                echo "[$(date)] wlan0 DISCONNECTED! Turning on access point..." >> $LOG_FILE
                /usr/local/bin/start-raspi-ap
                release_lock
                LAST_WLAN0_STATE="DOWN"
            fi

        elif [[ "$line" == *"state UP"* && "$LAST_WLAN0_STATE" != "UP" ]]; then
            if [[ "$IS_AP_MODE" == "active" ]]; then
                echo "[$(date)] wlan0 is UP but AP is active, skipping shutdown to avoid loop" >> $LOG_FILE
            else
                if acquire_lock; then
                    echo "[$(date)] wlan0 CONNECTED! Shutting down access point..." >> $LOG_FILE
                    /usr/local/bin/stop-raspi-ap
                    release_lock
                    LAST_WLAN0_STATE="UP"
                fi
            fi
        fi
    fi

    # --- eth0 ---
    if [[ "$line" == *"eth0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_ETH0_STATE" != "DOWN" ]]; then
            if acquire_lock; then
                echo "[$(date)] eth0 DISCONNECTED! Turning on access point..." >> $LOG_FILE
                /usr/local/bin/start-raspi-ap
                release_lock
                LAST_ETH0_STATE="DOWN"
            fi

        elif [[ "$line" == *"state UP"* && "$LAST_ETH0_STATE" != "UP" ]]; then
            if acquire_lock; then
                echo "[$(date)] eth0 CONNECTED! Shutting down access point..." >> $LOG_FILE
                /usr/local/bin/stop-raspi-ap
                release_lock
                LAST_ETH0_STATE="UP"
            fi
        fi
    fi
done
