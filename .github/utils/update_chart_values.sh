#!/bin/bash

set -e

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -t, --type                Update chart type
                                1) commit
                                2) release
    -cd, --chart-dir          Specify all charts dir (e.g. addons|addons-cluster)
    -bv, --base-values        Base values file path for update (e.g. commit-values.yaml or release-values.yaml)
    -uc, --update-chart       Specify update charts dir (e.g. addons/mysql|addons/postgresql)
    -rn, --ref-name           Ref name for update chart (commit id or branch name)
EOF
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
            ;;
            -t|--type)
                if [[ -n "${2:-}" ]]; then
                    TYPE="$2"
                    shift
                fi
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
            -uc|--update-chart)
                if [[ -n "${2:-}" ]]; then
                    UPDATE_DIR="$2"
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
    if [[ -z "${update_values_file}" ]]; then
        return
    fi
    echo "Updating values ${TYPE} info $update_values_file"
    case $TYPE in
        commit)
            if [[ -z "${REF_NAME}" ]]; then
                REF_NAME="$(git rev-parse HEAD)"
            fi

            if [[ "$UNAME" == "Darwin" ]]; then
                sed -i '' "s/^  commitTime:.*/  commitTime: \"${CURRENT_TIME}\"/" "${update_values_file}"
                sed -i '' "s/^  commitId:.*/  commitId: \"${REF_NAME}\"/" "${update_values_file}"
            else
                sed -i "s/^  commitTime:.*/  commitTime: \"${CURRENT_TIME}\"/" "${update_values_file}"
                sed -i "s/^  commitId:.*/  commitId: \"${REF_NAME}\"/" "${update_values_file}"
            fi
        ;;
        release)
            if [[ -z "${REF_NAME}" ]]; then
                REF_NAME="$(git rev-parse --abbrev-ref HEAD)"
            fi

            if [[ "$UNAME" == "Darwin" ]]; then
                sed -i '' "s/^  releaseTime:.*/  releaseTime: \"${CURRENT_TIME}\"/" "${update_values_file}"
                sed -i '' "s/^  releaseBranch:.*/  releaseBranch: \"${REF_NAME}\"/" "${update_values_file}"
            else
                sed -i "s/^  releaseTime:.*/  releaseTime: \"${CURRENT_TIME}\"/" "${update_values_file}"
                sed -i "s/^  releaseBranch:.*/  releaseBranch: \"${REF_NAME}\"/" "${update_values_file}"
            fi
        ;;
    esac
}

append_values_file() {
    append_values_file=${1:-""}
    echo "Appending ${TYPE} info to $append_values_file"
    echo "
" >> "$append_values_file"
    cat "$BASE_VALUES" >> "$append_values_file"
}

update_chart_values_file() {
    update_chart_values_file=${1:-""}
    update_flag=""
    case $TYPE in
        commit)
            update_flag=$(grep 'commitInfo:' ${update_chart_values_file} || true)
        ;;
        release)
            update_flag=$(grep 'releaseInfo:' ${update_chart_values_file} || true)
        ;;
    esac

    if [[ -n "${update_flag}" ]]; then
        update_values_file "${update_chart_values_file}"
    else
        append_values_file "${update_chart_values_file}"
    fi
}

update_chart_values() {
    # UPDATE_DIR takes precedence over CHART_DIR
    UPDATE_CHART_DIR="${CHART_DIR}"
    if [[ -n "${UPDATE_DIR}"  ]]; then
        UPDATE_CHART_DIR="${UPDATE_DIR}"
    fi

    for update_chart in $(echo "${UPDATE_CHART_DIR}" | sed 's/|/ /g' ); do
        echo "find ${update_chart} values.yaml"
        find "$update_chart" -type f -name 'values.yaml' | while read -r values_file; do
            update_chart_values_file "${values_file}"
        done
    done

    echo "update all charts values file ${TYPE} info done"
}

main() {
    local TYPE=""
    local BASE_VALUES=""
    local CHART_DIR=""
    local UPDATE_DIR=""
    local REF_NAME=""
    local CURRENT_TIME="$(date -u '+%Y-%m-%d %H:%M:%S')"
    local UNAME="$(uname -s)"

    parse_command_line "$@"

    if [[ -z "${TYPE}" || -z "${BASE_VALUES}" || (-z "${CHART_DIR}" && -z "${UPDATE_DIR}") ]]; then
        echo "Missing required arguments"
        return
    fi
    
    if [[ "${TYPE}" != "commit" && "${TYPE}" != "release" ]]; then
        echo "Invalid type ${TYPE}"
        return
    fi
    

    if [[ ! -f "$BASE_VALUES" ]]; then
        echo "$BASE_VALUES file not found."
        return
    fi

    update_values_file "${BASE_VALUES}"

    update_chart_values
}

main "$@"
