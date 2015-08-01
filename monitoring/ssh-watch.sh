#!/bin/bash
#
# Check SSH connection.
#
# VERSION       :0.1.2
# DATE          :2015-07-30
# AUTHOR        :Viktor Szépe <viktor@szepe.net>
# URL           :https://github.com/szepeviktor/debian-server-tools
# LICENSE       :The MIT License (MIT)
# BASH-VERSION  :4.2+
# DEPENDS       :apt-get install bind9-host scanssh
# LOCATION      :/usr/local/bin/ssh-watch.sh
# CRON-HOURLY   :/usr/local/bin/ssh-watch.sh
# CONFIG        :/etc/sshwatchrc

# Usage
#
# Configuration syntax
#
#     SSH_WATCH=(
#       hostname:port
#       szepe.net:22
#     )
#
# Host names should have only DNS A records.

SKIP_HOST="qss.qupdate.net"
SKIP_UNTIL="2015-07-31 10:00"
ALERT_ADDRESS="admin@szepe.net"
INTERNET_IF="eth0"
# bix.he.net.
#     http://bix.hu/index.php?lang=en&op=full&page=stat&nodefilt=1
ALWAYS_ONLINE="193.188.137.175"
RETRY_TIME="40"

DAEMON="ssh-watch"
SSH_WATCH_RC="/etc/sshwatchrc"
SSH_WATCH=( )
source "$SSH_WATCH_RC"

Log() {
    local MESSAGE="$1"

    if tty --quiet; then
        echo "$MESSAGE" >&2
    else
        logger -t "${DAEMON}[$$]" "$MESSAGE"
    fi
}

Is_online() {
    if ! ping -c 5 -W 2 -n "$ALWAYS_ONLINE" 2>&1 | grep -q ", 0% packet loss,"; then
        Log "Server is OFFLINE."
        Alert "Not online" "pocket loss on pinging ${ALWAYS_ONLINE}"
        exit 100
    fi
}

Alert() {
    local SUBJECT="$1"

    Log "${SUBJECT} is DOWN"
#    echo "$*" | mailx -s "[${DAEMON}] SSH failure: ${SUBJECT}" "$ALERT_ADDRESS"
}

Is_online

# Check all hosts
for HOST in "${SSH_WATCH[@]}"; do
    HNAME="${HOST%%:*}"
    PORT="${HOST#*:}"
    declare -i RETRY="0"

    # May fail once by prepending "2/"
    if [ "${HNAME:0:2}" == "2/" ]; then
        HNAME="${HNAME:2}"
        HRETRY="1"
    fi

    # Skip a host
    [ -n "$SKIP_HOST" ] && [ -n "$SKIP_UNTIL" ] \
        && [ "$HNAME" == "$SKIP_HOST" ] \
        && [ $(date "+%s") -lt $(date --date="$SKIP_UNTIL" "+%s") ] \
        && continue

    if LC_ALL=C host -W 2 -t A "$HNAME" 2>&1 | grep -qv " has\( IPv4\)\? address "; then
        Alert "${HNAME}/A" \
            "Failed to get address of ${HNAME}"
        continue
    fi

    declare -i RETRY="$HRETRY"
    # Retry at most once
    while true; do
        scanssh -i "$INTERNET_IF" -n "$PORT" "$HNAME" 2>&1 | grep -q "^[0-9.]\+:${PORT} SSH-2\.0-OpenSSH_"
        SCAN_RET="$?"
        # Exit loop on successful scan or no more retries
        if [ "$SCAN_RET" == 0 ] || [ "$RETRY" == 0 ]; then
            break
        fi
        RETRY+="-1"
        sleep "$RETRY_TIME"
    done
    if [ "$SCAN_RET" != 0 ]; then
        Alert "${HNAME}/SSH" \
            "Failed to scan host ${HNAME} on SSH port ${PORT}"
        continue
    fi

    Log "${HNAME} OK"
    # Pause scans
    sleep 1
done

exit 0
