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

# Adds the third party apt sources that Stretch's system packages come from
# (universe, Intel graphics PPA, ROS 2, NodeSource). Safe to run repeatedly.
function add_stretch_apt_sources {
    sudo apt-add-repository universe -y
    sudo add-apt-repository -y ppa:kobuk-team/intel-graphics

    # https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html
    if ! dpkg -s ros2-apt-source &> /dev/null; then
        local ros_apt_source_version
        ros_apt_source_version=$(curl -s --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 15 https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}')
        echo $ros_apt_source_version
        if [[ -z $ros_apt_source_version ]]; then
            echo "ERROR: could not reach the GitHub API to resolve the ros-apt-source version"
            return 1
        fi
        curl -L --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 15 -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ros_apt_source_version}/ros2-apt-source_${ros_apt_source_version}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
        sudo dpkg -i /tmp/ros2-apt-source.deb
    fi

    local node_major=24
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 15 https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg, arch=amd64] https://deb.nodesource.com/node_$node_major.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list

    retry_cmd sudo apt-get --yes update
}

# Answers postfix's install-time questions (pulled in by emacs) so apt stays non-interactive
function preseed_debconf {
    sudo bash -c 'echo "postfix postfix/mailname string my.hostname.example" | debconf-set-selections'
    sudo bash -c 'echo "postfix postfix/main_mailer_type string '\''Internet Site'\''" | debconf-set-selections'
}
