#!/bin/bash

LOG_FILE="/var/log/netlink.log"

LAST_WLAN0_STATE=""
LAST_ETH0_STATE=""

ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE

    # --- wlan0 ---
    if [[ "$line" == *"wlan0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_WLAN0_STATE" != "DOWN" ]]; then
            echo "[$(date)] wlan0 disconnected! Turning on access point..." >> $LOG_FILE
            /usr/local/bin/start-raspi-ap
            LAST_WLAN0_STATE="DOWN"
        elif [[ "$line" == *"state UP"* && "$LAST_WLAN0_STATE" != "UP" ]]; then
            echo "[$(date)] wlan0 connected! Shutting down access point..." >> $LOG_FILE
            /usr/local/bin/stop-raspi-ap
            LAST_WLAN0_STATE="UP"
        fi
    fi

    # --- eth0 ---
    if [[ "$line" == *"eth0"* ]]; then
        if [[ "$line" == *"state DOWN"* && "$LAST_ETH0_STATE" != "DOWN" ]]; then
            echo "[$(date)] eth0 disconnected! Turning on access point..." >> $LOG_FILE
            /usr/local/bin/start-raspi-ap
            LAST_ETH0_STATE="DOWN"
        elif [[ "$line" == *"state UP"* && "$LAST_ETH0_STATE" != "UP" ]]; then
            echo "[$(date)] eth0 connected! Shutting down access point..." >> $LOG_FILE
            /usr/local/bin/stop-raspi-ap
            LAST_ETH0_STATE="UP"
        fi
    fi

done
