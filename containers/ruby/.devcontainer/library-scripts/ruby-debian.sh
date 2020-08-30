#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------

# Syntax: ./ruby-debian.sh [Ruby version] [non-root user] [Add rvm to rc files flag]

RUBY_VERSION=${1:-"stable"}
USERNAME=${2:-"vscode"}
UPDATE_RC=${3:-"true"}
INSTALL_RUBY_TOOLS=${6:-"true"}

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run a root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Treat a user name of "none" or non-existant user as root
if [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

DEFAULT_GEMS="rake ruby-debug-ide debase"
if [ "${RUBY_VERSION}" = "none" ]; then
    RVM_INSTALL_ARGS=""
else
    RVM_INSTALL_ARGS="-s \"${RUBY_VERSION}\" --ruby"
    if [ "${INSTALL_RUBY_TOOLS}" = "true" ]; then
        RVM_INSTALL_ARGS="${RVM_INSALL_ARGS} --with-default-gems=\"${DEFAULT_GEMS}\""
        SKIP_GEM_INSTALL="true"
    fi
fi

function updaterc() {
    if [ "${UPDATE_RC}" = "true" ]; then
        echo -e "$1" | tee -a /etc/bash.bashrc >> /etc/zsh/zshrc
    fi
}

export DEBIAN_FRONTEND=noninteractive

# Install curl, software-properties-common, build-essential, gnupg2 if missing
if ! dpkg -s curl ca-certificates software-properties-common build-essential gnupg2 > /dev/null 2>&1; then
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        apt-get update
    fi
    apt-get -y install --no-install-recommends curl ca-certificates software-properties-common build-essential gnupg2
fi

# Just install Ruby if RVM already installed
if [ -d "/usr/local/rvm" ]; then
    echo "Ruby Version Manager already exists."
    if [ "${RUBY_VERSION}" != "none" ]; then
        echo "Installing specified Ruby version."
        su ${USERNAME} -c "source /usr/local/rvm/scripts/rvm && rvm install ${RUBY_VERSION}"
    fi
else
    # Use a temporary locaiton for gpg keys to avoid polluting image
    export GNUPGHOME="/tmp/rvm-gnupg"
    mkdir -p ${GNUPGHOME}
    echo "disable-ipv6" >> ${GNUPGHOME}/dirmngr.conf
    gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB 2>&1
    # Install RVM
    curl -sSL https://get.rvm.io | bash ${RVM_INSTALL_ARGS} 2>&1
    usermod -aG rvm ${USERNAME}
    su ${USERNAME} -c "source /usr/local/rvm/scripts/rvm && rvm fix-permissions system"
    rm -rf ${GNUPGHOME}
fi
if [ "${INSTALL_RUBY_TOOLS}" = "true" ] && [ "${SKIP_GEM_INSTALL}" = "true" ]; then
    su ${USERNAME} -c "source /usr/local/rvm/scripts/rvm && gem install ${DEFAULT_GEMS}"
fi

# VS Code server usually first in the path, so silence annoying rvm warning (that does not apply) and then source it
updaterc "if ! grep rvm_silence_path_mismatch_check_flag \$HOME/.rvmrc > /dev/null 2>&1; then echo 'rvm_silence_path_mismatch_check_flag=1' >> \$HOME/.rvmrc; fi\nsource /usr/local/rvm/scripts/rvm"

# Clean up
source /usr/local/rvm/scripts/rvm
rvm cleanup all 
gem cleanup
echo "Done!"
