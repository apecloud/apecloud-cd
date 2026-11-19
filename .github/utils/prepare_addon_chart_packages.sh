#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

MANIFEST_ADDONS=${1:-}
REPOSITORY=${2:-}
PREBUILT_DIR=${3:-prebuilt-charts}
METADATA_FILE=${4:-.addon-chart-metadata}
ADD_ADDONS_FILTER=${5:-}

normalize_version() {
    local version=${1:-}
    echo "${version#v}"
}

chart_field() {
    local chart_path=${1:-}
    local field=${2:-}
    yq e ".${field}" "${chart_path}/Chart.yaml"
}

find_chart_dir() {
    local addon=${1:-}
    local chart_dir
    for chart_dir in "addons/${addon}" "addons/${addon}-cluster"; do
        if [[ -f "${chart_dir}/Chart.yaml" ]]; then
            echo "${chart_dir}"
            return 0
        fi
    done

    for chart_dir in addons/*; do
        if [[ ! -f "${chart_dir}/Chart.yaml" ]]; then
            continue
        fi
        chart_name=$(chart_field "${chart_dir}" name)
        if [[ "${chart_name}" == "${addon}" || "${chart_name}" == "${addon}-cluster" ]]; then
            echo "${chart_dir}"
            return 0
        fi
    done
    return 1
}

case "${REPOSITORY}" in
    apecloud/apecloud-addons)
        project_id=165897
        ;;
    apecloud/kubeblocks-addons)
        project_id=150246
        ;;
    *)
        echo "unsupported addon repository: ${REPOSITORY}" >&2
        exit 1
        ;;
esac

if [[ -z "${MANIFEST_ADDONS}" ]]; then
    exit 0
fi

mkdir -p "${PREBUILT_DIR}"
: > "${METADATA_FILE}"
: > "${PREBUILT_DIR}/.chart-names"
repo_name="addon-chart-${project_id}"
repo_url="https://jihulab.com/api/v4/projects/${project_id}/packages/helm/stable"
repo_ready=0

IFS='|' read -ra addon_specs <<< "${MANIFEST_ADDONS}"
for addon_spec in "${addon_specs[@]}"; do
    addon_name="${addon_spec%%:*}"
    addon_version_and_enterprise="${addon_spec#*:}"
    expected_version="${addon_version_and_enterprise%%:*}"
    is_enterprise="${addon_version_and_enterprise#*:}"
    has_enterprise_flag=0
    if [[ "${addon_version_and_enterprise}" == *:* ]]; then
        has_enterprise_flag=1
        if [[ "${REPOSITORY}" == "apecloud/apecloud-addons" && "${is_enterprise}" != "1" ]]; then
            continue
        fi
        if [[ "${REPOSITORY}" == "apecloud/kubeblocks-addons" && "${is_enterprise}" != "0" ]]; then
            continue
        fi
    fi
    if [[ "${REPOSITORY}" == "apecloud/kubeblocks-addons" && -n "${ADD_ADDONS_FILTER}" ]]; then
        case "|${ADD_ADDONS_FILTER}|" in
            *"|${addon_name}|"*) ;;
            *) continue ;;
        esac
    fi
    chart_dir=""
    if ! chart_dir=$(find_chart_dir "${addon_name}"); then
        if [[ "${has_enterprise_flag}" -eq 0 ]]; then
            echo "skip ${addon_name}: not found in ${REPOSITORY}"
            continue
        fi
        chart_name="${addon_name}"
        current_version=""
    else
        chart_name=$(chart_field "${chart_dir}" name)
        current_version=$(normalize_version "$(chart_field "${chart_dir}" version)")
    fi
    if [[ "${addon_spec}" != *:* ]]; then
        expected_version="${current_version}"
    else
        expected_version=$(normalize_version "${expected_version}")
    fi

    if [[ "${current_version}" == "${expected_version}" ]]; then
        printf '%s\t%s\t%s\n' "${addon_name}" "${chart_name}" "${expected_version}" >> "${METADATA_FILE}"
        continue
    fi

    if [[ "${repo_ready}" -eq 0 ]]; then
        helm repo add "${repo_name}" "${repo_url}" \
            --username "${CHART_ACCESS_USER}" \
            --password "${CHART_ACCESS_TOKEN}" \
            --force-update
        helm repo update "${repo_name}"
        repo_ready=1
    fi

    package_path=""
    for attempt in $(seq 1 10); do
        download_dir=$(mktemp -d)
        if helm pull "${repo_name}/${chart_name}" \
            --version "${expected_version}" \
            --destination "${download_dir}"; then
            package_path=$(find "${download_dir}" -maxdepth 1 -type f -name '*.tgz' -print -quit)
        fi
        if [[ -n "${package_path}" ]]; then
            expected_package="${chart_name}-${expected_version}.tgz"
            if [[ "$(basename "${package_path}")" != "${expected_package}" ]]; then
                echo "downloaded package $(basename "${package_path}") does not match ${expected_package}" >&2
                rm -rf "${download_dir}"
                exit 1
            fi
            mv "${package_path}" "${PREBUILT_DIR}/"
            printf '%s\n' "${chart_name}" >> "${PREBUILT_DIR}/.chart-names"
            if [[ -n "${chart_dir}" ]]; then
                mv "${chart_dir}" "${PREBUILT_DIR}/.source-$(basename "${chart_dir}")"
            fi
            rm -rf "${download_dir}"
            break
        fi
        rm -rf "${download_dir}"
        if [[ "${attempt}" -lt 10 ]]; then
            sleep 1
        fi
    done

    if [[ -z "${package_path}" ]]; then
        echo "failed to download ${chart_name}:${expected_version} after 10 retries" >&2
        exit 1
    fi
    printf '%s\t%s\t%s\n' "${addon_name}" "${chart_name}" "${expected_version}" >> "${METADATA_FILE}"
done
