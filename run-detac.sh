#!/bin/bash
set -euo pipefail
PATH=/bin:/usr/bin
export TZ=UTC

: ${etcdir:='/nwp/etc'}

: ${refhour:=$(date +'%Y-%m-%dT%HZ')}
: ${basetime:=$(ruby -rtime -e 'puts(Time.at(((Time.parse(ARGV.first.sub(/Z/,":00:00Z")).to_i - 3600) / 10800) * 10800).utc.strftime("%Y-%m-%dT%H:%M:%SZ"))' $refhour)}
: ${today:=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y-%m-%d"))' $basetime)}

bindir=$(dirname $0)

datadir=/nwp/p0/${today}
if test ! -d ${datadir} ; then
  datadir=${datadir}.new
fi
test -d ${datadir}
test -f ${datadir}/obsan-${today}.tar
ruby ${bindir}/untar-unziplike.rb '^A_S([MI]|NUR)' ${datadir}/obsan-${today}.tar > ztac.txt
ruby ${bindir}/detac.rb ztac.txt > zdetac.txt
ruby ${bindir}/detac-locate.rb -o=zloctac.txt -nsd=${etcdir}/nsd_bbsss.txt zdetac.txt 2> zloctac.log
