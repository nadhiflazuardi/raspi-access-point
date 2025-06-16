#!/bin/bash

CONFIG_FILE="/etc/raspi-ap/config.conf"

LOG_FILE="/var/log/netlink.log"

LAST_WLAN0_STATE=""
LAST_ETH0_STATE=""

STATIC_IP=$(grep "^STATIC_IP=" "$CONFIG_FILE" | cut -d '=' -f2)

get_ip() {
    local iface="$1"
    ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "N/A"
}

ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE

    # --- wlan0 ---
    if [[ "$line" == *"wlan0"* ]]; then
        CURRENT_IP=$(get_ip wlan0)

        if [[ "$line" == *"state DOWN"* && "$LAST_WLAN0_STATE" != "DOWN" ]]; then
            echo "[$(date)] wlan0 DISCONNECTED (IP: $CURRENT_IP)! Turning on access point..." >> $LOG_FILE
            /usr/local/bin/start-raspi-ap
            LAST_WLAN0_STATE="DOWN"
        elif [[ "$line" == *"state UP"* && "$LAST_WLAN0_STATE" != "UP" ]]; then
            if [[ "$CURRENT_IP" == "$STATIC_IP" ]]; then
                echo "[$(date)] wlan0 is UP with STATIC_IP ($STATIC_IP), skipping shutdown to avoid loop" >> $LOG_FILE
            else
                echo "[$(date)] wlan0 CONNECTED (IP: $CURRENT_IP)! Shutting down access point..." >> $LOG_FILE
                /usr/local/bin/stop-raspi-ap
            fi
            LAST_WLAN0_STATE="UP"
        fi
    fi

    # --- eth0 ---
    if [[ "$line" == *"eth0"* ]]; then
        CURRENT_IP=$(get_ip eth0)

        if [[ "$line" == *"state DOWN"* && "$LAST_ETH0_STATE" != "DOWN" ]]; then
            echo "[$(date)] eth0 DISCONNECTED (IP: $CURRENT_IP)! Turning on access point..." >> $LOG_FILE
            /usr/local/bin/start-raspi-ap
            LAST_ETH0_STATE="DOWN"
        elif [[ "$line" == *"state UP"* && "$LAST_ETH0_STATE" != "UP" ]]; then
            echo "[$(date)] eth0 CONNECTED (IP: $CURRENT_IP)! Shutting down access point..." >> $LOG_FILE
            /usr/local/bin/stop-raspi-ap
            LAST_ETH0_STATE="UP"
        fi
    fi
done
