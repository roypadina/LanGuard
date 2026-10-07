#!/bin/bash
# Pure checks of languard-net validators (no root, no system changes). Run: bash Tests/helper/selftest.sh
set -u
LANGUARD_NET_LIB=1 source "$(dirname "$0")/../../Sources/LanGuardFeature/Resources/languard-net.sh"
fail=0; t(){ if eval "$2"; then r=ok; else r=no; fi; [ "$r" = "$1" ] || { echo "FAIL: expected $1: $2"; fail=1; }; }
t ok 'is_ip 192.168.1.249'; t no 'is_ip 256.1.1.1'; t no 'is_ip 1.2.3'; t no 'is_ip "1.2.3.4;rm -rf /"'; t no 'is_ip ""'
t ok 'is_pid 12345'; t no 'is_pid "12 34"'; t no 'is_pid -1'
t no 'is_iface utun5'; t no 'is_iface "en0;id"'; t no 'is_iface en999'
m=$(ip2int 255.255.255.0); a=$(ip2int 192.168.1.255); n=$(ip2int 192.168.1.0); h=$(ip2int 192.168.1.249)
t ok '(( ((a|m)&0xFFFFFFFF) == 0xFFFFFFFF ))'; t ok '(( ((n&~m)&0xFFFFFFFF) == 0 ))'; t ok '(( ((h&~m)&0xFFFFFFFF) != 0 && ((h|m)&0xFFFFFFFF) != 0xFFFFFFFF ))'
[ $fail = 0 ] && echo "selftest: all passed"; exit $fail
