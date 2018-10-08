#!/usr/bin/env bash

cd $(dirname "$0")

if [ $# -eq 0 ]; then
  echo "You must specify the target machine"
  exit 1
fi

TARGET=$1

scp ./job.yaml "user@$TARGET:/tmp/job.yaml"

ssh "$TARGET" << EOF
  kubectl create -f /tmp/job.yaml

  kubectl describe jobs

  rm -rf /tmp/job.yaml
EOF



