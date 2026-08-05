#!/usr/bin/env bash

set -u

namespace="${1:-}"
pod_name="${2:-}"
log_tail_lines="${LOG_TAIL_LINES:-100}"
log_limit_bytes="${LOG_LIMIT_BYTES:-32768}"
event_limit="${EVENT_LIMIT:-20}"
container_limit="${CONTAINER_LIMIT:-10}"

if [[ -z "${namespace}" || -z "${pod_name}" ]]; then
    echo "usage: $0 <namespace> <pod-name>" >&2
    exit 2
fi

for value in "${log_tail_lines}" "${log_limit_bytes}" "${event_limit}" "${container_limit}"; do
    if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
        echo "diagnostic limits must be positive integers" >&2
        exit 2
    fi
done

echo "==================== pod ${namespace}/${pod_name} diagnostics ===================="

pod_json="$(kubectl get pod -n "${namespace}" "${pod_name}" -o json 2>&1)"
if [[ $? -ne 0 ]]; then
    echo "unable to read pod: ${pod_json}"
    exit 0
fi

# Select only runtime fields needed for debugging. Environment variables,
# volumes, annotations, and Secret data are deliberately excluded.
printf '%s\n' "${pod_json}" | jq '
    def safe_arg:
        if test("(?i)(password|passwd|token|secret|authorization|credential|api.?key|license)") then
            "<redacted>"
        elif length > 256 then
            .[0:256] + "...<truncated>"
        else
            .
        end;
    def state_summary:
        if .waiting then
            {waiting: {reason: (.waiting.reason // ""), message: (.waiting.message // "")}}
        elif .terminated then
            {terminated: {
                reason: (.terminated.reason // ""),
                message: (.terminated.message // ""),
                exitCode: (.terminated.exitCode // null),
                signal: (.terminated.signal // null),
                startedAt: (.terminated.startedAt // null),
                finishedAt: (.terminated.finishedAt // null)
            }}
        elif .running then
            {running: {startedAt: (.running.startedAt // null)}}
        else
            {}
        end;
    def status_for($name):
        first(.status.containerStatuses[]? | select(.name == $name)) // {};
    {
        pod: .metadata.name,
        phase: (.status.phase // ""),
        reason: (.status.reason // ""),
        message: (.status.message // ""),
        containers: [
            .spec.containers[] as $spec
            | status_for($spec.name) as $status
            | {
                name: $spec.name,
                image: $spec.image,
                imageID: ($status.imageID // ""),
                command: (($spec.command // []) | map(safe_arg)),
                args: (($spec.args // []) | map(safe_arg)),
                restartCount: ($status.restartCount // 0),
                currentState: (($status.state // {}) | state_summary),
                lastState: (($status.lastState // {}) | state_summary)
            }
        ]
    }
'

echo "==================== pod ${namespace}/${pod_name} recent events ===================="
events_json="$(kubectl get events -n "${namespace}" \
    --field-selector "involvedObject.kind=Pod,involvedObject.name=${pod_name}" \
    -o json 2>&1)"
if [[ $? -eq 0 ]]; then
    printf '%s\n' "${events_json}" | jq -r --argjson limit "${event_limit}" '
        .items
        | sort_by(.lastTimestamp // .eventTime // .metadata.creationTimestamp // "")
        | .[-$limit:]
        | .[]
        | [
            (.lastTimestamp // .eventTime // .metadata.creationTimestamp // ""),
            (.type // ""),
            (.reason // ""),
            ((.message // "") | gsub("[\\r\\n]+"; " ") | .[0:1000])
        ]
        | @tsv
    '
else
    echo "unable to read pod events: ${events_json}"
fi

printf '%s\n' "${pod_json}" | jq -r '
    .spec.containers[] as $spec
    | (first(.status.containerStatuses[]? | select(.name == $spec.name)) // {}) as $status
    | [$spec.name, ($status.restartCount // 0)]
    | @tsv
' | head -n "${container_limit}" | while IFS=$'\t' read -r container_name restart_count; do
    echo "==================== pod ${namespace}/${pod_name} container ${container_name} current log ===================="
    kubectl logs -n "${namespace}" "${pod_name}" -c "${container_name}" \
        --tail="${log_tail_lines}" --limit-bytes="${log_limit_bytes}" 2>&1 || true

    if [[ "${restart_count}" -gt 0 ]]; then
        echo "==================== pod ${namespace}/${pod_name} container ${container_name} previous log ===================="
        kubectl logs -n "${namespace}" "${pod_name}" -c "${container_name}" --previous \
            --tail="${log_tail_lines}" --limit-bytes="${log_limit_bytes}" 2>&1 || true
    fi
done

exit 0
