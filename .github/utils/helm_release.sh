#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_RELEASER_VERSION=v1.6.1
GITHUB_API="https://api.github.com"
DELETE_CHARTS_DIR=".cr-release-packages"
DEFAULT_GITHUB_REPO="apecloud/helm-charts"

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help               Display help
    -v, --version            The chart-releaser version to use (default: $DEFAULT_CHART_RELEASER_VERSION)"
    -o, --owner              The repo owner
    -r, --repo               The repo name
    -n, --install-dir        The Path to install the cr tool
    -gr, --github-repo       Github repo
EOF
}

gh_curl() {
    if [[ -z "$CR_TOKEN" ]]; then
        curl -H "Accept: application/vnd.github.v3.raw" \
            $@
    else
        curl -H "Authorization: token $CR_TOKEN" \
            -H "Accept: application/vnd.github.v3.raw" \
            $@
    fi
}

delete_release_version() {
    release_id=$( gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$TAG_NAME | jq -r '.id' )
    if [[ -n "$release_id" && "$release_id" != "null" ]]; then
        echo "delete $GITHUB_REPO release $TAG_NAME"
        gh_curl -s -X DELETE $GITHUB_API/repos/$GITHUB_REPO/releases/$release_id
    fi
    echo "delete $GITHUB_REPO tag $TAG_NAME"
    gh_curl -s -X DELETE  $GITHUB_API/repos/$GITHUB_REPO/git/refs/tags/$TAG_NAME
}

filter_charts() {
    while read -r chart_name; do
        TAG_NAME=${chart_name%*.tgz}
        delete_release_version &
    done
    wait
}

delete_release_charts() {
    charts_files=$( ls -1 $DELETE_CHARTS_DIR )
    echo "$charts_files" | filter_charts
}

release_charts() {
    local args=( -o "$owner" -r "$repo" -c "$(git rev-parse HEAD)" -t $CR_TOKEN --make-release-latest false --skip-existing )

    echo "Releasing charts..."
    cr upload "${args[@]}"

    charts_files=$( ls -1 $DELETE_CHARTS_DIR )
    check_flag=0
    for i in {1..10}; do
        check_flag=0
        for chart_name in $(echo "$charts_files");do
            tag_name=${chart_name%*.tgz}
            release_id=$( gh_curl -s $GITHUB_API/repos/$GITHUB_REPO/releases/tags/$tag_name | jq -r '.id' )
            if [[ -z "$release_id" || "$release_id" == "null" ]]; then
                echo "$(tput -T xterm setaf 3)"checking chart release $tag_name..."$(tput -T xterm sgr0)"
                cr upload "${args[@]}"
                check_flag=1
                break
            fi
        done
        if [[ $check_flag -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)Releasing charts Successfully$(tput -T xterm sgr0)"
            break
        fi
        sleep 1
    done
}

check_latest_commit() {
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
            break
        else
            echo "Detected new commits on the remote branch, updating the local branch..."
            # Try to pull the latest changes from the remote branch
            git pull origin gh-pages

            if [ $? -eq 0 ]; then
                echo "The local branch has been successfully updated to the latest commit."
            fi
        fi
        sleep 1
    done
}

update_index() {
    local args=(-o "$owner" -r "$repo" -t $CR_TOKEN --push)
    # check_latest_commit
    echo 'Updating charts repo index...'
    cr index "${args[@]}"
}

main() {
    local version="$DEFAULT_CHART_RELEASER_VERSION"
    local owner=""
    local repo=""
    local install_dir=""
    local GITHUB_REPO="$DEFAULT_GITHUB_REPO"
    local TAG_NAME=""

    parse_command_line "$@"

    : "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"

    echo 'Adding install_dir to PATH...'
    export PATH="$install_dir:$PATH"

    if [ -d ../.cr-release-packages ]; then
        mv ../.cr-release-packages .
        mv ../.cr-index .
        delete_release_charts
        release_charts
        update_index
    fi
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
            -gr|--github-repo)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_REPO="$2"
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
