#!/bin/bash
# files/sshws.sh
# SSH over WebSocket (Dropbear bridge) — untuk repo forme
set -e

RETRY=0
MAX_RETRY=3

echo
echo "== SSHWS Installer for forme =="
echo "Ensure this runs as root."
echo

# CHECK ROOT
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Please run as root"
  exit 1
fi

# Default values (ubah kalau perlu)
WS_PORT_LOCAL=10015   # tempat nginx/xray proxy_pass -> ws-openssh
BACKEND_SSH_HOST=127.0.0.1
BACKEND_SSH_PORT=143  # Dropbear (dari /etc/default/dropbear)

WS_BIN_PATH="/usr/local/bin/ws-openssh"
WS_URL="https://raw.githubusercontent.com/99Myx/ssh-ws/main/ws-openssh"
SYSTEMD_UNIT_PATH="/etc/systemd/system/ws-openssh.service"

echo "[1/6] Pastikan Dropbear/service SSH hidup..."
if ! systemctl is-active --quiet dropbear; then
  echo "Dropbear belum aktif — cuba start..."
  systemctl restart dropbear || true
  sleep 1
fi
if systemctl is-active --quiet dropbear; then
  echo "Dropbear is active."
else
  echo "[WARNING] Dropbear tidak aktif. Pastikan Dropbear terpasang dan port backend (${BACKEND_SSH_PORT}) betul."
fi

echo "[2/6] Memasang ws-openssh handler jika belum ada..."
if [ ! -x "$WS_BIN_PATH" ]; then
  echo "Muat turun $WS_BIN_PATH ..."
  wget -q -O "$WS_BIN_PATH" "$WS_URL" || {
    echo "[ERROR] Gagal muat turun ws-openssh dari $WS_URL"
    exit 1
  }
  chmod +x "$WS_BIN_PATH"
  echo "ws-openssh dipasang."
else
  echo "ws-openssh sudah wujud, skip download."
fi

echo "[3/6] Membuat systemd unit..."
cat > "$SYSTEMD_UNIT_PATH" <<EOF
[Unit]
Description=SSH WebSocket Bridge (forme)
After=network.target dropbear.service
Wants=dropbear.service

[Service]
Type=simple
ExecStart=${WS_BIN_PATH} ${WS_PORT_LOCAL} ${BACKEND_SSH_HOST} ${BACKEND_SSH_PORT}
Restart=always
RestartSec=5s
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

echo "[4/6] Reload systemd dan enable service..."
systemctl daemon-reload
systemctl enable ws-openssh >/dev/null 2>&1 || true

echo "[5/6] Mulakan service ws-openssh..."
systemctl restart ws-openssh

sleep 1

if systemctl is-active --quiet ws-openssh; then
  echo "[OK] ws-openssh running."
else
  echo "[ERROR] ws-openssh gagal start. Lihat log:"
  journalctl -u ws-openssh --no-pager -n 80
  exit 1
fi

echo "[6/6] Semak listening port lokal ${WS_PORT_LOCAL}..."
ss -tuln | grep -E "${WS_PORT_LOCAL}" || {
  echo "[ERROR] Port ${WS_PORT_LOCAL} tidak listening. Semak service."
  journalctl -u ws-openssh --no-pager -n 80
  exit 1
}

echo
echo "== Selesai =="
echo "Nginx/HAProxy config(udah) proxy_pass ke 127.0.0.1:${WS_PORT_LOCAL} untuk path /fightertunnelssh"
echo "Jika anda mahu gunakan port lain atau backend SSH lain, edit ${SYSTEMD_UNIT_PATH} dan jalankan:"
echo "  systemctl daemon-reload && systemctl restart ws-openssh"
echo
exit 0
