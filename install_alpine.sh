#!/bin/sh

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

[ $(id -u) -ne 0 ] && echo "\033[0;31mFatal error: \033[0m Please run this script with root privilege\n" && exit 1

if [ -f /etc/os-release ]; then
    . /etc/os-release
    release=$ID
elif [ -f /usr/lib/os-release ]; then
    . /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

check_musl_version() {
    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        musl_version=$(ldd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
        required_version="1.2.0"
        if [ "$(printf '%s\n' "$required_version" "$musl_version" | sort -V | head -n1)" != "$required_version" ]; then
            echo "${red}musl libc version $musl_version is too old! Required: 1.2.0 or higher${plain}"
            echo "Please upgrade Alpine to a newer version with musl >= 1.2.0."
            exit 1
        fi
        echo "musl libc version: $musl_version (meets requirement of 1.2.0+)"
    else
        echo "${red}musl libc not detected. This script requires musl-based system.${plain}"
        exit 1
    fi
}
check_musl_version

install_base() {
    case "$release" in
    alpine)
        apk update && apk add --no-cache wget curl tar tzdata
        ;;
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata
        ;;
    esac
}

install_x-ui() {
    cd /usr/local/

    if [ $# -eq 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/Suyunmeng/3x-ui-alpine/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^\"]+)".*/\1/')
        if [ -z "$tag_version" ]; then
            echo "${red}Failed to fetch x-ui version, it may be due to GitHub API restrictions, please try it later${plain}"
            exit 1
        fi
        echo "Got x-ui latest version: ${tag_version}, beginning the installation..."
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/Suyunmeng/3x-ui-alpine/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz || {
            echo "${red}Downloading x-ui failed, please be sure that your server can access GitHub ${plain}"
            exit 1
        }
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"
        if [ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]; then
            echo "${red}Please use a newer version (at least v2.3.5). Exiting installation.${plain}"
            exit 1
        fi
        url="https://github.com/Suyunmeng/3x-ui-alpine/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo "Beginning to install x-ui $1"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url} || {
            echo "${red}Download x-ui $1 failed, please check if the version exists ${plain}"
            exit 1
        }
    fi

    [ -e /usr/local/x-ui/ ] && [ -x /etc/init.d/x-ui ] && /etc/init.d/x-ui stop && rm -rf /usr/local/x-ui/

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm -f x-ui-linux-$(arch).tar.gz
    cd x-ui
    chmod +x x-ui

    case $(arch) in
        armv5|armv6|armv7)
            mv bin/xray-linux-$(arch) bin/xray-linux-arm
            chmod +x bin/xray-linux-arm
            ;;
    esac

    chmod +x x-ui bin/xray-linux-$(arch)
    cp -f x-ui.rc /etc/init.d/x-ui
    chmod +x /etc/init.d/x-ui
    rc-update add x-ui default
    /etc/init.d/x-ui start

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/Suyunmeng/3x-ui-alpine/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui

    echo "${green}x-ui ${tag_version}${plain} installation finished, it is running now..."
    echo ""
    echo "┌───────────────────────────────────────────────────────┐"
    echo "│  ${blue}x-ui control menu usages (subcommands):${plain}              │"
    echo "│                                                       │"
    echo "│  ${blue}x-ui${plain}              - Admin Management Script          │"
    echo "│  ${blue}x-ui start${plain}        - Start                            │"
    echo "│  ${blue}x-ui stop${plain}         - Stop                             │"
    echo "│  ${blue}x-ui restart${plain}      - Restart                          │"
    echo "│  ${blue}x-ui status${plain}       - Current Status                   │"
    echo "│  ${blue}x-ui settings${plain}     - Current Settings                 │"
    echo "│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │"
    echo "│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │"
    echo "│  ${blue}x-ui log${plain}          - Check logs                       │"
    echo "│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │"
    echo "│  ${blue}x-ui update${plain}       - Update                           │"
    echo "│  ${blue}x-ui legacy${plain}       - legacy version                   │"
    echo "│  ${blue}x-ui install${plain}      - Install                          │"
    echo "│  ${blue}x-ui uninstall${plain}    - Uninstall                        │"
    echo "└───────────────────────────────────────────────────────┘"
}

echo "${green}Running...${plain}"
install_base
install_x-ui "$1"
