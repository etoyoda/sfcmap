#!/bin/bash
:
export LANG=en_US.UTF-8
export TZ=UTC
cd $(/usr/bin/dirname $0)
:
if expr match "$*" "20[0-9][0-9] [01][0-9] [0-3][0-9] [012][0-9]" > /dev/null; then
  echo using timecard="$*"
else
  set -- $(ruby -e 'puts((Time.now - 4200).localtime.strftime("%Y %m %d %H"))')
fi
yy=$1
mm=$2
dd=$3
hhx=$4
hr=$(expr $hhx / 3 '*' 3)
hh='xx'
case $hr in
0|3|6|9) hh=0${hr} ;;
*) hh=$hr ;;
esac
result=y${yy}${mm}${dd}T${hh}-ansf.json

exec 3>&2
if [ -f $result ]; then
  test ! -t 3 || echo no problem $result present
  exit 0
fi
test ! -t 3 || echo building $result ...

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
test ! -t 3 || echo unzip ... >&3
unzip -c $zip A_S*_C_????_${yy}${mm}${dd}${hh}*.txt > ansf.txt
test ! -t 3 || echo decode WMO Codes ... >&3
ruby ../detac.rb ansf.txt > ansf.ltsv
vt="${yy}-${mm}-${dd}T${hh}:00:00Z"
test ! -t 3 || echo compiling into JSON ... >&3
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

sh makelist-obs.sh > yobslist.json
