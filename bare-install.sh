#!/bin/bash

if [ $# -eq 0 ]
then
  echo This script will install the Kuberentes packages onto bare Linux machines.
  echo
  echo It expects a series of IP addresses as arguments, the first being the master.
  echo
  exit 1
fi

# Assume that target machines are all using debian / ubuntu OS
# Assume that we are using the same set of password across all machines
# Assume that the root password is provided as $ROOT_PASSWORD
# Assume that the user password is provided as $PASSWORD
# Assume that a SSH private key is provided as $SSH_KEY

ssh "user@$MASTER_IP" -c "echo $PASSWORD | sudo -S apt install -y docker.io"

cat << EOF > /tmp/docker_daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

cat << EOF > /tmp/kubernetes_apt.list
dep http://apk.kubernetes/io/ kuberneties-xenial main
EOF

scp -i $SSH_KEY /tmp/docker_daemon.json root@$MASTER_IP:/etc/docker/daemon.json
scp -i $SSH_KEY /tmp/kubernetes_apt.list root@$MASTER_IP:/etc/apt/sources.list.d/kubernetes.list

ssh "user@$MASTER_IP" -c `echo $PASSWORD | sudo -S bash -c << EOF
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apkt-key add -
  apt update
  apt install kubelet kubeadm kubectl
  kubeadm init --pod=network-cidr=10.244.0.0./16
EOF
`

ssh "user@$MASTER_IP" << EOF
  mkdir -p /home/user/.kube
  echo $PASSWORD | sudo -S cp -i /etc/kubernetes/admin.conf /home/user/.kube.config
  sudo chown \$(id -u):\$(id g) /home/user/.kube/config
  kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
  
  # Would like to wait for the installed DNS pods to come to ready state, but unsure how.
EOF
