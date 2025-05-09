#!/bin/bash
################################################################################
# Script for installing Odoo 18 on Ubuntu 24.04 LTS
# Author: Dinuth Perera
################################################################################
# This script will install Odoo 18 on your Ubuntu 24.04 server with Nginx
# Make a new file:
# sudo nano odoo18-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo18-install.sh
# Execute the script to install Odoo:
# ./odoo18-install.sh
################################################################################

# Set to True if you want to install Nginx
INSTALL_NGINX="True"

# Configuration parameters
OE_USER="odoo18"
OE_HOME="/opt/$OE_USER"
OE_HOME_EXT="$OE_HOME/odoo"
OE_PORT="8069"
OE_VERSION="18.0"
INSTALL_WKHTMLTOPDF="True"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="False"
ADMIN_EMAIL="odoo@yourdomain.com"
CREATE_VIRTUAL_ENV="True"

# Set to True if you want to install Odoo Enterprise version
IS_ENTERPRISE="False"

# PostgreSQL settings
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="$OE_USER"
DB_PASSWORD="False"
DB_CREATE_SUPERUSER="True"  # Set to True to create PostgreSQL superuser instead of regular user
USE_PGPASS="False"           # Set to True to use .pgpass file instead of storing password in odoo.conf

# Color variables for better readability
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[-] $1${NC}"
}

print_error() {
    echo -e "${RED}[!] $1${NC}"
}

#--------------------------------------------------
# Update Server
#--------------------------------------------------
print_status "Updating server..."
sudo apt update
sudo apt upgrade -y

#--------------------------------------------------
# Install essential packages
#--------------------------------------------------
print_status "Installing essential packages..."
sudo apt install -y software-properties-common wget curl git

#--------------------------------------------------
# Install fail2ban for security
#--------------------------------------------------
print_status "Installing fail2ban..."
sudo apt install -y fail2ban
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
print_status "Installing PostgreSQL Server..."
sudo apt install -y postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql

#--------------------------------------------------
# Set up PostgreSQL user and authentication
#--------------------------------------------------
print_status "Setting up PostgreSQL user and authentication..."

# Generate or set password
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    DB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    print_status "Generated random database password: $DB_PASSWORD"
else
    DB_PASSWORD="$OE_USER"  # Use OE_USER as password if not generating random one
fi

# Create PostgreSQL user with appropriate privileges
if [ $DB_CREATE_SUPERUSER = "True" ]; then
    print_status "Creating PostgreSQL superuser $OE_USER..."
    sudo -u postgres psql -c "CREATE USER $OE_USER WITH SUPERUSER CREATEDB LOGIN PASSWORD '$DB_PASSWORD';" 2> /dev/null || {
        print_warning "User may already exist, trying to alter user instead..."
        sudo -u postgres psql -c "ALTER USER $OE_USER WITH SUPERUSER CREATEDB LOGIN PASSWORD '$DB_PASSWORD';" 2> /dev/null
    }
    print_warning "Note: Using superuser privileges for database is less secure but can resolve some permission issues."
else
    print_status "Creating PostgreSQL user $OE_USER with CREATEDB privilege..."
    sudo -u postgres psql -c "CREATE USER $OE_USER WITH CREATEDB LOGIN PASSWORD '$DB_PASSWORD';" 2> /dev/null || {
        print_warning "User may already exist, trying to alter user instead..."
        sudo -u postgres psql -c "ALTER USER $OE_USER WITH CREATEDB LOGIN PASSWORD '$DB_PASSWORD';" 2> /dev/null
    }
fi

# Set up .pgpass file if enabled
if [ $USE_PGPASS = "True" ]; then
    print_status "Setting up .pgpass for secure PostgreSQL authentication..."
    sudo su - $OE_USER -c "echo '$DB_HOST:$DB_PORT:*:$DB_USER:$DB_PASSWORD' > ~/.pgpass"
    sudo su - $OE_USER -c "chmod 600 ~/.pgpass"
    print_status "PostgreSQL authentication is configured using .pgpass file at $OE_HOME/.pgpass"
fi

