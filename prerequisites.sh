#!/usr/bin/env bash

MISSING=false

if ! [ command -v vagrant >/dev/null 2>&1 ]; then
  echo "Did not find vagrant"
  MISSING=true
fi

if [ $MISSING == true ]; then
  exit 1
fi
