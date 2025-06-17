#!/bin/bash

CONFIG_FILE="/etc/raspi-ap/config.conf"
LOG_FILE="/var/log/netlink.log"
LOCK_FILE="/tmp/raspi-ap.lock"
STATE_FILE="/tmp/network_states"

# Initialize state file if it doesn't exist
if [[ ! -f "$STATE_FILE" ]]; then
    echo "LAST_WLAN0_STATE=" > "$STATE_FILE"
    echo "LAST_ETH_STATE=" >> "$STATE_FILE"
fi

# Function to read state from file
read_state() {
    source "$STATE_FILE"
}

# Function to write state to file
write_state() {
    echo "LAST_WLAN0_STATE=$LAST_WLAN0_STATE" > "$STATE_FILE"
    echo "LAST_ETH_STATE=$LAST_ETH_STATE" >> "$STATE_FILE"
}

# Dynamically detect Ethernet interface (eth0, end0, enx...)
get_eth_interface() {
    ip -o link show | awk -F': ' '{print $2}' | grep -E '^en[a-z0-9]*$' | head -n1
}

ETH_IFACE=$(get_eth_interface)

if [ -z "$ETH_IFACE" ]; then
    echo "[ERR] Could not detect Ethernet interface." >> $LOG_FILE
    exit 1
fi

# Check if interface is both UP and has a carrier (actually connected)
get_interface_status() {
    local iface="$1"
    
    # Check if interface exists
    if ! ip link show "$iface" &>/dev/null; then
        echo "down"
        return
    fi
    
    # Check if interface is UP and has carrier
    local state=$(ip link show "$iface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
    local carrier=""
    
    if [[ -f "/sys/class/net/$iface/carrier" ]]; then
        carrier=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null)
    fi
    
    if [[ "$state" == "UP" && "$carrier" == "1" ]]; then
        echo "up"
    else
        echo "down"
    fi
}

# Check if wlan0 is connected to a network (has IP)
is_wlan0_connected() {
    ip addr show wlan0 | grep -q "inet.*scope global" 2>/dev/null
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
    read_state
    LAST_WLAN0_STATE="DOWN"
    write_state

    local eth_status=$(get_interface_status "$ETH_IFACE")
    if [[ "$eth_status" != "down" ]]; then
        echo "[$(date)] wlan0 down, but $ETH_IFACE is up. No need to turn on access point." >> $LOG_FILE
        return
    fi

    acquire_lock || return
    echo "[$(date)] wlan0 DISCONNECTED and $ETH_IFACE is also down. Turning on access point..." >> $LOG_FILE
    /usr/local/bin/start-raspi-ap
    release_lock
}

handle_wlan0_up() {
    read_state
    LAST_WLAN0_STATE="UP"
    write_state
    
    # Give wlan0 a moment to potentially get an IP address
    sleep 2
    
    # Only shut down AP if wlan0 actually has internet connectivity
    if ! is_wlan0_connected; then
        echo "[$(date)] wlan0 UP but not connected to network, keeping access point active" >> $LOG_FILE
        return
    fi
    
    IS_AP_MODE=$(systemctl is-active hostapd 2>/dev/null)

    if [[ "$IS_AP_MODE" != "active" ]]; then
        echo "[$(date)] wlan0 connected but access point already inactive" >> $LOG_FILE
        return
    fi

    acquire_lock || return
    echo "[$(date)] wlan0 CONNECTED! Shutting down access point..." >> $LOG_FILE
    /usr/local/bin/stop-raspi-ap
    release_lock
}

handle_eth_down() {
    read_state
    LAST_ETH_STATE="DOWN"
    write_state

    local wlan_status=$(get_interface_status wlan0)
    if [[ "$wlan_status" != "down" ]] && is_wlan0_connected; then
        echo "[$(date)] $ETH_IFACE down, but wlan0 is up and connected. No need to turn on access point." >> $LOG_FILE
        return
    fi

    acquire_lock || return
    echo "[$(date)] $ETH_IFACE DISCONNECTED and wlan0 is also down. Turning on access point..." >> $LOG_FILE
    /usr/local/bin/start-raspi-ap
    release_lock
}

handle_eth_up() {
    read_state
    LAST_ETH_STATE="UP"
    write_state

    acquire_lock || return
    echo "[$(date)] $ETH_IFACE CONNECTED! Shutting down access point..." >> $LOG_FILE
    /usr/local/bin/stop-raspi-ap
    release_lock
}

# Main monitoring loop
ip monitor link | while read line; do
    echo "[$(date)] $line" >> $LOG_FILE
    read_state  # Read current state at the beginning of each iteration

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