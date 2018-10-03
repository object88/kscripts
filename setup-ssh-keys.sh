#!/usr/bin/env bash

# This script will generate a privte/public SSH key pair

if [ $# -eq 0 ]
then
  echo This script will create a new SSH keypair named 'id_rca_[TARGET_MACHINE]' and install it to the provided machines.
  echo
  echo It expects a series of IP addresses or DNA names.
  echo
  exit 1
fi

TARGETS=$@

echo "Generating new key"
rm -rf ~/.ssh/la_cka ~/.ssh/la_cka.pub
ssh-keygen -t rsa -b 4096 -q -f ~/.ssh/la_cka -N "" -n user

for TARGET in $TARGETS
do
  echo "Copying public key to '$TARGET'"
  scp -o StrictHostKeyChecking=no "$HOME/.ssh/la_cka.pub" "user@$TARGET:/home/user/.ssh/id_rsa.pub"
  echo "Copied, adding to authorized hosts"
  ssh -o StrictHostKeyChecking=no "user@$TARGET" 'cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys'
  echo "Added, validating..."
  ssh -i "$HOME/.ssh/la_cka" -o StrictHostKeyChecking=no -o IdentitiesOnly=yes "user@$TARGET" echo "foo"
  echo "Validated."
  echo ""
done

echo "Done"
