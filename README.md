<p align="center">
  <img src="assets/logo.png" alt="Ryoraku OS" width="520" />
</p>

# Ryoraku OS

An atomic `bootc` distro built from `quay.io/rakuos/rakuos-hyprland:latest` (Fedora 45, Hyprland 0.57, `rum`, bootc) with the full Ryoku 1.1.0 desktop baked in.

This is a **personal remix**, not an official Ryoku or RakuOS edition. Ryoku's Fedora installer explicitly refuses atomic systems, so none of its runtime installer runs here; everything is installed into the image at build time.

> There is no Arch/pacman layer here: Ryoku's desktop ships as signed **Fedora RPMs**, so both the RakuOS base and the Ryoku desktop are RPM-based.

## Status

The image is built locally as `localhost/ryoku-on-rakuos:test` and passes `./smoke-test.sh` (20 checks: packages, shell QML, QML modules, i18n, session, first-login config).

`bootc container lint` fails with `usr/sbin/chcon ... a path led outside of the filesystem` — the **stock RakuOS Hyprland image fails the same check**, so this is an upstream image quirk, not introduced by the Ryoku layer.

## What the build does

1. Trusts Ryoku's release key (`EB6D…D6E3`) and adds the signed Fedora 45 RPM repo.
2. Builds a small `ryoku-rakuos-shims` RPM that Provides `snapper`, `grub2-tools`, `grubby` and `plymouth`, which Ryoku's RPMs require for Ryoku's mutable-only update path. On bootc, updates are `bootc upgrade` and rollback is `bootc rollback`, so the real tools are neither needed nor installed.
3. Installs `ryoku`, `ryoku-keyring`, `ryoku-desktop`, `ryoku-desktop-hyprland` and their dependencies with `rum`. Pre-creates `/var/usrlocal/share/applications` because RakuOS symlinks `/usr/local` there and the `ryoku-desktop` RPM would otherwise fail to unpack `mimeapps.list`.
4. Clones Ryoku `v1.1.0` and deploys the parts the RPMs do not ship: shell/Hub QML config, `Ryoku.Ui`, `Ryoku.PluginKit`, `Ryoku.FrameBars`, `Ryoku.Wm.Hyprland`, i18n catalog and systemd user units.
5. Disables the RakuOS Noctalia **desktop shell** autostart (keeps Noctalia **greeter** for greetd), adds a `Ryoku (Hyprland)` wayland session, sets `/usr/share/rakuos/de-name=ryoku`, marks the Ryoku packages protected, seeds `/etc/skel` with `ryoku materialize`.
6. Repacks with the same pinned `chunkah` version as RakuOS and tags the result `containers.bootc=1`.

## Build

Requires `podman` (rootless is fine) and ~10 GB free. From this directory:

```sh
# 1. stack the Ryoku layer and pack it into an OCI archive (writes ./out.ociarchive)
podman build --security-opt label=disable \
  --build-arg BASE_IMAGE_TAG=latest \
  -v "$(pwd)":/run/src \
  -t localhost/ryoku-on-rakuos-chunkah:temp \
  --target chunkah .

# 2. build the final bootc image from that archive
podman build --security-opt label=disable \
  --build-arg BASE_IMAGE_TAG=latest \
  -v "$(pwd)":/run/src \
  -t localhost/ryoku-on-rakuos:test \
  --target final .
```

Two stages are required because `FROM oci-archive:out.ociarchive` cannot be built in the same invocation that produces the archive.

A portable copy of the finished image is included as `ryoku-on-rakuos.image.tar` (5.2 GB, OCI archive). On another machine with podman:

```sh
podman load -i ryoku-on-rakuos.image.tar
```

## Test en la laptop (RakuOS ya instalado)

RakuOS trae `bootc`, `podman` y `skopeo`, así que **no hace falta un registry**: `bootc switch` acepta un archivo OCI directamente.

**1. Pasa el archivo a la laptop** (5.2 GB). Elige una de estas:

```sh
# Por red (reemplaza el host/usuario):
scp /home/pixel/ryoku-on-rakuos/ryoku-on-rakuos.image.tar usuario@laptop:~/

# O copia laptop-install.sh + el .tar a un USB con exFAT/NTFS
# (FAT32 no sirve: el límite es 4 GB por archivo).
```

**2. En la laptop**, antes de cambiar nada:

```sh
bootc status          # anota el deployment actual
df -h /               # asegúrate de tener ~12 GB libres
```

**3. Instala:**

```sh
chmod +x laptop-install.sh
./laptop-install.sh ./ryoku-on-rakuos.image.tar
```

