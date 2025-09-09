#!/bin/bash
# ================================================================================================
# Deskripsi: Skrip untuk membangun OpenWrt menggunakan Image Builder.
# Hak Cipta:
# Copyright (C) 2021~ https://github.com/unifreq/openwrt_packit
# Copyright (C) 2021~ https://github.com/ophub/amlogic-s9xxx-openwrt
# Copyright (C) 2021~ https://downloads.openwrt.org/releases
# Copyright (C) 2023~ https://downloads.immortalwrt.org/releases
#
# Penggunaan: ./imagebuilder.sh <sumber:cabang> <target> [opsi_tunnel]
# Contoh: ./imagebuilder.sh openwrt:23.05.0 x86_64 openclash
#
# Opsi Tunnel: openclash, passwall, nikki, openclash-passwall, nikki-passwall, nikki-openclash, all-tunnel
# ================================================================================================

# --- Variabel Global dan Konfigurasi Awal ---
make_path="${PWD}"
openwrt_dir="imagebuilder"
imagebuilder_path="${make_path}/${openwrt_dir}"
custom_files_path="${make_path}/files"
custom_packages_path="${make_path}/packages"

STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"

declare -A TUNNEL_PACKAGES=(
    ["openclash"]="coreutils-nohup bash dnsmasq-full curl ca-certificates ipset ip-full libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy luci-compat luci luci-base luci-app-openclash"
    ["passwall"]="chinadns-ng dns2socks dns2tcp geoview hysteria ipt2socks microsocks naiveproxy simple-obfs sing-box tcping trojan-plus tuic-client v2ray-core v2ray-plugin xray-core xray-plugin v2ray-geoip v2ray-geosite luci-app-passwall"
    ["nikki"]="nikki luci-app-nikki"
)

# --- Fungsi Utility ---
error_msg() {
    echo -e "${ERROR} ${1}" >&2
    exit 1
}

download_packages() {
    local source=$1
    local package_list=("${!2}")
    
    for entry in "${package_list[@]}"; do
        IFS="|" read -r package_name base_url <<< "$entry"
        echo -e "${INFO} Memproses paket: ${package_name}"
        
        local file_url=""
        if [[ "${source}" == "github" ]]; then
            file_url=$(curl -s "${base_url}" | grep "browser_download_url" | grep -oE "https.*/${package_name}_[_0-9a-zA-Z\._~-]*\.ipk" | sort -V | tail -n 1)
        elif [[ "${source}" == "custom" ]]; then
            local search_patterns=("\"${package_name}[^\"]*\.ipk\"" "\"${package_name}[^\"]*\.apk\"" "${package_name}_.*\.ipk" "${package_name}_.*\.apk" "${package_name}.*\.ipk" "${package_name}.*\.apk")
            for pattern in "${search_patterns[@]}"; do
                file_url=$(curl -sL "$base_url" | grep -oE "$pattern" | sed 's/"//g' | sort -V | tail -n 1)
                if [ -n "$file_url" ]; then
                    file_url="${base_url}/${file_url%%\"*}"
                    break
                fi
            done
        fi
        
        if [ -z "${file_url}" ]; then
            error_msg "Gagal menemukan URL untuk paket [${package_name}]"
        fi

        echo -e "${INFO} Mengunduh ${package_name} dari ${file_url}"
        
        local max_attempts=3
        local attempt=1
        local download_success=false
        
        while [ $attempt -le $max_attempts ]; do
            echo -e "${INFO} Percobaan ke-${attempt} untuk mengunduh ${package_name}"
            if curl -fsSL --max-time 60 --retry 2 -o "${package_name}.ipk" "${file_url}"; then
                download_success=true
                echo -e "${SUCCESS} Paket [${package_name}] berhasil diunduh."
                break
            else
                echo -e "${WARNING} Unduh gagal untuk ${package_name} (Percobaan ke-${attempt})"
                ((attempt++))
                sleep 5
            fi
        done
        
        if [ "${download_success}" != true ]; then
            error_msg "Gagal mengunduh paket [${package_name}] setelah ${max_attempts} percobaan."
        fi
    done
}

