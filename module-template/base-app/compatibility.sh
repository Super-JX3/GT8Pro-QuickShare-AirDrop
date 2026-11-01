#!/system/bin/sh
# Modified for the GT8 Pro adaptation; removed verbatim during assembly.
# Generated from the 68 reviewed prerequisites; one scan per input file.
mosey_check_compatibility() {
    compatibility_ok=true
    if ! awk '
BEGIN {
  want["(expandtypeattribute (mosey_app_202504) true)"]=1
  want["(typeattribute mosey_app_202504)"]=1
  want["(typeattributeset mosey_app_202504 (mosey_app))"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /system_ext/etc/selinux/mapping/202504.cil; then compatibility_ok=false; fi
    if ! awk '
BEGIN {
  want["user=_app isPrivApp=true name=com.google.android.mosey domain=mosey_app type=app_data_file levelFrom=all"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /system_ext/etc/selinux/system_ext_seapp_contexts; then compatibility_ok=false; fi
    if ! awk '
BEGIN {
  want["(allow mosey_app app_api_service (service_manager (find)))"]=1
  want["(allow mosey_app appdomain_tmpfs (file (ioctl read write getattr map execute)))"]=1
  want["(allow mosey_app mosey_app_userfaultfd (anon_inode (ioctl read create)))"]=1
  want["(allow mosey_app servicemanager (binder (call transfer)))"]=1
  want["(allow servicemanager mosey_app (binder (call transfer)))"]=1
  want["(allowx mosey_app appdomain_tmpfs (ioctl file ((range 0x7701 0x770b))))"]=1
  want["(roletype object_r mosey_app)"]=1
  want["(roletype object_r mosey_app_userfaultfd)"]=1
  want["(type mosey_app)"]=1
  want["(type mosey_app_userfaultfd)"]=1
  want["(typetransition mosey_app mosey_app anon_inode \"[userfaultfd]\" mosey_app_userfaultfd)"]=1
  want["(typetransition mosey_app tmpfs file appdomain_tmpfs)"]=1
  need["appdomain" SUBSEP "mosey_app"]=1
  need["coredomain" SUBSEP "mosey_app"]=1
  need["domain" SUBSEP "mosey_app"]=1
  need["netdomain" SUBSEP "mosey_app"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /system_ext/etc/selinux/system_ext_sepolicy.cil; then compatibility_ok=false; fi
    if ! awk '
BEGIN {
  want["<hidden-api-whitelisted-app package=\"com.google.android.mosey\" />"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /system_ext/etc/sysconfig/hidden-api-whitelist-ext.xml; then compatibility_ok=false; fi
    if ! awk '
BEGIN {
  want["/(vendor|odm)/bin/mosey_server u:object_r:mosey_server_exec:s0"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /vendor/etc/selinux/vendor_file_contexts; then compatibility_ok=false; fi
    if ! awk '
BEGIN {
  want["(allow init_202504 mosey_server (process (siginh rlimitinh)))"]=1
  want["(allow init_202504 mosey_server (process (transition)))"]=1
  want["(allow init_202504 mosey_server_exec (file (read getattr map execute open)))"]=1
  want["(allow mosey_app_202504 mosey_server (binder (call transfer)))"]=1
  want["(allow mosey_app_202504 mosey_server (fd (use)))"]=1
  want["(allow mosey_app_202504 mosey_service (service_manager (find)))"]=1
  want["(allow mosey_server mosey_app_202504 (binder (transfer)))"]=1
  want["(allow mosey_server mosey_server (netlink_netfilter_socket (create)))"]=1
  want["(allow mosey_server mosey_server_exec (file (read getattr map execute open entrypoint)))"]=1
  want["(allow mosey_server mosey_service (service_manager (add find)))"]=1
  want["(allow mosey_server self (capability (net_admin net_raw)))"]=1
  want["(allow mosey_server self (netlink_generic_socket (ioctl read write create getattr setattr lock append map bind connect getopt setopt shutdown)))"]=1
  want["(allow mosey_server self (netlink_route_socket (read write create nlmsg_read nlmsg_write nlmsg_readpriv nlmsg_getneigh)))"]=1
  want["(allow mosey_server self (packet_socket (ioctl read write create getattr setattr lock append map bind connect listen accept getopt setopt shutdown)))"]=1
  want["(allow mosey_server self (tun_socket (create)))"]=1
  want["(allow mosey_server self (udp_socket (ioctl create)))"]=1
  want["(allow mosey_server self (unix_dgram_socket (ioctl)))"]=1
  want["(allow mosey_server servicemanager_202504 (binder (call transfer)))"]=1
  want["(allow mosey_server sysfs_net_202504 (dir (ioctl read getattr lock open watch watch_reads search)))"]=1
  want["(allow mosey_server sysfs_net_202504 (file (ioctl read getattr lock map open watch watch_reads)))"]=1
  want["(allow mosey_server sysfs_net_202504 (lnk_file (ioctl read getattr lock map open watch watch_reads)))"]=1
  want["(allow mosey_server tun_device_202504 (chr_file (ioctl read write getattr lock append map open watch watch_reads)))"]=1
  want["(allow servicemanager_202504 mosey_server (binder (call transfer)))"]=1
  want["(allowx mosey_server self (ioctl netlink_generic_socket (0x8946)))"]=1
  want["(allowx mosey_server self (ioctl packet_socket (0x8913 0x8927 0x8933)))"]=1
  want["(allowx mosey_server self (ioctl udp_socket ((range 0x8913 0x8914) 0x8916 0x8922 0x8924 0x8936 0x8946 0x8994 0x89f1)))"]=1
  want["(allowx mosey_server self (ioctl unix_dgram_socket ((range 0x8913 0x8914) 0x8946 0x8994)))"]=1
  want["(allowx mosey_server tun_device_202504 (ioctl chr_file (0x54ca 0x54d2)))"]=1
  want["(roletype object_r mosey_server)"]=1
  want["(roletype object_r mosey_server_exec)"]=1
  want["(roletype object_r mosey_service)"]=1
  want["(type mosey_server)"]=1
  want["(type mosey_server_exec)"]=1
  want["(type mosey_service)"]=1
  want["(typetransition init_202504 mosey_server_exec process mosey_server)"]=1
  need["domain" SUBSEP "mosey_app_202504"]=1
  need["domain" SUBSEP "mosey_server"]=1
  need["exec_type" SUBSEP "mosey_server_exec"]=1
  need["file_type" SUBSEP "mosey_server_exec"]=1
  need["hal_service_type" SUBSEP "mosey_service"]=1
  need["service_manager_type" SUBSEP "mosey_server"]=1
  need["service_manager_type" SUBSEP "mosey_service"]=1
  need["system_server_service" SUBSEP "mosey_server"]=1
  need["vendor_file_type" SUBSEP "mosey_server_exec"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /vendor/etc/selinux/vendor_sepolicy.cil; then compatibility_ok=false; fi
    if ! awk '
BEGIN {
  want["com.google.android.moseyservice.IMoseyService/default u:object_r:mosey_service:s0"]=1
  want["com.google.pixel.moseyservice.IMoseyService/default u:object_r:mosey_service:s0"]=1
}
{
  normalized=$0
  gsub(/[[:space:]]+/, " ", normalized)
  sub(/^ /, "", normalized); sub(/ $/, "", normalized)
  if (normalized in want) found[normalized]=1
  if ($0 ~ /^\(typeattributeset /) {
    gsub(/[()]/, " ")
    positive=1
    for (i=3; i<=NF; i++) if ($i == "and" || $i == "or" || $i == "not" || $i == "xor" || $i == "all") positive=0
    if (positive) for (i=3; i<=NF; i++) if (($2 SUBSEP $i) in need) found_member[$2 SUBSEP $i]=1
  }
}
END {
  bad=0
  for (item in want) if (!(item in found)) { print "MISSING prerequisite in " FILENAME ": " item; bad=1 }
  for (item in need) if (!(item in found_member)) { split(item, parts, SUBSEP); print "MISSING membership in " FILENAME ": " parts[1] " contains " parts[2]; bad=1 }
  exit bad
}
    ' /vendor/etc/selinux/vendor_service_contexts; then compatibility_ok=false; fi
    [ "$compatibility_ok" = true ] || return 1
    echo 'OK: 68 reviewed Mosey prerequisites'
}
