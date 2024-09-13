#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck
# Co-Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE
# Source: https://github.com/msgbyte/tianji

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y --no-install-recommends \
  postgresql \
  build-essential \
  curl \
  unzip \
  sudo \
  git \
  make \
  gnupg \
  ca-certificates \
  mc
msg_ok "Installed Dependencies"

msg_info "Setting up Node.js Repository"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
msg_ok "Set up Repositories"

msg_info "Installing Node.js, pnpm & pm2"
$STD apt-get install -y nodejs
$STD npm install -g pnpm@9.7.1
$STD npm install -g pm2 
msg_ok "Installed Node.js, pnpm & pm2"


msg_info "Setup Tianji (Patience)"
cd /opt
RELEASE=$(wget -q https://github.com/msgbyte/tianji/releases/latest -O - | grep "title>Release" | cut -d " " -f 4)
wget -q "https://github.com/msgbyte/tianji/archive/refs/tags/${RELEASE}.zip"
unzip -q ${RELEASE}.zip
CLEAN_RELEASE=$(echo $RELEASE | sed 's/^v//')
mv tianji-${CLEAN_RELEASE} /opt/tianji
cd tianji
export NODE_OPTIONS=--max_old_space_size=4096
echo "${RELEASE}" >"/opt/${APPLICATION}_version.txt"
$STD pnpm install
$STD pnpm build
msg_ok "Initial Setup complete"

msg_info "Setting up Database"
DB_NAME=tianji_db
DB_USER=tianji
DB_PASS="$(openssl rand -base64 18 | cut -c1-13)"
TIANJI_SECRET="$(openssl rand -base64 32 | cut -c1-24)"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"
$STD sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 
$STD sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;"
$STD sudo -u postgres psql -c "ALTER USER $DB_USER WITH SUPERUSER;"
echo "" >>~/tianji.creds
echo -e "Tianji Database User: $DB_USER" >>~/tianji.creds
echo -e "Tianji Database Password: $DB_PASS" >>~/tianji.creds
echo -e "Tianji Database Name: $DB_NAME" >>~/tianji.creds
echo -e "Tianji Secret: $TIANJI_SECRET" >>~/tianji.creds
msg_ok "Set up PostgreSQL database"

msg_info "Setting up Tianji Env"
cat <<EOF >/opt/tianji/src/server/.env
DATABASE_URL="postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME?schema=public"
JWT_SECRET="$TIANJI_SECRET"
EOF
msg_ok ".env successfully set up"

msg_info "Initialize Application"
cd /opt/tianji
$STD npm install pm2 -g
$STD pm2 install pm2-logrotate
cd src/server
$STD pnpm db:migrate:apply
msg_ok "Application Initialized"

msg_info "Activate PM2 Service" 
$STD pm2 start /opt/tianji/src/server/dist/src/server/main.js --name tianji
$STD pm2 save
msg_ok "Service activated"

motd_ssh
customize

msg_info "Cleaning up"
rm -R /opt/${RELEASE}.zip
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"
