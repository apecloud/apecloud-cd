#!/bin/bash

MANIFESTS_FILE=${1:-"deploy-manifests.yaml"}
CLOUD_TAG=${2:-""}


get_scan_images() {
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
        return
    fi
    SCAN_ADDONS="ape-local-csi-driver|kubebench|minio|postgresql"
    charts_name=$(yq e "to_entries|map(.key)|.[]"  "${MANIFESTS_FILE}")
    for chart_name in $(echo "$charts_name"); do
        scan_addon_flag=0
        for scan_addon in $(echo "${SCAN_ADDONS}" | sed 's/|/ /g'); do
            if [[ "${chart_name}" == "${scan_addon}" ]]; then
                scan_addon_flag=1
                break
            fi
        done
        is_addon=$(yq e "."${chart_name}"[0].isAddon" ${MANIFESTS_FILE})
        if [[ "$is_addon" == "true" && $scan_addon_flag -eq 0 ]]; then
            continue
        fi
        SCAN_IMAGES=""
        chart_images=$(yq e "."${chart_name}"[].images[]"  "${MANIFESTS_FILE}" | sort -u)
        for image_tmp in $(echo "${chart_images}"); do
            # skip apecloud/apecloud-addon-charts
            if [[ "${image_tmp}" == "apecloud/apecloud-addon-charts:"* ]]; then
                continue
            fi
            image_tmp="${SCAN_REGISTRY}/${image_tmp}"
            scan_image_exists=0
            for scan_image_tmp in $(echo "${ALL_SCAN_IMAGES}" | sed 's/|/ /g'); do
                if [[ "${scan_image_tmp}" == "${image_tmp}" ]]; then
                    scan_image_exists=1
                    break
                fi
            done
            # skip exists images
            if [[ ${scan_image_exists} -eq 1 ]]; then
                continue
            fi
            # add image
            if [[ -z "${SCAN_IMAGES}" ]]; then
                SCAN_IMAGES="${image_tmp}"
            else
                SCAN_IMAGES="${SCAN_IMAGES}|${image_tmp}"
            fi
            # add image to all
            ALL_SCAN_IMAGES="${ALL_SCAN_IMAGES}|${image_tmp}"
        done
        echo "[${chart_name}]${SCAN_IMAGES}"
        echo "${chart_name}-images=${SCAN_IMAGES}" >> $GITHUB_OUTPUT
        echo ""
    done
}

main() {
    local SCAN_REGISTRY="docker.io"
    local ALL_SCAN_IMAGES="${SCAN_REGISTRY}/apecloud/apecloud-addon-charts:${CLOUD_TAG}"
    local SCAN_IMAGES=""

    get_scan_images
}

main "$@"
