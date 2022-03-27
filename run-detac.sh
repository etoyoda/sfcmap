#!/bin/bash
set -euo pipefail
TZ=UTC
today=$(date +%Y-%m-%d)
datadir=/nwp/p0/${today}
if test ! -d ${datadir} ; then
  datadir=${datadir}.new
fi
test -d ${datadir}
test -f ${datadir}/obsan-${today}.tar
ruby untar-unziplike.rb ^A_SM ${datadir}/obsan-${today}.tar > zunzip.txt
ruby detac.rb zunzip.txt > zdetac.txt
