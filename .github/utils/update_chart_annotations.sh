#!/bin/bash

set -e

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -cd, --chart-dir          Update charts dir (e.g. addons|addons-cluster)
    -bc, --base-chart         Base chart yaml file path for update
    -bn, --branch-name        Branch name for update chart 
EOF
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
            ;;
            -bc|--base-chart)
                if [[ -n "${2:-}" ]]; then
                    BASE_CHART="$2"
                    shift
                fi
            ;;
            -cd|--chart-dir)
                if [[ -n "${2:-}" ]]; then
                    CHART_DIR="$2"
                    shift
                fi
            ;;
            -bn|--branch-name)
                if [[ -n "${2:-}" ]]; then
                    BRANCH_NAME="$2"
                    shift
                fi
            ;;
            *)
                break
            ;;
        esac

        shift
    done
}

update_chart_file() {
    update_chart_file=${1:-""}
    update_commit_id=${2:-""}
    update_commit_time=${3:-""}
    if [[ -z "${update_chart_file}" ]]; then
        return
    fi
    echo "Updating chart annotations info $update_chart_file"

    if [[ -z "${CURRENT_TIME}" ]]; then
        export TZ='Asia/Shanghai'
        CURRENT_TIME="$(date '+%Y-%m-%d %H:%M:%S %z')"
    fi

    if [[ -z "${BRANCH_NAME}" ]]; then
        BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)"
    fi

    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  addon.kubeblocks.io\/commitid:.*/  addon.kubeblocks.io\/commitid: \"${update_commit_id}\"/" "${update_chart_file}"
        sed -i '' "s/^  addon.kubeblocks.io\/committime:.*/  addon.kubeblocks.io\/committime: \"${update_commit_time}\"/" "${update_chart_file}"
        sed -i '' "s/^  addon.kubeblocks.io\/releasetime:.*/  addon.kubeblocks.io\/releasetime: \"${CURRENT_TIME}\"/" "${update_chart_file}"
        sed -i '' "s/^  addon.kubeblocks.io\/release-branch:.*/  addon.kubeblocks.io\/release-branch: \"${BRANCH_NAME}\"/" "${update_chart_file}"
    else
        sed -i "s/^  addon.kubeblocks.io\/commitid:.*/  addon.kubeblocks.io\/commitid: \"${update_commit_id}\"/" "${update_chart_file}"
        sed -i "s/^  addon.kubeblocks.io\/committime:.*/  addon.kubeblocks.io\/committime: \"${update_commit_time}\"/" "${update_chart_file}"
        sed -i "s/^  addon.kubeblocks.io\/releasetime:.*/  addon.kubeblocks.io\/releasetime: \"${CURRENT_TIME}\"/" "${update_chart_file}"
        sed -i "s/^  addon.kubeblocks.io\/release-branch:.*/  addon.kubeblocks.io\/release-branch: \"${BRANCH_NAME}\"/" "${update_chart_file}"
    fi
}

add_chart_file() {
    add_chart_file=${1:-""}
    release_branch_flag=$(grep 'addon.kubeblocks.io\/release-branch:' ${add_chart_file} || true)
    release_time_flag=$(grep 'addon.kubeblocks.io\/releasetime:' ${add_chart_file} || true)
    commit_time_flag=$(grep 'addon.kubeblocks.io\/committime:' ${add_chart_file} || true)
    commit_id_flag=$(grep 'addon.kubeblocks.io\/commitid:' ${add_chart_file} || true)
    if [[ "$UNAME" == "Darwin" ]]; then
        if [[ -z "${release_branch_flag}" ]]; then
            sed -i '' "s/^annotations:/annotations:\n  addon.kubeblocks.io\/release-branch: ""/" $add_chart_file
        fi

        if [[ -z "${release_time_flag}" ]]; then
            sed -i '' "s/^annotations:/annotations:\n  addon.kubeblocks.io\/releasetime: ""/" $add_chart_file
        fi

        if [[ -z "${commit_time_flag}" ]]; then
            sed -i '' "s/^annotations:/annotations:\n  addon.kubeblocks.io\/committime: ""/" $add_chart_file
        fi

        if [[ -z "${commit_id_flag}" ]]; then
            sed -i '' "s/^annotations:/annotations:\n  addon.kubeblocks.io\/commitid: ""/" $add_chart_file
        fi
    else
        if [[ -z "${release_branch_flag}" ]]; then
            sed -i "s/^annotations:/annotations:\n  addon.kubeblocks.io\/release-branch: ""/" $add_chart_file
        fi

        if [[ -z "${release_time_flag}" ]]; then
            sed -i "s/^annotations:/annotations:\n  addon.kubeblocks.io\/releasetime: ""/" $add_chart_file
        fi

        if [[ -z "${commit_time_flag}" ]]; then
            sed -i "s/^annotations:/annotations:\n  addon.kubeblocks.io\/committime: ""/" $add_chart_file
        fi

        if [[ -z "${commit_id_flag}" ]]; then
            sed -i "s/^annotations:/annotations:\n  addon.kubeblocks.io\/commitid: ""/" $add_chart_file
        fi
    fi
}

append_chart_file() {
    append_chart_file=${1:-""}
    echo "Appending annotations info to $append_chart_file"
    echo "
" >> "$append_chart_file"
    cat "$BASE_CHART" >> "$append_chart_file"
}

update_chart_yaml() {
    update_chart_yaml=${1:-""}
    update_chart_commit_id=${2:-""}
    update_chart_commit_time=${3:-""}

    update_flag=$(grep 'annotations:' ${update_chart_yaml} || true)
    if [[ -z "${update_flag}" ]]; then
        append_chart_file "${update_chart_yaml}"
    else    
        add_chart_file "${update_chart_yaml}"
    fi
    update_chart_file "${update_chart_yaml}" "${update_chart_commit_id}" "${update_chart_commit_time}"
}

update_charts_yaml() {
    for update_chart in $(echo "${CHART_DIR}" | sed 's/|/ /g' ); do
        echo "find ${update_chart} Chart.yaml"
        find "$update_chart" -type f -name 'Chart.yaml' | while read -r chart_file; do
            update_chart_dir_tmp="${chart_file%/*}"
            chart_log_info=$(git log -n 1 --pretty="format:%H %ad" --date="iso8601" -- "${update_chart_dir_tmp}")
            IFS=' ' read -r commit_id commit_time <<< "$chart_log_info"
            update_chart_yaml "${chart_file}" "${commit_id}" "${commit_time}"
        done
    done

    echo "update all charts yaml file release info done"
}

main() {
    local BASE_CHART=""
    local CHART_DIR=""
    local BRANCH_NAME=""
    local CURRENT_TIME=""
    local UNAME="$(uname -s)"

    parse_command_line "$@"

    if [[ -z "${CHART_DIR}" ]]; then
        echo "Chart dir is empty."
        return
    fi

    if [[ -z "${BASE_CHART}" || ! -f "$BASE_CHART" ]]; then
        echo "$BASE_CHART file not found."
        return
    fi

    if [[ "${BRANCH_NAME}" == *"/"* ]]; then
        BRANCH_NAME=${BRANCH_NAME//\//\\/}
    fi

    update_charts_yaml
}

main "$@"
