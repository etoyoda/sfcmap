#!/bin/bash
:
export LANG=en_US.UTF-8
export TZ=UTC
cd $(/usr/bin/dirname $0)
:
set -- $(ruby -e 'puts((Time.now - 4200).localtime.strftime("%Y %m %d %H"))')
yy=$1
mm=$2
dd=$3
hhx=$4
hr=$(expr $hhx / 6 '*' 6)
hh='xx'
case $hr in
0|6) hh=0${hr} ;;
*) hh=$hr ;;
esac
result=y${yy}${mm}${dd}T${hh}-ansf.json

if [ -f $result ]; then
  : no problem $result exists
  exit 0
fi

work="work-ansf-$yy$mm$dd$hhx"
if [ -d $work ]; then
  echo $work exists.
  exit 15
fi
mkdir $work
cd $work
exec 2> err.log
set -x -v
zip=$(sh -$- local-getzip.sh $yy $mm $dd $hh ansf)
echo $yy $mm $dd $hh 00 > timecard.txt
unzip -c $zip A_S*_C_????_${yy}${mm}${dd}${hh}*.txt > ansf.txt
ruby ../detac.rb ansf.txt > ansf.ltsv
vt="${yy}-${mm}-${dd}T${hh}:00:00Z"
ruby ../json-detac.rb -vt="${vt}" -nsd=../nsd_bbsss.txt ansf.ltsv > ansf.json
cd ..
set +x +v
exec 2>&1
if [ -s ${work}/ansf.json ]; then
  ln -f ${work}/ansf.json $result
  rm -rf ${work}
else
  echo ${work} fails to build json
fi

