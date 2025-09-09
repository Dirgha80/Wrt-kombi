#!/bin/bash
#================================================================================================
# Deskripsi: Build OpenWrt dengan Image Builder
# Copyright (C) 2021~ https://github.com/unifreq/openwrt_packit
# Copyright (C) 2021~ https://github.com/ophub/amlogic-s9xxx-openwrt
# Copyright (C) 2021~ https://downloads.openwrt.org/releases
# Copyright (C) 2023~ https://downloads.immortalwrt.org/releases
#
#
# Command: ./config/imagebuilder/imagebuilder.sh <source:branch> <target> [tunnel_option]
#           ./config/imagebuilder/imagebuilder.sh openwrt:21.02.3 x86_64 openclash
#
#
# Set default parameters
make_path="${PWD}"
openwrt_dir="imagebuilder"
imagebuilder_path="${make_path}/${openwrt_dir}"
custom_files_path="${make_path}/files"
custom_packages_path="${make_path}/packages"

# Set default parameters for colored output
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
#
#================================================================================================

# Encountered a serious error, abort the script execution
error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

# Fungsi untuk mengunduh paket eksternal
# USAGE: download_packages <source_type> <package_array>
download_packages() {
    local list=("${!2}")
    if [[ $1 == "github" ]]; then
        for entry in "${list[@]}"; do
            IFS="|" read -r filename base_url <<< "$entry"
            echo -e "${INFO} Processing file: $filename"
            # Menggunakan jq untuk parsing JSON lebih andal
            file_url=$(curl -s "$base_url" | jq -r '.[0].assets[] | select(.name | contains("'"$filename"'")) | .browser_download_url' | sort -V | tail -n 1)
            
            if [ -n "$file_url" ]; then
                echo -e "${INFO} Downloading $(basename "$file_url")"
                echo -e "${INFO} From $file_url"
                if curl -fsSL -o "$(basename "$file_url")" "$file_url" --max-time 60 --retry 3; then
                    echo -e "${SUCCESS} Package [$filename] downloaded successfully."
                else
                    error_msg "Failed to download package [$filename] from $file_url."
                fi
            else
                error_msg "Failed to retrieve packages [$filename] from $base_url."
            fi
        done
    elif [[ $1 == "custom" ]]; then
        for entry in "${list[@]}"; do
            IFS="|" read -r filename base_url <<< "$entry"
            echo -e "${INFO} Processing file: $filename"

            local file_url=""
            # Pola regex yang lebih spesifik
            local search_patterns=(
                "${filename}[_-][^\"/]*\.ipk"
                "${filename}_[^\"/]*\.ipk"
                "${filename}[^\"/]*\.ipk"
            )

            for pattern in "${search_patterns[@]}"; do
                file_url=$(curl -sL "$base_url" | grep -oE "$pattern" | sort -V | tail -n 1)
                if [ -n "$file_url" ]; then
                    file_url="${base_url}/${file_url}"
                    break
                fi
            done
            
            if [ -n "$file_url" ]; then
                echo -e "${INFO} Downloading $(basename "$file_url")"
                echo -e "${INFO} From $file_url"
                if curl -fsSL -O "$file_url" --max-time 60 --retry 3; then
                    echo -e "${SUCCESS} Package [$filename] downloaded successfully."
                else
                    error_msg "Failed to download package [$filename] from $file_url."
                fi
            else
                error_msg "No matching file found for [$filename] at $base_url."
            fi
        done
    fi
}

