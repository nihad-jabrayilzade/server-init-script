#!/bin/bash

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)"
  exit
fi

TARGET_DIR="/home/dev"

# ------------------------------------------------------------------------------

log_message "Starting system update and package installation..."

sudo apt-get update >/dev/null 2>&1
sudo apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1

log_message "System update and package installation completed."

# ------------------------------------------------------------------------------

log_message "Installing Git..."

sudo apt-get install -y git >/dev/null 2>&1

log_message "Git installation completed."

log_message "Generating SSH key for GitHub access..."

read -p "Enter your email address for the SSH key: " USER_EMAIL

ssh-keygen -t ed25519 -C "$USER_EMAIL"

log_message "SSH key generated."

# Display the public key and copy it to the clipboard
log_message "Displaying SSH public key. Please copy it and add it to your GitHub account."
cat ~/.ssh/id_ed25519.pub

# Prompt the user to add the SSH key to their GitHub account
read -p "Please add the above SSH key to your GitHub account. Press Enter to continue once it's done."

log_message "Continuing script after SSH key has been added to GitHub."

# ------------------------------------------------------------------------------

log_message "Setting up Docker repository..."

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null 2>&1
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1

log_message "Docker repository setup completed."

log_message "Installing Docker..."

sudo apt-get update >/dev/null 2>&1
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1

log_message "Docker installation completed."

# ------------------------------------------------------------------------------

log_message "Installing Nginx..."

sudo apt-get install -y nginx >/dev/null 2>&1

log_message "Nginx installation completed."

log_message "Configuring Nginx..."

sudo tee /etc/nginx/sites-available/authomatify >/dev/null <<EOF
server {
    server_name authomatify.com;

    location / {
        proxy_pass http://localhost:3000;
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
        proxy_pass http://localhost:3000/_next/static;
    }
}

server {
    server_name api.authomatify.com;

    location / {
        proxy_pass http://localhost:4000;
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

sudo ln -s /etc/nginx/sites-available/authomatify /etc/nginx/sites-enabled/
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

log_message "Setting up MySQL using Docker..."

# Prompt the user for the MySQL root password
read -sp "Enter the MySQL root password: " MYSQL_ROOT_PASSWORD
echo

sudo docker run -d --name mysql \
  -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
  -p 3306:3306 \
  -v db_data:/var/lib/mysql \
  mysql:8.0 >/dev/null 2>&1

log_message "MySQL setup using Docker completed."

# ------------------------------------------------------------------------------

log_message "Deploying the backend application..."

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"
git clone git@github.com:authomatify/authomatify-backend.git authomatify-backend
cd authomatify-backend
npm install >/dev/null 2>&1
pm2 start --name "authomatify-backend-dev" npm -- run start:dev

log_message "Backend application deployment completed."

log_message "Deploying the frontend application..."

cd "$TARGET_DIR"
git clone git@github.com:authomatify/authomatify-frontend.git authomatify-frontend
cd authomatify-frontend
npm install >/dev/null 2>&1
pm2 start --name "authomatify-frontend-dev" npm -- run dev

log_message "Frontend application deployment completed."

log_message "All tasks have been successfully completed. Run 'pm2 list' to view the running applications."

# nano server-init.sh
# chmod +x server-init.sh
# sudo ./server-init.sh