#--------------------------------------------------
# Install Python dependencies
#--------------------------------------------------
print_status "Installing Python dependencies..."
sudo apt install -y python3-dev python3-pip python3-venv
sudo apt install -y libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev
sudo apt install -y libldap2-dev libssl-dev libffi-dev 
sudo apt install -y libpq-dev libjpeg-dev liblcms2-dev libblas-dev libatlas-base-dev
sudo apt install -y build-essential

#--------------------------------------------------
# Install Node.js and npm
#--------------------------------------------------
print_status "Installing Node.js and npm..."
sudo apt install -y nodejs npm
# Create symbolic link for node if necessary (sometimes required for Odoo)
sudo ln -sf /usr/bin/nodejs /usr/bin/node

# Install Less and less-plugin-clean-css
sudo npm install -g less less-plugin-clean-css
sudo apt install -y node-less

#--------------------------------------------------
# Create Odoo user
#--------------------------------------------------
print_status "Creating system user $OE_USER..."
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --group $OE_USER

#--------------------------------------------------
# Install wkhtmltopdf
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
    print_status "Installing wkhtmltopdf..."
    # Odoo 18 requires newer version of wkhtmltopdf
    sudo apt install -y libssl1.1 || {
        print_warning "Installing libssl1.1 from older repository..."
        sudo wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
        sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb || sudo apt --fix-broken install -y
    }
    
    # Download and install wkhtmltopdf
    sudo wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
    sudo dpkg -i wkhtmltox_0.12.5-1.bionic_amd64.deb || sudo apt --fix-broken install -y
    
    # Create symbolic links
    sudo ln -sf /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
    sudo ln -sf /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
fi

#--------------------------------------------------
# Create Log directory
#--------------------------------------------------
print_status "Creating log directory..."
sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Create custom module directory
#--------------------------------------------------
print_status "Creating custom module directory..."
sudo mkdir -p $OE_HOME/custom/addons
sudo chown -R $OE_USER:$OE_USER $OE_HOME/custom

#--------------------------------------------------
# Install Odoo from GitHub
#--------------------------------------------------
print_status "Installing Odoo $OE_VERSION from GitHub..."

# Clone Odoo from GitHub
sudo su - $OE_USER -c "git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT"

if [ $CREATE_VIRTUAL_ENV = "True" ]; then
    print_status "Creating Python virtual environment..."
    sudo su - $OE_USER -c "python3 -m venv $OE_HOME/venv"
    
    # Install Odoo Python dependencies within the virtual environment
    print_status "Installing Odoo Python dependencies..."
    sudo su - $OE_USER -c "$OE_HOME/venv/bin/pip install wheel setuptools"
    sudo su - $OE_USER -c "$OE_HOME/venv/bin/pip install -r $OE_HOME_EXT/requirements.txt"
    
    # Additional common dependencies
    sudo su - $OE_USER -c "$OE_HOME/venv/bin/pip install num2words ofxparse dbfread psycopg2-binary"
else
    # Install Odoo Python dependencies system-wide
    print_status "Installing Odoo Python dependencies system-wide..."
    sudo pip3 install wheel setuptools
    sudo pip3 install -r $OE_HOME_EXT/requirements.txt
    sudo pip3 install num2words ofxparse dbfread psycopg2-binary
fi

if [ $IS_ENTERPRISE = "True" ]; then
    print_status "Installing Odoo Enterprise..."
    # Enterprise-specific libraries
    if [ $CREATE_VIRTUAL_ENV = "True" ]; then
        sudo su - $OE_USER -c "$OE_HOME/venv/bin/pip install pyOpenSSL"
    else
        sudo pip3 install pyOpenSSL
    fi
    
    # Clone enterprise repository
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"
    
    print_warning "IMPORTANT: Enterprise installation requires valid access to the official Odoo Enterprise repository"
    print_warning "You need to manually clone the enterprise repository using your credentials:"
    print_warning "sudo su $OE_USER -c \"git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise $OE_HOME/enterprise/addons\""
    print_warning "Without a valid Odoo Enterprise subscription and repository access, this will fail"
