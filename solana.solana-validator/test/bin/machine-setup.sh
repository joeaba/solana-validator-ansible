#!/usr/bin/env bash
#
# Remote setup script run on a new instance by |launch-cluster.sh|
#

set -ex
cd ~

SOLANA_VERSION=$1
NODE_TYPE=$2
DNS_NAME=$3

test -n "$SOLANA_VERSION"
test -n "$NODE_TYPE"

# Setup timezone
sudo ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime

# Install minimal tools
sudo apt-get update
sudo apt-get --assume-yes install \
  iputils-ping \
  psmisc \
  silversearcher-ag \
  software-properties-common \
  vim \

# Create sol user
sudo adduser sol --gecos "" --disabled-password --quiet
sudo adduser sol sudo
sudo adduser sol adm
sudo -- bash -c 'echo "sol ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers'

# Install solana release as the sol user
sudo --login -u sol -- bash -c "
  curl -sSf https://raw.githubusercontent.com/solana-labs/solana/v1.0.0/install/solana-install-init.sh | sh -s $SOLANA_VERSION
"

sudo --login -u sol -- bash -c "
  echo ~/bin/print-keys.sh >> ~/.profile;
  mkdir ~/.ssh;
  chmod 0700 ~/.ssh;
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKU6YrfEw24+hhxOsu7bAXr1m38G9CCmtUtPpgOjXys4 mvines@sol' >> ~/.ssh/authorized_keys;
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAsOLWUu8wbe6C5IdyB+gy1KwPCggiWv2UwhWRNOI6kV ryoqun@ubuqun' >> ~/.ssh/authorized_keys;
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIxN1jPgVdSqNmGAjFwA1ypcnME8uM/9NjfaUZBpNdMh sakridge@valverde' >> ~/.ssh/authorized_keys;
  echo 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOk4jgcX/VWSk3j//wXeIynSQjsOt+AjYXM/XZUMa7R1Q8lfIJGK/qHLBP86CMXdpyEKJ5i37QLYOL+0VuRy0CI=' >> ~/.ssh/authorized_keys;
  echo 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKMl07qHaMCmnvRKBCmahbBAR6GTWkR5BVe8jdzDJ7xzjXLZlf1aqfaOjt5Cu2VxvW7lUtpJQGLJJiMnWuD4Zmc= dan@Dans-MBP.local' >> ~/.ssh/authorized_keys;

"

ln -s /etc/systemd/system/sol.service .

cat > stop <<EOF
#!/usr/bin/env bash
# Stop the $NODE_TYPE software

set -ex
sudo systemctl stop sol
EOF
chmod +x stop

cat > restart <<EOF
#!/usr/bin/env bash
# Restart the $NODE_TYPE software

set -ex
sudo systemctl daemon-reload
sudo systemctl restart sol
EOF
chmod +x restart

cat > journalctl <<EOF
#!/usr/bin/env bash
# Stop the $NODE_TYPE software

set -ex
sudo journalctl -f "\$@"
EOF
chmod +x journalctl

cat > sol <<EOF
#!/usr/bin/env bash
# Switch to the sol user

set -ex
sudo --login -u sol -- "\$@"
EOF
chmod +x sol

cat > update <<EOF
#!/usr/bin/env bash
# Software update

if [[ -z \$1 ]]; then
  echo "Usage: \$0 [version]"
  exit 1
fi
set -ex
if [[ \$USER != sol ]]; then
  sudo --login -u sol -- solana-install init "\$@"
else
  solana-install init "\$@"
fi
sudo systemctl daemon-reload
sudo systemctl restart sol
sudo systemctl --no-pager status sol
EOF
chmod +x update

