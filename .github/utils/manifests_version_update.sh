#!/bin/bash
MANIFESTS_FILE=${1:-""}
RELEASE_VERSION=${2:-""}
CLOUD_SUFFIX="${3:-${CLOUD_SUFFIX:-false}}"

# update_addon_chart_version() {
#     if [[ ! -f "${MANIFESTS_FILE}" ]]; then
#         echo "$(tput -T xterm setaf 3)::warning title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
#         return
#     fi
#
#     charts_name=$(yq e "to_entries|map(.key)|.[]"  ${MANIFESTS_FILE})
#     for chart_name in $(echo "${charts_name}"); do
#         is_addon=$(yq e "."${chart_name}"[0].isAddon" ${MANIFESTS_FILE})
#         if [[ "$is_addon" == "false" && "${chart_name}" != "minio" ]]; then
#             continue
#         fi
#         chart_version=$(yq e "."${chart_name}"[0].version"  ${MANIFESTS_FILE})
#         is_enterprise=$(yq e "."${chart_name}"[0].isEnterprise"  ${MANIFESTS_FILE})
#
#         # update addon isEnterprise
#         if [[ "$is_addon" == "true" && -d "${INSTALLER_ADDON_DIR}"  ]]; then
#             for installer_addon_chart in $(ls ${INSTALLER_ADDON_DIR}); do
#                 installer_addon_chart_dir="${INSTALLER_ADDON_DIR}/${installer_addon_chart}"
#                 installer_addon_enterprise=$(yq e ".isEnterprise"  ${installer_addon_chart_dir})
#                 installer_addon_name=$(yq e ".name"  ${installer_addon_chart_dir})
#                 if [[ "$installer_addon_name" == "$chart_name" && "$is_enterprise" != "${installer_addon_enterprise}" ]]; then
#                     echo "set ${installer_addon_name} isEnterprise to ${installer_addon_enterprise}"
#                     is_enterprise="${installer_addon_enterprise}"
#                     yq e -i ".${chart_name}[0].isEnterprise=${installer_addon_enterprise}" "${MANIFESTS_FILE}"
#                 fi
#             done
#         fi
#
#         if [[ "$is_enterprise" == "true" ]]; then
#             addon_chart_file="${APECLOUD_ADDON_DIR}/${chart_name}/Chart.yaml"
#         else
#             addon_chart_file="${KUBEBLOCKS_ADDON_DIR}/${chart_name}/Chart.yaml"
#         fi
#
#         if [[ -f "${addon_chart_file}" ]]; then
#             addon_chart_version=$(yq e ".version" "${addon_chart_file}")
#             if [[ "${chart_version}" != "${addon_chart_version}" ]]; then
#                 yq e -i ".${chart_name}[0].version=\"${addon_chart_version}\"" "${MANIFESTS_FILE}"
#                 chart_version="${addon_chart_version}"
#             fi
#         fi
#
#         installer_addon_chart_file="${INSTALLER_ADDON_DIR}/${chart_name}.yaml"
#         if [[ -f "${installer_addon_chart_file}" ]]; then
#             installer_addon_chart_version=$(yq e ".version" "${installer_addon_chart_file}")
#             if [[ "${chart_version}" != "${installer_addon_chart_version}" ]]; then
#                 yq e -i ".version=\"${chart_version}\"" "${installer_addon_chart_file}"
#             fi
#         fi
#     done
# }

