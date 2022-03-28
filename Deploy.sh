#!/bin/bash

set -x
if [ -f .deploy ] ; then
  source ./.deploy
else
  cat > .deploy <<CONFIG
bindir=/nwp/bin
priv=nwp
etcdir=/nwp/etc
CONFIG
  echo please check config file .deploy and rerun.
  exit 1
fi
: ${bindir:?} ${priv:?} ${etcdir:?}

target="run-detac.sh detac.rb untar-unziplike.rb detac-locate.rb"

sudo -u $priv install -m 0755 $target $bindir
sudo -u $priv install -d $etcdir
sudo -u $priv install -m 0644 nsd_bbsss.txt $etcdir

