# Kestrel ISO

Builds the Kestrel live ISO: the image you boot to try Kestrel and to install it.

The live session is a full Kestrel desktop, not a text installer. The installer writes the running system to the target disk by copying it, so the machine you end up with is the machine you were just using. This is the casper/anaconda model rather than the Arch package-by-package model, and it is deliberate: there is no second definition of "what Kestrel is" to drift from the one you tested, and no package repository has to ride along on the medium.

## How an install works

- The ISO boots the Kestrel desktop as a dedicated `kestrel` live user (autologin, passwordless sudo).
- "Install Kestrel" lives at the root of the Super + D menu; it runs the configurator, then partitions the disk, copies the root filesystem, personalizes it (hostname, locale, user, bootloader), and reboots.
- Encryption is on by default. The same wizard can install without encryption, install into free space alongside another OS, or prepare the machine for a different owner and defer account setup to first boot.
- Everything needed to install is already in the image. The only network the live session might use is optional: hardware-specific packages the installer detects it needs.

## Creating the ISO

Run `./bin/kestrel-iso-make`; the output lands in `./release`.

The builder needs network access. It upgrades its Arch container, resolves the Arch package set from the payload's `install/*.packages` files, builds the AUR and source packages the payload needs (`trustsight` is built from its GitHub source), downloads the bundled Node tarball, and assembles the squashfs and boot loaders.

`--local-source` builds from the sibling `../kestrel` checkout (the default when that directory exists) instead of cloning the payload. `--no-cache` ignores the caches described below. `--no-boot-offer` skips the prompt to boot the result.

Caches live under `~/.cache/kestrel/`: `pacman-pkg/` for Arch packages, and `aur-packages/` for the AUR and source builds. They persist across runs, so repeat builds are much faster; a complete AUR cache skips the AUR build entirely.

### Environment variables

- `KESTREL_INSTALLER_REPO` the GitHub repository for the payload (default: `kestrel-distro/kestrel`).
- `KESTREL_INSTALLER_REF` the git ref (branch or tag) for the payload (default: `main`). Ignored with `--local-source`.

```bash
KESTREL_INSTALLER_REPO="myuser/kestrel-fork" KESTREL_INSTALLER_REF="some-feature" ./bin/kestrel-iso-make
```

## Repository layout

- `builder/build-iso.sh` the build, run inside an `archlinux/archlinux` container.
- `configs/` the archiso profile and the airootfs overlay: `profiledef.sh`, the boot loader configs, and the live-only files under `airootfs/` (the installer, the configurator, the live init, and the pre-boot seed).
- `bin/` the driver scripts: `kestrel-iso-make`, `kestrel-iso-boot`, `kestrel-iso-sign`, `kestrel-iso-release`.
- `archiso/` a vendored copy of upstream archiso, pinned as a submodule.
- `release/` build output (ignored by git).

## Testing the ISO

Run `./bin/kestrel-iso-boot`. It installs `qemu-full` and `edk2-ovmf` if they are missing, then boots the ISO under UEFI with a scratch disk attached. This is the only supported way to exercise an install: do not run the installer against your own machine.

## Signing and releasing

- `./bin/kestrel-iso-sign [gpg-user] [release/iso]` signs the image.
- `./bin/kestrel-iso-release` builds, signs, and prints the checksum.

## License

Released under the MIT License. See [LICENSE](LICENSE).
