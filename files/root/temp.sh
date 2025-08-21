#!/bin/sh

TARGET="/usr/share/ucode/luci/template/admin_status/index.ut"
BACKUP="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
TMPFILE="$(mktemp)"
LOG_FILE="/root/houjie-wrt.log"

# Fungsi log
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Patch yang mau disisipkan
PATCH=$(cat <<'EOF'
<div id="cpuusage">Loading CPU usage...</div>
<div id="tempcpu">Loading CPU temp...</div>

<script type="text/javascript">//<![CDATA[
    window.setTimeout(
        function() {
            XHR.poll(3, '{{ dispatcher.build_url("admin/status/realtime/cpuusage1") }}', null,
                function(x, json)
                {
                    if (e = document.getElementById('cpuusage'))
                        e.innerHTML = String.format('%1f %', json[0].cpu / 2);
                }
            );
            XHR.run();
        }
    );
//]]></script>

<script type="text/javascript">//<![CDATA[
    window.setTimeout(
        function() {
            XHR.poll(3, '{{ dispatcher.build_url("admin/status/realtime/temperature1") }}', null,
                function(x, json)
                {
                    if (e = document.getElementById('tempcpu'))
                        e.innerHTML = String.format('%1f&deg;C', json[0].cpu / 1000);
                }
            );
            XHR.run();
        }
    );
//]]></script>
EOF
)

# Cek apakah sudah pernah dipatch
if grep -q "id=\"cpuusage\"" "$TARGET"; then
    echo "[!] Patch sudah ada, tidak melakukan perubahan."
    log_message "Patch duplikat dicegah, tidak diubah: $TARGET"
    exit 0
fi

# Backup dulu
if cp "$TARGET" "$BACKUP"; then
    echo "Backup dibuat: $BACKUP"
    log_message "Backup index.ut → $BACKUP"
else
    echo "[✘] Gagal membuat backup!"
    log_message "Gagal membuat backup $TARGET"
    exit 1
fi

# Sisipkan patch sebelum {% include('footer') %}
if awk -v patch="$PATCH" '
{
    if ($0 ~ /\{\% *include\(.*footer.*\) *\%\}/) {
        print patch;
    }
    print;
}' "$TARGET" > "$TMPFILE" && mv "$TMPFILE" "$TARGET"; then
    echo "[+] Patch selesai. Silakan reload LuCI."
    log_message "Patch CPU Usage & Temp berhasil disisipkan ke index.ut"
else
    echo "[✘] Patch gagal!"
    log_message "Patch gagal untuk $TARGET"
    exit 1
fi
