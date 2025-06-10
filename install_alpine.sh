#!/bin/sh

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[ "$EUID" -ne 0 ] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS and set release variable
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
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

check_musl_version() {
    musl_version=$(ldd --version 2>&1 | grep -oE 'musl[^ ]* [0-9]+\.[0-9]+(\.[0-9]+)?' | awk '{print $2}')
    if [ -z "$musl_version" ]; then
        echo -e "${red}musl libc not detected. This script requires musl libc >= 1.2.0${plain}"
        exit 1
    fi

    required_version="1.2.0"
    if [ "$(printf '%s\n' "$required_version" "$musl_version" | sort -V | head -n1)" != "$required_version" ]; then
        echo -e "${red}musl libc version $musl_version is too old! Required: 1.2.0 or higher${plain}"
        exit 1
    fi
    echo "musl libc version: $musl_version (meets requirement of 1.2.0+)"
}
check_musl_version

install_base() {
    case "${release}" in
    alpine)
        apk update && apk add --no-cache wget curl tar tzdata openrc bash
        ;;
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    *)
        echo -e "${red}Unsupported OS for OpenRC installation. Only Alpine is officially supported.${plain}"
        exit 1
        ;;
    esac
}

gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local server_ip=$(curl -s https://api.ipify.org)

    if [ ${#existing_webBasePath} -lt 4 ]; then
        if [ "$existing_hasDefaultCredential" = "true" ]; then
            local config_webBasePath=$(gen_random_string 15)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "Would you like to customize the Panel Port settings? [y/n]: " config_confirm
            if [ "$config_confirm" = "y" ] || [ "$config_confirm" = "Y" ]; then
                read -rp "Please set up the panel port: " config_port
            else
                config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}Generated random port: ${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "$config_username" -password "$config_password" -port "$config_port" -webBasePath "$config_webBasePath"
            echo -e "This is a fresh installation, generating random login info:"
            echo -e "${green}Username: $config_username${plain}"
            echo -e "${green}Password: $config_password${plain}"
            echo -e "${green}Port: $config_port${plain}"
            echo -e "${green}WebBasePath: $config_webBasePath${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
        else
            local config_webBasePath=$(gen_random_string 15)
            echo -e "${yellow}Missing WebBasePath. Generating...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "$config_webBasePath"
            echo -e "${green}New WebBasePath: $config_webBasePath${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [ "$existing_hasDefaultCredential" = "true" ]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)
            /usr/local/x-ui/x-ui setting -username "$config_username" -password "$config_password"
            echo -e "${green}New credentials set:${plain}"
            echo -e "${green}Username: $config_username${plain}"
            echo -e "${green}Password: $config_password${plain}"
        else
            echo -e "${green}Credentials and WebBasePath are valid. Skipping config.${plain}"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/

    if [ $# -eq 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/Suyunmeng/3x-ui-alpine/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [ -z "$tag_version" ] && echo -e "${red}Failed to fetch x-ui version${plain}" && exit 1
        echo -e "Latest version: ${tag_version}"
        wget -N -O x-ui.tar.gz https://github.com/Suyunmeng/3x-ui-alpine/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"
        if [ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]; then
            echo -e "${red}Minimum required version is v2.3.5${plain}"
            exit 1
        fi
        wget -N -O x-ui.tar.gz https://github.com/Suyunmeng/3x-ui-alpine/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    fi

    [ -e /usr/local/x-ui/ ] && /etc/init.d/x-ui stop && rm -rf /usr/local/x-ui/
    tar zxvf x-ui.tar.gz && rm -f x-ui.tar.gz
    cd x-ui
    chmod +x x-ui bin/xray-linux-$(arch)

    if [ "$(arch)" = "armv5" ] || [ "$(arch)" = "armv6" ] || [ "$(arch)" = "armv7" ]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi

    chmod +x x-ui bin/xray-linux-$(arch)
    wget -O /etc/init.d/x-ui https://raw.githubusercontent.com/Suyunmeng/3x-ui-alpine/main/x-ui.rc
    chmod +x /etc/init.d/x-ui
    rc-update add x-ui default
    rc-service x-ui start

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/Suyunmeng/3x-ui-alpine/main/x-ui.sh
    chmod +x /usr/bin/x-ui
    chmod +x /usr/local/x-ui/x-ui.sh

    config_after_install

    echo -e "${green}x-ui ${tag_version}${plain} installation finished, it is running now..."
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}Running...${plain}"
install_base
install_x-ui $1
