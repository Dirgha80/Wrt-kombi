#!/bin/bash
#================================================================================================
# Description: Build OpenWrt with Image Builder
# Copyright (C) 2021~ https://github.com/unifreq/openwrt_packit
# Copyright (C) 2021~ https://github.com/ophub/amlogic-s9xxx-openwrt
# Copyright (C) 2021~ https://downloads.openwrt.org/releases
# Copyright (C) 2023~ https://downloads.immortalwrt.org/releases
#
# Command: ./config/imagebuilder/imagebuilder.sh <source:branch> <target> [tunnel-option]
#          ./config/imagebuilder/imagebuilder.sh openwrt:21.02.3 x86_64 openclash-passwall
#
#
# Set default parameters
# Perbaikan: Menggunakan variabel yang lebih konsisten
readonly make_path="${PWD}"
readonly openwrt_dir="imagebuilder"
readonly imagebuilder_path="${make_path}/${openwrt_dir}"
readonly custom_files_path="${make_path}/files"
readonly custom_packages_path="${make_path}/packages"
# custom_scripts_file tidak digunakan, jadi dihapus untuk kejelasan.

# Perbaikan: Menggunakan 'readonly' untuk variabel statis
readonly STEPS="[\033[95m STEPS \033[0m]"
readonly INFO="[\033[94m INFO \033[0m]"
readonly SUCCESS="[\033[92m SUCCESS \033[0m]"
readonly WARNING="[\033[93m WARNING \033[0m]"
readonly ERROR="[\033[91m ERROR \033[0m]"
#
#================================================================================================

# Encountered a serious error, abort the script execution
error_msg() {
    echo -e "${ERROR} ${1}" >&2  # Mengarahkan output ke stderr
    exit 1
}

# Perbaikan: Fungsi ini lebih ringkas dan menangani kegagalan dengan lebih baik.
# External Packages Download
download_packages() {
    local type="$1"
    local -n list=$2 # Menggunakan nameref untuk array
    local download_dir="${imagebuilder_path}/packages"
    mkdir -p "$download_dir"

    for entry in "${list[@]}"; do
        IFS="|" read -r filename base_url <<< "$entry"
        echo -e "${INFO} Processing file: $filename from $base_url"
        
        local file_url=""
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if [[ "$type" == "github" ]]; then
                file_url=$(curl -sL "$base_url" | grep "browser_download_url" | grep -oE "https.*/${filename}_[_0-9a-zA-Z\._~-]*\.ipk" | sort -V | tail -n 1)
            elif [[ "$type" == "custom" ]]; then
                file_url=$(curl -sL "$base_url" | grep -oE "\"${filename}[^\"]*?\.ipk\"|\"${filename}[^\"]*?\.apk\"|${filename}_.*?\.ipk|${filename}_.*?\.apk|${filename}.*?\.ipk|${filename}.*?\.apk" | sed 's/"//g' | sort -V | tail -n 1)
                # Perbaikan: Tambahkan full URL
                if [[ -n "$file_url" && "$file_url" != *"http"* ]]; then
                    file_url="${base_url}/${file_url}"
                fi
            fi

            if [[ -n "$file_url" ]]; then
                echo -e "${INFO} Downloading $(basename "$file_url"). Attempt $attempt..."
                if curl -fsSL --max-time 120 --retry 3 -o "${download_dir}/$(basename "$file_url")" "$file_url"; then
                    echo -e "${SUCCESS} Package [$(basename "$file_url")] downloaded successfully."
                    break # Keluar dari loop jika berhasil
                else
                    echo -e "${WARNING} Download failed for $(basename "$file_url") (Attempt $attempt)."
                    ((attempt++))
                    sleep 5
                fi
            else
                echo -e "${WARNING} No matching file found for [$filename] at $base_url. Attempt $attempt."
                ((attempt++))
                sleep 5
            fi
        done

        if [[ -z "$file_url" || ! -f "${download_dir}/$(basename "$file_url")" ]]; then
            error_msg "FAILED: Could not find or download $filename after $max_attempts attempts."
        fi
    done
}