update_kbInstaller_version() {
    kbInstaller_version="${1}"
    if [[ ! -f "${INSTALLER_CHART_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found installer chart values file:${INSTALLER_CHART_FILE} $(tput -T xterm sgr0)"
        return
    fi
    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  kbInstaller:.*/  kbInstaller: \"${kbInstaller_version}\"/" "${INSTALLER_CHART_FILE}"
    else
        sed -i "s/^  kbInstaller:.*/  kbInstaller: \"${kbInstaller_version}\"/" "${INSTALLER_CHART_FILE}"
    fi
}

update_oteld_version() {
    oteld_version="${1}"
    if [[ ! -f "${INSTALLER_CHART_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found installer chart values file:${INSTALLER_CHART_FILE} $(tput -T xterm sgr0)"
        return
    fi
    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  oteld:.*/  oteld: \"${oteld_version}\"/" "${INSTALLER_CHART_FILE}"
    else
        sed -i "s/^  oteld:.*/  oteld: \"${oteld_version}\"/" "${INSTALLER_CHART_FILE}"
    fi
}

update_addon_chart_cloud_suffix() {
    local charts_name chart_name chart_versions chart_version chart_index
    local is_addon engine_type manifests_images manifests_image image_num
    local chart_ref secure_image new_image
    charts_name=$(yq e 'to_entries|map(.key)|.[]' "${MANIFESTS_FILE}")
    for chart_name in ${charts_name}; do
        if [[ -z "${chart_name}" || "${chart_name}" == "#"* ]]; then
            continue
        fi
        chart_versions=$(yq e '[.'${chart_name}'[].version] | join("|")' ${MANIFESTS_FILE})
        chart_index=0
        for chart_version in $(echo "${chart_versions}" | sed 's/|/ /g'); do
            is_addon=$(yq e ".${chart_name}[${chart_index}].isAddon" "${MANIFESTS_FILE}")
            engine_type=$(yq e ".${chart_name}[${chart_index}].type" "${MANIFESTS_FILE}")
            if [[ "${is_addon}" != "true" || "${engine_type}" != "engine" ]]; then
                chart_index=$((chart_index + 1))
                continue
            fi
            # Build the tag from the component name and version. Do not parse the old tag.
            chart_ref="apecloud/apecloud-addon-charts:${chart_name}-${chart_version}"
            secure_image="apecloud/apecloud-addon-charts:${chart_name}-secure-${chart_version}"
            new_image="${chart_ref}-${RELEASE_VERSION}"
            manifests_images=$(yq e ".${chart_name}[${chart_index}].images[]" "${MANIFESTS_FILE}")
            image_num=0
            for manifests_image in ${manifests_images}; do
                if [[ "${manifests_image}" == "null" || "${manifests_image}" == "${secure_image}" ]]; then
                    image_num=$((image_num + 1))
                    continue
                fi
                if [[ "${manifests_image}" == "${chart_ref}" || "${manifests_image}" == "${chart_ref}-"* ]]; then
                    yq e -i ".${chart_name}[${chart_index}].images[${image_num}]=\"${new_image}\"" "${MANIFESTS_FILE}"
                fi
                image_num=$((image_num + 1))
            done
            chart_index=$((chart_index + 1))
        done
    done
}

# sync_kubeblocks_cloud_addon_charts
# kubeblocks-cloud may contain addon chart images such as the metadata database
#   apecloud/apecloud-addon-charts:postgresql-1.0.8-v2.3.0-alpha.231
# For each of them, parse the "<chart>-<major>.<minor>." prefix from its tag,
# then copy the matching image (same prefix) from the corresponding engine
# section (e.g. .postgresql) so cloud images stay identical to engine images
# after the engine images are updated.
sync_kubeblocks_cloud_addon_charts() {
    local cloud_images cloud_image tag chart_name prefix pattern engine_image

    cloud_images=$(yq e '.kubeblocks-cloud[].images[] | select(. == "apecloud/apecloud-addon-charts:*")' "${MANIFESTS_FILE}" 2>/dev/null)
    if [[ -z "${cloud_images}" ]]; then
        return 0
    fi

    for cloud_image in ${cloud_images}; do
        tag="${cloud_image##*:}"
        # tag format: <chart>-<major>.<minor>.<patch>-v<release...>
        chart_name=$(echo "${tag}" | sed -nE 's/^([a-zA-Z0-9_-]+)-[0-9]+\.[0-9]+\..*/\1/p')
        prefix=$(echo "${tag}" | sed -nE 's/^([a-zA-Z0-9_-]+-[0-9]+\.[0-9]+\.).*/\1/p')
        if [[ -z "${chart_name}" || -z "${prefix}" ]]; then
            echo "$(tput -T xterm setaf 3)::warning title=Can not parse addon chart prefix from image:${cloud_image} $(tput -T xterm sgr0)"
            continue
        fi
        pattern="apecloud/apecloud-addon-charts:${prefix}*"

        engine_image=$(CHART="${chart_name}" PATTERN="${pattern}" yq e '[.[strenv(CHART)][].images[] | select(. == strenv(PATTERN))][0] // ""' "${MANIFESTS_FILE}") || return 1
        if [[ -z "${engine_image}" ]]; then
            echo "$(tput -T xterm setaf 3)::warning title=No engine image matching ${pattern} found in ${chart_name} entries $(tput -T xterm sgr0)"
            continue
        fi
        PATTERN="${pattern}" ENGINE_IMAGE="${engine_image}" yq e -i \
            '(.kubeblocks-cloud[].images[] | select(. == strenv(PATTERN))) = strenv(ENGINE_IMAGE)' "${MANIFESTS_FILE}"
    done
}

update_manifests_file_version() {
    echo "MANIFESTS_FILE:${MANIFESTS_FILE}"
    if [[ ! -f "${MANIFESTS_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found manifests file:${MANIFESTS_FILE} $(tput -T xterm sgr0)"
        return
    fi

    if [[ -z "${RELEASE_VERSION}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=release version is empty $(tput -T xterm sgr0)"
        return
    fi
    echo "RELEASE_VERSION:${RELEASE_VERSION}"
    if [[ "${RELEASE_VERSION}" != "v"* ]]; then
        RELEASE_VERSION="v${RELEASE_VERSION}"
    fi
    RELEASE_VERSION_TMP=${RELEASE_VERSION/v/}

    KUBEBLOCKS_VERSION=$(yq e ".kubeblocks[0].version" "${MANIFESTS_FILE}")

    echo "KUBEBLOCKS_VERSION:${KUBEBLOCKS_VERSION}"
    charts_name=("kubeblocks-cloud" "kb-cloud-installer")
    update_images=("openconsole" "kubeblocks-console" "apiserver" "cubetran-front" "cr4w" "kubeblocks-installer" "dms" "servicemirror" "kb-cloud-hook" "kb-cloud-docs")
    if [[ "${CLOUD_SUFFIX}" != "true" ]]; then
        update_images+=("apecloud-addon-charts")
    fi
    for chart_name in "${charts_name[@]}"; do
        if [[ "${chart_name}" == "kb-cloud-installer" ]]; then
            yq e -i ".${chart_name}[0].version=\"${RELEASE_VERSION_TMP}\"" "${MANIFESTS_FILE}"
            update_images=("kb-cloud-installer")
        else
            yq e -i ".${chart_name}[0].version=\"${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
        fi

        manifests_images=$(yq e ".${chart_name}[0].images[]" ${MANIFESTS_FILE})
        image_num=0
        update_apecloud_addon_charts=0
        for manifests_image in $(echo "${manifests_images}"); do
            for update_image in "${update_images[@]}"; do
                if [[ "${manifests_image}" == "apecloud/${update_image}:"* ]]; then
                    if [[ "${manifests_image}" == "apecloud/oteld:"* ]]; then
                        oteld_version="${manifests_image#*:}"
                        update_oteld_version "${oteld_version}"
                    fi

                    if [[ "${manifests_image}" == "apecloud/kubeblocks-installer:"* ]]; then
                        kbInstaller_version="${RELEASE_VERSION}-offline"
                        if [[ "${RELEASE_VERSION}" == "v1.1."* || "${RELEASE_VERSION}" == "v1.0."* || "${RELEASE_VERSION}" == "v0.30."* || "${RELEASE_VERSION}" == "v0.28."* ]]; then
                            kbInstaller_version="${RELEASE_VERSION}-${KUBEBLOCKS_VERSION}-offline"
                        fi

                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${kbInstaller_version}\"" "${MANIFESTS_FILE}"
                        update_kbInstaller_version "${kbInstaller_version}"
                        update_air_gap_config_version "${RELEASE_VERSION}"
                    elif [[ "${manifests_image}" == "apecloud/dms:"* && -n "${DMS_VERSION}" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${DMS_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/servicemirror:"* && -n "${SERVICEMIRROR_VERSION}" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${SERVICEMIRROR_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/openconsole:"* && "${manifests_image}" != "apecloud/openconsole:"*"-console" && "${manifests_image}" != "apecloud/openconsole:"*"-admin" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/openconsole:"*"-console" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-console\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/openconsole:"*"-admin" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-admin\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/kubeblocks-console:"* && "${manifests_image}" != "apecloud/kubeblocks-console:"*"-rds" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/kubeblocks-console:"*"-rds" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-rds\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/apiserver:"* && "${manifests_image}" != "apecloud/apiserver:"*"-jni" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/apiserver:"*"-jni" ]]; then
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}-jni\"" "${MANIFESTS_FILE}"
                    elif [[ "${manifests_image}" == "apecloud/apecloud-addon-charts:"* ]]; then
                        if [[ "${update_apecloud_addon_charts}" -eq 0 && "${manifests_image}" =~ ^apecloud/apecloud-addon-charts:v[0-9]+ ]]; then
                            yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                            update_apecloud_addon_charts=1
                        fi
                    else
                        yq e -i ".${chart_name}[0].images[${image_num}]=\"apecloud/${update_image}:${RELEASE_VERSION}\"" "${MANIFESTS_FILE}"
                    fi
                    break
                fi
            done
            ((image_num++))
        done
    done

    if [[ "${CLOUD_SUFFIX}" == "true" ]]; then
        update_addon_chart_cloud_suffix
    fi
    sync_kubeblocks_cloud_addon_charts || return 1

    # update_addon_chart_version

    echo "update manifests file ${MANIFESTS_FILE} done!"
}

get_dependencies_version() {
    if [[ ! -f "${CLOUD_CHART_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found cloud chart file:${CLOUD_CHART_FILE} $(tput -T xterm sgr0)"
        return
    fi
    cloud_dependencies=$(yq e '.dependencies[].name' "${CLOUD_CHART_FILE}")
    if [[ -z "${cloud_dependencies}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found cloud chart dependencies $(tput -T xterm sgr0)"
        return
    fi
    dep_num=0
    for cloud_dependency in $(echo "${cloud_dependencies}"); do
        if [[ "${cloud_dependency}" == "dms" ]]; then
            DMS_VERSION=$(yq e ".dependencies[${dep_num}].version" "${CLOUD_CHART_FILE}")
        elif [[ "${cloud_dependency}" == "servicemirror" ]]; then
            SERVICEMIRROR_VERSION=$(yq e ".dependencies[${dep_num}].version" "${CLOUD_CHART_FILE}")
        fi
        ((dep_num++))
    done
}

update_air_gap_config_version() {
    air_gap_config_version="${1}"
    if [[ ! -f "${AIR_GAP_CONFIG_FILE}" ]]; then
        echo "$(tput -T xterm setaf 3)::warning title=Not found air gap config file:${AIR_GAP_CONFIG_FILE} $(tput -T xterm sgr0)"
        return
    fi
    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^version:.*/version: \"${air_gap_config_version}\"/" "${AIR_GAP_CONFIG_FILE}"
    else
        sed -i "s/^version:.*/version: \"${air_gap_config_version}\"/" "${AIR_GAP_CONFIG_FILE}"
    fi
}

main() {
    local RELEASE_VERSION_TMP=""
    local KUBEBLOCKS_VERSION=""
    local UNAME="$(uname -s)"
    local DMS_VERSION=""
    local SERVICEMIRROR_VERSION=""
    local INSTALLER_CHART_FILE="deploy/installer/values.yaml"
    local INSTALLER_ADDON_DIR="docker/kb-installer/addons"
    local CLOUD_CHART_FILE="deploy/helm/Chart.yaml"
#     local KUBEBLOCKS_ADDON_DIR="kubeblocks-addons/addons"
#     local APECLOUD_ADDON_DIR="apecloud-addons/addons"
    local AIR_GAP_CONFIG_FILE="fountain/air-gap/config.yaml"

    get_dependencies_version
    update_manifests_file_version
}

main "$@"
