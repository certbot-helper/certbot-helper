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
  if [ "$WEBSERVER" == "nginx" ]; then
    sudo systemctl restart nginx
  elif [ "$WEBSERVER" == "apache" ]; then
    sudo systemctl restart apache2
  fi
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

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
  echo -e "${WHITE}Certbot is not installed. Installing certbot...${NC}"
  sudo apt-get update
  sudo apt-get install -y certbot
fi

# Check if apache or nginx plugin for certbot is installed
if [ "$WEBSERVER" == "nginx" ] && ! dpkg -l | grep -q "python3-certbot-nginx"; then
  echo -e "${WHITE}Nginx plugin for Certbot is not installed. Installing nginx plugin...${NC}"
  sudo apt-get install -y python3-certbot-nginx
elif [ "$WEBSERVER" == "apache" ] && ! dpkg -l | grep -q "python3-certbot-apache"; then
  echo -e "${WHITE}Apache plugin for Certbot is not installed. Installing apache plugin...${NC}"
  sudo apt-get install -y python3-certbot-apache
fi

echo -e "${WHITE}For which domain do you want to create a certificate? E.g: domain.com${NC}"
echo -n "> "
read DOMAIN

if [ -z "$DOMAIN" ]; then
  echo -e "${RED}No domain provided. Exiting script.${NC}"
  exit 1
fi

# Function to handle DNS-related errors and show instructions
handle_dns_error() {
  echo -e "${RED}Certificate creation failed: $1${NC}"
  echo -e "${RED}Hint: The Certificate Authority failed to verify the temporary $WEBSERVER configuration changes made by Certbot.${NC}"
  echo -e "${RED}Ensure the listed domains point to this $WEBSERVER server and that it is accessible from the internet.${NC}"
  echo -e "${RED}Possible reasons for failure:${NC}"
  echo -e "${RED}- DNS problem: NXDOMAIN looking up A for $DOMAIN - check that a DNS record exists for this domain.${NC}"
  echo -e "${RED}- DNS problem: NXDOMAIN looking up AAAA for $DOMAIN - check that a DNS record exists for this domain.${NC}"
  echo -e "${RED}Solutions:${NC}"
  echo -e "${RED}1. Check your DNS settings to ensure that the A and/or AAAA records for $DOMAIN are correctly configured.${NC}"
  echo -e "${RED}   A record for $DOMAIN:${NC}"
  echo -e "${RED}   Host: $DOMAIN${NC}"
  echo -e "${RED}   Type: A${NC}"
  echo -e "${RED}   Value: <SERVER_IP>${NC}"
  echo -e "${RED}   TTL: 1 hour${NC}"
  echo -e "${RED}2. Verify that the listed domains point to this $WEBSERVER server.${NC}"
  echo -e "${RED}3. Ensure that your server is accessible from the internet.${NC}"
  echo -e "${RED}4. Retry running this script.${NC}"
}


# Obtain server IP
SERVER_IP=$(hostname -I | awk '/inet / {print $2}')

# Obtain SSL certificate using certbot for the domain
CERTBOT_OUTPUT=$(mktemp)
if [ "$WEBSERVER" == "nginx" ]; then
  echo -e "${WHITE}Certbot is obtaining a certificate for $DOMAIN with nginx...${NC}"
  if ! sudo certbot certonly --nginx -d "$DOMAIN" &> "$CERTBOT_OUTPUT"; then
    handle_dns_error "DNS problem: NXDOMAIN"
    cat "$CERTBOT_OUTPUT"
    rm -f "$CERTBOT_OUTPUT"
    exit 1
  fi
  CONF_FILE="/etc/nginx/sites-available/$DOMAIN.conf"
  CONF_LINK="/etc/nginx/sites-enabled/$DOMAIN.conf"
  ROOT_DIR="/var/www/$DOMAIN"
elif [ "$WEBSERVER" == "apache" ]; then
  echo -e "${WHITE}Certbot is obtaining a certificate for $DOMAIN with apache...${NC}"
  if ! sudo certbot certonly --apache -d "$DOMAIN" &> "$CERTBOT_OUTPUT"; then
    handle_dns_error "DNS problem: NXDOMAIN"
    cat "$CERTBOT_OUTPUT"
    rm -f "$CERTBOT_OUTPUT"
    exit 1
  fi
  CONF_FILE="/etc/apache2/sites-available/$DOMAIN.conf"
  CONF_LINK="/etc/apache2/sites-enabled/$DOMAIN.conf"
  ROOT_DIR="/var/www/$DOMAIN"
fi
rm -f "$CERTBOT_OUTPUT"

# Check PHP-FPM version for Nginx configuration
if [ "$WEBSERVER" == "nginx" ]; then
  PHP_FPM_VERSION=$(sudo systemctl list-units --type=service | grep -oP 'php\d\.\d-fpm' | head -n 1)
  if [ -z "$PHP_FPM_VERSION" ]; then
    echo -e "${RED}PHP-FPM is not installed. Please install PHP-FPM and try again.${NC}"
    exit 1
  fi
fi

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

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/$PHP_FPM_VERSION.sock;
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

  echo -e "${WHITE}Restarting Apache to apply changes.${NC}"
  sudo systemctl restart apache2
fi

# Create index.php file in the domain's root directory
echo -e "${WHITE}Creating index.php in $ROOT_DIR${NC}"
sudo bash -c "cat > $ROOT_DIR/index.php" <<EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Congratulations!</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f4f4f9;
            color: #333;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            text-align: center;
            padding: 20px;
            background: white;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
            border-radius: 8px;
        }
        h1 {
            color: #4CAF50;
        }
        p {
            margin: 10px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Congratulations!</h1>
        <p>Your website setup has been completed.</p>
        <p>Import your own files and change the root path and/or file extension as needed in /etc/nginx/sites-available/$DOMAIN.conf.</p>
    </div>
</body>
</html>
EOL

trap - ERR

# Warning message in red
echo -e "${RED}Be careful, the root is set to $ROOT_DIR. If you are using something else, please change it in $CONF_FILE and reload the web server accordingly.${NC}"

echo -e "${WHITE}All steps completed. Certificate has been created for $DOMAIN.${NC}"
echo -e "${WHITE}index.php has been created in $ROOT_DIR.${NC}"
