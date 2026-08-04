#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

APT_CONF_OPTS=(-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

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

function _apt_exec {
    if [[ -n ${APT_LOGFILE:-} ]]; then
        sudo apt-get "$@" >> "$APT_LOGFILE" 2>&1
    else
        sudo apt-get "$@"
    fi
}

function apt_retry {
    local attempt delay
    for attempt in 1 2 3 4 5; do
        if _apt_exec "$@"; then
            return 0
        fi
        if [[ $attempt -eq 5 ]]; then
            echo "ERROR: 'apt-get $*' failed after 5 attempts.${APT_LOGFILE:+ See $APT_LOGFILE}" >&2
            return 1
        fi
        delay=$((attempt * 15))
        echo "  network error, retrying in ${delay}s (attempt $attempt/5)..."
        sleep $delay
        _apt_exec --yes update || true
    done
}

function apt_install {
    apt_retry install -y -d "$@" || return 1
    apt_retry install -y "${APT_CONF_OPTS[@]}" "$@"
}

function apt_upgrade {
    apt_retry --yes -d upgrade || return 1
    apt_retry --yes "${APT_CONF_OPTS[@]}" upgrade
}
