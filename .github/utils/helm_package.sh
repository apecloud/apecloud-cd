#!/usr/bin/env bash

set -o nounset

DEFAULT_CHART_RELEASER_VERSION=v1.6.1
DEFAULT_TOOL=helm
DEFAULT_INSTALL_CR=false

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help               Display help
    -d, --charts-dir         The charts directory (default: deploy)
    -rv, --release-version   The release version of helm charts
    -av, --app-version       The release app version of helm charts
    -t, --tool               The tool of helm package (helm,cr default: $DEFAULT_TOOL)
    -ic, --install-cr        Install chart releaser (default: $DEFAULT_INSTALL_CR)
    -sc, --specify-chart     Only package the specify sub dir chart
    -o, --owner              The repo owner
    -r, --repo               The repo name
EOF
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
    if [[ -n "$SPECIFY_CHART" ]]; then
        if [[ "${SPECIFY_CHART}" == *"|"* ]]; then
            changed_files=$(echo "$SPECIFY_CHART" | sed 's/##/ /g')
        else
            changed_files="$SPECIFY_CHART"
        fi

    else
        changed_files=$(ls -1 "$charts_dir")
        if [[ "$changed_files" == *"gemini-monitor"* ]]; then
            changed_files=$(ls -1 "$charts_dir" | (grep -v "victoria-metrics-alert" || true) )
        fi
    fi
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
            package_flag=0
            for i in {1..10}; do
                ret_msg=""
                if [[ -z "$release_version" ]]; then
                    if [[ -n "$app_version" ]]; then
                        echo "helm package "${args[@]}" --app-version $app_version --dependency-update"
                        ret_msg=$(helm package "${args[@]}" --app-version $app_version --dependency-update)
                    else
                        echo "helm package "${args[@]}" --dependency-update "
                        ret_msg=$(helm package "${args[@]}" --dependency-update)
                    fi
                else
                    if [[ -n "$app_version" ]]; then
                        echo "helm package "${args[@]}" --version $release_version --app-version $app_version --dependency-update"
                        ret_msg=$(helm package "${args[@]}" --version $release_version --app-version $app_version --dependency-update)
                    else
                        echo "helm package "${args[@]}" --version $release_version --dependency-update"
                        ret_msg=$(helm package "${args[@]}" --version $release_version --dependency-update)
                    fi
                fi
                echo "return message:$ret_msg"
                if [[ "$ret_msg" == *"Successfully packaged"* ]]; then
                    echo "$(tput -T xterm setaf 2)$ret_msg$(tput -T xterm sgr0)"
                    package_flag=1
                    break
                fi
                sleep 1
            done
            if [[ $package_flag -eq 0 ]]; then
                echo "$(tput -T xterm setaf 1)helm package $chart error$(tput -T xterm sgr0)"
                exit 1
            fi
        ;;
        *)
            break
        ;;
    esac
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
            ;;
            -d|--charts-dir)
                if [[ -n "${2:-}" ]]; then
                    charts_dir="$2"
                    shift
                fi
            ;;
            -rv|--release-version)
                if [[ -n "${2:-}" ]]; then
                    release_version="$2"
                    shift
                fi
            ;;
            -av|--app-version)
                if [[ -n "${2:-}" ]]; then
                    app_version="$2"
                    shift
                fi
            ;;
            -t|--tool)
                if [[ -n "${2:-}" ]]; then
                    tool="$2"
                    shift
                fi
            ;;
            -ic|--install-cr)
                if [[ -n "${2:-}" ]]; then
                    install_cr="$2"
                    shift
                fi
            ;;
            -sc|--specify-chart)
                if [[ -n "${2:-}" ]]; then
                    SPECIFY_CHART="$2"
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

main() {
    local version="$DEFAULT_CHART_RELEASER_VERSION"
    local charts_dir=deploy
    local install_dir=""
    local release_version=""
    local app_version=""
    local tool=$DEFAULT_TOOL
    local install_cr=$DEFAULT_INSTALL_CR
    local SPECIFY_CHART=""

    parse_command_line "$@"

    : "${CR_TOKEN:?Environment variable CR_TOKEN must be set}"

    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    pushd "$repo_root" > /dev/null

    echo "Lookup charts..."
    local changed_charts=()
    readarray -t changed_charts <<< "$(lookup_changed_charts)"

    if [[ -n "${changed_charts[*]}" || "$install_cr" == "true" ]]; then
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

main "$@"
