#!/usr/bin/env python3
"""Turn click-test pod logs into one Feishu row per engine mode.

Output is a single line, safe to inject into a shell double-quoted string:
  mysql/主备/8.0.46|[PASSED];oracle/主备/19.3.0|[FAILED]
"""

import re
import sys

ENGINE = r"[A-Za-z0-9_.-]+"
PLAN_RE = re.compile(rf"^\s+- ({ENGINE}) slots=")
START_RE = re.compile(rf"^START ({ENGINE}) pid=")
DONE_RE = re.compile(rf"^DONE ({ENGINE})\b.*\bver=(\S*) exit=(-?\d+)\b")
WATCHDOG_RE = re.compile(rf"^WATCHDOG DONE ({ENGINE})\b")
SPEC_RE = re.compile(rf"^({ENGINE})\s+(.+?)\s+(PASSED|FAILED|NO-RUN)\s+\d+\s*$")
DEFER_RE = re.compile(r"^(?:DEFER|DEFERRED)\s+([A-Za-z0-9_.-]+):")
LOGIN_FAIL_RE = re.compile(rf"登录失败 \(({ENGINE})/([^/\s]+)/([^)\s]+)\)")
SAFE_RE = re.compile(r"^[\w./|;\[\]-]*$")
_VERSION_RE = re.compile(r"v?\d+(?:\.\d+)+(?:[-+][A-Za-z0-9.]+)*")
MODE_SUMMARY_RE = re.compile(
    r".*\[([^/\]]+)/([^\]]+)\].*?总计\s*(\d+)\s+通过\s*(\d+)\s+"
    r"失败\s*(\d+)\s+异常\s*(\d+)\s+跳过\s*(\d+)"
)
REPORT_HEADER_RE = re.compile(
    r"^([A-Za-z0-9_.-]+)/([^/\s]+)/([^\s]+)\s+failed=(\d+)"
)
REPORT_CASE_RE = re.compile(
    r"^\s+(TC-[^|]+?)\s*\|\s*[^|]+\|\s*(.+?)\s*\|\s*(FAIL|BROKEN)\s*$"
)
MODE_ALIASES = {"主备": "replication", "单机": "standalone", "默认": "default", "集群版": "cluster"}

ENGINE_GROUPS = (
    ("Relational", (
        "mysql", "mariadb", "postgresql", "polardb-pg", "oracle", "sqlserver",
        "damengdb", "kingbase", "oceanbase", "tidb", "gaussdb", "vastbase",
        "greatdb", "he3sql",
    )),
    ("NoSQL", ("mongodb", "redis", "valkey", "elasticsearch")),
    ("Analytics", (
        "clickhouse", "starrocks", "doris", "selectdb", "influxdb",
        "victoria_metrics", "tdengine",
    )),
    ("Messaging", ("kafka", "rabbitmq", "pulsar", "rocketmq")),
    ("Storage", (
        "minio", "rustfs", "seaweedfs", "foundationdb", "milvus", "nebula",
        "qdrant", "zookeeper", "etcd", "loki", "hadoop", "hive", "nacos",
        "camellia_redis_proxy", "victoria_logs",
    )),
)
_GROUP_OF = {
    engine: name
    for name, members in ENGINE_GROUPS
    for engine in members
}


def _clean_mode(mode):
    return re.sub(r"[^\w.-]+", "", mode)


def _split_spec(spec):
    parts = [part for part in re.sub(r"\s+", "", spec).split("/") if part]
    for index, part in enumerate(parts):
        if not _VERSION_RE.fullmatch(part):
            continue
        mode = _clean_mode(parts[0]) if index else ""
        return mode, "/".join(parts[index:])
    return _clean_mode("".join(parts)), ""


def _mode_status(result, exit_code):
    if result == "PASSED":
        return "PASSED"
    if result == "NO-RUN" and exit_code in (None, 0):
        return "SKIPPED"
    return "FAILED"


def _label(engine, mode, version):
    parts = [engine]
    if mode:
        parts.append(mode)
    if version:
        parts.append(version)
    return "/".join(parts)


