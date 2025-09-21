#!/bin/bash

## Update repositories
##
export DEBIAN_FRONTEND=dialog
apt-get -o DPkg::Lock::Timeout=60 update

## Install net tools
##
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=30 install net-tools -y

## Install kubectl for Kubernetes v1.32
##
apt-get -o DPkg::Lock::Timeout=30 install ca-certificates curl gpt -y
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get -o DPkg::Lock::Timeout=30 update
apt-get -o DPkg::Lock::Timeout=30 install kubectl -y

## Install Azure CLI
##
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

## Install Docker
##
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get -o DPkg::Lock::Timeout=30 update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add the localadmin user to the Docker group
sudo groupadd docker
sudo usermod -aG docker localadmin

mkdir -p /home/localadmin/.ssh
chmod 700 /home/localadmin/.ssh
chown localadmin:localadmin /home/localadmin/.ssh
echo "${1}" | tee -a /home/localadmin/.ssh/authorized_keys > /dev/null
chmod 600 /home/localadmin/.ssh/authorized_keys
