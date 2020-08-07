#!/bin/bash

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

$SUDO yum update -y
$SUDO yum install -y git

##########################################################################
# docker
##########################################################################

$SUDO amazon-linux-extras install -y docker

##########################################################################
# docker-compose
##########################################################################

# To update the steps, check https://docs.docker.com/compose/install/
if [ ! -f /usr/local/bin/docker-compose ]; then
    echo "Installing docker-compose"
    $SUDO curl -L "https://github.com/docker/compose/releases/download/1.26.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    $SUDO chmod +x /usr/local/bin/docker-compose
fi
command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Error during docker-compose installation. Aborting..."; exit 1; }
echo "Succesfully checked docker-compose!"


$SUDO yum update -y



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

