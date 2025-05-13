#!/bin/bash

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
  exit 1
}

check_root() {
  # Check if the script is running as root
  if [ "$EUID" -ne 0 ]; then
    error_exit "Please run this script as root (use sudo)"
  fi
}

install_system_packages() {
  log "Installing system packages"
  apt-get update >/dev/null 2>&1 || error_exit "Failed to update package lists"
  apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1 || error_exit "Failed to install system packages"
  log "System packages installation completed"
}

install_git() {
  log "Installing Git"
  apt-get install -y git >/dev/null 2>&1 || error_exit "Failed to install Git"
  log "Git installation completed"
}

configure_docker() {
  log "Starting Docker configuration"
  install -m 0755 -d /etc/apt/keyrings || error_exit "Failed to create Docker keyrings directory"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc >/dev/null 2>&1 || error_exit "Failed to download Docker GPG key"
  chmod a+r /etc/apt/keyrings/docker.asc || error_exit "Failed to set permissions on Docker GPG key"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1 || error_exit "Failed to add Docker repository"
  apt-get update >/dev/null 2>&1 || error_exit "Failed to update package lists after adding Docker repository"
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || error_exit "Failed to install Docker packages"
  log "Docker configuration completed"
}

install_nginx() {
  log "Installing Nginx"
  apt-get install -y nginx >/dev/null 2>&1 || error_exit "Failed to install Nginx"
  log "Nginx installation completed"
}

configure_node_environment() {
  log "Configuring Node environment"
  curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash >/dev/null 2>&1 || error_exit "Failed to download and install NVM"
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts >/dev/null 2>&1 || error_exit "Failed to install Node.js LTS version"
  nvm use --lts >/dev/null 2>&1 || error_exit "Failed to use Node.js LTS version"
  apt-get install -y npm >/dev/null 2>&1 || error_exit "Failed to install npm"
  npm install -g pm2 >/dev/null 2>&1 || error_exit "Failed to install PM2 globally"
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
    mysql:8.0 >/dev/null 2>&1 || error_exit "Failed to configure MySQL database in Docker"
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
