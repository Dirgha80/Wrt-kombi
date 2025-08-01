#!/bin/sh

# === KONFIGURASI ===
LUCI_PATH="/usr/lib/lua/luci"
CTRL_FILE="$LUCI_PATH/controller/openclash.lua"
FORM_CLIENT_FILE="$LUCI_PATH/model/cbi/openclash/settings.lua"
VIEW_OCEDITOR="$LUCI_PATH/view/openclash/oceditor.htm"
STATUS_FILE="/www/luci-static/resources/view/openclash/status.htm"  # Ubah jika lokasi berbeda

# === PATCH settings.lua ===
echo "[✔] Menghapus deskripsi panjang dari settings.lua"
sed -i 's/^m\.description.*/-- m.description = deleted/' "$FORM_CLIENT_FILE"

# === PATCH controller.lua ===
echo "[✔] Mengganti urutan menu 'log' menjadi 100"
sed -i 's/\(entry({.*"log".*Server Logs".*\), *90)/\1, 100)/' "$CTRL_FILE"

echo "[✔] Menambahkan entry menu oceditor jika belum ada"
grep -q 'openclash", "oceditor"' "$CTRL_FILE" || {
  sed -i '/acl_depends.*openclash.*}/a\
  entry({"admin", "services", "openclash", "oceditor"}, template("openclash/oceditor"), _("Config Editor"), 90).leaf = true' "$CTRL_FILE"
}

# === BUAT VIEW oceditor.htm ===
if [ ! -f "$VIEW_OCEDITOR" ]; then
  echo "[✔] Membuat template view oceditor.htm"
  mkdir -p "$(dirname "$VIEW_OCEDITOR")"
  cat << 'EOF' > "$VIEW_OCEDITOR"
<%+header%>
<div class="cbi-map">
  <iframe id="oceditor" style="width: 100%; min-height: 650px; border: none; border-radius: 2px;"></iframe>
</div>
<script type="text/javascript">
  document.getElementById("oceditor").src = window.location.protocol + "//" + window.location.host + "/tinyfm/oceditor.php";
</script>
<%+footer%>
EOF
else
  echo "[ℹ] File oceditor.htm sudah ada, lewati pembuatan"
fi

# === PATCH FILE status.htm (dark mode style + data-darkmode attr) ===
if [ -f "$STATUS_FILE" ]; then
  echo "[✔] Menerapkan dark mode ke status.htm"
  cp "$STATUS_FILE" "${STATUS_FILE}.bak"

  # Tambahkan style darkmode setelah <style>
  sed -i '/<style>/a\
body {\n  background-color: #1f2937 !important;\n  color: #e5e7eb !important;\n}' "$STATUS_FILE"

  # Tambahkan atribut data-darkmode ke div.oc
  sed -i 's/<div class="oc">/<div class="oc" data-darkmode="true">/' "$STATUS_FILE"
else
  echo "[⚠️] File status.htm tidak ditemukan di $STATUS_FILE, lewati patch darkmode"
fi

# === BUAT SYMLINK /www/tinyfm/openclash -> /etc/openclash ===
create_safe_openclash_symlink() {
	local target="/etc/openclash"
	local link="/www/tinyfm/openclash"

	mkdir -p /www/tinyfm

	# Jika sudah ada symlink yang tepat, lewati
	if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$target" ]; then
		echo "[✓] Symlink sudah benar: $link -> $target"
		return 0
	fi

	# Jika ada file/folder yang salah, hapus dulu
	if [ -e "$link" ]; then
		echo "[!] Menghapus $link karena bukan symlink yang benar"
		rm -rf "$link"
	fi

	# Buat symlink baru
	ln -sf "$target" "$link" && echo "[+] Symlink dibuat: $link -> $target"
}

create_safe_openclash_symlink

echo "[✅] Semua patch berhasil diterapkan!"
