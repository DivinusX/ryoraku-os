#!/usr/bin/env bash
# End-user installer for Ryoraku OS.
# Run on a machine that already has RakuOS installed. No downloads of 5 GB,
# no local build, no registry credentials: the image comes from GHCR.
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/divinusx/ryoraku:latest}"

if ! command -v bootc >/dev/null 2>&1; then
    echo "ERROR: bootc not found. This installer requires RakuOS." >&2
    exit 1
fi

echo "Ryoraku OS image: ${IMAGE}"
echo
echo "Current system:"
sudo bootc status || true
echo
echo "This stages a new deployment next to your current one."
echo "Your files, /home and your config are untouched, and you can roll back with:"
echo "  sudo bootc rollback && sudo reboot"
echo
read -r -p "Continue? [y/N] " answer
[ "${answer}" = "y" ] || { echo "Cancelled."; exit 1; }

# RakuOS's /etc/containers/policy.json already allows ghcr.io without a
# signature, so no policy edit is needed for the hosted image.
sudo bootc switch --retain "${IMAGE}"

echo
echo "=== Status after switch ==="
sudo bootc status
echo
echo "Done. Next:"
echo "  1) sudo reboot"
echo "  2) At the greeter choose 'Ryoku (Hyprland)'"
echo "  3) Later updates are just: sudo bootc upgrade && rum update"
