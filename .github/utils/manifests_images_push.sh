#!/bin/bash
MANIFESTS_FILE=${1:-"deploy-manifests.yaml"}
VALUES_FILE=${2:-"deploy-values.yaml"}
DEST_REGISTRY=${3:-""}
DEST_USERNAME=${4:-""}
DEST_PASSWORD=${5:-""}
TLS_VERIFY=false


skopeo_sync() {
    image_tmp=$1
    image_namespace=${image_tmp%/*}
    skopeo_msg="skopeo sync $SRC_REGISTRY/$image_tmp to $DEST_REGISTRY/$image_tmp"
    echo "$skopeo_msg"
    skopeo_flag=0
    ret_msg=""
    for i in {1..3}; do
        ret_msg=$(skopeo sync --all --dest-username "$DEST_USERNAME" --dest-password "$DEST_PASSWORD" \
            --src docker --dest docker --src-tls-verify=${TLS_VERIFY} --dest-tls-verify=${TLS_VERIFY} \
            ${SRC_REGISTRY}/${image_tmp} ${DEST_REGISTRY}/${image_namespace})
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
    fi
}

skopeo_copy() {
    image_tmp=$1
    skopeo_msg="skopeo copy $SRC_REGISTRY/$image_tmp to $DEST_REGISTRY/$image_tmp"
    echo "$skopeo_msg"
    skopeo_flag=0
    ret_msg=""
    for i in {1..3}; do
        ret_msg=$( skopeo copy --all --dest-username "$DEST_USERNAME" --dest-password "$DEST_PASSWORD" \
            --src-tls-verify=${TLS_VERIFY} --dest-tls-verify=${TLS_VERIFY}  \
            "docker://${SRC_REGISTRY}/${image_tmp}" "docker://${DEST_REGISTRY}/${image_tmp}")
        if [[ "$ret_msg" == *"Storing list signatures"* || "$ret_msg" == *"Skipping"* ]]; then
            echo "$(tput -T xterm setaf 2)$skopeo_msg success$(tput -T xterm sgr0)"
            skopeo_flag=1
            break
        fi
        sleep 1
    done
    if [[ $skopeo_flag -eq 0 ]]; then
        echo "$(tput -T xterm setaf 1)$skopeo_msg error$(tput -T xterm sgr0)"
    fi
}

push_chart_images() {
    for image in $(echo "$chart_images"); do
        image_digest=""
        for i in {1..3}; do
            image_digest=$(skopeo inspect "docker://${SRC_REGISTRY}/${image}" --tls-verify=${TLS_VERIFY} | (grep "Digest" || true))
            ret_msg=$?
            if [[ $ret_msg -eq 0 ]]; then
                break
            fi
            sleep 1
        done
        if [[ -z "$image_digest" ]]; then
            skopeo_copy $image
        else
            skopeo_sync $image
        fi
    done
}

main() {
    local SRC_REGISTRY=""
    if [[ ! -f "${MANIFESTS_FILE}" || ! -f "${VALUES_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
        return
    fi

    if [[ -z "${DEST_REGISTRY}" || -z "${DEST_PASSWORD}" || -z "${DEST_USERNAME}" ]]; then
        echo "$(tput -T xterm setaf 1)Image destination registry or credential is empty!$(tput -T xterm sgr0)"
        return
    fi

    skopeo login --username ${DEST_USERNAME} --password "${DEST_PASSWORD}" "${DEST_REGISTRY}" --tls-verify=${TLS_VERIFY}

    charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
    SRC_REGISTRY=$(yq e ".registry"  ${VALUES_FILE})
    for chart_name in $(echo "$charts_name"); do
        chart_enable=$(yq e ".${chart_name}.enable" ${VALUES_FILE})
        if [[ "${chart_enable}" == "false" ]]; then
            echo "$(tput -T xterm setaf 3)skip push ${chart_name} images$(tput -T xterm sgr0)"
            continue
        fi

        chart_images=$(yq e "."${chart_name}"[0].images[]"  ${MANIFESTS_FILE})
        push_chart_images "$chart_images" &
    done
    wait
    echo "
      Push images done!
    "
}

main "$@"
