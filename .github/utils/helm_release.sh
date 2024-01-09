#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_RELEASER_VERSION=v1.6.1
GITHUB_API="https://api.github.com"
DELETE_CHARTS_DIR="../.cr-release-packages"
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

gh_release_create() {
    gh release create $TAG_NAME --repo $GITHUB_REPO --title $TAG_NAME --prerelease --generate-notes
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
        echo "delete chart $chart_name"
        TAG_NAME=${chart_name%*.tgz}
        delete_release_version &
    done
    wait
}

delete_release_charts() {
    charts_files=$( ls -1 $DELETE_CHARTS_DIR )
    echo "$charts_files" | filter_charts
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
        delete_release_charts
        mv ../.cr-release-packages .
        mv ../.cr-index .
        sleep 10
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
                else
                    echo "ERROR: '-v|--version' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -o|--owner)
                if [[ -n "${2:-}" ]]; then
                    owner="$2"
                    shift
                else
                    echo "ERROR: '--owner' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -r|--repo)
                if [[ -n "${2:-}" ]]; then
                    repo="$2"
                    shift
                else
                    echo "ERROR: '--repo' cannot be empty." >&2
                    show_help
                    exit 1
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

    if [[ -z "$owner" ]]; then
        echo "ERROR: '-o|--owner' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$repo" ]]; then
        echo "ERROR: '-r|--repo' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$install_dir" ]]; then
        local arch
        arch=$(uname -m)
        install_dir="$RUNNER_TOOL_CACHE/cr/$version/$arch"
    fi
}

release_charts() {
    local args=( -o "$owner" -r "$repo" -c "$(git rev-parse HEAD)" -t $CR_TOKEN)

    echo "Releasing charts... $args"
    cr upload "${args[@]}"
}

update_index() {
    local args=(-o "$owner" -r "$repo" -t $CR_TOKEN --push)

    echo 'Updating charts repo index...'
    cr index "${args[@]}"
}

main "$@"
