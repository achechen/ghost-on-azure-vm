#!/bin/bash
sitename='<<sitename>>'
username='<<username>>'
siteurl='<<siteurl>>'
dbhost='<<dbhost>>'
dbuser='<<dbuser>>'
dbpassword='<<dbpassword>>'
ghostadminuser='<<ghostadminuser>>'
ghostadminpass='<<ghostadminpass>>'
ghostadminemail='<<ghostadminemail>>'

sitename_prod=$sitename
sitename_staging="staging_${sitename}"

siteurl_prod=$siteurl
siteurl_staging="staging_${siteurl}"

dbname_prod="${sitename}_db"
dbname_staging="staging_${sitename}_db"

siteurl_without_dots=$(sed 's/\./-/g' <<<"$siteurl")

servicename_prod="ghost_${siteurl_without_dots}.service"
servicename_staging="ghost_staging_${siteurl_without_dots}.service"

port_prod="2368"
port_staging="2369"

# install necessary packages
apt-get update
apt-get install nginx -y
apt-get install mysql-server -y

# get node.js and install
wget https://deb.nodesource.com/setup_14.x
chmod +x setup_14.x
./setup_14.x
DEBIAN_FRONTEND=noninteractive apt-get install nodejs -y

# install ghost-cli
npm install ghost-cli@latest -g -y

#function declaration
install_and_configure_ghost(){
  local sitename=$1
  local siteurl=$2
  local dbname=$3
  local servicename=$4
  local port=$5
  local ghostadminuser="$6"
  local ghostadminpass=$7
  local ghostadminemail=$8
  
  # create website folder and fix permissions
  mkdir -p /var/www/$sitename
  chown $username:$username /var/www/$sitename
  chmod 775 /var/www/$sitename

  # run ghost install but do not start and do not set it up
  # run as $username because ghost cli cannot be run as root - LOL
  su - $username -c "cd /var/www/$sitename && ghost install --no-start --no-setup --db=mysql --url=$siteurl"

  # Have to configure ghost manually because it is practically impossible 
  # to configure ghost programmatically using ghost-cli

  # create ghost user and make it owner of the content folder
  useradd --system --user-group ghost
  chown -R ghost:ghost /var/www/$sitename/content

  # create ghost configuration file
  # According to ghost documentation, you can create this configuration using "ghost config"
  # but they don't go into details so, easier to create it manually
  # Remove ssl part altogether if your mysql instance does not support SSL
  cat <<EOT > /var/www/$sitename/config.production.json
{
  "url": "http://$siteurl",
  "server": {
    "port": $port,
    "host": "127.0.0.1"
  },
  "database": {
    "client": "mysql",
    "connection": {
      "host": "$dbhost",
      "user": "$dbuser",
      "password": "$dbpassword",
      "database": "$dbname",
      "ssl": {
        "rejectUnauthorized": "true",
        "secureProtocol": "TLSv1_2_method"
      }
    }
  },
  "mail": {
    "transport": "Direct"
  },
  "logging": {
    "transports": [
      "file",
      "stdout"
    ]
  },
  "process": "systemd",
  "paths": {
    "contentPath": "/var/www/$sitename/content"
  }
}
EOT

  # fix ownership of the config file
  chown $username:$username /var/www/$sitename/config.production.json

  # This sets up .ghost-cli file with the correct service name so that ghost ls command would work. Again, cannot run as root
  su - $username -c "cd /var/www/$sitename && ghost setup instance"

  # create systemd service file
  cat <<EOT > /lib/systemd/system/$servicename
[Unit]
Description=Ghost systemd service for blog: $siteurl
Documentation=https://ghost.org/docs/

[Service]
Type=simple
WorkingDirectory=/var/www/$sitename
User=999
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node /usr/bin/ghost run
Restart=always

[Install]
WantedBy=multi-user.target
EOT

  # create nginx configuration file for the site
  cat <<EOT > /etc/nginx/sites-available/$siteurl.conf
server {
    listen 80;
    listen [::]:80;

    server_name $siteurl;
    root /var/www/$sitename/system/nginx-root; # Used for acme.sh SSL verification (https://acme.sh)

    location / {
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$http_host;
        proxy_pass http://127.0.0.1:$port;

    }

    location ~ /.well-known {
        allow all;
    }

    client_max_body_size 50m;
}
EOT

  ln -sf /etc/nginx/sites-available/$siteurl.conf /etc/nginx/sites-enabled/$siteurl.conf
  nginx -s reload

  # enable and start ghost service
  systemctl enable $servicename
  systemctl start $servicename

  # update hosts file
  echo "127.0.0.1 ${siteurl}" >> /etc/hosts

  # set up initial admin user
  sleep 120
  url="http://${siteurl}/ghost/api/canary/admin/authentication/setup/"
  jsonbody=$(cat <<-END
    { "setup": 
        [ { "name": "${ghostadminuser}",
            "email": "${ghostadminemail}",
            "password": "${ghostadminpass}",
            "blogTitle": "${sitename}" } ] }
END
)
  request=$(curl -d "$jsonbody" -H 'Content-Type:application/json' $url)
  echo $request
  if [[ "$request" =~ "busy updating our site" ]]; then
    sleep 120
    request=$(curl -d "$jsonbody" -H 'Content-Type:application/json' $url)
  fi

}

# install production
install_and_configure_ghost $sitename_prod $siteurl_prod $dbname_prod $servicename_prod $port_prod "$ghostadminuser" $ghostadminpass $ghostadminemail

# install staging
install_and_configure_ghost $sitename_staging $siteurl_staging $dbname_staging $servicename_staging $port_staging "$ghostadminuser" $ghostadminpass $ghostadminemail

# remove mysql server
apt-get remove mysql-server

