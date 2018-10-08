#!/usr/bin/env bash

cd $(dirname "$0")

# Ensure that the $PASSWORD env var is specified
if [[ ${PASSWORD:-nil} == "nil" ]];
then
  echo "The password for target machines must be specified in the \$PASSWORD environment variable; exiting."
  exit -1
fi

./prerequisites.sh

# Arguments are list of IP addresses or machine names

# First will be master
MASTER=$1
shift

# All remaining are non-master
NONMASTERS=$@

check_ip() {
  # Must be ssh'able
  nmap "$MASTER" -PN -p ssh | egrep 'open|closed|filtered'
  REACHABLE_IP=$?

  if ! [[ $REACHABLE_IP == 0 ]];
  then
    echo "Failed to connect to node, '$MASTER'; exiting."
    exit 1
  fi
}

# Check master
check_ip $MASTER

# Check any non-masters
for IP in $NONMASTERS; do
  check_ip $IP
done

# Create some suitable token
TOKEN=$(ssh "$MASTER" kubeadm token generate)

# Configure the initial Kubernetes settings on the master node
ssh "$MASTER" << EOF
  # Obliterate any pre-existing configuration
  echo $PASSWORD | sudo -S kubeadm reset -f
  
  # Pull down configuration images
  sudo kubeadm config images pull
  
  # Set up new system
  sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --token "$TOKEN"

  # Prepare config file
  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

  # Set up flannel
  sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
EOF

if ! [ ${#NONMASTERS[@]} -eq 0 ]; then
  # Need to get a cert hash from the master.
  CA_CERT_HASH=$(ssh "$MASTER" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")

  # Also need to get the IP address of the master.
  MASTERIP=$(ssh "$MASTER" "ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'")

  # On non-masters...
  for NONMASTER in $NONMASTERS; do
    # Ask the non-master to join the kube
    ssh "$NONMASTER" << EOF
      echo $PASSWORD | sudo -S kubeadm join "$MASTERIP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "sha256:$CA_CERT_HASH"
EOF
  done
fi

echo "Done"
