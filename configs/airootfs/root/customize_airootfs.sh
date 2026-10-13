#!/bin/bash
# Runs inside the airootfs chroot during the ISO build, after packages are
# installed and the custom airootfs files are copied in.

set -euo pipefail

export KESTREL_PATH=/usr/share/kestrel

# The payload is copied in preserving source modes; make sure every command is
# runnable before we invoke one (and so the installed copy stays runnable).
find "$KESTREL_PATH/bin" -type f -exec chmod +x {} +

# Turn the freshly pacstrapped tree into an installed-shaped Kestrel system: the
# /usr/bin command symlinks, Kestrel-owned /etc drop-ins, the /usr integration
# files, and the /etc/skel seed new users are created from. The installer copies
# this tree to disk, so what the live session runs is what gets installed.
"$KESTREL_PATH/bin/kestrel-apply-system-files"

# Kestrel tracks upstream Arch mirrors; both the live session and the installed
# copy use the stable repository set.
install -Dm644 "$KESTREL_PATH/default/pacman/pacman-stable.conf" /etc/pacman.conf
install -Dm644 "$KESTREL_PATH/default/pacman/mirrorlist-stable" /etc/pacman.d/mirrorlist

# The kernel ships under /usr/lib/modules/<ver>/vmlinuz and is normally copied to
# /boot/vmlinuz-<pkgbase> by the mkinitcpio pacman hook. The AUR limine hook
# shadows that hook during the build, so the copy never happens; the archiso
# preset and mkarchiso both expect /boot/vmlinuz-linux, so place it here.
for kernel in /usr/lib/modules/*/vmlinuz; do
  [[ -e $kernel ]] || continue
  install -Dm644 "$kernel" /boot/vmlinuz-linux
done

# The AUR limine hook deploys to a FAT32 ESP, which does not exist while the ISO
# is being built, so its install-time run aborts initramfs generation. Build the
# live initramfs with the stock mkinitcpio (the package's /usr/local/bin/mkinitcpio
# wrapper is what pulls the deploy step in); the hook files stay installed for
# the target, where an ESP does exist.
if [[ ! -e /boot/initramfs-linux.img ]]; then
  /usr/bin/mkinitcpio -P
fi
