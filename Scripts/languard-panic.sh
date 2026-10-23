#!/bin/bash
# LanGuard panic: restore normal networking by removing connection protection
# (the stable address and its two /1 routes). Works even if LanGuard is hung.
# Run:  bash Scripts/languard-panic.sh   (asks for your password)
# Optional: bind it in Raycast as a Script Command; the header below is all it needs.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title LanGuard Panic
# @raycast.mode fullOutput
# @raycast.packageName LanGuard

H=/Library/PrivilegedHelperTools/languard-net
if [ -x "$H" ] && sudo "$H" panic; then echo "Normal networking restored"; exit 0; fi
# No helper (or it failed): inline teardown, same as the README one-liner. Removes only en* /1 routes + en* /32 aliases.
sudo bash -s <<'EOF' && echo "Normal networking restored" || { echo "Panic failed: reboot restores normal networking"; exit 1; }
for n in 0.0.0.0/1 128.0.0.0/1; do i=$(route -n get -net $n 2>/dev/null | awk '$1=="interface:"{print $2}'); case $i in en[0-9]*) route -q -n delete -net $n;; esac; done; for i in $(ifconfig -l | tr ' ' '\n' | grep -E '^en[0-9]+$'); do p=$(ipconfig getifaddr $i); ifconfig $i | awk '/inet .* netmask 0xffffffff/{print $2}' | while read a; do [ "$a" != "$p" ] && ifconfig $i inet $a -alias; done; done; rm -f /var/run/languard-net.state; touch /var/run/languard-net.panic
EOF
