#!/bin/bash
cd ~/rec; rm -rf /tmp/scratch; mkdir -p /tmp/scratch; : > replay.log
for f in $HOME/rec/cmds/*.sh; do echo "=== $f" >> replay.log; ( cd /tmp; BASH_ENV=$HOME/rec/shim.sh timeout 25 bash "$f" >> replay.log 2>&1 ) || echo "  [rc=$?]" >> replay.log; done
echo DONE >> replay.log
