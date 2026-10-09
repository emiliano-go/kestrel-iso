# Installer helpers for the live ISO. Self-locating so the live environment
# can source this tree from /root/helpers regardless of KESTREL_INSTALL.
helpers_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$helpers_dir/chroot.sh"
source "$helpers_dir/presentation.sh"
source "$helpers_dir/errors.sh"
source "$helpers_dir/logging.sh"