El script usa `bootc switch --transport oci-archive --retain`, conserva el deployment actual de RakuOS y te pide confirmación.

La policy de RakuOS trae `"default": [{"type":"reject"}]` y no tiene entrada para `oci-archive`, así que un switch directo falla con `is rejected by policy`. El instalador añade temporalmente:

```json
"oci-archive": { "": [ { "type": "insecureAcceptAnything" } ] }
```

...dentro de `transports` en `/etc/containers/policy.json`, hace el switch y restaura la policy original automáticamente (trap `EXIT`). Es una excepción solo para esta imagen casera; no modifica la verificación de las imágenes oficiales de RakuOS.

**4. Reinicia y comprueba:**

```sh
sudo reboot
# tras el arranque:
bootc status
rpm -q ryoku-desktop ryoku-desktop-hyprland
```

En el greeter elige **Ryoku (Hyprland)**. Secure Boot no debería dar problemas: el kernel y los módulos siguen siendo los de RakuOS.

**Rollback** (si algo no arranca):

```sh
sudo bootc rollback && sudo reboot
```

Nota: al haber hecho switch desde un archivo local, `bootc upgrade` ya no sabrá de dónde actualizar. Para actualizar repite `bootc switch --transport oci-archive` con un tar nuevo.

## Test en entorno aislado

```sh
./smoke-test.sh                 # static checks inside the image
podman run --rm -it --privileged localhost/ryoku-on-rakuos:test /bin/bash
```

Si prefieres usar un registry en vez del tar:

```sh
podman tag localhost/ryoku-on-rakuos:test <registry>/ryoku-on-rakuos:test
podman push <registry>/ryoku-on-rakuos:test
# On the RakuOS test machine:
sudo bootc switch --mutate-in-place <registry>/ryoku-on-rakuos:test
sudo reboot
```

RakuOS images are cosign-signed. If your policy requires a signature, sign your image with your own key and add it to `/etc/containers/policy.json`, or relax the policy on the test machine only. **Do not switch a daily driver until rollback has been verified** (`bootc status`, `sudo bootc rollback`, reboot).

At the greeter, choose **Ryoku (Hyprland)** from the session list. Noctalia Greeter stays as the login greeter.

## Maintaining Ryoraku OS

There are three independent update lanes:

| What | How | Command |
|---|---|---|
| Base RakuOS + baked-in Ryoku desktop | Rebuild the image from a newer base/RPMs and switch | `bootc switch --transport oci-archive <new tar>` |
| Packages you installed yourself (rum overlay) | RakuOS package layers | `rum update` |
| User config | Persists; re-lay Ryoku's base config if needed | `ryoku materialize` |

Because this image was switched from a local OCI archive, **`bootc upgrade` has no registry to pull from**. To update the system, rebuild and re-run `laptop-install.sh` with the new tar. It updates RakuOS and Ryoku together in one atomic transaction, and `laptop-install.sh` temporarily fixes the `oci-archive` signature policy each time.

Never run these here:

```sh
ryoku update        # DNF + snapper + GRUB, for mutable Fedora only
sudo pacman -Syu    # there is no pacman in this image
sudo dnf install    # /usr is read-only; use rum
```

Roll back to the previous deployment at any time:

```sh
sudo bootc rollback && sudo reboot
```

If you push the images to a registry such as `quay.io/<you>/rakuryo:latest`, RakuOS's policy already accepts `quay.io` without a signature, and `bootc upgrade` works normally.

## Remaining runtime things to verify on real hardware

- **Hyprland plugin ABI.** Ryoku's plugins carry `.abi` receipts (`11cbc6c5…_aq_0.16_hu_0.14…`) built against Ryoku's Hyprland; this image has Hyprland 0.57.2. If a plugin fails to load, rebuild it from `~/.cache/ryoku/hypr-plugins-src` with `ryoku-hub desktop plugins rebuild --stale`.
- **QML import path.** The modules are in `/usr/lib64/qt6/qml/Ryoku`; check `qs -c shell` starts from a TTY if the shell does not appear.
- **Lock screen.** Ryoku's qylock SDDM greeter theme is not wired up; the in-session Quickshell lockscreen is used instead.

## Licensing

Ryoku is GPL-3.0. A personal image is fine; if you distribute it, honour the GPL source/notice obligations for Ryoku's packages and keep upstream `NOTICE` files.

## Upstream references

- RakuOS Hyprland image: https://gitlab.com/rakuos/images/rakuos-hyprland
- RakuOS: https://gitlab.com/rakuos · https://rakuos.org
- Ryoku: https://github.com/Ryoku-dev/ryoku · repo `https://repo.ryoku.dev/stable/fedora/$releasever/x86_64`
