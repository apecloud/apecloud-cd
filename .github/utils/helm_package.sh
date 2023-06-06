#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_RELEASER_VERSION=v1.4.1
DEFAULT_TOOL=helm

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help               Display help
    -v, --version            The chart-releaser version to use (default: $DEFAULT_CHART_RELEASER_VERSION)"
    -d, --charts-dir         The charts directory (default: charts)
    -o, --owner              The repo owner
    -r, --repo               The repo name
    -n, --install-dir        The Path to install the cr tool
    -rv, --release-version   The release version of helm charts
    -t, --tool               The tool of helm package (helm,cr default: $DEFAULT_TOOL)
EOF
}

main() {
    local version="$DEFAULT_CHART_RELEASER_VERSION"
    local charts_dir=charts
    local owner=
    local repo=
    local install_dir=
    local release_version=""
    local tool=$DEFAULT_TOOL

    parse_command_line "$@"

    : "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"

    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    pushd "$repo_root" > /dev/null

    echo "Lookup charts..."
    local changed_charts=()
    readarray -t changed_charts <<< "$(lookup_changed_charts)"

    if [[ -n "${changed_charts[*]}" ]]; then
        install_chart_releaser

        rm -rf .cr-release-packages
        mkdir -p .cr-release-packages

        rm -rf .cr-index
        mkdir -p .cr-index

        for chart in "${changed_charts[@]}"; do
            if [[ -d "$chart" ]]; then
                package_chart "$chart"
            else
                echo "Chart '$chart' no longer exists in repo. Skipping it..."
            fi
        done
    else
        echo "Nothing to do. No chart changes detected."
    fi

    popd > /dev/null
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
            -d|--charts-dir)
                if [[ -n "${2:-}" ]]; then
                    charts_dir="$2"
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
            -rv|--release-version)
                if [[ -n "${2:-}" ]]; then
                    release_version="$2"
                    shift
                fi
                ;;
            -t|--tool)
                if [[ -n "${2:-}" ]]; then
                    tool="$2"
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

install_chart_releaser() {
    if [[ ! -d "$RUNNER_TOOL_CACHE" ]]; then
        echo "Cache directory '$RUNNER_TOOL_CACHE' does not exist" >&2
        exit 1
    fi

    if [[ ! -d "$install_dir" ]]; then
        mkdir -p "$install_dir"

        echo "Installing chart-releaser on $install_dir..."
        curl -sSLo cr.tar.gz "https://github.com/helm/chart-releaser/releases/download/$version/chart-releaser_${version#v}_linux_amd64.tar.gz"
        tar -xzf cr.tar.gz -C "$install_dir"
        rm -f cr.tar.gz
    fi

    echo 'Adding install_dir to PATH...'
    export PATH="$install_dir:$PATH"
}

filter_charts() {
    while read -r chart; do
        [[ ! -d "$charts_dir/$chart" ]] && continue
        local file="$charts_dir/$chart/Chart.yaml"
        if [[ -f "$file" ]]; then
            echo "$charts_dir/$chart"
        else
           echo "WARNING: $file is missing, assuming that '$charts_dir/$chart' is not a Helm chart. Skipping." 1>&2
        fi
    done
}

lookup_changed_charts() {
    local changed_files
    changed_files=$(ls -1 "$charts_dir")
    echo "$changed_files" | filter_charts
}

package_chart() {
    local chart="$1"
    local args=("$chart" --package-path .cr-release-packages)
    echo "$tool packaging $release_version chart '$chart'..."
    case $tool in
        cr)
            cr package "${args[@]}"
        ;;
        helm)
            args=("$chart" --destination .cr-release-packages)
            helm package "${args[@]}" --version $release_version
        ;;
        *)
            break
        ;;
    esac
}

main "$@"
