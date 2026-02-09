#!/bin/bash
set -eux

apt-get update -y
apt-get install -y docker.io docker-compose-plugin
systemctl enable docker
systemctl start docker

docker rm -f wordpress || true

docker run -d --name wordpress \
  -p 80:80 \
  --restart always \
  -e WORDPRESS_DB_HOST=${db_host}:3306 \
  -e WORDPRESS_DB_USER=${db_user} \
  -e WORDPRESS_DB_PASSWORD=${db_pass} \
  -e WORDPRESS_DB_NAME=${db_name} \
  wordpress:latest
