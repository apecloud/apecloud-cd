#!/bin/bash

set -e

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -cd, --chart-dir          Update charts dir (e.g. addons|addons-cluster)
    -bv, --base-values        Base chart values file path
    -rn, --ref-name           The release chart ref name
EOF
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
            ;;
            -bv|--base-values)
                if [[ -n "${2:-}" ]]; then
                    BASE_VALUES="$2"
                    shift
                fi
            ;;
            -cd|--chart-dir)
                if [[ -n "${2:-}" ]]; then
                    CHART_DIR="$2"
                    shift
                fi
            ;;
            -rn|--ref-name)
                if [[ -n "${2:-}" ]]; then
                    REF_NAME="$2"
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

update_values_file() {
    update_values_file=${1:-""}
    update_commit_id=${2:-""}
    update_commit_time=${3:-""}
    if [[ -z "${update_values_file}" ]]; then
        return
    fi
    echo "Updating values release info $update_values_file"

    if [[ -z "${CURRENT_TIME}" ]]; then
        export TZ='Asia/Shanghai'
        CURRENT_TIME="$(date '+%Y-%m-%d %H:%M:%S %z')"
    fi

    if [[ -z "${REF_NAME}" ]]; then
        REF_NAME="$(git rev-parse --abbrev-ref HEAD)"
    fi

    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  releaseTime:.*/  releaseTime: \"${CURRENT_TIME}\"/" "${update_values_file}"
        sed -i '' "s/^  releaseBranch:.*/  releaseBranch: \"${REF_NAME}\"/" "${update_values_file}"
        sed -i '' "s/^  commitTime:.*/  commitTime: \"${update_commit_time}\"/" "${update_values_file}"
        sed -i '' "s/^  commitId:.*/  commitId: \"${update_commit_id}\"/" "${update_values_file}"
    else
        sed -i "s/^  releaseTime:.*/  releaseTime: \"${CURRENT_TIME}\"/" "${update_values_file}"
        sed -i "s/^  releaseBranch:.*/  releaseBranch: \"${REF_NAME}\"/" "${update_values_file}"
        sed -i "s/^  commitTime:.*/  commitTime: \"${update_commit_time}\"/" "${update_values_file}"
        sed -i "s/^  commitId:.*/  commitId: \"${update_commit_id}\"/" "${update_values_file}"
    fi
}

append_values_file() {
    append_values_file=${1:-""}
    echo "Appending release info to $append_values_file"
    echo "
" >> "$append_values_file"
    cat "$BASE_VALUES" >> "$append_values_file"
}

update_chart_values_file() {
    update_chart_values_file=${1:-""}
    update_chart_commit_id=${2:-""}
    update_chart_commit_time=${3:-""}

    update_flag=$(grep 'releaseInfo:' ${update_chart_values_file} || true)

    if [[ -z "${update_flag}" ]]; then
        append_values_file "${update_chart_values_file}"
    fi
    update_values_file "${update_chart_values_file}" "${update_chart_commit_id}" "${update_chart_commit_time}"
}

update_chart_values() {
    for update_chart in $(echo "${CHART_DIR}" | sed 's/|/ /g' ); do
        echo "find ${update_chart} values.yaml"
        find "$update_chart" -type f -name 'values.yaml' | while read -r values_file; do
            update_chart_dir_tmp="${values_file%/*}"
            chart_log_info=$(git log -n 1 --pretty="format:%H %ad" --date="iso8601" -- "${update_chart_dir_tmp}")
            IFS=' ' read -r commit_id commit_time <<< "$chart_log_info"
            update_chart_values_file "${values_file}" "${commit_id}" "${commit_time}"
        done
    done

    echo "update all charts values file release info done"
}

main() {
    local BASE_VALUES=""
    local CHART_DIR=""
    local REF_NAME=""
    local CURRENT_TIME=""
    local UNAME="$(uname -s)"

    parse_command_line "$@"

    if [[ -z "${CHART_DIR}" ]]; then
        echo "Chart dir is empty."
        return
    fi

    if [[ -z "${BASE_VALUES}" || ! -f "$BASE_VALUES" ]]; then
        echo "$BASE_VALUES file not found."
        return
    fi

    if [[ "${REF_NAME}" == *"/"* ]]; then
        REF_NAME=${REF_NAME//\//\\/}
    fi

    update_chart_values
}

main "$@"
