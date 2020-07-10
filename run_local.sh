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
#docker run -it --name=${container_name} -d amazonlinux:2
#docker exec -it ${container_name} bash -c "yum update -y"
#docker exec -it ${container_name} bash -c "yum install -y git fuser shadow-utils"
#docker exec -it ${container_name} bash -c "adduser ec2-user"
#docker stop ${container_name}
#
#
#docker exec -it ${container_name} bash -c "amazon-linux-extras install -y docker"
#
## Restart the container
#docker container restart ${container_name}
#
## Run the second part of the setup
##docker exec -it ${container_name} bash -c "service docker start"
#docker info || exit 1;
#docker exec -it ${container_name} bash -c "cd /userver"
#docker exec -it ${container_name} bash -c "cd /userver && chmod +x ./setup.sh && ./setup.sh"

echo "uServer is running! Check it on container ${container_name}"
# docker stop ${container_name} || true
