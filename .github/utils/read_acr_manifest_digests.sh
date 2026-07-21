#!/usr/bin/env bash
set -euo pipefail

readonly APPROVED_ACR_PREFIX="apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com/apecloud/"

if [[ $# -eq 0 ]]; then
    echo "at least one ACR image reference is required" >&2
    exit 2
fi

inspect_file="$(mktemp)"
raw_file="$(mktemp)"
trap 'rm -f "${inspect_file}" "${raw_file}"' EXIT

for ref in "$@"; do
    case "${ref}" in
        "${APPROVED_ACR_PREFIX}"*:* ) ;;
        * )
            echo "ref is outside the approved ACR path: ${ref}" >&2
            exit 2
            ;;
    esac

    docker buildx imagetools inspect "${ref}" > "${inspect_file}"
    docker buildx imagetools inspect --raw "${ref}" > "${raw_file}"

    root_digest="$(awk '$1 == "Digest:" { print $2; exit }' "${inspect_file}")"
    amd64_digest="$(
        jq -er '
            [.manifests[]
             | select(.platform.os == "linux" and .platform.architecture == "amd64")
             | .digest]
            | if length == 1 then .[0] else error("expected exactly one linux/amd64 manifest") end
        ' "${raw_file}"
    )"

    digest_pattern='^sha256:[0-9a-f]{64}$'
    if [[ ! "${root_digest}" =~ ${digest_pattern} ]]; then
        echo "invalid root digest for ${ref}" >&2
        exit 1
    fi
    if [[ ! "${amd64_digest}" =~ ${digest_pattern} ]]; then
        echo "invalid linux/amd64 digest for ${ref}" >&2
        exit 1
    fi

    printf 'ref=%s root_digest=%s linux_amd64_digest=%s\n' \
        "${ref}" "${root_digest}" "${amd64_digest}"
done
