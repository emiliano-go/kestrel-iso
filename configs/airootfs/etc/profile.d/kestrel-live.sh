# Live ISO: the payload lives at the installed-system path so the shell and menu
# resolve their KESTREL_PATH-based paths.
export KESTREL_PATH=/usr/share/kestrel
case ":$PATH:" in
*":$KESTREL_PATH/bin:"*) ;;
*) export PATH="$KESTREL_PATH/bin:$PATH" ;;
esac
