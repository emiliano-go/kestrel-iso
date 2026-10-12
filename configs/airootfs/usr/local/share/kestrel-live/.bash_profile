# Live ISO: start the Kestrel desktop on the first virtual terminal.
# Only when nothing graphical is already running, so subshells and scp/ssh
# logins never try to start a second session.
if [[ $(tty 2>/dev/null) == /dev/tty1 && -z ${WAYLAND_DISPLAY:-} && -z ${KESTREL_LIVE_SESSION:-} ]]; then
  export KESTREL_LIVE_SESSION=1
  exec uwsm start -g -1 -e -D Hyprland hyprland.desktop
fi