fi

#--------------------------------------------------
# Configure Odoo
#--------------------------------------------------
print_status "Creating server config file..."

# Create configuration file
sudo touch /etc/${OE_CONFIG}.conf
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    print_status "Generated random admin password: $OE_SUPERADMIN"
fi

# Basic config
sudo tee /etc/${OE_CONFIG}.conf > /dev/null <<EOF
[options]
; This is the password that allows database operations:
admin_passwd = ${OE_SUPERADMIN}
http_port = ${OE_PORT}
longpolling_port = ${LONGPOLLING_PORT}
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
logrotate = True
proxy_mode = ${INSTALL_NGINX}

; Workers configuration
workers = $(nproc)
max_cron_threads = 2
limit_time_cpu = 600
limit_time_real = 1200
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648

; Database settings
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_name = False
EOF

# Add password to config file if not using .pgpass
if [ $USE_PGPASS = "False" ]; then
    sudo su root -c "echo 'db_password = ${DB_PASSWORD}' >> /etc/${OE_CONFIG}.conf"
else
    sudo su root -c "echo '; Password is stored in .pgpass file for security' >> /etc/${OE_CONFIG}.conf"
fi

# Configure addons path
if [ $IS_ENTERPRISE = "True" ]; then
    sudo su root -c "echo 'addons_path = ${OE_HOME_EXT}/addons,${OE_HOME}/enterprise/addons,${OE_HOME}/custom/addons' >> /etc/${OE_CONFIG}.conf"
else
    sudo su root -c "echo 'addons_path = ${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons' >> /etc/${OE_CONFIG}.conf"
fi

# Set proper permissions for config file
sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

#--------------------------------------------------
# Creating systemd service
#--------------------------------------------------
print_status "Creating systemd service..."

# Create systemd service file
sudo tee /etc/systemd/system/$OE_CONFIG.service > /dev/null <<EOF
[Unit]
Description=Odoo18 Server
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=${OE_USER}
Group=${OE_USER}
ExecStart=
EOF

if [ $CREATE_VIRTUAL_ENV = "True" ]; then
    sudo su root -c "echo 'ExecStart=${OE_HOME}/venv/bin/python3 ${OE_HOME_EXT}/odoo-bin -c /etc/${OE_CONFIG}.conf' >> /etc/systemd/system/$OE_CONFIG.service"
else
    sudo su root -c "echo 'ExecStart=/usr/bin/python3 ${OE_HOME_EXT}/odoo-bin -c /etc/${OE_CONFIG}.conf' >> /etc/systemd/system/$OE_CONFIG.service"
fi

sudo tee -a /etc/systemd/system/$OE_CONFIG.service > /dev/null <<EOF
Restart=always
RestartSec=5
SyslogIdentifier=${OE_CONFIG}
KillMode=mixed
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions for the service file
sudo chmod 755 /etc/systemd/system/$OE_CONFIG.service
sudo chown root:root /etc/systemd/system/$OE_CONFIG.service

print_status "Enabling and starting Odoo service..."
sudo systemctl daemon-reload
sudo systemctl enable $OE_CONFIG.service
sudo systemctl start $OE_CONFIG.service

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
    print_status "Installing and configuring Nginx..."
    sudo apt install -y nginx
    
    # Create Nginx site config
    sudo tee /etc/nginx/sites-available/$OE_CONFIG > /dev/null <<EOF
upstream odoo {
    server 127.0.0.1:${OE_PORT};
}

upstream odoo-chat {
    server 127.0.0.1:${LONGPOLLING_PORT};
}