# USAGE:
# dl_zip_gh "githubuser/repo:branch" "path to extract"
dl_zip_gh() {
    if [[ "${1}" =~ ^([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)$ ]]; then
        github_user="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
        branch="${BASH_REMATCH[3]}"
        extract_path="${2}"
        
        target_dir="${extract_path%/}"
        
        [[ -d "${extract_path}" ]] && rm -rf "${extract_path}"
        mkdir -p "${target_dir}" || error_msg "Failed to create directory: ${target_dir}"

        zip_file="${target_dir}/${repo}-${branch}.zip"
        zip_url="https://github.com/${github_user}/${repo}/archive/refs/heads/${branch}.zip"

        echo -e "${INFO} Downloading ZIP from: ${zip_url}"
        if ! curl -fsSL -o "${zip_file}" "${zip_url}" --max-time 120 --retry 3; then
            error_msg "ZIP file not downloaded successfully from ${zip_url}."
        fi

        echo -e "${INFO} ZIP file downloaded to: ${zip_file}"

        extracted_dir="${target_dir}/${repo}-${branch}"
        if [[ -d "${extracted_dir}" ]]; then
            rm -rf "${extracted_dir}"
        fi
        
        echo -e "${INFO} Extracting ${zip_file} to ${target_dir}..."
        unzip -q "${zip_file}" -d "${target_dir}" || error_msg "Failed to unzip file."

        if [[ -d "${extracted_dir}" ]]; then
            echo -e "${INFO} Moving extracted directory content to ${target_dir}..."
            shopt -s dotglob
            mv "${extracted_dir}"/* "${target_dir}/" || error_msg "Failed to move extracted files."
            shopt -u dotglob
            rmdir "${extracted_dir}"
        else
            error_msg "Extracted directory not found. Expected: ${extracted_dir}"
        fi

        echo -e "${INFO} Removing ZIP file: ${zip_file}"
        rm -f "${zip_file}"
        
        echo -e "${SUCCESS} Download and extraction complete. Directory created at: ${target_dir}"
    else
        error_msg "Invalid format. Usage: dl_zip_gh \"githubuser/repo:branch\" \"path to extract\""
    fi
}


# Downloading OpenWrt ImageBuilder
download_imagebuilder() {
    cd "${make_path}" || error_msg "Failed to change directory to ${make_path}"
    echo -e "${STEPS} Start downloading OpenWrt files..."

    case "${op_target}" in
        amlogic|AMLOGIC)
            op_target="amlogic"
            target_profile=""
            target_system="armsr/armv8"
            target_name="armsr-armv8"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_generic"
            ;;
        rpi-3)
            op_target="rpi-3"
            target_profile="rpi-3"
            target_system="bcm27xx/bcm2710"
            target_name="bcm27xx-bcm2710"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_cortex-a53"
            ;;
        rpi-4)
            op_target="rpi-4"
            target_profile="rpi-4"
            target_system="bcm27xx/bcm2711"
            target_name="bcm27xx-bcm2711"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_cortex-a72"
            ;;
        friendlyarm_nanopi-r2c|nanopi-r2c)
            op_target="nanopi-r2c"
            target_profile="friendlyarm_nanopi-r2c"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_generic"
            ;;
        friendlyarm_nanopi-r2s|nanopi-r2s)
            op_target="nanopi-r2s"
            target_profile="friendlyarm_nanopi-r2s"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_generic"
            ;;
        friendlyarm_nanopi-r4s|nanopi-r4s)
            op_target="nanopi-r4s"
            target_profile="friendlyarm_nanopi-r4s"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_generic"
            ;;
        xunlong_orangepi-r1-plus|orangepi-r1-plus)
            op_target="orangepi-r1-plus"
            target_profile="xunlong_orangepi-r1-plus"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_generic"
            ;;
        xunlong_orangepi-r1-plus-lts|orangepi-r1-plus-lts)
            op_target="orangepi-r1-plus-lts"
            target_profile="xunlong_orangepi-r1-plus-lts"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_1="arm64"
            ARCH_2="aarch64"
            ARCH_3="aarch64_generic"
            ;;
        generic|x86-64|x86_64)
            op_target="x86-64"
            target_profile="generic"
            target_system="x86/64"
            target_name="x86-64"
            ARCH_1="amd64"
            ARCH_2="x86_64"
            ARCH_3="x86_64"
            ;;
        *)
            error_msg "Unsupported target: ${op_target}"
            ;;
    esac
	
    local file_ext=""
    local tar_cmd=""
    local file_type=$(curl -sI "https://downloads.${op_sourse}.org/releases/${op_branch}/targets/${target_system}/" | head -n1 | grep -oE 'zst|xz|gz')
    
    case "${file_type}" in
        "zst")
            file_ext="tar.zst"
            tar_cmd="tar --zstd -xvf"
            ;;
        "xz")
            file_ext="tar.xz"
            tar_cmd="tar -xvJf"
            ;;
        *)
            error_msg "Unsupported file type or URL not found for op_branch: $op_branch"
            ;;
    esac

    download_file="https://downloads.${op_sourse}.org/releases/${op_branch}/targets/${target_system}/${op_sourse}-imagebuilder-${op_branch}-${target_name}.Linux-x86_64.${file_ext}"
    imagebuilder_file="${op_sourse}-imagebuilder-${op_branch}-${target_name}.Linux-x86_64.${file_ext}"

    if ! curl -fsSOL --retry 3 "${download_file}"; then
        error_msg "Download failed: [ ${download_file} ]"
    fi
    echo -e "${SUCCESS} Download Base ${op_branch} ${target_name} successfully!"

    if ! ${tar_cmd} "${imagebuilder_file}"; then
        error_msg "Failed to extract imagebuilder file."
    fi
    sync && rm -f "${imagebuilder_file}"
    mv -f *-imagebuilder-* "${openwrt_dir}" || error_msg "Failed to move extracted directory."

    sync && sleep 3
    echo -e "${INFO} [ ${make_path} ] directory status: $(ls -al 2>/dev/null)"
}

# Adjust related files in the ImageBuilder directory
adjust_settings() {
    cd "${imagebuilder_path}" || error_msg "Failed to change directory to ${imagebuilder_path}"
    echo -e "${STEPS} Start adjusting .config file settings..."

    local DTM=$(date '+%d-%m-%Y')
    
    if [ -f "${custom_files_path}/etc/uci-defaults/99-first-setup" ]; then
        sed -i "s|Ouc3kNF6|$DTM|g" "${custom_files_path}/etc/uci-defaults/99-first-setup"
    fi

    if [[ -s "repositories.conf" ]]; then
        sed -i '\|option check_signature| s|^|#|' repositories.conf
    fi

    if [[ -s "Makefile" ]]; then
        sed -i "s/install \$(BUILD_PACKAGES)/install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade/" Makefile
    fi

    if [[ -s ".config" ]]; then
        sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/" .config
        sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=1024/" .config

        if [ "$op_target" == "amlogic" ]; then
            sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
            sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
            sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
            sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
        fi

        if [ "$ARCH_2" == "x86_64" ]; then
            sed -i "s/CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/" .config
            sed -i "s/CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/" .config
        fi
    else
        echo -e "${INFO} [ ${imagebuilder_path} ] directory status: $(ls -al 2>/dev/null)"
        error_msg "There is no .config file in the [ ${download_file} ]"
    fi

    sync && sleep 3
    echo -e "${INFO} [ ${imagebuilder_path} ] directory status: $(ls -al 2>/dev/null)"
}

# Add custom packages
custom_packages() {
    cd "${imagebuilder_path}" || error_msg "Failed to change directory to ${imagebuilder_path}"
    echo -e "${STEPS} Start adding custom packages..."

    [[ -d "packages" ]] || mkdir -p packages
    if [[ -d "${custom_packages_path}" ]]; then
        cp -rf "${custom_packages_path}"/* packages
        echo -e "${INFO} [ packages ] directory status: $(ls packages -al 2>/dev/null)"
    else
        echo -e "${WARNING} No customized Packages were added."
    fi

    cd packages || error_msg "Failed to change directory to ${imagebuilder_path}/packages"

    declare -a github_packages
    declare -a other_packages

    if [ "$op_target" == "amlogic" ]; then
        github_packages+=("luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest")
    fi

    case "$TUNNEL_OPTION" in
        "openclash"|"openclash-passwall"|"nikki-openclash"|"all-tunnel")
            github_packages+=("luci-app-openclash|https://api.github.com/repos/tes-rep/OpenClash/releases")
            ;;
    esac

    case "$TUNNEL_OPTION" in
        "passwall"|"openclash-passwall"|"nikki-passwall"|"all-tunnel")
            github_packages+=("luci-app-passwall|https://api.github.com/repos/xiaorouji/openwrt-passwall/releases")
            ;;
    esac

    case "$TUNNEL_OPTION" in
        "nikki"|"nikki-passwall"|"nikki-openclash"|"all-tunnel")
            # Nikki
            other_packages+=("nikki|https://api.github.com/repos/rizkikotet-dev/OpenWrt-nikki-Mod/releases")
            other_packages+=("luci-app-nikki|https://api.github.com/repos/rizkikotet-dev/OpenWrt-nikki-Mod/releases")
            ;;
    esac
    
    local CURVER=$(echo "$op_branch" | awk -F. '{print $1"."$2}')
    other_packages+=(    
        "luci-app-internet-detector|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "internet-detector-mod-modem-restart|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "internet-detector|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "modemmanager-rpcd|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "luci-proto-modemmanager|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/luci"
        "libqmi|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "libmbim|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "modemmanager|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "sms-tool|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "tailscale|https://downloads.${op_sourse}.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "luci-app-modeminfo|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-tailscale|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-diskman|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "modeminfo|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "atinout|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-poweroff|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "xmm-modem|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-disks-info|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-temp-status|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-ramfree|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-3ginfo-lite|https://downloads.immortalwrt.org/releases/packages-$CURVER/$ARCH_3/luci"
        "modemband|https://downloads.immortalwrt.org/releases/packages-${op_branch}/$ARCH_3/packages"
        "luci-app-modemband|https://downloads.immortalwrt.org/releases/packages-${op_branch}/$ARCH_3/luci"
        "luci-app-sms-tool-js|https://downloads.immortalwrt.org/releases/packages-${op_branch}/$ARCH_3/luci"
        "luci-app-eqosplus|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
        "luci-app-tinyfilemanager|https://dl.openwrt.ai/packages-${CURVER}/$ARCH_3/kiddin9"
    )
    
    download_packages "github" github_packages[@]
    download_packages "custom" other_packages[@]
    
    # Download core OpenClash
    if [[ "$TUNNEL_OPTION" == *"openclash"* ]]; then
        echo -e "${STEPS} Start Clash Core Download !"
        core_dir="${custom_files_path}/etc/openclash/core"
        mkdir -p "${core_dir}"

        if [[ "$ARCH_3" == "x86_64" ]]; then
            clash_meta_file="mihomo-linux-amd64-compatible-alpha-smart"
        else
            clash_meta_file="mihomo-linux-arm64-alpha-smart"
        fi
        
        clash_meta_url=$(curl -s "https://api.github.com/repos/vernesong/mihomo/releases" | jq -r '.[0].assets[] | select(.name | contains("'"$clash_meta_file"'")) | .browser_download_url' | head -n 1)

        if [ -n "$clash_meta_url" ]; then
            echo -e "${INFO} Downloading OpenClash core from ${clash_meta_url}"
            if curl -fsSL -o "${core_dir}/clash_meta.gz" "${clash_meta_url}" --max-time 60 --retry 3; then
                gzip -d "${core_dir}/clash_meta.gz"
                echo -e "${SUCCESS} OpenClash core downloaded and extracted successfully."
            else
                error_msg "Failed to download OpenClash core."
            fi
        else
            error_msg "Failed to find OpenClash core download URL."
        fi
    fi

    echo -e "${INFO} Final packages in imagebuilder/packages:"
    ls -lh "${imagebuilder_path}/packages/"
    
    echo -e "${SUCCESS} Download and extraction All complete."
    sync && sleep 3
    echo -e "${INFO} [ packages ] directory status: $(ls -al 2>/dev/null)"
}


# Add custom packages, lib, theme, app and i18n, etc.
custom_config() {
    cd "${imagebuilder_path}" || error_msg "Failed to change directory to ${imagebuilder_path}"
    echo -e "${STEPS} Start adding custom config..."

    echo -e "${INFO} Downloading custom script"
    sync_time="https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh"
    clock="https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock"
    repair_ro="https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh"
    mount_hdd="https://raw.githubusercontent.com/frizkyiman/auto-mount-hdd/main/mount_hdd"

    curl -fsSL -o "${custom_files_path}/sbin/sync_time.sh" "${sync_time}"
    curl -fsSL -o "${custom_files_path}/usr/bin/clock" "${clock}"
    curl -fsSL -o "${custom_files_path}/root/install2.sh" "${repair_ro}"
    # curl -fsSL -o "${custom_files_path}/usr/bin/mount_hdd" "${mount_hdd}"

    echo -e "${INFO} All custom configuration setup completed!"
}

# Add custom files
custom_files() {
    cd "${imagebuilder_path}" || error_msg "Failed to change directory to ${imagebuilder_path}"
    echo -e "${STEPS} Start adding custom files..."

    if [[ -d "${custom_files_path}" ]]; then
        [[ -d "files" ]] || mkdir -p files
        cp -rf "${custom_files_path}"/* files || error_msg "Failed to copy custom files."

        sync && sleep 3
        echo -e "${INFO} [ files ] directory status: $(ls files -al 2>/dev/null)"
    else
        echo -e "${WARNING} No customized files were added."
    fi
}

# Tambahan paket Tunnel
OPENCLASH="coreutils-nohup bash dnsmasq-full curl ca-certificates ipset ip-full libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy luci-compat luci luci-base luci-app-openclash"
NIKKI="nikki luci-app-nikki"
PASSWALL="chinadns-ng dns2socks dns2tcp geoview hysteria ipt2socks microsocks naiveproxy simple-obfs sing-box tcping trojan-plus tuic-client v2ray-core v2ray-plugin xray-core xray-plugin v2ray-geoip v2ray-geosite luci-app-passwall"

# Fungsi memilih paket tunnel
handle_tunnel_option() {
    case "$1" in
        "openclash")
            PACKAGES+=" $OPENCLASH"
            ;;
        "passwall")
            PACKAGES+=" $PASSWALL"
            ;;
        "nikki")
            PACKAGES+=" $NIKKI"
            ;;
        "openclash-passwall")
            PACKAGES+=" $OPENCLASH $PASSWALL"
            ;;
        "nikki-passwall")
            PACKAGES+=" $NIKKI $PASSWALL"
            ;;
        "nikki-openclash")
            PACKAGES+=" $NIKKI $OPENCLASH"
            ;;
        "all-tunnel")
            PACKAGES+=" $OPENCLASH $PASSWALL $NIKKI"
            ;;
    esac
}

# Rebuild OpenWrt firmware
rebuild_firmware() {
    cd "${imagebuilder_path}" || error_msg "Failed to change directory to ${imagebuilder_path}"
    echo -e "${STEPS} Start building OpenWrt with Image Builder..."

    # Default packages
    PACKAGES="file lolcat kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 -kmod-usb-net-asix -kmod-usb-net-asix-ax88179 kmod-mii kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan uqmi kmod-usb3 kmod-usb-net-cdc-ether kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils kmod-usb-serial-qualcomm kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim modemmanager modemmanager-rpcd luci-proto-modemmanager libmbim libqmi usbutils luci-proto-mbim luci-proto-ncm kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-sierrawireless kmod-usb-ohci kmod-usb-serial-sierrawireless kmod-usb-uhci kmod-usb2 kmod-usb-ehci kmod-usb-net-ipheth usbmuxd libusbmuxd-utils libimobiledevice-utils usb-modeswitch kmod-nls-utf8 mbim-utils xmm-modem kmod-phy-broadcom kmod-phylib-broadcom kmod-tg3 iptables-nft coreutils-stty luci-app-base64 perl perlbase-essential perlbase-cpan perlbase-utf8 perlbase-time perlbase-xsloader perlbase-extutils perlbase-cpan coreutils-base64"
    
    PACKAGES+=" tailscale luci-app-tailscale luci-app-droidnet luci-app-ipinfo luci-theme-initials luci-theme-argon luci-app-argon-config luci-theme-hj jq"
    
    PACKAGES+=" luci-app-diskman smartmontools kmod-usb-storage kmod-usb-storage-uas ntfs-3g"
    
    PACKAGES+=" internet-detector luci-app-internet-detector internet-detector-mod-modem-restart vnstat2 vnstati2 netdata luci-app-netmonitor"
    
    PACKAGES+=" luci-theme-material"
    
    PACKAGES+=" php8 php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv php8-mod-mbstring"
    
    local misc=""
    if [ "$op_target" == "amlogic" ]; then
        misc+=" luci-app-amlogic ath9k-htc-firmware btrfs-progs hostapd hostapd-utils kmod-ath kmod-ath9k kmod-ath9k-common kmod-ath9k-htc kmod-cfg80211 kmod-crypto-acompress kmod-crypto-crc32c kmod-crypto-hash kmod-fs-btrfs kmod-mac80211 wireless-tools wpa-cli wpa-supplicant"
    elif [ "$op_target" == "rpi-4" ]; then
        misc+=" kmod-i2c-bcm2835 i2c-tools kmod-i2c-core kmod-i2c-gpio luci-app-oled"
    elif [ "$ARCH_2" == "x86_64" ]; then
        misc+=" kmod-iwlwifi iw-full pciutils"
    fi

    PACKAGES+=" $misc zram-swap adb parted losetup resize2fs luci luci-ssl block-mount luci-app-ramfree htop bash curl wget-ssl tar unzip unrar gzip jq luci-app-ttyd nano httping screen openssh-sftp-server"

    local EXCLUDED="-libgd"
    if echo "$op_branch" | grep -q "^24\."; then
        EXCLUDED+=" -dnsmasq" # Sesuai immortalwrt
    else
        EXCLUDED+=" -dnsmasq"
    fi

    if [ "${op_sourse}" == "immortalwrt" ]; then
        EXCLUDED+=" -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        if [ "$ARCH_2" == "x86_64" ]; then
            EXCLUDED+=" -kmod-usb-net-rtl8152-vendor"
        fi
    fi

    if [ -n "$TUNNEL_OPTION" ]; then
        echo "[INFO] Menambahkan paket tunnel: $TUNNEL_OPTION"
        handle_tunnel_option "$TUNNEL_OPTION"
    fi

    make clean
    make image PROFILE="${target_profile}" PACKAGES="${PACKAGES} ${EXCLUDED}" FILES="files"
    if [ $? -ne 0 ]; then
        error_msg "OpenWrt build failed. Check logs for details."
    else
        sync && sleep 3
        echo -e "${INFO} [ ${openwrt_dir}/bin/targets/*/* ] directory status: $(ls bin/targets/*/* -al 2>/dev/null)"
        echo -e "${SUCCESS} The rebuild is successful, the current path: [ ${PWD} ]"
    fi
}

# Show welcome message
echo -e "${STEPS} Welcome to Rebuild OpenWrt Using the Image Builder."
[[ -x "${0}" ]] || error_msg "Please give the script permission to run: [ chmod +x ${0} ]"
[[ -z "${1}" ]] && error_msg "Please specify the OpenWrt Branch, such as [ ${0} openwrt:22.03.3 x86-64 ]"
[[ -z "${2}" ]] && error_msg "Please specify the OpenWrt Target, such as [ ${0} openwrt:22.03.3 x86-64 ]"
[[ "${1}" =~ ^[a-z]{3,}:[0-9]+ ]] || echo "Incoming parameter format <source:branch> <target>: openwrt:22.03.3 x86-64 or openwrt:22.03.3 amlogic"
[[ "${2}" =~ ^[a-zA-Z0-9_-]+ ]] || echo "Incoming parameter format <source:branch> <target>: openwrt:22.03.3 x86-64 or openwrt:22.03.3 amlogic"

op_sourse="${1%:*}"
op_branch="${1#*:}"
op_target="${2}"
TUNNEL_OPTION="${3}"

echo -e "${INFO} Rebuild path: [ ${PWD} ]"
echo -e "${INFO} Rebuild Source: [ ${op_sourse} ], Branch: [ ${op_branch} ], Target: ${op_target}"
echo -e "${INFO} Server space usage before starting to compile: \n$(df -hT "${make_path}") \n"

# Perform related operations
download_imagebuilder
adjust_settings
custom_packages
custom_config
custom_files
rebuild_firmware

# Show server end information
echo -e "Server space usage after compilation: \n$(df -hT "${make_path}") \n"
# All process completed
wait
