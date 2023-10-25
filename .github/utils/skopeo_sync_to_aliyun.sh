#!/usr/bin/env bash

DOCKER_USERNAME=$1
DOCKER_PASSWORD=$2
ALIYUN_USERNAME=$3
ALIYUN_PASSWORD=$4
FILE_NAME=$5
REGISTRY=$6

if [[ -z "$REGISTRY" ]]; then
    REGISTRY=docker.io
fi

while read -r image
do
    skopeo_msg="skopeo sync $REGISTRY/$image to registry.cn-hangzhou.aliyuncs.com/apecloud"
    echo "$skopeo_msg"
    skopeo_flag=0
    for i in {1..10}; do
        ret_msg=$(skopeo sync --all \
            --src-username "$DOCKER_USERNAME" \
            --src-password "$DOCKER_PASSWORD" \
            --dest-username "$ALIYUN_USERNAME" \
            --dest-password "$ALIYUN_PASSWORD" \
            --src docker \
            --dest docker \
            $REGISTRY/$image \
            registry.cn-hangzhou.aliyuncs.com/apecloud)
        echo "return message:$ret_msg"
        if [[ "$ret_msg" == *"Storing list signatures"* || "$ret_msg" == *"Skipping"* ]]; then
            echo "$(tput -T xterm setaf 2)$skopeo_msg success$(tput -T xterm sgr0)"
            skopeo_flag=1
            break
        fi
        sleep 1
    done
    if [[ $skopeo_flag -eq 0 ]]; then
        echo "$(tput -T xterm setaf 1)$skopeo_msg error$(tput -T xterm sgr0)"
        exit 1
    fi
done < $FILE_NAME