def parse_click_engines(text):
    planned = []
    seen = set()
    started = set()
    watchdog = set()
    deferred = set()
    done_exit = {}
    versions = {}
    specs = {}
    login_failed = {}
    hold = False

    def add_planned(engine):
        engine = engine.lower()
        if engine not in seen:
            planned.append(engine)
            seen.add(engine)

    for raw in text.splitlines():
        line = raw.strip("\r")
        plan = PLAN_RE.match(line)
        if plan:
            add_planned(plan.group(1))
            continue
        start = START_RE.match(line)
        if start:
            engine = start.group(1)
            add_planned(engine)
            started.add(engine)
            specs[engine] = []
            login_failed.pop(engine, None)
            continue
        done = DONE_RE.match(line)
        if done:
            engine, version, exit_code = done.group(1), done.group(2), int(done.group(3))
            add_planned(engine)
            done_exit[engine] = exit_code
            if version and version != "default":
                versions[engine] = version
            continue
        watchdog_hit = WATCHDOG_RE.match(line)
        if watchdog_hit:
            engine = watchdog_hit.group(1)
            add_planned(engine)
            watchdog.add(engine)
            continue
        defer_match = DEFER_RE.search(line)
        if defer_match:
            engine = defer_match.group(1)
            add_planned(engine)
            deferred.add(engine.lower())
            continue
        spec = SPEC_RE.match(line)
        if spec and not line[:1].isdigit():
            engine, spec_text, result = spec.group(1), spec.group(2), spec.group(3)
            if engine in seen or engine in started:
                specs.setdefault(engine, []).append((_split_spec(spec_text), result))
            continue
        login_fail = LOGIN_FAIL_RE.search(line)
        if login_fail:
            engine, _version, mode_key = login_fail.groups()
            add_planned(engine)
            modes = login_failed.setdefault(engine, [])
            if mode_key not in modes:
                modes.append(mode_key)
            continue
        if "环境不可用" in line and "跳过剩余" in line:
            hold = True
        elif "不再启动新引擎" in line:
            hold = True

    def unrun_rows(engine, covered):
        found = []
        for mode_key in login_failed.get(engine, []):
            mode = "" if mode_key == "default" else _clean_mode(mode_key)
            if mode and mode in covered:
                continue
            if not mode and covered:
                continue
            found.append(f"{_label(engine, mode, '')}|[FAILED]")
        return found

    rows = []
    for engine in planned:
        spec_rows = specs.get(engine) or []
        if spec_rows and engine not in watchdog:
            exit_code = done_exit.get(engine)
            covered = set()
            for (mode, spec_version), result in spec_rows:
                version = spec_version or versions.get(engine, "")
                rows.append(f"{_label(engine, mode, version)}|[{_mode_status(result, exit_code)}]")
                if mode:
                    covered.add(mode)
            rows.extend(unrun_rows(engine, covered))
            continue
        missed = unrun_rows(engine, set())
        if missed and engine not in watchdog:
            rows.extend(missed)
            continue
        if engine in watchdog:
            status = "FAILED"
        elif engine.lower() in deferred:
            status = "SKIPPED"
        elif engine in done_exit:
            status = "FAILED" if done_exit[engine] != 0 else "SKIPPED"
        elif engine not in started and hold:
            status = "SKIPPED"
        else:
            status = "FAILED"
        version = versions.get(engine, "")
        label = f"{engine}/{version}" if version else engine
        rows.append(f"{label}|[{status}]")

    out = ";".join(rows)
    if not SAFE_RE.fullmatch(out or ""):
        return ""
    return out


def group_click_rows(text):
    buckets = {name: [] for name, _members in ENGINE_GROUPS}
    buckets["Other"] = []
    for row in text.split(";"):
        row = row.strip()
        if not row or "|" not in row:
            continue
        engine = row.split("|", 1)[0].split("/", 1)[0]
        buckets[_GROUP_OF.get(engine, "Other")].append(row)
    order = [name for name, _members in ENGINE_GROUPS] + ["Other"]
    return [(name, ";".join(buckets[name])) for name in order if buckets[name]]


def parse_click_full_results(text):
    summaries = {}
    order = []
    first_failed = {}
    current_report = None

    for raw in text.splitlines():
        line = raw.strip("\r")
        summary = MODE_SUMMARY_RE.match(line)
        if summary:
            engine, mode, total, passed, failed, broken, skipped = summary.groups()
            key = (engine.lower(), mode)
            summaries[key] = {
                "total": int(total),
                "passed": int(passed),
                "failed": int(failed) + int(broken),
                "skipped": int(skipped),
                "version": "",
            }
            if key not in order:
                order.append(key)
            current_report = None
            continue

        report = REPORT_HEADER_RE.match(line)
        if report:
            engine, mode, version, _failed = report.groups()
            key = (engine.lower(), mode)
            item = summaries.setdefault(key, {
                "total": 0, "passed": 0, "failed": 0, "skipped": 0,
                "version": version,
            })
            item["version"] = version
            if key not in order:
                order.append(key)
            current_report = key
            continue

        case = REPORT_CASE_RE.match(line)
        if case and current_report and current_report not in first_failed:
            case_id, name, _status = case.groups()
            first_failed[current_report] = f"{case_id.strip()}: {name.strip()}"

    for label in parse_click_engines(text).split(";"):
        if not label or "|" not in label:
            continue
        engine_mode, status = label.split("|", 1)
        parts = engine_mode.split("/")
        engine = parts[0].lower()
        version_at = next((i for i, part in enumerate(parts[1:], 1)
                           if _VERSION_RE.fullmatch(part)), None)
        if version_at is None:
            mode, version = "/".join(parts[1:]), ""
        else:
            mode, version = "/".join(parts[1:version_at]), "/".join(parts[version_at:])
        mode = MODE_ALIASES.get(mode, mode)
        key = (engine, mode)
        item = summaries.setdefault(key, {
            "total": 0, "passed": 0, "failed": 0, "skipped": 0,
            "version": version,
        })
        item["version"] = item["version"] or version
        if not item["total"]:
            item["status"] = status
        if key not in order:
            order.append(key)

    rows = []
    for key in order:
        engine, mode = key
        item = summaries[key]
        status = item.get("status")
        if not status:
            status = "[FAILED]" if item["failed"] else "[PASSED]" if item["passed"] else "[SKIPPED]"
        rows.append("|".join((
            engine,
            str(item["passed"]),
            str(item["failed"]),
            str(item["skipped"]),
            item["version"],
            mode,
            first_failed.get(key, "-"),
            status,
        )))
    return "\n".join(rows)


def main(argv):
    if len(argv) == 3 and argv[1] == "--group":
        for name, rows in group_click_rows(argv[2]):
            print(f"{name}\t{rows}")
        return 0
    if len(argv) == 3 and argv[1] == "--full":
        with open(argv[2], encoding="utf-8", errors="replace") as handle:
            print(parse_click_full_results(handle.read()))
        return 0
    if len(argv) != 2:
        print("usage: click_engine_results.py <pod-log>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8", errors="replace") as handle:
        print(parse_click_engines(handle.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))