server {
    listen 80;
    server_name ${WEBSITE_NAME};

    # Redirect requests to odoo backend server
    location / {
        proxy_pass http://odoo;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }

    # Redirect longpolling requests to odoo-chat
    location /longpolling {
        proxy_pass http://odoo-chat;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }

    # Cache static files
    location ~* /web/static/ {
        proxy_cache_valid 200 304 60m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo;
    }

    # Gzip
    gzip on;
    gzip_min_length 1000;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/xml text/css text/javascript application/json application/x-javascript application/javascript;
    gzip_disable "MSIE [1-6]\.";

    # Log files
    access_log /var/log/nginx/${OE_CONFIG}-access.log;
    error_log /var/log/nginx/${OE_CONFIG}-error.log;

    # Increase proxy buffer size
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;
    proxy_read_timeout 900s;
    proxy_connect_timeout 900s;
    proxy_send_timeout 900s;
    
    # Request timeouts
    proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
    
    # Max upload size
    client_max_body_size 100m;
}
EOF

    # Enable the Odoo Nginx site
    sudo ln -sf /etc/nginx/sites-available/$OE_CONFIG /etc/nginx/sites-enabled/$OE_CONFIG
    
    # Disable default site
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload Nginx
    sudo nginx -t && sudo systemctl reload nginx
    
    print_status "Nginx has been configured for Odoo."
fi

#--------------------------------------------------
# Enable SSL with certbot if requested
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@yourdomain.com" ] && [ $WEBSITE_NAME != "_" ]; then
    print_status "Setting up SSL with Let's Encrypt..."
    
    # Install certbot
    sudo apt install -y snapd
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    
    # Create symbolic link
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
    
    # Obtain and install certificate
    sudo certbot --nginx --non-interactive --agree-tos --email $ADMIN_EMAIL --redirect -d $WEBSITE_NAME
    
    # Reload Nginx
    sudo systemctl reload nginx
    
    print_status "SSL/HTTPS has been enabled!"
else
    if [ $ENABLE_SSL = "True" ]; then
        if [ $ADMIN_EMAIL = "odoo@yourdomain.com" ]; then
            print_warning "Certbot requires a valid email address. Please update ADMIN_EMAIL."
        fi
        if [ $WEBSITE_NAME = "_" ]; then
            print_warning "Website name is set as '_'. Cannot obtain SSL Certificate. Please use a valid domain."
        fi
    fi
fi

#--------------------------------------------------
# Final steps and output information
#--------------------------------------------------
print_status "Adjusting file permissions..."
sudo chown -R $OE_USER:$OE_USER $OE_HOME

print_status "=============================================="
print_status "Odoo 18 installation completed successfully!"
print_status "=============================================="
print_status "Odoo Configuration:"
print_status "Database User: $OE_USER"
print_status "Odoo Version: $OE_VERSION"
print_status "Port: $OE_PORT"
print_status "Longpolling Port: $LONGPOLLING_PORT"
print_status "User Service: $OE_USER"
print_status "Configuration File: /etc/${OE_CONFIG}.conf"
print_status "Logs Path: /var/log/$OE_USER"
print_status "Admin Password: $OE_SUPERADMIN"
print_status "Database Password: $DB_PASSWORD"

if [ $DB_CREATE_SUPERUSER = "True" ]; then
    print_status "PostgreSQL Role: SUPERUSER (has full database access)"
else
    print_status "PostgreSQL Role: Regular user with CREATEDB privilege"
fi

if [ $USE_PGPASS = "True" ]; then
    print_status "Authentication: Using .pgpass file (${OE_HOME}/.pgpass)"
else
    print_status "Authentication: Password stored in configuration file"
fi

print_status "=============================================="
print_status "Service Commands:"
print_status "Start Odoo: sudo systemctl start $OE_CONFIG"
print_status "Stop Odoo: sudo systemctl stop $OE_CONFIG"
print_status "Restart Odoo: sudo systemctl restart $OE_CONFIG"
print_status "Check Status: sudo systemctl status $OE_CONFIG"
print_status "View Logs: sudo tail -f /var/log/$OE_USER/${OE_CONFIG}.log"
if [ $INSTALL_NGINX = "True" ]; then
    print_status "=============================================="
    print_status "Nginx Configuration:"
    print_status "Config File: /etc/nginx/sites-available/$OE_CONFIG"
    print_status "Access Logs: /var/log/nginx/${OE_CONFIG}-access.log"
    print_status "Error Logs: /var/log/nginx/${OE_CONFIG}-error.log"
fi
print_status "=============================================="