#!/bin/bash

set -e

echo "===== Update packages ====="
sudo apt-get update

echo "===== Install dependencies ====="
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "===== Add Docker GPG key ====="
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "===== Add Docker repository ====="

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "===== Install Docker ====="

sudo apt-get update

sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "===== Enable Docker ====="

sudo systemctl enable docker
sudo systemctl start docker

echo "===== Add current user to docker group ====="

sudo usermod -aG docker $USER

echo "===== Docker version ====="

docker --version

echo "===== Docker Compose version ====="

docker compose version

echo "===== Installation completed ====="
echo "Please logout/login again to use docker without sudo."
