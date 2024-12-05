#!/bin/bash

set -e

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help                Display help
    -cd, --chart-dir          Update charts dir (e.g. addons|addons-cluster)
    -bn, --base-notes         Base chart notes file path
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
            -bn|--base-notes)
                if [[ -n "${2:-}" ]]; then
                    BASE_NOTES="$2"
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

update_chart_notes_file() {
    update_chart_notes=${1:-""}
    update_commit_id=${2:-""}
    update_commit_time=${3:-""}
    if [[ -z "${update_chart_notes}" ]]; then
        return
    fi
    echo "Updating chart notes release info $update_chart_notes"

    if [[ -z "${CURRENT_TIME}" ]]; then
        export TZ='Asia/Shanghai'
        CURRENT_TIME="$(date '+%Y-%m-%d %H:%M:%S %z')"
    fi

    if [[ -z "${REF_NAME}" ]]; then
        REF_NAME="$(git rev-parse --abbrev-ref HEAD)"
    fi

    if [[ "$UNAME" == "Darwin" ]]; then
        sed -i '' "s/^  Commit ID:.*/  Commit ID: \"${update_commit_id}\"/" "${update_chart_notes}"
        sed -i '' "s/^  Commit Time:.*/  Commit Time: \"${update_commit_time}\"/" "${update_chart_notes}"
        sed -i '' "s/^  Release Time:.*/  Release Time:  \"${CURRENT_TIME}\"/" "${update_chart_notes}"
        sed -i '' "s/^  Release Branch:.*/  Release Branch: \"${REF_NAME}\"/" "${update_chart_notes}"
    else
        sed -i "s/^  Commit ID:.*/  Commit ID: \"${update_commit_id}\"/" "${update_chart_notes}"
        sed -i "s/^  Commit Time:.*/  Commit Time: \"${update_commit_time}\"/" "${update_chart_notes}"
        sed -i "s/^  Release Time: .*/  Release Time:  \"${CURRENT_TIME}\"/" "${update_chart_notes}"
        sed -i "s/^  Release Branch:.*/  Release Branch: \"${REF_NAME}\"/" "${update_chart_notes}"
    fi
}

append_chart_notes() {
    append_chart_notes=${1:-""}
    echo "Appending release info to $append_chart_notes"
    notes_info=$(cat "$append_chart_notes")
    if [[ -n "${notes_info}" ]]; then
        echo "
" >> "$append_chart_notes"
    fi
    cat "$BASE_NOTES" >> "$append_chart_notes"
}

update_chart_notes() {
    update_chart_notes=${1:-""}
    update_chart_commit_id=${2:-""}
    update_chart_commit_time=${3:-""}

    update_flag=$(grep 'Release Information:' ${update_chart_notes} || true)
    if [[ -z "${update_flag}" ]]; then
        append_chart_notes "${update_chart_notes}"
    fi
    update_chart_notes_file "${update_chart_notes}" "${update_chart_commit_id}" "${update_chart_commit_time}"
}

update_charts_notes() {
    for update_charts_dir in $(echo "${CHART_DIR}" | sed 's/|/ /g' ); do
        echo "find ${update_charts_dir} NOTES.txt"
        for update_chart_dir in $(ls ${update_charts_dir}); do
            update_chart_dir_tmp="${update_charts_dir}/${update_chart_dir}"
            update_chart_dir="${update_chart_dir_tmp}/templates"
            if [[ ! -d ${update_chart_dir} ]]; then
                echo "not found ${update_chart_dir} dir"
                continue
            fi

            chart_notes_path="${update_chart_dir}/NOTES.txt"
            if [[ ! -f "$chart_notes_path" ]]; then
                echo "create chart notes $chart_notes_path"
                touch ${chart_notes_path}
            fi
            chart_log_info=$(git log -n 1 --pretty="format:%H %ad" --date="iso8601" -- "${update_chart_dir_tmp}")
            IFS=' ' read -r commit_id commit_time <<< "$chart_log_info"
            update_chart_notes "${chart_notes_path}" "${commit_id}" "${commit_time}"
        done
    done

    echo "update all charts NOTES.txt file release info done"
}

main() {
    local BASE_NOTES=""
    local CHART_DIR=""
    local REF_NAME=""
    local CURRENT_TIME=""
    local UNAME="$(uname -s)"

    parse_command_line "$@"

    if [[ -z "${CHART_DIR}" ]]; then
        echo "Chart dir is empty."
        return
    fi

    if [[ -z "${BASE_NOTES}" || ! -f "$BASE_NOTES" ]]; then
        echo "$BASE_NOTES file not found."
        return
    fi

    if [[ "${REF_NAME}" == *"/"* ]]; then
        REF_NAME=${REF_NAME//\//\\/}
    fi

    update_charts_notes
}

main "$@"
