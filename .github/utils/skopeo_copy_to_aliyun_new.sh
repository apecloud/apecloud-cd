#!/usr/bin/env bash

ALIYUN_USERNAME=$1
ALIYUN_PASSWORD=$2
FILE_NAME=$3
REGISTRY=$4

if [[ -z "$REGISTRY" ]]; then
    REGISTRY=docker.io
fi

while read -r image
do
    image_name=${image##*/}
    skopeo_msg="skopeo copy $REGISTRY/$image to infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/$image_name"
    echo "$skopeo_msg"
    skopeo_flag=0
    for i in {1..10}; do
        ret_msg=$( skopeo copy --all \
            --dest-username "$ALIYUN_USERNAME" \
            --dest-password "$ALIYUN_PASSWORD" \
            docker://$REGISTRY/$image \
            docker://infracreate-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/$image_name)
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
