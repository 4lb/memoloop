#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
python3 -c "import yaml" 2>/dev/null || { echo "Install PyYAML first (pacman -S python-yaml / apt install python3-yaml)"; exit 1; }

install -Dm755 "$here/intervald.py" "$HOME/.local/bin/intervald"
install -Dm644 "$here/intervald.service" "$HOME/.config/systemd/user/intervald.service"
if [ ! -e "$HOME/.config/intervald/config.yaml" ]; then
  install -Dm644 "$here/config.example.yaml" "$HOME/.config/intervald/config.yaml"
  echo "created ~/.config/intervald/config.yaml (edit it!)"
fi

"$HOME/.local/bin/intervald" check
systemctl --user daemon-reload
systemctl --user enable --now intervald.service
sleep 1
"$HOME/.local/bin/intervald" status
