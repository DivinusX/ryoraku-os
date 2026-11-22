#!/bin/bash
# Install the Ryoku desktop into a finished rakuos-hyprland image.
#
# This runs inside the image build (Containerfile RUN), where /usr is writable.
# Nothing here runs on a booted RakuOS system: the runtime installer cannot be
# used because Ryoku's Fedora path refuses atomic systems and expects DNF,
# GRUB, snapper and Plymouth.
set -euo pipefail

FEDORA_VERSION=$(rpm -E %fedora)
echo "[ryoku-on-rakuos] building on Fedora ${FEDORA_VERSION}"

if [ "${FEDORA_VERSION}" != "45" ]; then
    echo "[ryoku-on-rakuos] WARNING: Ryoku publishes RPMs for Fedora 44/45; \
checking repo metadata for ${FEDORA_VERSION} is on you." >&2
fi

# ── Trust Ryoku's signing key ────────────────────────────────────────────────
# The key and /etc/yum.repos.d/ryoku.repo are baked in from system_files/.
# Fail loudly if the key is not the one Ryoku publishes.
if command -v gpg >/dev/null 2>&1; then
    # A rootless image build has no writable /root/.gnupg, so use a temp homedir.
    gnupghome=$(mktemp -d /var/tmp/ryoku-gpg.XXXXXX)
    fingerprint=$(gpg --homedir "${gnupghome}" --show-keys --with-colons \
        /etc/pki/rpm-gpg/RPM-GPG-KEY-ryoku \
        | awk -F: '$1 == "fpr" { print $10; exit }')
    rm -rf "${gnupghome}"
    [ "${fingerprint}" = "EB6D3C0F55A7B3CABA6B2838847B274F025DD6E3" ] || {
        echo "[ryoku-on-rakuos] ERROR: unexpected Ryoku key fingerprint: ${fingerprint}" >&2
        exit 1
    }
fi
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-ryoku

# ── Third-party repos Ryoku's RPMs may need ──────────────────────────────────
# RakuOS disables Terra and RPM Fusion in the finished image. Turn them on for
# the install and disable them again at the end, exactly like upstream build.sh.
rum config-manager --default --set-enabled terra 2>/dev/null || true
if [ -f /usr/share/rakuos/rpmfusion-default-repos ]; then
    rum config-manager --default --set-enabled \
        "$(cat /usr/share/rakuos/rpmfusion-default-repos)" 2>/dev/null || true
fi

# ── Remove the Quickshell the RakuOS image ships ─────────────────────────────
# rakuos-hyprland has a FIXME: "Remove quickshell-git when Fedora gets 0.3".
# Ryoku requires >= 0.3 and ships its own build, so let the Ryoku RPM own it.
rum remove -y quickshell-git 2>/dev/null || true

# ── Shim mutable-only dependencies ───────────────────────────────────────────
# Ryoku's Fedora RPMs hard-require snapper, grubby, grub2-tools and plymouth
# because `ryoku update` drives DNF snapshots and a GRUB snapshot menu. None of
# that applies to a bootc host: updates are `bootc upgrade`, rollback is
# `bootc rollback`. Build a tiny noarch RPM that Provides those names so the
# resolver accepts the Ryoku set. This is intentional: do not run `ryoku
# update` on this image.
if ! command -v rpmbuild >/dev/null 2>&1; then
    rum install -y rpm-build
fi

shimdir=$(mktemp -d /var/tmp/ryoku-shim.XXXXXX)
cat > "${shimdir}/ryoku-rakuos-shims.spec" <<'EOF'
Name:           ryoku-rakuos-shims
Version:        1
Release:        1%{?dist}
Summary:        Satisfy Ryoku's mutable-Fedora-only dependencies on bootc
License:        GPL-3.0-or-later
BuildArch:      noarch
# RakuOS has no SELinux policy, and its linkdupes brp hook fails with
# "selabel_open() failed". This shim is empty, so skip that hook entirely.
%global         __brp_linkdupes /bin/true
Provides:       snapper = 0
Provides:       grub2-tools = 0
Provides:       grub2-tools-extra = 0
Provides:       grubby = 0
Provides:       plymouth = 0
Provides:       plymouth-plugin-label = 0
Provides:       plymouth-plugin-script = 0
Provides:       plymouth-scripts = 0
Provides:       libdnf5-plugin-actions = 0

%description
Empty package that Provides the snapshot/bootloader dependencies Ryoku's RPMs
declare. On this bootc image those roles are filled by bootc and rum instead,
so no real snapper, GRUB or Plymouth tooling is installed.

%install
mkdir -p %{buildroot}/usr/share/ryoku-rakuos-shims
printf '%s\n' 'See README.md: updates are bootc upgrade, rollback is bootc rollback.' \
    > %{buildroot}/usr/share/ryoku-rakuos-shims/README

%files
/usr/share/ryoku-rakuos-shims/README
EOF
rpmbuild --define "_topdir ${shimdir}" -bb "${shimdir}/ryoku-rakuos-shims.spec"
# RPM 6 on RakuOS refuses unsigned packages by default; this one is built
# locally in the image, so bypass signature/digest checks for it only.
rpm -Uvh --nodeps --nodigest --nosignature "${shimdir}"/RPMS/noarch/ryoku-rakuos-shims-*.rpm
rm -rf "${shimdir}"