# USAGE:
# dl_zip_gh "githubuser/repo:branch" "path to extract"
dl_zip_gh() {
    if [[ ! "${1}" =~ ^([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)$ ]]; then
        error_msg "Invalid format. Usage: dl_zip_gh \"githubuser/repo:branch\" \"path to extract\""
    fi

    local github_user="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    local branch="${BASH_REMATCH[3]}"
    local extract_path="${2}"
    local target_dir="${extract_path%/}"

    # Perbaikan: Cek dan hapus direktori dengan aman
    if [[ -d "${target_dir}" ]]; then
        echo -e "${INFO} Removing existing directory: ${target_dir}"
        rm -rf "${target_dir}"
    fi

    mkdir -p "${target_dir}" || error_msg "Failed to create directory: ${target_dir}"

    local zip_file="${target_dir}/${repo}-${branch}.zip"
    local zip_url="https://github.com/${github_user}/${repo}/archive/refs/heads/${branch}.zip"

    echo -e "${INFO} Downloading ZIP from: ${zip_url}"
    curl -fsSL -o "${zip_file}" "${zip_url}" || error_msg "Failed to download ZIP from GitHub."

    if [[ ! -f "${zip_file}" ]]; then
        error_msg "ZIP file not downloaded successfully."
    fi

    echo -e "${INFO} ZIP file downloaded to: ${zip_file}"
    echo -e "${INFO} Extracting ${zip_file} to ${target_dir}..."

    # Perbaikan: Menggunakan 'unzip -qq' untuk output yang lebih bersih
    unzip -qq "${zip_file}" -d "${target_dir}" || error_msg "Failed to extract ZIP file."

    local extracted_dir="${target_dir}/${repo}-${branch}"
    if [[ -d "${extracted_dir}" ]]; then
        echo -e "${INFO} Moving extracted directory content to ${target_dir}..."
        mv "${extracted_dir}"/* "${target_dir}/" || error_msg "Failed to move extracted files."
        rm -rf "${extracted_dir}"
    else
        error_msg "Extracted directory not found. Expected: ${extracted_dir}"
    fi

    echo -e "${INFO} Removing ZIP file: ${zip_file}"
    rm -f "${zip_file}"

    echo -e "${SUCCESS} Download and extraction complete. Directory created at: ${target_dir}"
}

# Downloading OpenWrt ImageBuilder
download_imagebuilder() {
    cd "${make_path}" || error_msg "Failed to navigate to ${make_path}"
    echo -e "${STEPS} Start downloading OpenWrt files..."

    local target_profile=""
    local target_system=""
    local target_name=""
    local ARCH_1=""
    local ARCH_2=""
    local ARCH_3=""

    # Perbaikan: Menggunakan case statement untuk readability
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

    # Perbaikan: Logic untuk deteksi file ekstensi lebih ringkas
    local file_ext="tar.xz"
    local tar_cmd="tar -xvJf"
    if echo "$op_branch" | grep -q "^24\."; then
        file_ext="tar.zst"
        tar_cmd="tar --zstd -xvf"
    elif ! echo "$op_branch" | grep -q "^23\."; then
        error_msg "Unsupported OpenWrt branch: $op_branch"
    fi

    local download_file="https://downloads.${op_sourse}.org/releases/${op_branch}/targets/${target_system}/${op_sourse}-imagebuilder-${op_branch}-${target_name}.Linux-x86_64.${file_ext}"
    local imagebuilder_file="$(basename "$download_file")"

    echo -e "${INFO} Attempting to download: ${download_file}"
    curl -fsSOL "${download_file}" || error_msg "Download failed: [ ${download_file} ]"
    echo -e "${SUCCESS} Download Base ${op_branch} ${target_name} successfully!"

    # Perbaikan: Hapus direktori lama dan ekstrak
    rm -rf "${openwrt_dir}"
    mkdir -p "${openwrt_dir}"
    
    echo -e "${INFO} Extracting ${imagebuilder_file}..."
    if ! $tar_cmd "${imagebuilder_file}" -C "${openwrt_dir}" --strip-components=1; then
        error_msg "Failed to extract ${imagebuilder_file}"
    fi

    rm -f "${imagebuilder_file}"
    sync && sleep 3
    echo -e "${INFO} [ ${make_path} ] directory status: $(ls -al 2>/dev/null)"
}

# Adjust related files in the ImageBuilder directory
adjust_settings() {
    cd "${imagebuilder_path}" || error_msg "Failed to navigate to ${imagebuilder_path}"
    echo -e "${STEPS} Start adjusting .config file settings..."

    local DTM=$(date '+%d-%m-%Y')
    local config_file=".config"
    local repositories_file="repositories.conf"
    local makefile="Makefile"
    local first_setup_script="${custom_files_path}/etc/uci-defaults/99-first-setup"

    # Perbaikan: Cek file sebelum diubah
    if [[ -f "${first_setup_script}" ]]; then
        sed -i "s|Ouc3kNF6|$DTM|g" "${first_setup_script}"
    else
        echo -e "${WARNING} Custom script file not found: ${first_setup_script}"
    fi

    if [[ -s "${repositories_file}" ]]; then
        sed -i '\|option check_signature| s|^|#|' "${repositories_file}"
    fi

    if [[ -s "${makefile}" ]]; then
        sed -i 's/install \$(BUILD_PACKAGES)/install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade/' "${makefile}"
    fi

    if [[ -s "${config_file}" ]]; then
        sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/" "${config_file}"
        sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=1024/" "${config_file}"

        if [ "$op_target" == "amlogic" ]; then
            sed -i 's|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g' "${config_file}"
            sed -i 's|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g' "${config_file}"
            sed -i 's|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g' "${config_file}"
            sed -i 's|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g' "${config_file}"
        fi

        if [ "$ARCH_2" == "x86_64" ]; then
            sed -i 's/CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/' "${config_file}"
            sed -i 's/CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/' "${config_file}"
        fi
    else
        error_msg "No .config file found in ${imagebuilder_path}"
    fi

    sync && sleep 3
    echo -e "${INFO} [ ${imagebuilder_path} ] directory status: $(ls -al 2>/dev/null)"
}

# Add custom packages
custom_packages() {
    cd "${imagebuilder_path}" || error_msg "Failed to navigate to ${imagebuilder_path}"
    echo -e "${STEPS} Start adding custom packages..."
    mkdir -p packages

    if [[ -d "${custom_packages_path}" ]]; then
        cp -rf "${custom_packages_path}"/* packages/
        echo -e "${INFO} [ packages ] directory status: $(ls packages -al 2>/dev/null)"
    else
        echo -e "${WARNING} No customized Packages were added from ${custom_packages_path}."
    fi

    # Download IPK From Github
    local github_packages=()
    if [ "$op_target" == "amlogic" ]; then
        echo "Adding [luci-app-amlogic] from bulider script type."
        github_packages+=("luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest")
    fi
    github_packages+=(
        "luci-app-netmonitor|https://api.github.com/repos/rtaserver/rta-packages/releases"
        "luci-app-base64|https://api.github.com/repos/rtaserver/rta-packages/releases"
    )
    download_packages "github" github_packages

    # Download IPK From Custom
    local other_packages=(    
        "luci-app-internet-detector|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "internet-detector-mod-modem-restart|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "internet-detector|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "modemmanager-rpcd|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/packages"
        "luci-proto-modemmanager|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/luci"
        "libqmi|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/packages"
        "libmbim|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/packages"
        "modemmanager|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/packages"
        "sms-tool|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/packages"
        "tailscale|https://downloads.${op_sourse}.org/releases/packages-24.10/${ARCH_3}/packages"
        "luci-app-modeminfo|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-tailscale|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-diskman|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "modeminfo|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "atinout|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-poweroff|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "xmm-modem|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-disks-info|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-temp-status|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-ramfree|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-3ginfo-lite|https://downloads.immortalwrt.org/releases/packages-24.10/${ARCH_3}/luci"
        "modemband|https://downloads.immortalwrt.org/releases/packages-24.10/${ARCH_3}/packages"
        "luci-app-modemband|https://downloads.immortalwrt.org/releases/packages-24.10/${ARCH_3}/luci"
        "luci-app-sms-tool-js|https://downloads.immortalwrt.org/releases/packages-24.10/${ARCH_3}/luci"
        "luci-app-eqosplus|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
        "luci-app-tinyfilemanager|https://dl.openwrt.ai/packages-24.10/${ARCH_3}/kiddin9"
    )
    download_packages "custom" other_packages

    # Perbaikan: Menyederhanakan proses download & instalasi paket-paket ini
    echo -e "${STEPS} Installing OpenClash, Mihomo, and Passwall"

    # OpenClash
    local openclash_api="https://api.github.com/repos/tes-rep/OpenClash/releases"
    local openclash_ipk_url=$(curl -sL "${openclash_api}" | grep "browser_download_url" | grep -oE "https.*luci-app-openclash.*.ipk" | head -n 1)
    curl -fsSL -o "${imagebuilder_path}/packages/$(basename "${openclash_ipk_url}")" "${openclash_ipk_url}" || error_msg "Failed to download OpenClash package."

    # Mihomo Core
    local core_dir="${custom_files_path}/etc/openclash/core"
    mkdir -p "${core_dir}"
    local mihomo_api="https://api.github.com/repos/vernesong/mihomo/releases"
    local mihomo_file="mihomo-linux-${ARCH_1}-compatible-alpha-smart"
    if [ "$ARCH_3" != "x86_64" ]; then
        mihomo_file="mihomo-linux-${ARCH_1}-alpha-smart"
    fi
    local mihomo_url=$(curl -sL "${mihomo_api}" | grep "browser_download_url" | grep -oE "https.*${mihomo_file}-[a-z0-9]+\.gz" | head -n 1)
    curl -fsSL -o "${core_dir}/clash_meta.gz" "${mihomo_url}" || error_msg "Failed to download mihomo core."
    gzip -d "${core_dir}/clash_meta.gz" || error_msg "Failed to extract mihomo core."

    # Passwall
    local passwall_api="https://api.github.com/repos/xiaorouji/openwrt-passwall/releases"
    local passwall_ipk_url=$(curl -sL "${passwall_api}" | grep "browser_download_url" | grep -oE "https.*luci-23.05_luci-app-passwall.*.ipk" | head -n 1)
    local passwall_zip_url=$(curl -sL "${passwall_api}" | grep "browser_download_url" | grep -oE "https.*passwall_packages_ipk_${ARCH_3}.*.zip" | head -n 1)
    
    curl -fsSL -o "${imagebuilder_path}/packages/$(basename "${passwall_ipk_url}")" "${passwall_ipk_url}" || error_msg "Failed to download Passwall IPK."
    curl -fsSL -o "${imagebuilder_path}/packages/$(basename "${passwall_zip_url}")" "${passwall_zip_url}" || error_msg "Failed to download Passwall ZIP."
    
    unzip -q "${imagebuilder_path}/packages/$(basename "${passwall_zip_url}")" -d "${imagebuilder_path}/packages" || error_msg "Failed to extract Passwall ZIP."
    rm "${imagebuilder_path}/packages/$(basename "${passwall_zip_url}")"

    # Nikki
    local nikki_api="https://api.github.com/repos/rizkikotet-dev/OpenWrt-nikki-Mod/releases"
    local nikki_tar_url=$(curl -sL "${nikki_api}" | grep "browser_download_url" | grep -oE "https.*nikki_${ARCH_3}-openwrt-24.10.*.tar.gz" | head -n 1)
    curl -fsSL -o "${imagebuilder_path}/packages/$(basename "${nikki_tar_url}")" "${nikki_tar_url}" || error_msg "Failed to download Nikki."
    tar -xzvf "${imagebuilder_path}/packages/$(basename "${nikki_tar_url}")" -C "${imagebuilder_path}/packages" || error_msg "Failed to extract Nikki."
    rm "${imagebuilder_path}/packages/$(basename "${nikki_tar_url}")"

    echo -e "${SUCCESS} Download and extraction for all packages complete."
    sync && sleep 3
    echo -e "${INFO} [ packages ] directory status: $(ls -al "${imagebuilder_path}/packages" 2>/dev/null)"
}


# Add custom packages, lib, theme, app and i18n, etc.
custom_config() {
    cd "${imagebuilder_path}" || error_msg "Failed to navigate to ${imagebuilder_path}"
    echo -e "${STEPS} Start adding custom config..."

    echo -e "${INFO} Downloading custom script" 
    local custom_scripts=(
        "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh|${custom_files_path}/sbin/sync_time.sh"
        "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock|${custom_files_path}/usr/bin/clock"
        "https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh|${custom_files_path}/root/install2.sh"
        "https://raw.githubusercontent.com/frizkyiman/auto-mount-hdd/main/mount_hdd|${custom_files_path}/usr/bin/mount_hdd"
    )

    for script in "${custom_scripts[@]}"; do
        IFS="|" read -r url dest_path <<< "$script"
        mkdir -p "$(dirname "$dest_path")"
        echo -e "${INFO} Downloading $(basename "$url") to $dest_path"
        curl -fsSL -o "$dest_path" "$url" || echo -e "${WARNING} Failed to download $(basename "$url")"
    done

    echo -e "${INFO} All custom configuration setup completed!"
}

# Add custom files
custom_files() {
    cd "${imagebuilder_path}" || error_msg "Failed to navigate to ${imagebuilder_path}"
    echo -e "${STEPS} Start adding custom files..."

    if [[ -d "${custom_files_path}" ]]; then
        mkdir -p files
        cp -rf "${custom_files_path}"/* files || error_msg "Failed to copy custom files."
        
        sync && sleep 3
        echo -e "${INFO} [ files ] directory status: $(ls files -al 2>/dev/null)"
    else
        echo -e "${WARNING} No customized files were added from ${custom_files_path}."
    fi
}
# Perbaikan: Mendefinisikan paket di sini lebih baik
readonly OPENCLASH_PACKAGES="coreutils-nohup bash dnsmasq-full curl ca-certificates ipset ip-full libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy luci-compat luci luci-base luci-app-openclash"
readonly NIKKI_PACKAGES="nikki luci-app-nikki"
readonly PASSWALL_PACKAGES="chinadns-ng dns2socks dns2tcp geoview hysteria ipt2socks microsocks naiveproxy simple-obfs sing-box tcping trojan-plus tuic-client v2ray-core v2ray-plugin xray-core xray-plugin v2ray-geoip v2ray-geosite luci-app-passwall"

# Fungsi memilih paket tunnel
handle_tunnel_option() {
    case "$1" in
        "openclash")
            PACKAGES+=" ${OPENCLASH_PACKAGES}"
            ;;
        "passwall")
            PACKAGES+=" ${PASSWALL_PACKAGES}"
            ;;
        "nikki")
            PACKAGES+=" ${NIKKI_PACKAGES}"
            ;;
        "openclash-passwall")
            PACKAGES+=" ${OPENCLASH_PACKAGES} ${PASSWALL_PACKAGES}"
            ;;
        "nikki-passwall")
            PACKAGES+=" ${NIKKI_PACKAGES} ${PASSWALL_PACKAGES}"
            ;;
        "nikki-openclash")
            PACKAGES+=" ${NIKKI_PACKAGES} ${OPENCLASH_PACKAGES}"
            ;;
        "all-tunnel")
            PACKAGES+=" ${OPENCLASH_PACKAGES} ${PASSWALL_PACKAGES} ${NIKKI_PACKAGES}"
            ;;
    esac
}   

# Rebuild OpenWrt firmware
rebuild_firmware() {
    cd "${imagebuilder_path}" || error_msg "Failed to navigate to ${imagebuilder_path}"
    echo -e "${STEPS} Start building OpenWrt with Image Builder..."

    # Menyatukan semua paket ke satu variabel utama
    PACKAGES="file lolcat kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 -kmod-usb-net-asix -kmod-usb-net-asix-ax88179"
    PACKAGES+=" kmod-mii kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan uqmi kmod-usb3 \
    kmod-usb-net-cdc-ether kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils \
    kmod-usb-serial-qualcomm kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim \
    modemmanager modemmanager-rpcd luci-proto-modemmanager libmbim libqmi usbutils luci-proto-mbim luci-proto-ncm \
    kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-sierrawireless kmod-usb-ohci kmod-usb-serial-sierrawireless \
    kmod-usb-uhci kmod-usb2 kmod-usb-ehci kmod-usb-net-ipheth usbmuxd libusbmuxd-utils libimobiledevice-utils usb-modeswitch kmod-nls-utf8 mbim-utils xmm-modem \
    kmod-phy-broadcom kmod-phylib-broadcom kmod-tg3 iptables-nft coreutils-stty"
    PACKAGES+=" luci-app-base64 perl perlbase-essential perlbase-cpan perlbase-utf8 perlbase-time perlbase-xsloader perlbase-extutils perlbase-cpan coreutils-base64"

    PACKAGES+=" tailscale luci-app-tailscale  luci-app-droidnet luci-app-ipinfo luci-theme-initials luci-theme-argon luci-app-argon-config luci-theme-hj jq"
    PACKAGES+=" luci-app-diskman smartmontools kmod-usb-storage kmod-usb-storage-uas ntfs-3g"
    PACKAGES+=" internet-detector luci-app-internet-detector internet-detector-mod-modem-restart vnstat2 vnstati2 netdata luci-app-netmonitor"
    PACKAGES+=" luci-theme-material"
    PACKAGES+=" php8 php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv php8-mod-mbstring"

    local misc_packages=""
    if [ "$op_target" == "rpi-4" ]; then
        misc_packages+=" kmod-i2c-bcm2835 i2c-tools kmod-i2c-core kmod-i2c-gpio luci-app-oled"
    elif [ "$ARCH_2" == "x86_64" ]; then
        misc_packages+=" kmod-iwlwifi iw-full pciutils"
    fi

    if [ "$op_target" == "amlogic" ]; then
        PACKAGES+=" luci-app-amlogic ath9k-htc-firmware btrfs-progs hostapd hostapd-utils kmod-ath kmod-ath9k kmod-ath9k-common kmod-ath9k-htc kmod-cfg80211 kmod-crypto-acompress kmod-crypto-crc32c kmod-crypto-hash kmod-fs-btrfs kmod-mac80211 wireless-tools wpa-cli wpa-supplicant"
    fi

    PACKAGES+=" $misc_packages zram-swap adb parted losetup resize2fs luci luci-ssl block-mount luci-app-ramfree htop bash curl wget-ssl tar unzip unrar gzip jq luci-app-ttyd nano httping screen openssh-sftp-server"

    # Exclude package (must use - before packages name)
    local EXCLUDED="-libgd"
    if [ "${op_sourse}" == "openwrt" ]; then
        EXCLUDED+=" -dnsmasq"
    elif [ "${op_sourse}" == "immortalwrt" ]; then
        EXCLUDED+=" -dnsmasq -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        if [ "$ARCH_2" == "x86_64" ]; then
            EXCLUDED+=" -kmod-usb-net-rtl8152-vendor"
        fi
    fi

    # Tambah paket tunnel jika ada pilihan
    if [ -n "$TUNNEL_OPTION" ]; then
        echo "[INFO] Menambahkan paket tunnel: $TUNNEL_OPTION"
        handle_tunnel_option "$TUNNEL_OPTION"
    fi

    # Perbaikan: Hapus direktori 'bin' sebelum membangun
    rm -rf bin/targets
    
    echo -e "${INFO} Running make image with PROFILE=${target_profile} PACKAGES=\"${PACKAGES} ${EXCLUDED}\" FILES=\"files\""
    
    make clean > /dev/null
    make image PROFILE="${target_profile}" PACKAGES="${PACKAGES} ${EXCLUDED}" FILES="files"
    if [ $? -ne 0 ]; then
        error_msg "OpenWrt build failed. Check logs for details."
    else
        sync && sleep 3
        echo -e "${INFO} [ ${openwrt_dir}/bin/targets/*/* ] directory status: $(ls bin/targets/*/* -al 2>/dev/null)"
        echo -e "${SUCCESS} The rebuild is successful, the current path: [ ${PWD} ]"
    fi

}
# Perbaikan: Memperbaiki logika argument parsing dan validasi
echo -e "${STEPS} Welcome to Rebuild OpenWrt Using the Image Builder."
if [[ ! -x "${0}" ]]; then
    error_msg "Please give the script permission to run: [ chmod +x ${0} ]"
fi

if [[ -z "${1}" ]]; then
    error_msg "Please specify the OpenWrt Branch, such as [ ${0} openwrt:22.03.3 x86-64 ]"
fi
if [[ -z "${2}" ]]; then
    error_msg "Please specify the OpenWrt Target, such as [ ${0} openwrt:22.03.3 x86-64 ]"
fi

op_sourse="${1%:*}"
op_branch="${1#*:}"
op_target="${2}"
TUNNEL_OPTION="${3}"

if [[ ! "${1}" =~ ^[a-z]{3,}:[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo -e "${WARNING} Incoming parameter format <source:branch> may be incorrect. Expected: openwrt:22.03.3"
fi
if [[ ! "${2}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${WARNING} Incoming parameter format <target> may be incorrect. Expected: x86-64"
fi

echo -e "${INFO} Rebuild path: [ ${PWD} ]"
echo -e "${INFO} Rebuild Source: [ ${op_sourse} ], Branch: [ ${op_branch} ], Target: ${op_target}"
if [ -n "$TUNNEL_OPTION" ]; then
    echo -e "${INFO} Tunnel option: [ ${TUNNEL_OPTION} ]"
fi
echo -e "${INFO} Server space usage before starting to compile: \n$(df -hT ${make_path}) \n"

# Perform related operations
download_imagebuilder
adjust_settings
custom_packages
custom_config
custom_files
rebuild_firmware

# Show server end information
echo -e "Server space usage after compilation: \n$(df -hT ${make_path}) \n"
echo -e "${SUCCESS} All processes completed successfully."
wait
