#!/bin/bash

CONFIG_FILE="/etc/raspi-ap/config.conf"
LOG_FILE="/var/log/netlink.log"

LAST_WLAN0_STATE=""
LAST_ETH0_STATE=""

ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE

    # --- wlan0 ---
    if [[ "$line" == *"wlan0"* ]]; then
        IS_AP_MODE=$(systemctl is-active hostapd)

        if [[ "$line" == *"state DOWN"* && "$LAST_WLAN0_STATE" != "DOWN" ]]; then
            echo "[$(date)] wlan0 DISCONNECTED! Turning on access point..." >> $LOG_FILE
            /usr/local/bin/start-raspi-ap
            LAST_WLAN0_STATE="DOWN"

        elif [[ "$line" == *"state UP"* && "$LAST_WLAN0_STATE" != "UP" ]]; then
            if [[ "$IS_AP_MODE" == "active" ]]; then
                echo "[$(date)] wlan0 is UP but AP is active, skipping shutdown to avoid loop" >> $LOG_FILE
            else
                echo "[$(date)] wlan0 CONNECTED! Shutting down access point..." >> $LOG_FILE
                /usr/local/bin/stop-raspi-ap
            fi
            LAST_WLAN0_STATE="UP"
        fi
    fi

    # --- eth0 ---
    if [[ "$line" == *"eth0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_ETH0_STATE" != "DOWN" ]]; then
            echo "[$(date)] eth0 DISCONNECTED! Turning on access point..." >> $LOG_FILE
            /usr/local/bin/start-raspi-ap
            LAST_ETH0_STATE="DOWN"

        elif [[ "$line" == *"state UP"* && "$LAST_ETH0_STATE" != "UP" ]]; then
            echo "[$(date)] eth0 CONNECTED! Shutting down access point..." >> $LOG_FILE
            /usr/local/bin/stop-raspi-ap
            LAST_ETH0_STATE="UP"
        fi
    fi
done
