#!/usr/bin/env bash

PID=$$

#rem set -x
#rem if [ "$1" == "" ] ; then
#rem   echo "Please run $0 <namespace>"
#rem   exit 1;
#rem fi

NAMESPACE=demo-$PID

oc new-project $NAMESPACE

if [ -z $TMUX ] ; then
  echo "Start new tmux session"
  tmux new-session -d -s demo-$PID "./01_deploy.sh demo-$PID"
fi
tmux split-window -d -t 0 -v  "watch oc get pod -o wide"
#tmux split-window -d -t 0 -h  "watch curl -s -k https://selma-bouvier.${SERVER}/demo"
#tmux split-window -d -t 2 -h  "watch curl -s -k https://patty-bouvier.${SERVER}/demo"

if [ -z $TMUX ] ; then
  echo "Attach to session"
  tmux attach-session -t demo-$PID
else
  watch curl -s -k http://homer-simpson.${SERVER}/demox
fi

oc delete project $NAMESPACE
echo end