#!/bin/bash
# ----------------------------------------------------------------------
# Simple script to invoke logrotate at regular intervals
# ----------------------------------------------------------------------

LOGROTATE_BIN="logrotate"

STATE="/var/run/logrotate.state"
CONF="/etc/logrotate.conf"

export LOGROTATE_BIN STATE CONF

RUN_INTERVAL="3600"     # every hour

# helper functions for logging
export FMT="%a %b %d %Y %H:%M:%S GMT%z (%Z)"

# TODO: these functions better be provided by external, preferably shared script
function log_date() {
    echo "$(date +"$FMT"): $*"
}

# ----------------------------------------------------------------------
# Main loop of the logrotate service:
#
#   while True:
#       sleep N seconds
#       run logrotate
#
# ----------------------------------------------------------------------

function logrotate_loop() {

    trap on_terminate TERM INT

    local interval="${1}"

    log_date "===================================================="
    log_date
    log_date "logrotate service starting (pid=$$)"
    log_date "logrotate process will run every ${interval} seconds"

    while true; do

        current_time=$(date "+%s")
        next_run_time=$(( current_time + interval ))

        while (( current_time < next_run_time  ))
        do
            logrotate_sleep $(( next_run_time - current_time ))
            current_time=$(date "+%s")
        done

        logrotate_run
    done        
}

# helper function to execute logrotate and pass it the right parameters
function logrotate_run() {

    log_date "logrotate will run now"
    ${LOGROTATE_BIN} -s ${STATE} ${CONF}
}

# ----------------------------------------------------------------------
# Procedure to idle the execution for a number of seconds
#
# There are two requirements:
#
#   - export the PID of the sleep command so that it can be terminated
#     in case the logrotate service is being shutdown
#   - keep this (bash) process responsive to SIGTERM while in sleep
#     mode (normally the signal will be masked and will not be delivered
#     until the subprocess completes)
# ----------------------------------------------------------------------

proc_sleep_pid=""

function logrotate_sleep() {

    local sleep_interval=${1}

    log_date "logrotate will sleep for ${sleep_interval} seconds"            

    ( exec -a "logrotate: sleep" sleep ${sleep_interval} )&

    proc_sleep_pid=$!
    wait ${proc_sleep_pid}
}

# ----------------------------------------------------------------------
# Signal handler for logrotate service to make sure the process exits:
#
#   - properly by terminating the sleep process that is used to idle
#     the service
#   - gracefully by writing a message in the log
# ----------------------------------------------------------------------

function on_terminate() {

    log_date "logrotate will terminate"
    log_date

    kill -TERM ${proc_sleep_pid}
    exit 0
}

# ----------------------------------------------------------------------
#  main
# ----------------------------------------------------------------------

usage() {
    echo
    echo "usage: $0 [ -c logrotate-config-file ] [ -s logrotate-state-file ] < run interval in seconds >"
    echo
    echo "default values:"
    echo
    echo " - config-file: ${CONF}"
    echo " - state-file:  ${STATE}"
    echo
}

while getopts "c:s:" OPT; do
    case "${OPT}" in
        c )	CONF="${OPTARG}"	;;
        s ) STATE="${OPTARG}"	;;
        * ) usage; exit 1 		;;
    esac
done

shift $((OPTIND-1))

logrotate_loop ${1:-$RUN_INTERVAL}
