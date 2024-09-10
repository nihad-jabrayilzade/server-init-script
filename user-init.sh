#!/bin/bash

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)"
  exit
fi

TARGET="seymur"
TARGET_DIR="/home/$TARGET"

PROJECT_NAME="authomatify"
WEB_DOMAIN="$TARGET.$PROJECT_NAME.com"
API_DOMAIN="$TARGEGT.api.$PROJECT_NAME.com"
NGINX_CONFIG_NAME="$PROJECT_NAME-$TARGET"

FRONTEND_APPLICATION_NAME="$PROJECT_NAME-frontend"
FRONTEND_APPLICATION_SERVICE_NAME="$FRONTEND_APPLICATION_NAME-$TARGET"
FRONTEND_APPLICATION_HOST="localhost"
FRONTEND_APPLICATION_PORT=3001
FRONTEND_APPLICATION_PROXY_PASS="http://$FRONTEND_APPLICATION_HOST:$FRONTEND_APPLICATION_PORT"

BACKEND_APPLICATION_NAME="$PROJECT_NAME-backend"
BACKEND_APPLICATION_SERVICE_NAME="$BACKEND_APPLICATION_NAME-$TARGET"
BACKEND_APPLICATION_HOST="localhost"
BACKEND_APPLICATION_PORT=4001
BACKEND_APPLICATION_PROXY_PASS="http://$BACKEND_APPLICATION_HOST:$BACKEND_APPLICATION_PORT"

# ------------------------------------------------------------------------------

read -p "Enter the username of the new user: " NEW_USER
read -p "Enter the email address for the new user's SSH key: " USER_EMAIL

log_message "Creating new user $NEW_USER..."
sudo adduser $NEW_USER

read -p "Do you want to add $NEW_USER to the sudo group? (y/n): " ADD_SUDO
if [ "$ADD_SUDO" == "y" ]; then
  sudo usermod -aG sudo $NEW_USER
  log_message "Added $NEW_USER to the sudo group."
fi

# ------------------------------------------------------------------------------

log_message "Starting system update and package installation..."

sudo apt-get update >/dev/null 2>&1
sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1

log_message "System update and package installation completed."

# ------------------------------------------------------------------------------
log_message "Generating SSH key for GitHub access..."

sudo su - $TARGET
ssh-keygen -t ed25519 -C "$USER_EMAIL"

log_message "SSH key generated."

# Display the public key and copy it to the clipboard
log_message "Displaying SSH public key. Please copy it and add it to your GitHub account."
cat $TARGET_DIR/.ssh/id_ed25519.pub

# Prompt the user to add the SSH key to their GitHub account
read -p "Please add the above SSH key to your GitHub account. Press Enter to continue once it's done."

log_message "Continuing script after SSH key has been added to GitHub."

sudo su - root
# ------------------------------------------------------------------------------

log_message "Configuring Nginx..."

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

log_message "Nginx configuration completed."

log_message "Enabling Nginx configuration and reloading the service..."

sudo ln -s /etc/nginx/sites-available/$NGINX_CONFIG_NAME /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

log_message "Nginx configuration enabled and service reloaded."

# ------------------------------------------------------------------------------

log_message "Installing Node.js and PM2..."

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash >/dev/null 2>&1
source ~/.bashrc
[[ -s $HOME/.nvm/nvm.sh ]] && . $HOME/.nvm/nvm.sh
nvm install --lts >/dev/null 2>&1
nvm use --lts >/dev/null 2>&1
sudo apt-get install -y npm >/dev/null 2>&1
sudo npm install -g pm2 >/dev/null 2>&1

log_message "Node.js and PM2 installation completed."

# ------------------------------------------------------------------------------

log_message "Deploying the backend application..."

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"
git clone git@github.com:$PROJECT_NAME/$BACKEND_APPLICATION_NAME.git $BACKEND_APPLICATION_NAME
cd $BACKEND_APPLICATION_NAME
npm install >/dev/null 2>&1
pm2 start --name "$BACKEND_APPLICATION_SERVICE_NAME" npm -- run start:dev

log_message "Backend application deployment completed."

log_message "Deploying the frontend application..."

cd "$TARGET_DIR"
git clone git@github.com:$PROJECT_NAME/$FRONTEND_APPLICATION_NAME.git $FRONTEND_APPLICATION_NAME
cd $FRONTEND_APPLICATION_NAME
npm install >/dev/null 2>&1
pm2 start --name "$FRONTEND_APPLICATION_SERVICE_NAME" npm -- run dev

log_message "Frontend application deployment completed."

log_message "All tasks have been successfully completed. Run 'pm2 list' to view the running applications."

# nano server-init.sh
# chmod +x server-init.sh
# sudo ./server-init.sh
