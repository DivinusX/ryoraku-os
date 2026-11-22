#!/usr/bin/env bash
# Smoke-test the built image without booting it. Run from this directory.
set -euo pipefail

IMAGE="${1:-localhost/ryoku-on-rakuos:test}"
echo "Testing image: ${IMAGE}"

podman run --rm "${IMAGE}" /bin/bash -lc '
fail=0
ok()   { printf "  OK   %s\n" "$1"; }
bad()  { printf "  FAIL %s\n" "$1"; fail=1; }
has()  { if "$@" >/dev/null 2>&1; then ok "$*"; else bad "$*"; fi; }
file() { if [ -e "$1" ]; then ok "$1"; else bad "$1"; fi; }

echo "[packages]"
has rpm -q ryoku
has rpm -q ryoku-desktop
has rpm -q ryoku-desktop-hyprland
has rpm -q ryoku-shell
has rpm -q ryoku-hub
has rpm -q ryoku-rakuos-shims
if quickshell --version 2>/dev/null | grep -qE "Quickshell 0\.[3-9]"; then ok "quickshell >= 0.3"; else bad "quickshell >= 0.3"; fi

echo "[desktop payload]"
file /usr/share/ryoku/config/quickshell/shell/shell.qml
file /usr/share/ryoku/config/quickshell/hub/AppPicker.qml
file /usr/lib64/qt6/qml/Ryoku/Ui/qmldir
file /usr/lib64/qt6/qml/Ryoku/FrameBars/qmldir
file /usr/lib64/qt6/qml/Ryoku/Wm/Hyprland/qmldir
file /usr/share/ryoku/i18n/langs.json
if rpm -q hyprland 2>/dev/null | grep -q 0.57; then ok "hyprland 0.57"; else bad "hyprland 0.57"; fi
if ls /usr/lib/hyprland/plugins/*.so >/dev/null 2>&1; then ok "hyprland plugins"; else bad "hyprland plugins"; fi

echo "[session / first login]"
file /usr/share/wayland-sessions/ryoku.desktop
has test -x /usr/bin/noctalia-greeter-session
if [ "$(cat /usr/share/rakuos/de-name 2>/dev/null)" = ryoku ]; then ok "de-name"; else bad "de-name"; fi
file /etc/skel/.config/quickshell/shell/shell.qml
file /etc/systemd/user/ryoku-shell.service

h=$(mktemp -d)
out=$(HOME="$h" XDG_CONFIG_HOME="$h/.config" ryoku materialize 2>/dev/null || true)
n=$(printf "%s" "$out" | sed -n "s/^materialized \([0-9]*\) files.*/\1/p")
if [ "${n:-0}" -gt 1000 ]; then ok "materialize ($n files)"; else bad "materialize ($n files)"; fi

exit $fail
'
status=$?
echo "smoke test exit: ${status}"
exit "${status}"
