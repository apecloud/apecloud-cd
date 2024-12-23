#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_RELEASER_VERSION=v1.6.1

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help               Display help
    -v, --version            The chart-releaser version to use (default: $DEFAULT_CHART_RELEASER_VERSION)"
    -o, --owner              The repo owner
    -r, --repo               The repo name
    -n, --install-dir        The Path to install the cr tool
EOF
}

check_latest_commit() {
    retry_times=0
    for i in {1..5}; do
        # Get the latest commit hash of the remote branch gh-pages
        remote_commit=$(git ls-remote origin refs/heads/gh-pages | awk '{print $1}')
        # Get the latest commit hash of the local current branch
        local_commit=$(git rev-parse HEAD)
        echo "remote_commit: $remote_commit"
        echo "local_commit: $local_commit"
        # Compare the remote and local commit hashes
        if [[ "$remote_commit" == "$local_commit" ]]; then
            echo "The local branch is already up-to-date, no update needed."
            if [ $retry_times -eq 1 ]; then
                break
            fi
            retry_times=1
        else
            echo "Detected new commits on the remote branch, updating the local branch..."
            # Try to pull the latest changes from the remote branch
            git pull origin gh-pages
            if [ $? -eq 0 ]; then
                echo "The local branch has been successfully updated to the latest commit."
            fi
            retry_times=0
        fi
        sleep 1
    done
}

update_index() {
    local args=(-o "$owner" -r "$repo" -t $CR_TOKEN --push)
    check_latest_commit
    echo 'Updating charts repo index...'
    cr index "${args[@]}"
}

main() {
    local version="$DEFAULT_CHART_RELEASER_VERSION"
    local owner=""
    local repo=""
    local install_dir=""

    parse_command_line "$@"

    : "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"

    echo 'Adding install_dir to PATH...'
    export PATH="$install_dir:$PATH"

    update_index
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -v|--version)
                if [[ -n "${2:-}" ]]; then
                    version="$2"
                    shift
                fi
                ;;
            -o|--owner)
                if [[ -n "${2:-}" ]]; then
                    owner="$2"
                    shift
                fi
                ;;
            -r|--repo)
                if [[ -n "${2:-}" ]]; then
                    repo="$2"
                    shift
                fi
                ;;
            -n|--install-dir)
                if [[ -n "${2:-}" ]]; then
                    install_dir="$2"
                    shift
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done

    if [[ -z "$install_dir" ]]; then
        local arch
        arch=$(uname -m)
        install_dir="$RUNNER_TOOL_CACHE/cr/$version/$arch"
    fi
}

main "$@"
