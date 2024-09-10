#!/bin/bash

read -p "Enter the username of the new user: " USER
read -p "Enter the email address for the new user's SSH key: " USER_EMAIL

USER_DIR="/home/$USER"
PROJECT_NAME="authomatify"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)"
    exit
  fi
}

system_update() {
  log "Starting system update and package installation."
  sudo apt-get update >/dev/null 2>&1
  sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
  log "System update and package installation completed."
}

create_user() {
  log "Creating new user $USER."
  sudo adduser $USER
  read -p "Do you want to add $USER to the sudo group? (y/n): " ADD_SUDO
  if [ "$ADD_SUDO" == "y" ]; then
    sudo usermod -aG sudo $USER
    log "Added $USER to the sudo group."
  fi
  log "New user $USER created."4

  su - $USER
  exit
  log "Switched to user $USER."
}

generate_ssh_key() {
  log "Generating SSH key for GitHub access."
  ssh-keygen -t ed25519 -C "$USER_EMAIL"
  log "SSH key generated."

  log "Displaying SSH public key. Please copy it and add it to your GitHub account."
  cat ~/.ssh/id_ed25519.pub
  read -p "Please add the above SSH key to your GitHub account. Press Enter to continue once it's done."
  log "Continuing script after SSH key has been added to GitHub."

  su root
  exit
  log "Switched back to root user."
}

get_available_application_port() {
  local APP_NAME=$1
  local STARTING_PORT=$2

  local APPS_COUNT=$(pm2 list | grep -c "$APP_NAME")
  local ASSIGNED_PORT=$((STARTING_PORT + APPS_COUNT + 1))

  echo "$ASSIGNED_PORT"
}

install_node_pm2() {
  log "Installing Node.js and PM2."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash >/dev/null 2>&1
  source ~/.bashrc
  [[ -s $HOME/.nvm/nvm.sh ]] && . $HOME/.nvm/nvm.sh
  nvm install --lts >/dev/null 2>&1
  nvm use --lts >/dev/null 2>&1
  sudo apt-get install -y npm >/dev/null 2>&1
  sudo npm install -g pm2 >/dev/null 2>&1
  log "Node.js and PM2 installation completed."
}

deploy_backend_application() {
  BACKEND_APPLICATION_NAME="$PROJECT_NAME-backend"
  BACKEND_APPLICATION_SERVICE_NAME="$BACKEND_APPLICATION_NAME-$USER"

  BACKEND_APPLICATION_PORT=$(get_available_application_port "$BACKEND_APPLICATION_NAME" "4000")
  BACKEND_APPLICATION_PROXY_PASS=http://localhost:$BACKEND_APPLICATION_PORT
  echo "Assigned port for new backend application: $BACKEND_APPLICATION_PORT"

  log "Deploying the backend application."
  mkdir -p "$USER_DIR"
  cd "$USER_DIR"
  git clone git@github.com:$PROJECT_NAME/$BACKEND_APPLICATION_NAME.git $BACKEND_APPLICATION_NAME
  cd $BACKEND_APPLICATION_NAME
  npm install >/dev/null 2>&1
  pm2 start --name "$BACKEND_APPLICATION_SERVICE_NAME" npm -- run start:dev
  log "Backend application is running on $BACKEND_APPLICATION_PROXY_PASS"
}

deploy_frontend_application() {
  FRONTEND_APPLICATION_NAME="$PROJECT_NAME-frontend"
  FRONTEND_APPLICATION_SERVICE_NAME="$FRONTEND_APPLICATION_NAME-$USER"

  FRONTEND_APPLICATION_PORT=$(get_available_application_port "$FRONTEND_APPLICATION_NAME" "3000")
  FRONTEND_APPLICATION_PROXY_PASS=http://localhost:$FRONTEND_APPLICATION_PORT
  echo "Assigned port for new frontend application: $FRONTEND_APPLICATION_PORT"

  log "Deploying the frontend application."
  cd "$USER_DIR"
  git clone git@github.com:$PROJECT_NAME/$FRONTEND_APPLICATION_NAME.git $FRONTEND_APPLICATION_NAME
  cd $FRONTEND_APPLICATION_NAME
  npm install >/dev/null 2>&1
  pm2 start --name "$FRONTEND_APPLICATION_SERVICE_NAME" npm -- run dev
  log "Frontend application is running on $FRONTEND_APPLICATION_PROXY_PASS"
}

configure_nginx() {
  WEB_DOMAIN="$PROJECT_NAME.com"
  API_DOMAIN="api.$PROJECT_NAME.com"
  NGINX_CONFIG_NAME="$PROJECT_NAME-$USER"

  log "Configuring Nginx."
  sudo tee /etc/nginx/sites-available/$NGINX_CONFIG_NAME >/dev/null <<EOF
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
  log "Nginx configuration completed."

  log "Enabling Nginx configuration and reloading the service."
  sudo ln -s /etc/nginx/sites-available/$NGINX_CONFIG_NAME /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx
  log "Nginx configuration enabled and service reloaded."
}

main() {
  log "Starting user environment initialization script"
  check_root
  system_update
  create_user
  generate_ssh_key
  configure_nginx
  install_node_pm2
  deploy_backend_application
  deploy_frontend_application
  log "User environment initialization script completed"
}

main