dl_zip_gh() {
    local repo_and_branch="${1}"
    local extract_path="${2}"

    if [[ ! "${repo_and_branch}" =~ ^([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+):([a-zA-Z0-9_-]+)$ ]]; then
        error_msg "Format input tidak valid. Penggunaan: dl_zip_gh \"user/repo:branch\" \"path/to/extract\""
    fi

    local github_user="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    local branch="${BASH_REMATCH[3]}"
    local target_dir="${extract_path%/}"
    local zip_url="https://github.com/${github_user}/${repo}/archive/refs/heads/${branch}.zip"
    
    mkdir -p "${target_dir}"
    
    echo -e "${INFO} Mengunduh ZIP dari: ${zip_url}"
    curl -fsSL -o "${target_dir}/${repo}.zip" "${zip_url}" || error_msg "Gagal mengunduh file ZIP."
    
    unzip -q "${target_dir}/${repo}.zip" -d "${target_dir}" || error_msg "Gagal mengekstrak file ZIP."
    
    mv -f "${target_dir}/${repo}-${branch}"/* "${target_dir}/" || error_msg "Gagal memindahkan file yang diekstrak."
    rm -rf "${target_dir}/${repo}-${branch}" "${target_dir}/${repo}.zip"
    
    echo -e "${SUCCESS} Unduhan dan ekstraksi selesai. Direktori: ${target_dir}"
}

# 1. Mengunduh OpenWrt ImageBuilder
download_imagebuilder() {
    echo -e "${STEPS} Memulai unduhan OpenWrt Image Builder..."

    case "${op_target}" in
        amlogic|AMLOGIC)
            target_profile=""
            target_system="armsr/armv8"
            target_name="armsr-armv8"
            ARCH_3="aarch64_generic"
            ;;
        rpi-3)
            target_profile="rpi-3"
            target_system="bcm27xx/bcm2710"
            target_name="bcm27xx-bcm2710"
            ARCH_3="aarch64_cortex-a53"
            ;;
        rpi-4)
            target_profile="rpi-4"
            target_system="bcm27xx/bcm2711"
            target_name="bcm27xx-bcm2711"
            ARCH_3="aarch64_cortex-a72"
            ;;
        friendlyarm_nanopi-r2c|nanopi-r2c)
            target_profile="friendlyarm_nanopi-r2c"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_3="aarch64_generic"
            ;;
        friendlyarm_nanopi-r2s|nanopi-r2s)
            target_profile="friendlyarm_nanopi-r2s"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_3="aarch64_generic"
            ;;
        friendlyarm_nanopi-r4s|nanopi-r4s)
            target_profile="friendlyarm_nanopi-r4s"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_3="aarch64_generic"
            ;;
        xunlong_orangepi-r1-plus|orangepi-r1-plus)
            target_profile="xunlong_orangepi-r1-plus"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_3="aarch64_generic"
            ;;
        xunlong_orangepi-r1-plus-lts|orangepi-r1-plus-lts)
            target_profile="xunlong_orangepi-r1-plus-lts"
            target_system="rockchip/armv8"
            target_name="rockchip-armv8"
            ARCH_3="aarch64_generic"
            ;;
        generic|x86-64|x86_64)
            target_profile="generic"
            target_system="x86/64"
            target_name="x86-64"
            ARCH_3="x86_64"
            ;;
        *)
            error_msg "Target tidak didukung: ${op_target}"
            ;;
    esac

    local file_ext
    local tar_cmd
    case "${op_branch}" in
        24.*)
            file_ext="tar.zst"
            tar_cmd="tar --zstd -xvf"
            ;;
        23.*)
            file_ext="tar.xz"
            tar_cmd="tar -xvJf"
            ;;
        *)
            error_msg "Versi tidak dikenali untuk op_branch: ${op_branch}"
            ;;
    esac

    local download_file="https://downloads.${op_sourse}.org/releases/${op_branch}/targets/${target_system}/${op_sourse}-imagebuilder-${op_branch}-${target_name}.Linux-x86_64.${file_ext}"
    local imagebuilder_file="$(basename "${download_file}")"

    curl -fsSOL "${download_file}" || error_msg "Gagal mengunduh: ${download_file}"
    echo -e "${SUCCESS} Berhasil mengunduh Image Builder dasar."

    if [ ! -f "${imagebuilder_file}" ]; then
        error_msg "File Image Builder tidak ditemukan setelah diunduh."
    fi
    ${tar_cmd} "${imagebuilder_file}" && rm -f "${imagebuilder_file}"
    mv -f *-imagebuilder-* "${openwrt_dir}"

    echo -e "${SUCCESS} Image Builder berhasil diekstrak ke ${openwrt_dir}"
    cd "${imagebuilder_path}" || error_msg "Gagal masuk ke direktori Image Builder."
}

# 2. Menyesuaikan Pengaturan
adjust_settings() {
    echo -e "${STEPS} Menyesuaikan file konfigurasi Image Builder..."

    cd "${imagebuilder_path}"
    if [ ! -s ".config" ]; then
        error_msg "File .config tidak ditemukan di direktori Image Builder."
    fi

    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/" .config
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=1024/" .config

    case "${op_target}" in
        amlogic|AMLOGIC)
            sed -i "/CONFIG_TARGET_ROOTFS_CPIOGZ/d; /CONFIG_TARGET_ROOTFS_EXT4FS/d; /CONFIG_TARGET_ROOTFS_SQUASHFS/d; /CONFIG_TARGET_IMAGES_GZIP/d" .config
            ;;
        x86_64)
            sed -i "s/CONFIG_ISO_IMAGES=y/# CONFIG_ISO_IMAGES is not set/" .config
            sed -i "s/CONFIG_VHDX_IMAGES=y/# CONFIG_VHDX_IMAGES is not set/" .config
            ;;
    esac
    
    if [[ -s "repositories.conf" ]]; then
        sed -i 's|option check_signature|# option check_signature|' repositories.conf
    fi
    
    if [[ -s "Makefile" ]]; then
        sed -i "s/install \$(BUILD_PACKAGES)/install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade/" Makefile
    fi

    echo -e "${SUCCESS} Penyesuaian konfigurasi selesai."
}

# 3. Menambahkan Paket Kustom
custom_packages() {
    echo -e "${STEPS} Menambahkan paket kustom..."

    cd "${imagebuilder_path}"
    mkdir -p packages

    if [[ -d "${custom_packages_path}" ]]; then
        cp -rf "${custom_packages_path}"/* packages/
        echo -e "${INFO} Paket kustom dari direktori 'packages' ditambahkan."
    fi

    cd packages

    local github_packages=()
    if [ "${op_target}" == "amlogic" ]; then
        github_packages+=("luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest")
    fi
    github_packages+=("luci-app-netmonitor|https://api.github.com/repos/rtaserver/rta-packages/releases" "luci-app-base64|https://api.github.com/repos/rtaserver/rta-packages/releases")
    download_packages "github" github_packages[@]

    local cur_ver=$(echo "${op_branch}" | awk -F. '{print $1"."$2}')
    local other_packages=(
        "luci-app-internet-detector|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "internet-detector-mod-modem-restart|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "internet-detector|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "modemmanager-rpcd|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "luci-proto-modemmanager|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/luci"
        "libqmi|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "libmbim|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "modemmanager|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "sms-tool|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "tailscale|https://downloads.${op_sourse}.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "luci-app-modeminfo|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-tailscale|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-diskman|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "modeminfo|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "atinout|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-poweroff|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "xmm-modem|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-disks-info|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-temp-status|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-ramfree|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-3ginfo-lite|https://downloads.immortalwrt.org/releases/packages-${cur_ver}/${ARCH_3}/luci"
        "modemband|https://downloads.immortalwrt.org/releases/${op_branch}/packages/${ARCH_3}/packages"
        "luci-app-modemband|https://downloads.immortalwrt.org/releases/${op_branch}/packages/${ARCH_3}/luci"
        "luci-app-sms-tool-js|https://downloads.immortalwrt.org/releases/${op_branch}/packages/${ARCH_3}/luci"
        "luci-app-eqosplus|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
        "luci-app-tinyfilemanager|https://dl.openwrt.ai/packages-${cur_ver}/${ARCH_3}/kiddin9"
    )
    download_packages "custom" other_packages[@]

    echo -e "${STEPS} Mengunduh paket-paket khusus: OpenClash, Passwall, Nikki..."
    local openclash_url=$(curl -s "https://api.github.com/repos/tes-rep/OpenClash/releases" | grep "browser_download_url" | grep -oE "https.*luci-app-openclash.*\.ipk" | head -n 1)
    local passwall_url=$(curl -s "https://api.github.com/repos/xiaorouji/openwrt-passwall/releases" | grep "browser_download_url" | grep -oE "https.*luci-23.05_luci-app-passwall.*\.ipk" | head -n 1)
    local passwall_zip_url=$(curl -s "https://api.github.com/repos/xiaorouji/openwrt-passwall/releases" | grep "browser_download_url" | grep -oE "https.*passwall_packages_ipk_${ARCH_3}.*\.zip" | head -n 1)
    local nikki_url=$(curl -s "https://api.github.com/repos/rizkikotet-dev/OpenWrt-nikki-Mod/releases" | grep "browser_download_url" | grep -oE "https.*nikki_${ARCH_3}-openwrt-24.10.*\.tar\.gz" | head -n 1)
    
    [[ -n "${openclash_url}" ]] && curl -fsSOL "${openclash_url}"
    [[ -n "${passwall_url}" ]] && curl -fsSOL "${passwall_url}"
    [[ -n "${passwall_zip_url}" ]] && { curl -fsSOL "${passwall_zip_url}" && unzip -q "$(basename "${passwall_zip_url}")" && rm "$(basename "${passwall_zip_url}")"; }
    [[ -n "${nikki_url}" ]] && { curl -fsSOL "${nikki_url}" && tar -xzvf "$(basename "${nikki_url}")" && rm "$(basename "${nikki_url}")"; }

    local clash_meta_api="https://api.github.com/repos/vernesong/mihomo/releases"
    local clash_meta_file_pattern="mihomo-linux-arm64-alpha-smart"
    if [ "${ARCH_3}" == "x86_64" ]; then
        clash_meta_file_pattern="mihomo-linux-amd64-compatible-alpha-smart"
    fi
    local clash_meta_url=$(curl -s "${clash_meta_api}" | grep "browser_download_url" | grep -oE "https.*${clash_meta_file_pattern}-[a-z0-9]+\.gz" | head -n 1)
    
    mkdir -p "${custom_files_path}/etc/openclash/core"
    curl -fsSL -o "${custom_files_path}/etc/openclash/core/clash_meta.gz" "${clash_meta_url}"
    gzip -d "${custom_files_path}/etc/openclash/core/clash_meta.gz"

    echo -e "${SUCCESS} Pengunduhan paket kustom selesai."
}

# 4. Menambahkan File Kustom
custom_files() {
    echo -e "${STEPS} Menambahkan file kustom..."

    cd "${imagebuilder_path}"
    mkdir -p files
    
    if [[ -d "${custom_files_path}" ]]; then
        cp -rf "${custom_files_path}"/* files/
        echo -e "${INFO} File kustom dari direktori 'files' ditambahkan."
    else
        echo -e "${WARNING} Tidak ada file kustom yang ditambahkan."
    fi

    echo -e "${INFO} Mengunduh skrip tambahan..."
    curl -fsSL -o "files/sbin/sync_time.sh" "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh"
    curl -fsSL -o "files/usr/bin/clock" "https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock"
    curl -fsSL -o "files/root/install2.sh" "https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh"
    
    dtm=$(date '+%d-%m-%Y')
    sed -i "s|Ouc3kNF6|$dtm|g" "files/etc/uci-defaults/99-first-setup"

    echo -e "${SUCCESS} Penyiapan file kustom selesai."
}

# 5. Membangun Firmware OpenWrt
rebuild_firmware() {
    echo -e "${STEPS} Memulai proses build OpenWrt..."

    cd "${imagebuilder_path}"
    
    local packages=" file lolcat kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 -kmod-usb-net-asix -kmod-usb-net-asix-ax88179"
    packages+=" kmod-mii kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan uqmi kmod-usb3 kmod-usb-net-cdc-ether kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils"
    packages+=" kmod-usb-serial-qualcomm kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim modemmanager modemmanager-rpcd luci-proto-modemmanager libmbim libqmi usbutils luci-proto-mbim luci-proto-ncm"
    packages+=" kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-sierrawireless kmod-usb-ohci kmod-usb-serial-sierrawireless"
    packages+=" kmod-usb-uhci kmod-usb2 kmod-usb-ehci kmod-usb-net-ipheth usbmuxd libusbmuxd-utils libimobiledevice-utils usb-modeswitch kmod-nls-utf8 mbim-utils xmm-modem"
    packages+=" kmod-phy-broadcom kmod-phylib-broadcom kmod-tg3 iptables-nft coreutils-stty"
    packages+=" luci-app-base64 perl perlbase-essential perlbase-cpan perlbase-utf8 perlbase-time perlbase-xsloader perlbase-extutils perlbase-cpan coreutils-base64"
    packages+=" tailscale luci-app-tailscale  luci-app-droidnet luci-app-ipinfo luci-theme-initials luci-theme-argon luci-app-argon-config luci-theme-hj jq"
    packages+=" luci-app-diskman smartmontools kmod-usb-storage kmod-usb-storage-uas ntfs-3g"
    packages+=" internet-detector luci-app-internet-detector internet-detector-mod-modem-restart vnstat2 vnstati2 netdata luci-app-netmonitor"
    packages+=" luci-theme-material"
    packages+=" php8 php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv php8-mod-mbstring"
    packages+=" zram-swap adb parted losetup resize2fs luci luci-ssl block-mount luci-app-ramfree htop bash curl wget-ssl tar unzip unrar gzip jq luci-app-ttyd nano httping screen openssh-sftp-server"
    
    if [ "${op_target}" == "rpi-4" ]; then
        packages+=" kmod-i2c-bcm2835 i2c-tools kmod-i2c-core kmod-i2c-gpio luci-app-oled"
    elif [ "${ARCH_3}" == "x86_64" ]; then
        packages+=" kmod-iwlwifi iw-full pciutils"
    elif [ "${op_target}" == "amlogic" ]; then
        packages+=" luci-app-amlogic ath9k-htc-firmware btrfs-progs hostapd hostapd-utils kmod-ath kmod-ath9k kmod-ath9k-common kmod-ath9k-htc kmod-cfg80211 kmod-crypto-acompress kmod-crypto-crc32c kmod-crypto-hash kmod-fs-btrfs kmod-mac80211 wireless-tools wpa-cli wpa-supplicant"
    fi
    
    local tunnel_option_list
    if [ -n "${TUNNEL_OPTION}" ]; then
        echo -e "${INFO} Menambahkan paket tunnel: ${TUNNEL_OPTION}"
        case "${TUNNEL_OPTION}" in
            openclash-passwall)
                tunnel_option_list="openclash passwall"
                ;;
            nikki-passwall)
                tunnel_option_list="nikki passwall"
                ;;
            nikki-openclash)
                tunnel_option_list="nikki openclash"
                ;;
            all-tunnel)
                tunnel_option_list="openclash passwall nikki"
                ;;
            *)
                tunnel_option_list="${TUNNEL_OPTION}"
                ;;
        esac
        
        for option in ${tunnel_option_list}; do
            packages+=" ${TUNNEL_PACKAGES[${option}]}"
        done
    fi

    local excluded_packages="-libgd"
    if [ "${op_sourse}" == "openwrt" ]; then
        excluded_packages+=" -dnsmasq"
    elif [ "${op_sourse}" == "immortalwrt" ]; then
        excluded_packages+=" -dnsmasq -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        if [ "${ARCH_3}" == "x86_64" ]; then
            excluded_packages+=" -kmod-usb-net-rtl8152-vendor"
        fi
    fi

    if echo "$OPENWRT_KERNEL" | grep -q "5.4"; then
        echo "[INFO] Detected kernel 5.4, excluding procd-ujail"
        excluded_packages+=" -procd-ujail"
    fi
    
    make clean
    make image PROFILE="${target_profile}" PACKAGES="${packages} ${excluded_packages}" FILES="files"
    
    if [ $? -ne 0 ]; then
        error_msg "Build OpenWrt gagal. Periksa log."
    fi
    
    echo -e "${SUCCESS} Build firmware berhasil. File ada di: ${imagebuilder_path}/bin/targets/${target_system}"
}

echo -e "${STEPS} Selamat datang di Rebuild OpenWrt Menggunakan Image Builder."
if [ ! -x "${0}" ]; then
    error_msg "Harap berikan izin eksekusi pada skrip: [ chmod +x ${0} ]"
fi

if [[ -z "${1}" || -z "${2}" ]]; then
    echo "Penggunaan: ./imagebuilder.sh <sumber:cabang> <target> [opsi_tunnel]"
    echo "Contoh: ./imagebuilder.sh openwrt:23.05.0 x86_64 openclash"
    error_msg "Argumen tidak lengkap."
fi

op_sourse="${1%:*}"
op_branch="${1#*:}"
op_target="${2}"
TUNNEL_OPTION="${3}"

echo -e "${INFO} Sumber: ${op_sourse}, Cabang: ${op_branch}, Target: ${op_target}"
echo -e "${INFO} Penggunaan ruang server sebelum kompilasi:\n$(df -hT "${make_path}")\n"

download_imagebuilder
adjust_settings
custom_packages
custom_files
rebuild_firmware

echo -e "${SUCCESS} Semua proses selesai."
echo -e "Penggunaan ruang server setelah kompilasi:\n$(df -hT "${make_path}")\n"
exit 0
