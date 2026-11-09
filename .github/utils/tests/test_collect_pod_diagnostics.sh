#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
diagnostic_script="${script_dir}/../collect_pod_diagnostics.sh"

kubectl() {
    if [[ "$1" == "get" && "$2" == "pod" ]]; then
        printf '%s\n' '{
            "metadata": {"name": "hermes-agent-abc"},
            "spec": {
                "containers": [{
                    "name": "hermes-agent",
                    "image": "apecloud/hermes-agent:v1",
                    "command": ["/app/hermes-agent"],
                    "args": ["--token=top-secret", "--mode=worker"],
                    "env": [{"name": "PRIVATE_VALUE", "value": "must-not-leak"}]
                }]
            },
            "status": {
                "phase": "Pending",
                "containerStatuses": [{
                    "name": "hermes-agent",
                    "imageID": "docker-pullable://apecloud/hermes-agent@sha256:1234",
                    "restartCount": 2,
                    "state": {"waiting": {"reason": "RunContainerError", "message": "runtime failed"}},
                    "lastState": {"terminated": {"reason": "Error", "exitCode": 126}}
                }]
            }
        }'
        return 0
    fi

    if [[ "$1" == "get" && "$2" == "events" ]]; then
        printf '%s\n' '{
            "items": [{
                "lastTimestamp": "2026-08-05T00:00:00Z",
                "type": "Warning",
                "reason": "Failed",
                "message": "container start failed"
            }]
        }'
        return 0
    fi

    if [[ "$1" == "logs" ]]; then
        printf 'mock-log args: %s\n' "$*"
        return 0
    fi

    printf 'unexpected kubectl call: %s\n' "$*" >&2
    return 1
}
export -f kubectl

output="$(bash "${diagnostic_script}" kb-cloud hermes-agent-abc)"

for expected in \
    'RunContainerError' \
    '"exitCode": 126' \
    'docker-pullable://apecloud/hermes-agent@sha256:1234' \
    $'Warning\tFailed\tcontainer start failed' \
    '--tail=100 --limit-bytes=32768' \
    '--previous --tail=100 --limit-bytes=32768'; do
    if ! grep -Fq -- "${expected}" <<<"${output}"; then
        printf 'missing expected diagnostic: %s\n%s\n' "${expected}" "${output}" >&2
        exit 1
    fi
done

for forbidden in 'top-secret' 'must-not-leak'; do
    if grep -Fq -- "${forbidden}" <<<"${output}"; then
        printf 'sensitive value leaked: %s\n%s\n' "${forbidden}" "${output}" >&2
        exit 1
    fi
done

echo "collect_pod_diagnostics contract: PASS"
