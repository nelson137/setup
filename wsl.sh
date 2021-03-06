#!/bin/bash

if [[ "$EUID" != 0 ]]; then
    echo "This script must be run as root. Try 'sudo $0'" >&2
    exit 1
fi


dl_file() {
    local url='https://raw.githubusercontent.com/nelson137/setup/master'
    eval curl -sS "$url/files/$1" ${2:+>"${2%/}/$1"}
}


# Cache passwords
cache_passwds() {
    read -srp 'Github password: ' GITHUB_PASSWD
    echo
}


# Update, upgrade, and install packages
pkgs() {
    # Update and upgrade
    apt-get update
    apt-get dist-upgrade -y ||
        apt-get dist-upgrade -y --fix-missing
    apt-get upgrade -y

    # Make sure add-apt-repository is installed
    which add-apt-repository &>/dev/null ||
        apt-get install -y software-properties-common

    # PPAs
    add-apt-repository -y ppa:nextcloud-devs/client

    # Nodejs 8 setup
    curl -sSL https://deb.nodesource.com/setup_8.x | bash -

    # Installations
    apt-get install -y boxes build-essential cmake dnsutils figlet git \
        golang-go html-xml-utils jq libsecret-tools lolcat nmap nodejs \
        phantomjs pylint python3-pip python3-tk tmux vim zip zsh

    # Manually install youtube-dl because the repositories might be behind
    local url='https://yt-dl.org/downloads/latest/youtube-dl'
    curl -sSL "$url" -o /usr/local/bin/youtube-dl
    chmod a+rx /usr/local/bin/youtube-dl

    # Go installations
    su -c 'go get github.com/ericchiang/pup' nelson

    # Pip installations
    su -c 'python3 -m pip install --upgrade pip' nelson
    su -c '~nelson/.local/bin/pip3 install --user --no-warn-script-location \
        flake8 flake8-docstrings isort pycodestyle' nelson

    # Install figlet font files
    local -a fonts=(banner3 colossal nancyj roman univers)
    for f in "${fonts[@]}"; do
        if [[ ! -e /usr/share/figlet/${f}.flf ]]; then
            curl -sS "http://www.figlet.org/fonts/${f}.flf" \
                -o "/usr/share/figlet/${f}.flf"
        fi
    done
}


# User directory and environment
user() {
    cd ~nelson

    # File structure
    mkdir -p Downloads Projects .ssh
    git clone 'https://github.com/nelson137/.dot.git'

    # Config files
    local conf_files=(
        .vimrc .tmux.conf .zshrc .bashrc .bash_additions .bash_aliases
        .bash_functions
    )
    for cf in "${conf_files[@]}"; do
        ln -fs .dot/files/"$cf" .
    done
    ln -fs .dot/bin .

    # Oh My Zsh
    git clone --depth=1 'https://github.com/robbyrussell/oh-my-zsh.git' \
        ~nelson/.oh-my-zsh
    chsh -s /usr/bin/zsh nelson

    # Vim
    # - Install Vundle
    # - Install all Vundle plugins
    git clone 'https://github.com/VundleVim/Vundle.vim.git' \
        ~nelson/.vim/bundle/Vundle.vim
    vim +PluginInstall +qall

    # git
    # - Copy .gitconfig to ~nelson/
    # - Copy /usr/share/git-core/templates/ to ~nelson/.git_templates/
    # - Copy commit-msg to ~nelson/.git_templates/
    dl_file .gitconfig .
    cp -r /usr/share/git-core/templates/ .git_templates/
    dl_file commit-msg .git_templates/hooks/
    chmod a+x .git_templates/hooks/commit-msg
}


# Generate a new SSH key, replace the old Github key with the new one
git_ssh_key() {
    curl_git() {
        # Query Github API
        local url="https://api.github.com$1"
        shift
        curl -sSLiu "nelson137:$GITHUB_PASSWD" "$@" "$url"
    }

    # Generate SSH key
    yes y | ssh-keygen -t rsa -b 4096 -C 'nelson.earle137@gmail.com' \
        -f ~nelson/.ssh/id_rsa -N ''

    # Find the old WSL SSH key, delete it, upload the new one
    local -a key_ids=(
        $(curl_git '/users/nelson137/keys' | awk '/^\[/,/^\]/' | jq '.[].id')
    )
    local ssh_key="$(cat ~nelson/.ssh/id_rsa.pub)"
    for id in "${key_ids[@]}"; do
        local json="$(curl_git "/user/keys/$id" | awk '/^\{/,/^\}/')"
        if [[ $(echo "$json" | jq -r '.title') == WSL ]]; then
            curl_git "/user/keys/$id" -X DELETE
            break
        fi
    done
    curl_git '/user/keys' -d '{ "title": "Pop", "key": "'"$ssh_key"'" }'
}


# Root directory
root() {
    local files=(.bashrc .bash_additions .bash_aliases .bash_functions .vimrc)
    for f in "${files[@]}"; do
        ln -fs ~nelson/"$f" /root/
    done
    ln -fs ~nelson/bin /root/
}


cleanup() {
    # Make sure all files and directories in ~nelson are owned by nelson
    chown -R nelson:nelson ~nelson/
}


cache_passwds
pkgs
user
git_ssh_key
root
cleanup
