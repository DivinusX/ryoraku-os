#!/usr/bin/env bash
# Ejecutar EN LA LAPTOP con RakuOS ya instalado.
# Uso: ./laptop-install.sh /ruta/a/ryoku-on-rakuos.image.tar
set -euo pipefail

ARCHIVE="${1:-./ryoku-on-rakuos.image.tar}"

if [ ! -f "${ARCHIVE}" ]; then
    echo "ERROR: no encuentro ${ARCHIVE}" >&2
    echo "Uso: $0 /ruta/a/ryoku-on-rakuos.image.tar" >&2
    exit 1
fi

if ! command -v bootc >/dev/null 2>&1; then
    echo "ERROR: bootc no está disponible. Esto solo funciona en RakuOS." >&2
    exit 1
fi

echo "=== Estado actual de RakuOS ==="
sudo bootc status || true
echo
echo "=== Archivo a instalar ==="
ls -lh "${ARCHIVE}"
echo
echo "Ryoraku OS se instalará como nuevo deployment."
echo "El deployment actual de RakuOS se conserva para rollback."
echo
read -r -p "¿Continuar? [y/N] " answer
[ "${answer}" = "y" ] || { echo "Cancelado."; exit 1; }

# La policy de RakuOS rechaza por defecto todo lo que no esté firmado,
# incluido el transporte oci-archive. Añadimos una excepción SOLO para este
# switch y restauramos la policy original al salir (incluso si falla).
POLICY=/etc/containers/policy.json
BACKUP=$(mktemp /tmp/ryoraku-policy.XXXXXX.json)
sudo cp "${POLICY}" "${BACKUP}"
restore_policy() {
    sudo cp "${BACKUP}" "${POLICY}"
    rm -f "${BACKUP}"
}
trap restore_policy EXIT

sudo python3 - <<'PY'
import json
path = "/etc/containers/policy.json"
with open(path) as f:
    policy = json.load(f)
policy.setdefault("transports", {})
policy["transports"]["oci-archive"] = {"": [{"type": "insecureAcceptAnything"}]}
with open(path, "w") as f:
    json.dump(policy, f, indent=2)
PY

# --retain conserva la referencia al deployment actual.
sudo bootc switch --transport oci-archive --retain "${ARCHIVE}"

echo
echo "=== Estado tras el switch (debe decir 'Staged image') ==="
sudo bootc status

echo
echo "Listo. Ahora:"
echo "  1) sudo reboot"
echo "  2) En el greeter elige la sesión 'Ryoku (Hyprland)'"
echo "  3) Verifica: bootc status && rpm -q ryoku-desktop ryoku-desktop-hyprland"
echo
echo "Si algo falla, vuelve a RakuOS con:"
echo "  sudo bootc rollback && sudo reboot"
