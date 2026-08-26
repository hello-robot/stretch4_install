#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

function apt_configure {
    {
        echo 'Acquire::Retries "5";'
        echo 'Acquire::http::Timeout "30";'
        echo 'Acquire::https::Timeout "30";'
        if [[ -n ${STRETCH_APT_PROXY:-} ]]; then
            echo "Acquire::http::Proxy \"$STRETCH_APT_PROXY\";"
        fi
    } | sudo tee /etc/apt/apt.conf.d/80-hello-robot-retries > /dev/null
}

function retry_cmd {
    local max_attempts=3
    local delay=5
    local attempt=1
    while true; do
        "$@" && return 0
        if (( attempt >= max_attempts )); then
            echo "ERROR: Command failed after $max_attempts attempts: $*"
            return 1
        fi
        echo "Attempt $attempt failed. Retrying in ${delay}s..."
        sleep $delay
        ((attempt++))
        ((delay *= 2))
    done
}
