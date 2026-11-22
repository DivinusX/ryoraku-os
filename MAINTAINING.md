# Maintaining Ryoraku OS

Short runbook for the person publishing images. End-user docs live in `README.md`.

## 0. Security first

- **Never paste a Personal Access Token in chat, issues or logs.** The GitHub Actions workflow
  uses the built-in `GITHUB_TOKEN`; no PAT is needed.
- If a token is ever exposed, revoke it immediately at
  GitHub → Settings → Developer settings → Personal access tokens, then issue a new one.
- Keep 2FA enabled on the maintainer account.
- Do not put personal files, dotfiles, credentials or wallpapers in `system_files/`. Everything in
  that directory is baked into every user's image.

## 1. Publish an update

The `.github/workflows/build-image.yml` workflow is fully automated:

1. **Daily check** (and on demand): it computes a fingerprint from the latest Ryoku release tag
   plus the RakuOS base image digest, and compares it with the label
   `org.ryoraku.fingerprint` on the published GHCR image.
2. **If nothing changed**, the build is skipped — no wasted runner time.
3. **If something changed**, it pins the new `RYOKU_REF`, builds both stages, runs
   `image-check.sh` **inside the image**, pushes to GHCR, makes the package public and creates a
   GitHub Release containing the exact digest.
4. To force a rebuild without an upstream change, run the workflow manually with **force** checked.

What you still do:

- Watch the Actions run for failures (the in-image smoke test is the gate).
- Confirm once that the GHCR package `ryoraku` is public.
- Spot-check a real boot after a release, then point users at the new digest if needed.
- Optional: run `./update.sh` locally to verify a build before pushing changes.

Users update with `sudo bootc upgrade` + `rum update`. No tar files, no local builds.

## 2. What to watch upstream

| Upstream | What matters | Where |
|---|---|---|
| RakuOS | New Fedora base / image tag, `rum` changes, kernel & MOK changes, signed-module changes | https://gitlab.com/rakuos/images/rakuos-hyprland |
| Ryoku | New release tag, Fedora RPM repo for the running Fedora release, **release key rotation**, new QML modules | https://github.com/Ryoku-dev/ryoku · https://repo.ryoku.dev/stable/fedora/releases |

`update.sh` auto-detects the newest Ryoku release tag and writes it to `build_files/RYOKU_REF`.
Ryoku RPMs are always installed fresh from the signed repository.
The build pins Ryoku's key fingerprint `EB6D3C0F55A7B3CABA6B2838847B274F025DD6E3` — if Ryoku
rotates it, update both `build_files/ryoku.sh` and
`system_files/etc/pki/rpm-gpg/RPM-GPG-KEY-ryoku`.

The `chunkah` digest in `Containerfile` is pinned to the same version RakuOS uses. Only change it
when RakuOS changes it, and rebuild fully: a different version plans layers differently.

## 3. Test before declaring an image good

```sh
./smoke-test.sh
podman run --rm -it --privileged localhost/ryoku-on-rakuos:test /bin/bash
```

Then, on a real RakuOS test machine:

1. `sudo bootc switch --retain ghcr.io/divinusx/ryoraku:latest`
2. `sudo reboot`, choose **Ryoku (Hyprland)** at the greeter.
3. Confirm `systemctl --user status ryoku-shell` is `active (running)`.
4. Confirm `sudo bootc status` shows the expected digest.
5. Test `sudo bootc rollback && sudo reboot` once, then `sudo bootc upgrade` again.

Do not ship an image that has not passed the real-boot test.

## 4. Releases and known-good digests

Tag tested builds so users can pin a known-good image if a newer one breaks:

```sh
git tag -a v1.1.0-ryoraku.1 -m 'Tested image for Ryoku 1.1.0 / RakuOS 45'
git push --tags
```

Record the GHCR digest of each tested image in the release notes. Users can pin it with:

```sh
sudo bootc switch ghcr.io/divinusx/ryoraku@sha256:<digest>
```

## 5. Repository hygiene

- Keep `README.md` and this file in English.
- Never commit `out.ociarchive` or `*.image.tar` — `.gitignore` already excludes them.
- Keep the GPL-3.0 `LICENSE` and upstream notices; Ryoku and its components are GPL-3.0.
- Do not add personal keys, tokens or machine-specific config to the repository.
- If you add branding or a custom theme, keep it clearly separated from upstream content so
  future syncs from Ryoku stay easy.

## 6. User support

- Install, update and rollback instructions are in `README.md`.
- If a user reports broken apps they installed themselves, the fix is `rum update` or
  `rum install <package>`; base rollback does not touch their own packages.
- If a user's shell does not appear, have them run `ryoku materialize` and start
  `ryoku-session.target` as documented in the README.
