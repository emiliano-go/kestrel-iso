#!/bin/bash

set -e

# Note that these are packages installed to the Arch container used to build the ISO.
pacman-key --init
pacman --noconfirm -Sy archlinux-keyring
pacman --noconfirm -Sy archiso git sudo base-devel jq grub

# AUR packages pull multilib dependencies (lib32-zlib, lib32-libglvnd, ...);
# the base container ships multilib commented out, so enable it.
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
  pacman --noconfirm -Sy >/dev/null
fi

# Setup build locations
build_cache_dir="/var/cache"
offline_mirror_dir="$build_cache_dir/airootfs/var/cache/kestrel/mirror/offline"
mkdir -p $build_cache_dir/
mkdir -p $offline_mirror_dir/

# We base our ISO on the official arch ISO (releng) config
cp -r /archiso/configs/releng/* $build_cache_dir/
rm "$build_cache_dir/airootfs/etc/motd"

# The vendored archiso releng list can name packages Arch has since dropped
# (broadcom-wl, for one). Keep only what the repositories still provide so the
# offline download step does not abort on an unresolvable target.
pacman --noconfirm -Sy >/dev/null
mapfile -t releng_pkgs <"$build_cache_dir/packages.x86_64"
: >"$build_cache_dir/packages.x86_64"
for pkg in "${releng_pkgs[@]}"; do
  if pacman -Si "$pkg" >/dev/null 2>&1; then
    printf '%s\n' "$pkg" >>"$build_cache_dir/packages.x86_64"
  else
    echo "Dropping unavailable live-env package: $pkg" >&2
  fi
done

# Avoid using reflector for mirror identification as we are relying on the global CDN
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service"
rm -rf "$build_cache_dir/airootfs/etc/systemd/system/reflector.service.d"
rm -rf "$build_cache_dir/airootfs/etc/xdg/reflector"

# Bring in our configs
cp -r /configs/* $build_cache_dir/

# Setup Kestrel itself
if [[ -d /kestrel ]]; then
  cp -rp /kestrel "$build_cache_dir/airootfs/root/kestrel"
else
  git clone -b $KESTREL_INSTALLER_REF https://github.com/$KESTREL_INSTALLER_REPO.git "$build_cache_dir/airootfs/root/kestrel"
fi

# The live session runs the payload from /usr/share/kestrel, the same layout an
# installed system uses, so the shell and menu resolve their paths.
mkdir -p "$build_cache_dir/airootfs/usr/share"
cp -rp "$build_cache_dir/airootfs/root/kestrel" "$build_cache_dir/airootfs/usr/share/kestrel"
rm -rf "$build_cache_dir/airootfs/usr/share/kestrel/.git"

# Baked skel for the `kestrel` live user: the shipped user config the init
# service seeds into its home at boot.
live_skel="$build_cache_dir/airootfs/usr/local/share/kestrel-live"
mkdir -p "$live_skel/.config"
cp -rp "$build_cache_dir/airootfs/root/kestrel/config/." "$live_skel/.config/"
cp -p "$build_cache_dir/airootfs/root/kestrel/default/bashrc" "$live_skel/.bashrc"
mkdir -p "$live_skel/.local/share/nautilus-python/extensions"
cp -rp "$build_cache_dir/airootfs/root/kestrel/default/nautilus-python/extensions/." \
  "$live_skel/.local/share/nautilus-python/extensions/" 2>/dev/null || true
mkdir -p "$live_skel/.local/state/kestrel/toggles/hypr"
cp -rp "$build_cache_dir/airootfs/root/kestrel/default/hypr/toggles/." \
  "$live_skel/.local/state/kestrel/toggles/hypr/" 2>/dev/null || true
mkdir -p "$live_skel/.config/kestrel/branding"
cp -p "$build_cache_dir/airootfs/root/kestrel/icon.txt" "$live_skel/.config/kestrel/branding/about.txt"
cp -p "$build_cache_dir/airootfs/root/kestrel/logo.txt" "$live_skel/.config/kestrel/branding/screensaver.txt"

# Make log uploader available in the ISO too
mkdir -p "$build_cache_dir/airootfs/usr/local/bin/"
cp "$build_cache_dir/airootfs/root/kestrel/bin/kestrel-upload-log" "$build_cache_dir/airootfs/usr/local/bin/kestrel-upload-log"

# Copy the Kestrel Plymouth theme to the ISO
mkdir -p "$build_cache_dir/airootfs/usr/share/plymouth/themes/kestrel"
cp -r "$build_cache_dir/airootfs/root/kestrel/default/plymouth/"* "$build_cache_dir/airootfs/usr/share/plymouth/themes/kestrel/"

# Download and verify Node.js binary for offline installation
NODE_DIST_URL="https://nodejs.org/dist/latest"

# Get checksums and parse filename and SHA
NODE_SHASUMS=$(curl -fsSL "$NODE_DIST_URL/SHASUMS256.txt")
NODE_FILENAME=$(echo "$NODE_SHASUMS" | grep "linux-x64.tar.gz" | awk '{print $2}')
NODE_SHA=$(echo "$NODE_SHASUMS" | grep "linux-x64.tar.gz" | awk '{print $1}')

# Download the tarball
curl -fsSL "$NODE_DIST_URL/$NODE_FILENAME" -o "/tmp/$NODE_FILENAME"

# Verify SHA256 checksum
echo "$NODE_SHA /tmp/$NODE_FILENAME" | sha256sum -c - || {
    echo "ERROR: Node.js checksum verification failed!"
    exit 1
}

# Copy to ISO
mkdir -p "$build_cache_dir/airootfs/opt/packages/"
cp "/tmp/$NODE_FILENAME" "$build_cache_dir/airootfs/opt/packages/"

# Live environment packages. Start from the releng set (already in
# packages.x86_64) and add the full Kestrel desktop so the ISO boots to a
# graphical Hyprland + Quickshell session. mkarchiso installs these from the
# bundled [offline] repo below.
arch_packages=(linux git gum jq openssl plymouth)
mapfile -t kestrel_desktop < <(grep -hvE '^[[:space:]]*(#|$)' \
  "$build_cache_dir/airootfs/root/kestrel/install/kestrel-base.packages" \
  "$build_cache_dir/airootfs/root/kestrel/install/kestrel-other.packages")
printf '%s\n' "${arch_packages[@]}" "${kestrel_desktop[@]}" >>"$build_cache_dir/packages.x86_64"

# Build list of all the packages needed for the offline mirror. The live list
# already carries the base/other desktop set; add the archinstall substrate.
all_packages=($(cat "$build_cache_dir/packages.x86_64"))
all_packages+=($(grep -v '^#' /builder/archinstall.packages | grep -v '^$'))

# Download all the packages to the offline mirror inside the ISO
mkdir -p /tmp/offlinedb
pacman --config /configs/pacman-online.conf --noconfirm -Syw "${all_packages[@]}" --cachedir $offline_mirror_dir/ --dbpath /tmp/offlinedb
repo-add --new "$offline_mirror_dir/offline.db.tar.gz" "$offline_mirror_dir/"*.pkg.tar.zst

# Build AUR packages and add them to the offline mirror. AUR packages can depend
# on other AUR packages, so build `yay` first and let it resolve the rest of the
# closure instead of failing on the first missing AUR dependency.
aur_pkg_list="$build_cache_dir/airootfs/root/kestrel/install/kestrel-aur.packages"
if [[ -f "$aur_pkg_list" ]] && grep -qvE '^\s*(#|$)' "$aur_pkg_list"; then
  aur_names=()
  while IFS= read -r entry; do
    [[ -z $entry ]] && continue
    # The list pins a frozen version as name=version.
    aur_names+=("${entry%%=*}")
  done < <(grep -vE '^\s*(#|$)' "$aur_pkg_list")

  useradd -m builduser
  echo "builduser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
  echo "Defaults:builduser !syslog" >> /etc/sudoers

  aur_pkgdest="/tmp/aur-packages"
  aur_build_dir=/tmp/aur-build
  mkdir -p "$aur_build_dir" "$aur_pkgdest"
  chown builduser:builduser "$aur_build_dir" "$aur_pkgdest"

  build_aur() {
    local pkg="$1" dir="$aur_build_dir/$1"
    echo "Building AUR package: $pkg"
    rm -rf "$dir"
    mkdir -p "$dir"
    chown builduser:builduser "$dir"
    su - builduser -c "cd '$dir' && git clone --depth 1 https://aur.archlinux.org/$pkg.git . && PKGDEST='$aur_pkgdest' makepkg -s -f --noconfirm --nocheck"
  }

  # yay first, so it can resolve AUR dependencies for everything else.
  build_aur yay
  pacman -U --noconfirm "$aur_pkgdest"/yay-*.pkg.tar.zst

  yay_names=()
  for name in "${aur_names[@]}"; do
    [[ $name == yay ]] && continue
    yay_names+=("$name")
  done
  echo "Installing AUR closure: ${yay_names[*]}"
  su - builduser -c "PKGDEST='$aur_pkgdest' yay -S --noconfirm --needed --answerclean None --answerdiff None --removemake --mflags '--nocheck' ${yay_names[*]}"

  # Collect every package built (the pinned list plus any AUR dependencies)
  # before tearing the build user down; the container is disposable, so a
  # lingering process must not abort the build.
  cp "$aur_pkgdest"/*.pkg.tar.zst "$offline_mirror_dir/" 2>/dev/null || true
  pkill -u builduser 2>/dev/null || true
  userdel -r builduser 2>/dev/null || true

  # Rebuild repo database to include AUR packages
  repo-add --new "$offline_mirror_dir/offline.db.tar.gz" "$offline_mirror_dir/"*.pkg.tar.zst
fi

# Create a symlink to the offline mirror instead of duplicating it.
# mkarchiso needs packages at /var/cache/kestrel/mirror/offline in the container,
# but they're actually in $build_cache_dir/airootfs/var/cache/kestrel/mirror/offline
mkdir -p /var/cache/kestrel/mirror
ln -s "$offline_mirror_dir" "/var/cache/kestrel/mirror/offline"

# Copy the pacman.conf to the ISO's /etc directory so the live environment uses our
# same config when booted
cp $build_cache_dir/pacman.conf "$build_cache_dir/airootfs/etc/pacman.conf"

# Finally, we assemble the entire ISO
mkarchiso -v -w "$build_cache_dir/work/" -o "/out/" "$build_cache_dir/"

# Fix ownership of output files to match host user
if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
    chown -R "$HOST_UID:$HOST_GID" /out/
fi
