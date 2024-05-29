#!/bin/bash

# ASCII art for certbot-helper.sh, created by @devwesley
echo -e "\n\e[1;32m"
echo "    .___                                 .__                "
echo "  __| _/_______  ____  _  __ ____   _____|  |   ____ ___.__."
echo " / __ |/ __ \  \/ /\ \/ \/ // __ \ /  ___/  | _/ __ <   |  |"
echo "/ /_/ \  ___/\   /  \     /\  ___/ \___ \|  |_\  ___/\___  |"
echo "\____ |\___  >\_/    \/\_/  \___  >____  >____/\___  > ____|"
echo "     \/    \/                   \/     \/          \/\/     "
echo -e "\e[0m\n"

RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

cleanup() {
  echo -e "${RED}An error occurred: $1${NC}"
  echo -e "${WHITE}Cleaning up...${NC}"
  if [ -f "$CONF_FILE" ]; then
    sudo rm -f "$CONF_FILE"
    echo -e "${WHITE}Deleted $CONF_FILE${NC}"
  fi
  if [ -L "$CONF_LINK" ]; then
    sudo rm -f "$CONF_LINK"
    echo -e "${WHITE}Deleted symlink $CONF_LINK${NC}"
  fi
  if [ -d "$ROOT_DIR" ]; then
    sudo rm -rf "$ROOT_DIR"
    echo -e "${WHITE}Deleted directory $ROOT_DIR${NC}"
  fi
  sudo systemctl restart nginx
  sudo systemctl restart apache2
  exit 1
}

trap 'cleanup "$BASH_COMMAND"' ERR

echo -e "${WHITE}Which web server are you using? (apache/nginx)${NC}"
echo -n "> "
read WEBSERVER

if [[ "$WEBSERVER" != "apache" && "$WEBSERVER" != "nginx" ]]; then
  echo -e "${RED}Invalid input. Please enter 'apache' or 'nginx'.${NC}"
  exit 1
fi

echo -e "${WHITE}For which domain do you want to create a certificate?${NC}"
echo -n "> "
read DOMAIN

if [ -z "$DOMAIN" ]; then
  echo -e "${RED}No domain provided. Exiting script.${NC}"
  exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
  echo -e "${WHITE}Certbot is not installed. Installing certbot...${NC}"
  sudo apt-get update
  sudo apt-get install -y certbot

  if [ "$WEBSERVER" == "nginx" ]; then
    sudo apt-get install -y python3-certbot-nginx
  elif [ "$WEBSERVER" == "apache" ]; then
    sudo apt-get install -y python3-certbot-apache
  fi
else
  echo -e "${WHITE}Certbot is already installed.${NC}"
fi

# Function to handle DNS-related errors and show instructions
handle_dns_error() {
  echo -e "${RED}DNS-related error detected. Please ensure your A record is correctly configured in your DNS settings. You can set it as follows:${NC}"
  echo -e "${WHITE}A record for $DOMAIN:${NC}"
  echo -e "${WHITE}Host: @${NC}"
  echo -e "${WHITE}Type: A${NC}"
  echo -e "${WHITE}Value: <YOUR_SERVER_IP>${NC}"
  echo -e "${WHITE}TTL: 1 hour${NC}"
  exit 1
}

# Obtain SSL certificate using certbot for the domain
CERTBOT_OUTPUT=$(mktemp)
if [ "$WEBSERVER" == "nginx" ]; then
  echo -e "${WHITE}Certbot is obtaining a certificate for $DOMAIN with nginx...${NC}"
  if ! sudo certbot certonly --nginx -d "$DOMAIN" &> "$CERTBOT_OUTPUT"; then
    if grep -q "The server could not resolve" "$CERTBOT_OUTPUT"; then
      handle_dns_error
    else
      cleanup "Certificate creation failed: $(<"$CERTBOT_OUTPUT")"
    fi
    rm -f "$CERTBOT_OUTPUT"
  fi
  CONF_FILE="/etc/nginx/sites-available/$DOMAIN.conf"
  CONF_LINK="/etc/nginx/sites-enabled/$DOMAIN.conf"
  ROOT_DIR="/var/www/$DOMAIN"
elif [ "$WEBSERVER" == "apache" ]; then
  echo -e "${WHITE}Certbot is obtaining a certificate for $DOMAIN with apache...${NC}"
  if ! sudo certbot certonly --apache -d "$DOMAIN" &> "$CERTBOT_OUTPUT"; then
    if grep -q "The server could not resolve" "$CERTBOT_OUTPUT"; then
      handle_dns_error
    else
      cleanup "Certificate creation failed: $(<"$CERTBOT_OUTPUT")"
    fi
    rm -f "$CERTBOT_OUTPUT"
  fi
  CONF_FILE="/etc/apache2/sites-available/$DOMAIN.conf"
  CONF_LINK="/etc/apache2/sites-enabled/$DOMAIN.conf"
  ROOT_DIR="/var/www/$DOMAIN"
fi
rm -f "$CERTBOT_OUTPUT"

# Create web server configuration and set up directories
echo -e "${WHITE}Creating configuration for $WEBSERVER...${NC}"
sudo mkdir -p "$ROOT_DIR"
sudo touch "$CONF_FILE"

if [ "$WEBSERVER" == "nginx" ]; then
  sudo bash -c "cat > $CONF_FILE" <<EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    root $ROOT_DIR;
    index index.php index.html;

    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log  /var/log/nginx/$DOMAIN-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
       ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock; # Adjust PHP version as needed
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

  echo -e "${WHITE}Creating a symlink to sites-enabled.${NC}"
  sudo ln -s "$CONF_FILE" "$CONF_LINK"

  echo -e "${WHITE}Creating directory: $ROOT_DIR${NC}"
  sudo mkdir -p "$ROOT_DIR"

  echo -e "${WHITE}Restarting Nginx to apply changes.${NC}"
  sudo systemctl restart nginx

elif [ "$WEBSERVER" == "apache" ]; then
  sudo bash -c "cat > $CONF_FILE" <<EOL
<VirtualHost *:80>
  ServerName $DOMAIN
  
  RewriteEngine On
  RewriteCond %{HTTPS} !=on
  RewriteRule ^/?(.*) https://%{SERVER_NAME}/$1 [R,L] 
</VirtualHost>

<VirtualHost *:443>
  ServerName $DOMAIN
  DocumentRoot "$ROOT_DIR"

  AllowEncodedSlashes On
  
  php_value upload_max_filesize 100M
  php_value post_max_size 100M

  <Directory "$ROOT_DIR">
    Require all granted
    AllowOverride all
  </Directory>

  SSLEngine on
  SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
</VirtualHost>
EOL

  echo -e "${WHITE}Creating a symlink to sites-enabled.${NC}"
  sudo ln -s "$CONF_FILE" "$CONF_LINK"

  echo -e "${WHITE}Creating directory: $ROOT_DIR${NC}"
  sudo mkdir -p "$ROOT_DIR"

  echo -e "${WHITE}Restarting Apache to apply changes.${NC}"
  sudo systemctl restart apache2
fi

trap - ERR

# Warning message in red
echo -e "${RED}Be careful, the root is set to $ROOT_DIR. If you are using something else, please change it in $CONF_FILE and reload the web server accordingly.${NC}"

echo -e "${WHITE}All steps completed. Certificate has been created for $DOMAIN.${NC}"
