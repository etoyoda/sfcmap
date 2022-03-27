#!/bin/bash
set -euo pipefail
export TZ=UTC
today=$(date +%Y-%m-%d)
datadir=/nwp/p0/${today}
if test ! -d ${datadir} ; then
  datadir=${datadir}.new
fi
test -d ${datadir}
test -f ${datadir}/obsan-${today}.tar
ruby untar-unziplike.rb '^A_S[MI]' ${datadir}/obsan-${today}.tar > zunzip.txt
ruby detac.rb zunzip.txt > zdetac.txt
ruby detac-locate.rb zdetac.txt > zloctac.txt 2> zloctac.log
