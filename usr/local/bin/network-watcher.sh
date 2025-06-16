#!/bin/bash

LOG_FILE="/var/log/netlink.log"

ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE

    # Detect DISCONNECT
    if [[ "$line" == *"wlan0"* && "$line" == *"state DOWN"* ]] || [[ "$line" == *"eth0"* && "$line" == *"state DOWN"* ]]; then
        echo "[$(date)] 🔌 Network disconnected! Turning on access point..." >> $LOG_FILE
        /usr/local/bin/start-raspi-ap
    fi

    # Detect CONNECT
    if [[ "$line" == *"wlan0"* && "$line" == *"state UP"* ]] || [[ "$line" == *"eth0"* && "$line" == *"state UP"* ]]; then
        echo "[$(date)] 🔗 Network connected! Shutting down access point..." >> $LOG_FILE
        /usr/local/bin/stop-raspi-ap
done
