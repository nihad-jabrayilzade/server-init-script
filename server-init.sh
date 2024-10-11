#!/bin/bash

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_root() {
  # Check if the script is running as root
  if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)"
    exit
  fi
}

install_system_packages() {
  log "Installing system packages"
  apt-get update >/dev/null 2>&1
  apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
  log "System packages installation completed"
}

install_git() {
  log "Installing Git"
  apt-get install -y git >/dev/null 2>&1
  log "Git installation completed"
}

configure_docker() {
  log "Starting Docker configuration"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc >/dev/null 2>&1
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1
  apt-get update >/dev/null 2>&1
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
  log "Docker configuration completed"
}

install_nginx() {
  log "Installing Nginx"
  apt-get install -y nginx >/dev/null 2>&1
  log "Nginx installation completed"
}

configure_node_environment() {
  log "Configuring Node environment"
  curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash >/dev/null 2>&1
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts >/dev/null 2>&1
  nvm use --lts >/dev/null 2>&1
  apt-get install -y npm >/dev/null 2>&1
  npm install -g pm2 >/dev/null 2>&1
  log "Node configuration completed"
}

configure_database() {
  log "Starting Database configuration using docker"
  read -sp "Enter the MySQL root password: " MYSQL_ROOT_PASSWORD
  echo
  sudo docker run -d --name mysql \
    -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
    -p 3306:3306 \
    -v db_data:/var/lib/mysql \
    mysql:8.0 >/dev/null 2>&1
  log "Database configuration completed"
}

main() {
  log "Starting server initialization tasks"
  check_root
  install_system_packages
  install_git
  install_nginx
  configure_node_environment
  configure_docker
  configure_database
  log "Server initialization tasks completed"
}

main
