log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (use sudo)"
  exit
fi

# Prompt for the username and email of the new user
read -p "Enter the username of the new user: " NEW_USER
read -p "Enter the email address for the new user's SSH key: " USER_EMAIL

# Add the new user to the system
log_message "Creating new user $NEW_USER..."
sudo adduser $NEW_USER

# Add the user to the sudo group (optional, if admin rights are needed)
read -p "Do you want to add $NEW_USER to the sudo group? (y/n): " ADD_SUDO
if [ "$ADD_SUDO" == "y" ]; then
  sudo usermod -aG sudo $NEW_USER
  log_message "Added $NEW_USER to the sudo group."
fi

# Switch to the new user's home directory and generate an SSH key
log_message "Generating SSH key for the new user..."
sudo -u $NEW_USER ssh-keygen -t ed25519 -C "$USER_EMAIL" -f /home/$NEW_USER/.ssh/id_ed25519 -N ""

# Display the public key
log_message "Displaying the public SSH key. Please add it to GitHub for repository access."
cat /home/$NEW_USER/.ssh/id_ed25519.pub

# Prompt the user to add the SSH key to GitHub
read -p "Please add the above SSH key to the user's GitHub account. Press Enter to continue once it's done."

log_message "SSH key has been added to GitHub."

# Setting correct permissions for the SSH directory and files
log_message "Setting correct permissions for SSH directory and files..."
sudo chmod 700 /home/$NEW_USER/.ssh
sudo chmod 600 /home/$NEW_USER/.ssh/id_ed25519
sudo chmod 644 /home/$NEW_USER/.ssh/id_ed25519.pub
sudo chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh

# Grant the new user access to the project directories
PROJECT_DIR="/home/dev"
log_message "Granting access to project directories..."
sudo chown -R $NEW_USER:$NEW_USER $PROJECT_DIR
sudo chmod -R 755 $PROJECT_DIR

log_message "Access to project directories granted to $NEW_USER."

log_message "All tasks have been successfully completed."


authomatify12!