# RakuOS symlinks /usr/local -> /var/usrlocal. The ryoku-desktop RPM ships
# /usr/local/share/applications/mimeapps.list, and cpio cannot create that path
# through a dangling symlink ("mkdir failed - File exists"). Pre-create it.
mkdir -p /var/usrlocal/share/applications

# ── Install the Ryoku desktop ────────────────────────────────────────────────
# `ryoku`        : the CLI (materialize, status, doctor)
# `ryoku-keyring`: owns the repo key so updates rotate it
# `ryoku-desktop-hyprland`: the umbrella package for the Hyprland desktop
rum install -y ryoku ryoku-keyring ryoku-desktop ryoku-desktop-hyprland

# ── Deploy the parts the RPM set does not ship ───────────────────────────────
# Ryoku's Fedora RPMs carry binaries and QML *modules*, but the shell's QML
# config (the actual UI), the Hub config, i18n catalog and systemd user units
# are deployed from the source tree by `ryoku/shell/deploy.sh`. On a mutable
# system the shell installer does that; here we bake the same files into the
# image so `ryoku materialize` can compose them into /etc/skel.
src=$(mktemp -d /var/tmp/ryoku-src.XXXXXX)
git clone --depth 1 --branch v1.1.0 https://github.com/Ryoku-dev/ryoku.git "${src}"

qmldir=/usr/lib64/qt6/qml
"${src}/ryoku/ui/install.sh" "${qmldir}"
"${src}/ryoku/shell/quickshell/plugins/kit/install.sh" "${qmldir}"
"${src}/ryoku/shell/framebars/install.sh" "${qmldir}"
rm -rf "${qmldir}/Ryoku/Wm/Hyprland"
mkdir -p "${qmldir}/Ryoku/Wm/Hyprland"
cp -a "${src}/ryoku/wm/hyprland/qml/." "${qmldir}/Ryoku/Wm/Hyprland/"

"${src}/ryoku/i18n/tools/install.sh" /usr/share
mkdir -p /usr/share/ryoku/config/quickshell/hub
cp -a "${src}/ryoku/shell/quickshell/." /usr/share/ryoku/config/quickshell/
cp -a "${src}/ryoku/hub/quickshell/." /usr/share/ryoku/config/quickshell/hub/

mkdir -p /etc/systemd/user
cp -a "${src}/ryoku/shell/systemd/user/." /etc/systemd/user/
systemctl --global enable ryoku-session.target 2>/dev/null || true
rm -rf "${src}"

# ── Stop RakuOS's desktop shell from fighting the Ryoku shell ────────────────
# Keep noctalia-greeter (it is the greetd session wrapper); disable only the
# desktop shell autostart. Globs are guarded so a new upstream package layout
# does not break the build.
shopt -s nullglob
for unit in /etc/xdg/autostart/*noctalia*.desktop /etc/xdg/autostart/*origami*.desktop; do
    rm -f "${unit}"
done
systemctl --global disable 'noctalia*.service' 2>/dev/null || true
systemctl --global disable 'origami*.service' 2>/dev/null || true

# ── Wayland session ──────────────────────────────────────────────────────────
# Written here rather than copied from system_files: an RPM may own the file
# at the same path and clobber a COPY. uwsm is already set up by the base image.
mkdir -p /usr/share/wayland-sessions
cat > /usr/share/wayland-sessions/ryoku.desktop <<'EOF'
[Desktop Entry]
Name=Ryoku (Hyprland)
Comment=Ryoku desktop on Hyprland
Exec=env UWSM_SILENT_START=2 uwsm start -e -D Hyprland hyprland.desktop
TryExec=uwsm
DesktopNames=Ryoku;Hyprland
Type=Application
EOF

# ── Tell rum this image is a different DE ────────────────────────────────────
# RakuOS detects a DE change at boot and soft-resets the overlay from
# packages.list. Marking the Ryoku packages protected keeps them across it.
echo "ryoku" > /usr/share/rakuos/de-name
if [ -f /usr/share/rakuos/protected-packages.txt ]; then
    for pkg in ryoku ryoku-keyring ryoku-desktop-hyprland quickshell ryoku-rakuos-shims; do
        grep -qx "  ${pkg}" /usr/share/rakuos/protected-packages.txt || \
            printf '  %s\n' "${pkg}" >> /usr/share/rakuos/protected-packages.txt
    done
fi
if [ -x /usr/libexec/rakuos/generate-base-manifest ]; then
    /usr/libexec/rakuos/generate-base-manifest
fi

# ── Seed new users' config ──────────────────────────────────────────────────
# `ryoku materialize` writes ~/.config from the installed desktop tree. Run it
# once during the build against a throwaway HOME and bake the result into
# /etc/skel, so the first session already has the right config.
seed=$(mktemp -d /var/tmp/ryoku-skel.XXXXXX)
if HOME="${seed}" XDG_CONFIG_HOME="${seed}/.config" ryoku materialize; then
    rm -rf /etc/skel/.config
    cp -a "${seed}/.config" /etc/skel/
    echo "[ryoku-on-rakuos] seeded /etc/skel/.config from ryoku materialize"
else
    echo "[ryoku-on-rakuos] WARNING: ryoku materialize failed; run it after first login" >&2
fi
rm -rf "${seed}"

# ── Put third-party repos back to disabled ──────────────────────────────────
rum config-manager --default --set-disabled terra 2>/dev/null || true
rum config-manager --default --set-disabled 'rpmfusion-*' 2>/dev/null || true

echo "[ryoku-on-rakuos] done"
