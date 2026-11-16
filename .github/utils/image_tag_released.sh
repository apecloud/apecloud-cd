#!/bin/bash

# 0: tag already exists. 1: manifest is absent. 2: lookup failed.
# ponytail: registry manifest is the full-tag record. releases_notes.yaml only stores chart versions.
image_tag_released() {
    local ref="${1:-}" err
    if [[ -z "${ref}" ]]; then
        echo "image ref is empty" >&2
        return 2
    fi
    err="$(mktemp)"
    if docker manifest inspect "${ref}" >/dev/null 2>"${err}"; then
        rm -f "${err}"
        return 0
    fi
    if grep -Eqi 'manifest unknown|not found|no such manifest' "${err}"; then
        rm -f "${err}"
        return 1
    fi
    cat "${err}" >&2
    rm -f "${err}"
    return 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    root="$(mktemp -d)"
    cat > "${root}/docker" << 'END'
#!/bin/bash
ref="${3:-}"
case "${ref}" in
    *":he3sql-1.0.2-v2.3.0")
        exit 0
        ;;
    *":he3sql-1.0.2-v2.3.1")
        echo "manifest unknown" >&2
        exit 1
        ;;
    *)
        echo "unauthorized: authentication required" >&2
        exit 1
        ;;
esac
END
    chmod +x "${root}/docker"
    PATH="${root}:${PATH}"
    image_tag_released "docker.io/apecloud/apecloud-addon-charts:he3sql-1.0.2-v2.3.0"
    rc=0
    image_tag_released "docker.io/apecloud/apecloud-addon-charts:he3sql-1.0.2-v2.3.1" || rc=$?
    [[ "${rc}" -eq 1 ]]
    rc=0
    image_tag_released "docker.io/apecloud/apecloud-addon-charts:broken" || rc=$?
    [[ "${rc}" -eq 2 ]]
    rm -rf "${root}"
    echo "image_tag_released ok"
fi
