#!/bin/bash

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)"
    exit
  fi
}

update_system_and_install_packages() {
  log "Starting system update and package installation"
  sudo apt-get update >/dev/null 2>&1
  sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
  log "System update and package installation completed."
}

install_git() {
  log "Installing Git"
  sudo apt-get install -y git >/dev/null 2>&1
  log "Git installation completed."
}

setup_docker_repository() {
  log "Setting up Docker repository"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null 2>&1
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1
  log "Docker repository setup completed."
}

install_docker() {
  log "Installing Docker"
  sudo apt-get update >/dev/null 2>&1
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
  log "Docker installation completed."
}

install_nginx() {
  log "Installing Nginx"
  sudo apt-get install -y nginx >/dev/null 2>&1
  log "Nginx installation completed."
}

install_node_and_pm2() {
  log "Installing Node.js and PM2"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash >/dev/null 2>&1
  source ~/.bashrc
  [[ -s $HOME/.nvm/nvm.sh ]] && . $HOME/.nvm/nvm.sh
  nvm install --lts >/dev/null 2>&1
  nvm use --lts >/dev/null 2>&1
  sudo apt-get install -y npm >/dev/null 2>&1
  sudo npm install -g pm2 >/dev/null 2>&1
  log "Node.js and PM2 installation completed."
}

setup_database() {
  log "Setting up MySQL using Docker"
  read -sp "Enter the MySQL root password: " MYSQL_ROOT_PASSWORD
  sudo docker run -d --name mysql \
    -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
    -p 3306:3306 \
    -v db_data:/var/lib/mysql \
    mysql:8.0 >/dev/null 2>&1
  log "MySQL setup using Docker completed."
}

main() {
  log "Starting server initialization script"
  check_root
  update_system_and_install_packages
  install_git
  setup_docker_repository
  install_docker
  install_nginx
  install_node_and_pm2
  setup_database
  log "Server initialization script completed"
}

main
