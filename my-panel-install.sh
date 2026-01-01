#!/usr/bin/env bash
# Run as root!

set -euo pipefail

# Colors - different palette
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${PURPLE}"
echo "======================================"
echo "   CUSTOM PANEL INSTALLER v1.0"
echo "   by [YourNameHere]"
echo "======================================"
echo -e "${NC}"

# Safety check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root!${NC}"
   exit 1
fi

echo -e "${CYAN}This will install Pterodactyl Panel on a fresh Ubuntu/Debian server.${NC}"
echo -e "${RED}WARNING: Backup your server first! This modifies system packages.${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Ask for domain
read -p "Enter your panel domain (example: panel.mydomain.com): " PANEL_DOMAIN
if [[ -z "$PANEL_DOMAIN" ]]; then
    echo -e "${RED}Domain cannot be empty!${NC}"
    exit 1
fi

# Ask for secure DB password (no hardcoded!)
read -sp "Enter a STRONG database password for 'pterouser': " DB_PASS
echo
if [[ ${#DB_PASS} -lt 12 ]]; then
    echo -e "${RED}Password too short! Use at least 12 characters.${NC}"
    exit 1
fi

echo -e "${GREEN}Starting installation...${NC}"

# Update & basic deps
apt update -y && apt upgrade -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar sudo

# PHP repo (Ubuntu/Debian compatible)
if [[ "$(lsb_release -is)" == "Ubuntu" ]]; then
    add-apt-repository ppa:ondrej/php -y
else
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list
fi

# Redis repo
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis.gpg
echo "deb [signed-by=/usr/share/keyrings/redis.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

apt update -y

# Install packages
apt install -y php8.3 php8.3-{cli,fpm,mysql,zip,gd,mbstring,curl,xml,bcmath,common,intl} \
    mariadb-server nginx redis-server composer

# Database setup
DB_NAME="pterodb"
DB_USER="pterouser"

mariadb -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mariadb -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# Pterodactyl download & setup
mkdir -p /var/www/pteropanel
cd /var/www/pteropanel

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# .env config
cp .env.example .env
sed -i "s|^APP_URL=.*|APP_URL=https://${PANEL_DOMAIN}|" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env

# Composer & artisan
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan p:environment:setup --no-interaction
php artisan migrate --seed --force

# Permissions
chown -R www-data:www-data /var/www/pteropanel/*

# Queue worker (simple version)
cat > /etc/systemd/system/ptero-queue.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=network.target

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pteropanel/artisan queue:work --sleep=3 --tries=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now redis-server ptero-queue.service

# Nginx (basic https with self-signed)
# You can replace this with certbot later!
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/ptero.key \
    -out /etc/ssl/certs/ptero.crt \
    -subj "/CN=${PANEL_DOMAIN}"

cat > /etc/nginx/sites-available/pteropanel <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${PANEL_DOMAIN};

    root /var/www/pteropanel/public;
    index index.php;

    ssl_certificate /etc/ssl/certs/ptero.crt;
    ssl_certificate_key /etc/ssl/private/ptero.key;

    location / {
        try_files \$uri /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pteropanel /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# Finish
clear
echo -e "${GREEN}Installation finished!${NC}"
echo "Panel URL: https://${PANEL_DOMAIN}"
echo "Database User: ${DB_USER}"
echo "Database Password: (the one you entered)"
echo "Create admin account: cd /var/www/pteropanel && php artisan p:user:make"
echo ""
echo "Next steps: Set up real SSL with certbot, configure Wings daemon, etc."
echo "Good luck with your hosting!"
