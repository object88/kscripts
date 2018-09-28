#!/bin/bash

# Ensure that the $PASSWORD env var is specified
if [[ ${PASSWORD:-nil} == "nil" ]];
then
  echo "The password for target machines must be specified in the \$PASSWORD environment variable; exiting."
  exit -1
fi

# Arguments are list of IP addresses

# First will be master
MASTER_IP=$1
shift

# All remaining are non-master
NONMASTER_IPS=$@

check_ip() {
  # Must be ssh'able
  nmap "$MASTER_IP" -PN -p ssh | egrep 'open|closed|filtered'
  REACHABLE_IP=$?

  if ! [[ $REACHABLE_IP == 0 ]];
  then
    echo "Failed to connect to node, '$MASTER_IP'; exiting."
    exit 1
  fi

  return 0
}

# Check master
check_ip $MASTER_IP

# On non-masters...
for IP in $NONMASTER_IPS
do
  check_ip $IP
next

# Create some suitable token
TOKEN=""

# Configure the initial Kubernetes settings on the master node
ssh "user@$MASTER_IP" << EOF
  echo $PASSWORD | sudo -S kubeadm init --pod-network-cidr=10.244.0.0/16 --token "$TOKEN"

  mkdir -p \$HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

  # Setting up flannel
  sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
EOF

# Need to get a cert hash from the master.
CA_CERT_HASH=$(ssh "user@$MASTER_IP" -c "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")

# On non-masters...
for IP in $NONMASTER_IPS
do
  # Ask the non-master to join the kube
  ssh "user@$IP" << EOF
    echo $PASSWORD | sudo -S kubeadm join "$MASTER_IP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "sha256:$CA_CERT_HASH"
EOF
done

echo "Success"

