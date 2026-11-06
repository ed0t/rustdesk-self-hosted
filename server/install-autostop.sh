# Installs (or removes) auto-shutdown on the RustDesk server. Run as root via
# ./rd autostop, which pipes this file over ssh:  bash -s -- <minutes|off>
#
# The server powers itself off after <minutes> without any relay (TCP 21117)
# or SSH connection. Direct RustDesk sessions don't pass through the server
# and keep working after it shuts down.
set -euo pipefail

MINUTES="${1:?usage: install-autostop.sh <minutes|off>}"

if [ "$MINUTES" = off ]; then
  systemctl disable --now rustdesk-autostop.timer 2>/dev/null || true
  rm -f /etc/systemd/system/rustdesk-autostop.{service,timer} /usr/local/bin/rustdesk-autostop
  systemctl daemon-reload
  echo "Auto-shutdown disabled."
  exit 0
fi

case "$MINUTES" in
  ''|*[!0-9]*) echo "Minutes must be a number or 'off'." >&2; exit 1 ;;
esac

cat > /usr/local/bin/rustdesk-autostop <<EOF
#!/bin/bash
# Power off after $MINUTES idle minutes. Installed by ./rd autostop.
set -eu
LIMIT=\$(( $MINUTES * 60 ))
STAMP=/run/rustdesk-autostop.last   # tmpfs: reset on every boot

if [ -n "\$(ss -Htn state established '( sport = :21117 or sport = :22 )')" ]; then
  touch "\$STAMP"
  exit 0
fi

now=\$(date +%s)
if [ -e "\$STAMP" ]; then
  last=\$(stat -c %Y "\$STAMP")
else
  last=\$(( now - \$(cut -d. -f1 /proc/uptime) ))
fi

if [ \$(( now - last )) -ge "\$LIMIT" ]; then
  logger -t rustdesk-autostop "idle for $MINUTES minutes, powering off"
  systemctl poweroff
fi
EOF
chmod 755 /usr/local/bin/rustdesk-autostop

cat > /etc/systemd/system/rustdesk-autostop.service <<'EOF'
[Unit]
Description=Power off RustDesk server when idle

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rustdesk-autostop
EOF

cat > /etc/systemd/system/rustdesk-autostop.timer <<'EOF'
[Unit]
Description=Check every 5 minutes whether the RustDesk server is idle

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now rustdesk-autostop.timer
echo "Auto-shutdown enabled: powers off after $MINUTES idle minutes."
