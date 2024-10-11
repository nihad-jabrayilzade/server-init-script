#!/bin/bash

read -p "Enter the username of the new user: " USER
read -p "Enter the email address for the new user's SSH key: " USER_EMAIL

USER_DIR="/home/$USER"
PROJECT_NAME="authomatify"

NVM_DIR_COMMAND='[ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm"'

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

run_as_user() {
  sudo -u "$USER" bash -c "$@"
}

run_as_user_nvm() {
  run_as_user "export NVM_DIR=\"\$($NVM_DIR_COMMAND)\" && . \"\$NVM_DIR/nvm.sh\" && $1"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)"
    exit
  fi
}

install_system_packages() {
  log "Starting system packages installation"
  apt-get update >/dev/null 2>&1
  apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
  log "System packages installation completed"
}

create_user() {
  log "Creating new user $USER"
  adduser $USER
  read -p "Do you want to add $USER to the sudo group? (y/n): " ADD_SUDO
  if [ "$ADD_SUDO" == "y" ]; then
    usermod -aG sudo $USER
    log "Added $USER to the sudo group"
  fi
  log "New user $USER created"
}


log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

generate_ssh_key() {
  log "Generating SSH key for GitHub access for user $USER"
  run_as_user "ssh-keygen -t ed25519 -C $USER_EMAIL"
  log "Displaying SSH public key. Please copy it and add it to your GitHub account"
  run_as_user "cat ~/.ssh/id_ed25519.pub"
  read -p "Please add the above SSH key to your GitHub account. Press Enter to continue once it's done"
  log "Continuing script after SSH key has been added to GitHub"
}

get_available_application_port() {
  local APP_NAME=$1
  local STARTING_PORT=$2

  local APPS_COUNT=$(run_as_user_nvm "pm2 list | grep -c '$APP_NAME'")
  local ASSIGNED_PORT=$((STARTING_PORT + APPS_COUNT + 1))

  echo "$ASSIGNED_PORT"
}

configure_node_environment() {
  NVM_VERSION="v0.39.5"
  NODE_VERSION="lts/*"
  NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"

  log "Starting Node ennvironment configuration for user $USER"
  run_as_user "export NVM_DIR=\"\$($NVM_DIR_COMMAND)\" && curl -o- -s $NVM_INSTALL_URL | bash &> /dev/null"
  run_as_user_nvm "nvm install $NODE_VERSION &> /dev/null"
  run_as_user_nvm "npm install -g pm2 &> /dev/null"
  log "Node ennvironment configuration completed for user $USER"
}

deploy_applications() {
  BACKEND_APPLICATION_NAME="$PROJECT_NAME-backend"
  BACKEND_APPLICATION_SERVICE_NAME="$BACKEND_APPLICATION_NAME-$USER"
  BACKEND_APPLICATION_OFFSET_PORT=4000
  BACKEND_APPLICATION_PORT=$(get_available_application_port $BACKEND_APPLICATION_NAME $BACKEND_APPLICATION_OFFSET_PORT)
  BACKEND_APPLICATION_PROXY_PASS="http://localhost:$BACKEND_APPLICATION_PORT"

  run_as_user_nvm "mkdir -p $USER_DIR && cd $USER_DIR && git clone git@github.com:$PROJECT_NAME/$BACKEND_APPLICATION_NAME.git $BACKEND_APPLICATION_NAME &> /dev/null"
  log "Deploying the backend application for user $USER"
  run_as_user_nvm "cd $USER_DIR/$BACKEND_APPLICATION_NAME && npm install && pm2 start --name '$BACKEND_APPLICATION_SERVICE_NAME' npm -- run start:dev"
  log "Backend application is running on $BACKEND_APPLICATION_PROXY_PASS"

  log "Deploying the frontend application for user $USER"
  FRONTEND_APPLICATION_NAME="$PROJECT_NAME-frontend"
  FRONTEND_APPLICATION_SERVICE_NAME="$FRONTEND_APPLICATION_NAME-$USER"
  FRONTEND_APPLICATION_PORT=$(get_available_application_port "$FRONTEND_APPLICATION_NAME" "3000")
  FRONTEND_APPLICATION_PROXY_PASS="http://localhost:$FRONTEND_APPLICATION_PORT"
  run_as_user_nvm "cd $USER_DIR && git clone git@github.com:$PROJECT_NAME/$FRONTEND_APPLICATION_NAME.git $FRONTEND_APPLICATION_NAME &> /dev/null"
  run_as_user_nvm "cd $USER_DIR/$FRONTEND_APPLICATION_NAME && npm install && pm2 start --name '$FRONTEND_APPLICATION_SERVICE_NAME' npm -- run dev"
  log "Frontend application is running on $FRONTEND_APPLICATION_PROXY_PASS"
}

configure_nginx() {
  WEB_DOMAIN="$USER.$PROJECT_NAME.com"
  API_DOMAIN="$USER.api.$PROJECT_NAME.com"
  NGINX_CONFIG_NAME="$PROJECT_NAME-$USER"

  log "Configuring Nginx"
  tee /etc/nginx/sites-available/$NGINX_CONFIG_NAME >/dev/null <<EOF
    server {
        server_name $WEB_DOMAIN;

        location / {
            proxy_pass $FRONTEND_APPLICATION_PROXY_PASS;
            proxy_read_timeout 60;
            proxy_connect_timeout 60;
            proxy_redirect off;

            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
        }
        
        location /_next/static {
            add_header Cache-Control "public, max-age=3600, immutable";
            proxy_pass $FRONTEND_APPLICATION_PROXY_PASS/_next/static;
        }
    }

    server {
        server_name $API_DOMAIN;

        location / {
            proxy_pass $BACKEND_APPLICATION_PROXY_PASS;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
        }
    }
EOF

  log "Nginx configuration completed"

  log "Enabling Nginx configuration and reloading the service"
  ln -s /etc/nginx/sites-available/$NGINX_CONFIG_NAME /etc/nginx/sites-enabled/
  nginx -t && systemctl reload nginx
  log "Nginx configuration enabled and service reloaded"
}

main() {
  log "Starting user environment initialization script"
  check_root
  install_system_packages
  create_user
  generate_ssh_key
  configure_node_environment
  deploy_applications
  configure_nginx
  log "User environment initialization script completed"
}

main