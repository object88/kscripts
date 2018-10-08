#!/usr/bin/env bash

MISSING=()

check() {
  TARGET=$1
  command -v $TARGET >/dev/null 2>&1
  local RESULT=$?
  if [ $RESULT != 0 ]; then
    MISSING+=($TARGET)
  fi
}

check "nmap"
check "vagrant"

if ! [ ${#MISSING[@]} -eq 0 ]; then
  echo "Missing prerequisites:"
  for TARGET in $MISSING; do
    echo "  $TARGET"
  done

  exit 1
fi
