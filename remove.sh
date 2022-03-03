#!/usr/bin/env bash

# Common functions
. ./functions.sh --source-only

opt=$1
force=0
if [[ "$opt" =~ ^(\-f|\-\-force)$ ]]; then
    force=1
fi

if [[ "$force" -eq "0" ]]; then
    read -p "Are you sure? [y|N] " -n 1 -r
    echo # move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting without making any change"
        [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
    fi
fi

./stop.sh

remove_service_images_and_volumes userver-filemgr
remove_service_images_and_volumes userver-auth
remove_service_images_and_volumes userver-mailer
remove_service_images_and_volumes userver-datamgr
remove_service_images_and_volumes userver-logger
remove_service_images_and_volumes userver-web

echo "Removing service files"
sudo rm -rf userver-filemgr
sudo rm -rf userver-auth
sudo rm -rf userver-mailer
sudo rm -rf userver-datamgr
sudo rm -rf userver-logger
sudo rm -rf userver-web

echo "=== uServer Uninstall is COMPLETE =="
