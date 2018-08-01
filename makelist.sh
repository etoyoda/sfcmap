#!/bin/bash

export TZ=JST-9

limit=$(ruby -e 'puts (Time.now - 86400 * 2).strftime("%Y-%m-%dT%H:%M:%S+09:00")')

echo "{"
for json in y*-V*.json
do
  btime=$(sed -n '/x-validtime/{s/.*": "//;s/".*//;p}' $json)
  if [[ $btime < $limit ]]
  then
    test ! -t 2 || echo rm -f $json
    rm -f $json
  else
    btutc=$(ruby -rtime -e 'puts Time.parse(ARGV.first).utc.strftime("%Y-%m-%dT%H")' $btime)
    hdr=$(echo $json | sed 's/.*-//; s/\.json//')
    case $hdr in
    VZSA50) hdr=SPAS;;
    VZSA60) hdr=ASAS;;
    VZSF60) hdr=FSAS24;;
    VZSF61) hdr=FSAS48;;
    esac
    echo "\"${json}\": \"${hdr}/${btutc}\","
  fi
done
echo '"stop": "dummy"'
echo "}"
