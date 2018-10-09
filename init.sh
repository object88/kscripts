#!/usr/bin/env bash

function green() {
  echo -e "\033[0;32m${1}\033[0m"
}

function red() {
  echo -e "\033[0;31m${1}\033[0m"
}

cd $(dirname "$0")

# Ensure that the $PASSWORD env var is specified
if [[ ${PASSWORD:-nil} == "nil" ]]; then
  echo "The password for target machines must be specified in the \$PASSWORD environment variable; exiting."
  exit -1
fi

./prerequisites.sh
RETVAL=$?
if [ $RETVAL != 0 ]; then
  red "Prerequisites failed; exitting."
  exit 1
fi

# Arguments are list of IP addresses or machine names

# First will be master
MASTER=$1
shift

# All remaining are non-master
NONMASTERS=$@

check_ip() {
  NODE_ADDR=$1

  # Must be ssh'able
  nmap "$NODE_ADDR" -PN -p ssh | egrep 'open|closed|filtered'
  REACHABLE_IP=$?

  if ! [[ $REACHABLE_IP == 0 ]];
  then
    red "Failed to connect to node '$NODE_ADDR'; exiting."
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
green "Generating kube token on master..."
TOKEN=$(ssh "$MASTER" kubeadm token generate)
green "Have token '${TOKEN}'"

# Configure the initial Kubernetes settings on the master node
ssh "$MASTER" << EOF
  echo "Ensuring that jq is installed"
  echo $PASSWORD | sudo -S apt install -y jq

  # Obliterate any pre-existing configuration
  echo "Removing any previous k8s configuration on master..."
  sudo kubeadm reset -f
  
  # Pull down configuration images
  echo "Pulling down k8s images"
  sudo kubeadm config images pull
  
  # Set up new system
  echo "Initializing master"
  sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --token "$TOKEN"

  # Prepare config file
  echo "Setting up k8s config files"
  mkdir -p \$HOME/.kube
  sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
  sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config

  # Set up flannel
  echo "Configuring flannel"
  sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
EOF
RETVAL=$?
if [ $RETVAL != 0 ]; then
  red "Failed master node setup; exitting."
  exit 1
fi

SECONDS=0
TIMEOUT=180

while :; do
  if (( SECONDS > TIMEOUT )); then
    echo "Time out waiting for dns pods to be ready; exiting."
    exit 1
  fi

  # OUT=$(ssh $MASTER "echo $PASSWORD | sudo -S kubectl get pods --all-namespaces")
  echo "Gathering pods..."
  OUT=$(ssh $MASTER kubectl get pods --all-namespaces -o json)
  echo $?
  if [ $(echo "$OUT" | jq -r '.items | length') == "0" ]; then
    echo "Not ready yet"
  elif [ $(echo "$OUT" | jq -r '[.items[] | select(.metadata.name | startswith("coredns")) | .status.containerStatuses[].ready] | all') == "true" ]; then
    echo "Completed master configuration."
    ssh $MASTER kubectl get pods --all-namespaces
    break
  fi

  echo "Not ready; sleeping."
  sleep 1
done

if ! [ ${#NONMASTERS[@]} -eq 0 ]; then
  green "Have non-master nodes to configure."

  # Need to get a cert hash from the master.
  green "Retrieving cert hash from master..."
  CA_CERT_HASH=$(ssh "$MASTER" "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")

  # Also need to get the IP address of the master.
  green "Getting IP address for master..."
  MASTERIP=$(ssh "$MASTER" "ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'")

  # On non-masters...
  for NONMASTER in $NONMASTERS; do
    green ""
    green "Configuring non-master node '$NONMASTER'"
    ssh "$NONMASTER" << EOF
      # Obliterate any pre-existing configuration
      echo "Removing any previous k8s configuration on non-master..."
      echo $PASSWORD | sudo -S kubeadm reset -f

      # Ask the non-master to join the kube
      echo "Joining current configuration"
      sudo kubeadm join "$MASTERIP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "sha256:$CA_CERT_HASH"
EOF
    green "Completed non-master configuration for node '$NONMASTER'."
  done
fi

green "Done"
