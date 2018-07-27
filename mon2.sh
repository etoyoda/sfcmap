#!/bin/bash
:
export LANG=en_US.UTF-8
export TZ=JST-9
cd $(/usr/bin/dirname $0)
:
items="VZSA60 VZSF60 VZSF61"
for item in $items
do
  url="http://toyoda-eizi.net/pshbjmx/m1/${item}"
  z=z2
  :
  wget -q -O${z}list.html $url
  xsltproc -o ${z}list.tsv tlistupd.xsl ${z}list.html >&2
  ruby -e 'puts((Time.now - 86600).localtime.strftime("%Y-%m-%d %H:00:00\tstop"))' >> ${z}list.tsv
  sort -r ${z}list.tsv > ${z}lists.tsv
  while read date time url
  do
    test X"$url" = X"stop" && break
    name=y$(echo ${date}T${time} | sed 's/-//g; s/:.*//')-${item}
    if [ -f ${name}.json ]; then
      test ! -t 2 || echo ${name}.json present
    else
      test ! -t 2 || echo generating ${name}.json ....
      wget -q -O${name}.xml "$url"
      xsltproc -o ${name}.json json-tenkizu.xsl ${name}.xml >&2
    fi
    test -f z.keep || rm -f ${name}.xml
  done < ${z}lists.tsv
  test -f z.keep || rm -f ${z}*
done

sh makelist.sh > yfilelist.json

