#!/usr/bin/env bash

container_name="userver-local"

# Stop and remove container if already present
docker stop ${container_name} || true
docker rm ${container_name} || true

# Run the first part of the setup
docker build -t ${container_name}:latest - < Dockerfile


docker run \
  --name=${container_name} \
  --user=ec2-user \
  --volume=$(pwd):/userver \
  --volume=/var/run/docker.sock:/var/run/docker.sock \
  --detach=true \
  ${container_name}:latest

docker logs ${container_name}

echo "uServer is running! Check it on container ${container_name}"
