#!/bin/bash
# LanGuard root helper: keeps a stable /32 address A ("protection") on whichever wired/Wi-Fi
# interface is active, and routes all non-local IPv4 through it with two /1 routes, so
# connections survive LAN <-> Wi-Fi switches.
#
# Installed root:wheel 0755 at /Library/PrivilegedHelperTools/languard-net, run via
# `sudo -n` (sudoers grants exactly this path) and by the LaunchDaemon
# com.roypadina.languard-net every 3 s (`check`).
#
# SAFETY CONTRACT: the only things this script ever creates are one /32 alias on an en*
# interface and the routes 0.0.0.0/1 + 128.0.0.0/1 via en*. `down` removes exactly those
# (never a utun's /1, never a DHCP address, never the default route, DNS, service order or
# Wi-Fi power). Everything it creates is non-persistent: a reboot clears it.
#
# Verbs: up <iface> <A> <pid> | move <iface> | adopt <pid> | down | panic | arm | check | status
#        netinfo <iface>   (read-only: router IP + MAC on iface; root sees ARP despite Local Network privacy)
# Exit codes: 0 ok, 2 bad args, 3 route/VPN conflict, 4 panic set, 5 other instance,
#             6 address taken, 7 verify failed (rolled back), 8 no state, 9 guardian not running.
set -u
PATH=/usr/sbin:/sbin:/usr/bin:/bin
export PATH
STATE=/var/run/languard-net.state
PANIC=/var/run/languard-net.panic
FAIL=/var/run/languard-net.fail
TICK=/var/run/languard-net.tick      # written by every `check`: proof the guardian runs
REASON=/var/run/languard-net.reason  # why the guardian last tore down (iface-gone|link|network|vpn|unhealthy)
NETS="0.0.0.0/1 128.0.0.0/1"