# Move the remainder of the files in the home directory over to the sol user
sudo chown -R sol:sol ./*
sudo mv ./* /home/sol
# Move the systemd service file into /etc
sudo cp /home/sol/bin/"$NODE_TYPE".service /etc/systemd/system/sol.service
sudo systemctl daemon-reload

# Start the solana service
sudo systemctl start sol
sudo systemctl enable sol
sudo systemctl --no-pager status sol

[[ $NODE_TYPE = api ]] || exit 0

# Install blockexplorer dependencies
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get install -y nodejs screen
sudo /home/sol/bin/install-redis.sh

sudo --login -u sol -- bash -c "
  set -ex;
  echo '@reboot /home/sol/bin/run-blockexplorer.sh' > crontab.txt;
  if [[ -f faucet.json ]]; then
    echo '@reboot /home/sol/bin/run-faucet.sh' >> crontab.txt;
  fi;
  cat crontab.txt | crontab -;
  rm crontab.txt;
  crontab -l;
"
screen -dmS blockexplorer sudo --login -u sol /home/sol/bin/run-blockexplorer.sh
screen -dmS faucet sudo --login -u sol /home/sol/bin/run-blockexplorer.sh

# Create a self-signed certificate for haproxy to use
# https://security.stackexchange.com/questions/74345/provide-subjectaltname-to-openssl-directly-on-the-command-line
openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=Acme Root CA" -out ca.crt
openssl req -newkey rsa:2048 -nodes -keyout server.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=*.example.com" -out server.csr
openssl x509 -req -extfile <(printf "subjectAltName=DNS:example.com,DNS:www.example.com") -days 365 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt
sudo bash -c "cat server.key server.crt >> /etc/ssl/private/haproxy.pem"

rm ca.key ca.crt ca.srl server.crt server.csr server.key

sudo add-apt-repository --yes ppa:certbot/certbot
sudo apt-get --assume-yes install haproxy certbot

{
  cat <<EOF
frontend http
    bind *:80
    default_backend jsonrpc
    stats enable
    stats hide-version
    stats refresh 30s
    stats show-node
    stats uri /stats
    acl letsencrypt-acl path_beg /.well-known/acme-challenge/
    use_backend letsencrypt if letsencrypt-acl

frontend https
    bind *:443 ssl crt /etc/ssl/private/haproxy.pem
    bind *:8443 ssl crt /etc/ssl/private/haproxy.pem
    default_backend jsonrpc
    stats enable
    stats hide-version
    stats refresh 30s
    stats show-node
    stats uri /stats
    #acl letsencrypt-acl path_beg /.well-known/acme-challenge/
    #use_backend letsencrypt if letsencrypt-acl

frontend wss
    bind *:8901 ssl crt /etc/ssl/private/haproxy.pem
    bind *:8444 ssl crt /etc/ssl/private/haproxy.pem
    default_backend pubsub

backend jsonrpc
    mode http
    server rpc 127.0.0.1:8899

backend pubsub
    mode http
    server rpc 127.0.0.1:8900

backend letsencrypt
    mode http
    server letsencrypt 127.0.0.1:4444


frontend blockexplorer_api_wss
    bind *:3443 ssl crt /etc/ssl/private/haproxy.pem
    default_backend blockexplorer_api

backend blockexplorer_api
    mode http
    server blockexplorer 127.0.0.1:3001

EOF
} | sudo tee -a /etc/haproxy/haproxy.cfg

sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl --no-pager status haproxy


# Skip letsencrypt TLS setup if no DNS name
[[ -n $DNS_NAME ]] || exit 0

{
  cat <<EOF
#!/usr/bin/env bash

if [[ \$(id -u) != 0 ]]; then
  echo Not root
  exit 1
fi

set -ex

if [[ -r /letsencrypt.tgz ]]; then
  tar -C / -zxf /letsencrypt.tgz
fi

certbot certonly \
  --standalone -d $DNS_NAME \
  --non-interactive \
  --agree-tos \
  --email maintainers@solana.com \
  --http-01-port=4444

tar zcf /letsencrypt.new.tgz /etc/letsencrypt
mv -f /letsencrypt.new.tgz /letsencrypt.tgz
ls -l /letsencrypt.tgz

if [[ -z \$maybeDryRun ]]; then
  cat \
    /etc/letsencrypt/live/$DNS_NAME/fullchain.pem \
    /etc/letsencrypt/live/$DNS_NAME/privkey.pem \
    | tee /etc/ssl/private/haproxy.pem
fi

systemctl restart haproxy
systemctl --no-pager status haproxy
EOF
} | sudo tee /solana-renew-cert.sh
sudo chmod +x /solana-renew-cert.sh


sudo /solana-renew-cert.sh
# TODO: By default, LetsEncrypt creates a CRON entry at /etc/cron.d/certbot.
# The entry runs twice a day (by default, LetsEncrypt will only renew the
# certificate if its expiring within 30 days).
#
# What I like to do is to run a bash script that's run monthly, and to force a renewal of the certificate every time.
#
# We can start by editing the CRON file to run a script monthly:
# "0 0 1 * * root bash /opt/update-certs.sh"

exit 0