is_iface() { [[ "$1" =~ ^en[0-9]{1,2}$ ]] && ifconfig "$1" >/dev/null 2>&1; }
is_ip()    { [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] &&
             for o in "${BASH_REMATCH[@]:1}"; do ((10#$o <= 255)) || return 1; done; }
is_pid()   { [[ "$1" =~ ^[0-9]{1,7}$ ]] && (( 10#$1 >= 2 )); }
ip2int()   { local IFS=. a b c d; read -r a b c d <<<"$1"; echo $(( (10#$a<<24) + (10#$b<<16) + (10#$c<<8) + 10#$d )); }
dhcp_ip()  { ipconfig getifaddr "$1" 2>/dev/null; }
router()   { ipconfig getoption "$1" router 2>/dev/null; }
gw_mac()   { arp -n "$1" 2>/dev/null | grep -oE '([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}' | head -1; }
# MAC in arp's short form (no leading zeros per octet: 0b:00 -> b:0) so ifconfig and arp compare equal.
norm_mac() { tr 'A-F' 'a-f' | sed -E 's/(^|:)0([0-9a-f])/\1\2/g'; }
# This Mac's own adapter MACs (normalized), one per line.
own_macs() { ifconfig 2>/dev/null | awk '/ether /{print $2}' | norm_mac; }
# Someone ELSE answers ARP for $1 (our own stale entries, e.g. after a relaunch, don't count).
arp_taken() {
  local m; m=$(arp -n "$1" 2>/dev/null | grep -oE '([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}' | head -1 | norm_mac)
  [ -n "$m" ] && ! own_macs | grep -qxF "$m"
}
mask()     { ipconfig getoption "$1" subnet_mask 2>/dev/null; }
link_up()  { [ "$(ifconfig "$1" 2>/dev/null | awk '/status:/{print $2}')" = active ]; }
# Interface of OUR exact /1 route, or empty. `route get -net` falls back to the default route when
# the /1 is absent, so require mask 128.0.0.0 (gate-2 blocker #1).
route_if() { route -n get -net "$1" 2>/dev/null | awk '$1=="mask:"{m=$2} $1=="interface:"{i=$2} END{if(m=="128.0.0.0")print i}'; }
default_if() { route -n get default 2>/dev/null | awk '$1=="interface:"{print $2}'; }
holders()  { for i in $(ifconfig -l); do ifconfig "$i" | grep -q "inet $1 " && echo "$i"; done; }
# State file: KEY=value lines; values were validated before being written. Parsed, never sourced.
state()    { [ -f "$STATE" ] && awk -F= -v k="$1" '$1==k{print $2}' "$STATE"; }
log()      { logger -t languard-net "$*"; }
# Does any en* interface have a DHCP address right now?
any_dhcp() { local i; for i in $(ifconfig -l | tr ' ' '\n' | grep -E '^en[0-9]+$'); do is_ip "$(dhcp_ip "$i")" && return 0; done; return 1; }
# Is $1 a live LanGuard process? (kill -0 alone is fooled by pid reuse)
lg_alive() { is_pid "$1" && ps -o comm= -p "$1" 2>/dev/null | grep -q LanGuard; }

# Remove ONLY what this helper creates; idempotent; safe to run anytime.
# With state: remove our address A only. Without state (or `panic`): sweep every non-DHCP /32 alias on en*.
down() {
  local n i pri a own=""
  [ "${1:-}" = sweep ] || own=$(state A)
  for n in $NETS; do
    i=$(route_if "$n")
    case "$i" in en[0-9]*) route -q -n delete -net "$n" >/dev/null 2>&1 ;; esac   # never a utun's /1
  done
  for i in $(ifconfig -l | tr ' ' '\n' | grep -E '^en[0-9]+$'); do
    pri=$(dhcp_ip "$i")
    ifconfig "$i" | awk '/inet .* netmask 0xffffffff/{print $2}' | while read -r a; do
      [ "$a" != "$pri" ] && { [ -z "$own" ] || [ "$a" = "$own" ]; } && ifconfig "$i" inet "$a" -alias
    done
  done
  rm -f "$STATE" "$FAIL"
}

# Add alias + both routes on iface; verify. Any failure -> down + exit 7.
attach() { # iface A gw
  local n
  for n in $NETS; do case "$(route_if "$n")" in ""|en[0-9]*) ;; *) down; exit 3 ;; esac; done   # a VPN's /1: never repoint it
  ifconfig "$1" inet "$2" netmask 255.255.255.255 alias 2>/dev/null
  for n in $NETS; do
    # Never `route change`: on a missing /1 (e.g. a concurrent teardown) it edits the DEFAULT route.
    # Delete our en* /1 if present, then add. Routes don't own sockets, so the ms gap is harmless.
    case "$(route_if "$n")" in en[0-9]*) route -q -n delete -net "$n" >/dev/null 2>&1 ;; esac
    route -q -n add -net "$n" "$3" -ifp "$1" -ifa "$2" >/dev/null 2>&1
  done
  sleep 1; ifconfig "$1" inet "$2" netmask 255.255.255.255 alias 2>/dev/null   # 2nd gratuitous ARP
  # Many home routers ignore gratuitous ARP for an existing entry but DO update it from an ARP request
  # aimed at them (RFC 826 merge): forget our cached router entry on this link, then ping it FROM A.
  arp -d "$3" ifscope "$1" >/dev/null 2>&1
  ping -c1 -t1 -q -b "$1" -S "$2" "$3" >/dev/null 2>&1
  for n in $NETS; do [ "$(route_if "$n")" = "$1" ] || { log "verify failed ($n)"; down; exit 7; }; done
  [ "$(holders "$2")" = "$1" ] || { log "verify failed (alias)"; down; exit 7; }
  [ -f "$PANIC" ] && { down sweep; exit 4; }                                     # panic landed while we worked
}

write_state() { # A iface gw pid mac
  local tmp; tmp=$(mktemp /var/run/languard-net.XXXXXX) || { down; exit 7; }
  printf 'A=%s\nIFACE=%s\nGW=%s\nPID=%s\nMAC=%s\n' "$1" "$2" "$3" "$4" "$5" >"$tmp"
  chmod 644 "$tmp"; mv -f "$tmp" "$STATE"
}

cmd_up() { # iface A pid
  [ $# -eq 3 ] && is_iface "$1" && is_ip "$2" && is_pid "$3" || exit 2
  local ifc=$1 A=$2 pid=$3 gw pri m n old
  [ -f "$PANIC" ] && exit 4
  local t; t=$(cat "$TICK" 2>/dev/null); [[ "$t" =~ ^[0-9]+$ ]] && (( $(date +%s) - t <= 15 )) || exit 9   # no guardian, no protection
  old=$(state PID)
  if [ -n "$old" ] && [ "$old" != "$pid" ] && lg_alive "$old"; then exit 5; fi
  for n in $NETS; do case "$(route_if "$n")" in ""|en[0-9]*) ;; *) exit 3 ;; esac; done   # a VPN's /1 (utun): step aside
  case "$(default_if)" in en[0-9]*) ;; *) exit 3 ;; esac                         # VPN / exit node owns default
  link_up "$ifc" || exit 2
  pri=$(dhcp_ip "$ifc"); gw=$(router "$ifc"); m=$(mask "$ifc")
  is_ip "$pri" && is_ip "$gw" && is_ip "$m" || exit 2
  local ai pi mi; ai=$(ip2int "$A"); pi=$(ip2int "$pri"); mi=$(ip2int "$m")
  (( (ai & mi) == (pi & mi) )) || exit 2                                         # same subnet
  (( ((ai & ~mi) & 0xFFFFFFFF) != 0 && ((ai | mi) & 0xFFFFFFFF) != 0xFFFFFFFF )) || exit 2 # not network/broadcast
  [ "$A" != "$pri" ] && [ "$A" != "$gw" ] || exit 2
  down                                                                          # clean slate (stale state, leftover /1 via en*)
  [ -z "$(holders "$A")" ] || exit 6
  ping -c1 -t1 -q -b "$ifc" "$A" >/dev/null 2>&1
  arp_taken "$A" && exit 6                                                       # another device answers for A
  write_state "$A" "$ifc" "$gw" "$pid" "$(gw_mac "$gw")"                        # state first: check covers a crash mid-up
  attach "$ifc" "$A" "$gw"
  log "up $A on $ifc via $gw"
}

cmd_move() { # iface
  [ $# -eq 1 ] && is_iface "$1" || exit 2
  local ifc=$1 A cur gw pid mac
  A=$(state A); cur=$(state IFACE); gw=$(state GW); pid=$(state PID); mac=$(state MAC)
  [ -n "$A" ] || exit 8
  link_up "$ifc" && is_ip "$(dhcp_ip "$ifc")" || exit 2
  [ "$(router "$ifc")" = "$gw" ] || { down; exit 3; }                           # different network: drop protection
  [ -n "$(gw_mac "$gw")" ] || ping -c1 -t1 -q -b "$ifc" "$gw" >/dev/null 2>&1     # fresh link: fill the ARP entry
  [ -z "$mac" ] || [ "$(gw_mac "$gw")" = "$mac" ] || { down; exit 3; }          # same router IP, different router
  [ "$ifc" = "$cur" ] && [ "$(holders "$A")" = "$ifc" ] && return 0
  [ -n "$cur" ] && ifconfig "$cur" inet "$A" -alias 2>/dev/null
  write_state "$A" "$ifc" "$gw" "$pid" "$mac"
  attach "$ifc" "$A" "$gw"
  log "move $A to $ifc"
}

cmd_adopt() { # pid: a relaunched LanGuard takes over existing state if it is still sane
  [ $# -eq 1 ] && is_pid "$1" || exit 2
  [ -f "$STATE" ] || exit 8
  local old; old=$(state PID)
  if [ "$old" != "$1" ] && lg_alive "$old"; then exit 5; fi
  write_state "$(state A)" "$(state IFACE)" "$(state GW)" "$1" "$(state MAC)"
}

# Guardian (LaunchDaemon, every 3 s). Judges kernel state only; tears down when it is not sane.
cmd_check() {
  date +%s >"$TICK"
  [ -f "$PANIC" ] && [ -f "$STATE" ] && { echo panic >"$REASON"; down sweep; exit 0; }   # panic always wins within 3 s
  [ -f "$STATE" ] || { rm -f "$FAIL"; exit 0; }
  local A ifc gw pid why="" n fails limit plain
  A=$(state A); ifc=$(state IFACE); gw=$(state GW); pid=$(state PID)
  if ! is_ip "$A" || ! is_iface "$ifc" || ! is_ip "$gw"; then echo iface-gone >"$REASON"; down; log "check: iface gone/bad state, down"; exit 0; fi
  link_up "$ifc" && is_ip "$(dhcp_ip "$ifc")" || why="link"
  [ -z "$why" ] && [ "$(router "$ifc")" != "$gw" ] && why=network
  [ -z "$why" ] && case "$(default_if)" in en[0-9]*) ;; *) why=vpn ;; esac
  [ -z "$why" ] && [ "$(holders "$A")" != "$ifc" ] && why=unhealthy
  if [ -z "$why" ]; then for n in $NETS; do [ "$(route_if "$n")" = "$ifc" ] || why=unhealthy; done; fi
  if [ -z "$why" ] && ! ping -c1 -t1 -q -S "$A" "$gw" >/dev/null 2>&1; then
    plain=$(dhcp_ip "$ifc")
    if ping -c1 -t1 -q -S "$plain" "$gw" >/dev/null 2>&1; then why=unhealthy        # gateway answers plain, not via A
    elif ! nc -z -w2 -s "$A" 1.1.1.1 443 >/dev/null 2>&1 &&
           nc -z -w2 -s "$plain" 1.1.1.1 443 >/dev/null 2>&1; then why=unhealthy   # ICMP-silent gateway: compare TCP
    fi
  fi
  if [ -z "$why" ]; then rm -f "$FAIL"; exit 0; fi
  # LAN gone and Wi-Fi still joining (no en* has DHCP yet): nothing to black-hole against — don't count.
  if [ "$why" = link ] && lg_alive "$pid" && ! any_dhcp; then exit 0; fi
  fails=$(cat "$FAIL" 2>/dev/null); [[ "$fails" =~ ^[0-9]+$ ]] || fails=0
  fails=$((fails + 1)); echo "$fails" >"$FAIL"
  limit=2; lg_alive "$pid" && limit=7                                            # app alive: ~21 s grace (join wait itself isn't counted)
  if [ "$fails" -ge "$limit" ]; then echo "$why" >"$REASON"; down; log "check: $why x$fails, down"; fi
}

# Self-test hook: `LANGUARD_NET_LIB=1 source languard-net.sh` loads functions only (sudo env_reset never passes it).
[ "${LANGUARD_NET_LIB:-}" = 1 ] && return 0

case "${1:-}" in
  up)     shift; cmd_up "$@" ;;
  move)   shift; cmd_move "$@" ;;
  adopt)  shift; cmd_adopt "$@" ;;
  down)   down; rm -f "$REASON" ;;
  panic)  down sweep; touch "$PANIC"; log "panic" ;;
  arm)    rm -f "$PANIC" "$REASON" ;;
  check)  cmd_check ;;
  netinfo) shift; [ $# -eq 1 ] && is_iface "$1" || exit 2
          g=$(router "$1"); is_ip "$g" || exit 8
          [ -n "$(gw_mac "$g")" ] || ping -c1 -t1 -q -b "$1" "$g" >/dev/null 2>&1
          printf 'GW=%s\nMAC=%s\n' "$g" "$(gw_mac "$g")" ;;
  status) cat "$STATE" 2>/dev/null; [ -f "$PANIC" ] && echo "PANIC=1"; for n in $NETS; do echo "$n -> $(route_if "$n")"; done ;;
  *)      exit 2 ;;
esac
