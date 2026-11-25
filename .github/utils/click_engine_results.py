#!/usr/bin/env python3
"""Turn click-test pod logs into one Feishu row per engine mode.

Enhanced to robustly extract First Failed Case from ALL current output formats:
- Legacy TC-XXXX | ... | FAIL reports
- Playwright ✅❌ step counters
- _inline_save / 确认按钮点击失败 warnings (most common root cause)
- Benchmark/test step failures ([14. 基准测试] ❌1, etc.)
- Generic 失败/异常/error lines
- TC-EXT-xxx ⏭️/❌ patterns

Never returns "-" when failed > 0. Fully backward compatible.
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
    r".*?\[([^/\]]+)/([^\]]+)\].*?总计\s*(\d+)[ \t]+通过\s*(\d+)\s+"
    r"失败\s*(\d+)[ \t]+异常\s*(\d+)[ \t]+跳过\s*(\d+)"
)
ENGINE_NAME_ALIASES = {
    "nebula graph": "nebula",
    "loki logging system": "loki",
    "kingbasedb": "kingbase",
    "victorialogs": "victoria_logs",
    "victoria metrics": "victoria_metrics",
    "camellia redis proxy": "camellia_redis_proxy",
    "sql server": "sqlserver",
}
REPORT_HEADER_RE = re.compile(
    r"^([A-Za-z0-9_.-]+)/([^/\s]+)/([^\s]+)\s+failed=(\d+)\s+broken=(\d+)"
)
REPORT_CASE_RE = re.compile(
    r"^\s+(TC-[^|]+?)\s*\|\s*[^|]+\|\s*(.+?)\s*\|\s*(FAIL|BROKEN|SKIP)\s*$"
)
SKIP_REASON_RE = re.compile(
    r"^(?:DEFER|DEFERRED|SKIP(?:PED)?)\s+([A-Za-z0-9_.-]+)(?::|\s)\s*(.+)$",
    re.IGNORECASE,
)

# Enhanced failure patterns to catch current test output (Playwright + Chinese UI tests)
INLINE_SAVE_FAIL_RE = re.compile(r"_inline_save:.*确认按钮常规点击失败")
BUTTON_FAIL_RE = re.compile(r"确认按钮.*(?:点击|常规).*失败|翻页失败|inline_save.*失败")
TC_SKIP_RE = re.compile(r"(TC-[A-Z0-9-]+)\s*[⏭️⚠️❌]\s*(.+)")
FAILURE_STEP_RE = re.compile(r"\[(.*?)\]\s*✅.*?(?:❌(\d+)|失败|error|异常).*?(?:$|WARNING)", re.IGNORECASE)
BENCHMARK_FAIL_RE = re.compile(r"\[14\.\s*基准测试\].*?❌(\d+)")
GENERAL_FAIL_RE = re.compile(r"(?:失败|error|FAILED|❌|异常|WARNING.*失败|点击失败).*?([^\n]{10,80}?)", re.IGNORECASE)

MODE_ORDER = {
    "default": 0,
    "standalone": 1,
    "single-node": 2,
    "singlenode": 3,
    "single": 4,
    "replication": 5,
    "cluster": 6,
    "clustermode": 7,
    "triple": 8,
    "realtime-replication": 9,
    "replicaset": 10,
    "master-slave": 11,
    "dledger": 12,
    "combined": 13,
    "withzookeeper": 14,
    "zookeeper模式": 15,
    "distribution": 16,
    "distributed": 17,
    "distributed-2-6": 18,
    "aggregated": 19,
    "disaggregated": 20,
    "integrated": 21,
    "shared-data": 22,
    "standard": 23,
    "pulsar-enhanced-with-kb-zk": 24,
    "vm-single": 25,
}
MODE_ALIASES = {
    "主备": "replication", "单机": "standalone", "默认": "default", "集群版": "cluster",
    "单机版": "single-node", "集群": "cluster", "高可用集群": "cluster",
    "组合": "combined", "分布式2.6": "distributed-2-6", "分布式(2.6+)": "distributed-2-6",
    "实时主备": "realtime-replication", "存算一体": "aggregated", "存算分离": "disaggregated",
    "简单可扩展": "standard", "单节点": "single", "三节点": "triple",
    "主从模式": "master-slave", "分布式": "distributed",
}

ENGINE_GROUPS = (
    ("Relational", (
        "mysql", "mariadb", "postgresql", "polardb-pg", "oracle", "sqlserver",
        "damengdb", "kingbase", "oceanbase", "tidb", "gaussdb", "vastbase",
        "greatdb", "he3sql",
    )),
    ("NoSQL", ("mongodb", "redis", "valkey", "elasticsearch")),
    ("Analytics", (
        "clickhouse", "starrocks", "doris", "dolphindb", "selectdb", "influxdb",
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


def _natural_key(value):
    return tuple(
        int(part) if part.isdigit() else part.casefold()
        for part in re.split(r"(\d+)", str(value))
        if part
    )


def _mode_key(mode):
    normalized = _mode_alias(mode).casefold()
    return (MODE_ORDER.get(normalized, len(MODE_ORDER)), _natural_key(mode))


def _row_sort_key(row):
    """Sort Click rows by engine, mode, then natural version order."""
    fields = row.split("|")
    if len(fields) >= 8 and all(field.isdigit() for field in fields[1:4]):
        engine, version, mode = fields[0], fields[4], fields[5]
    else:
        label = fields[0]
        parts = label.split("/")
        engine = parts[0]
        version_at = next(
            (index for index, part in enumerate(parts[1:], 1) if _version_token(part)),
            None,
        )
        version = "/".join(parts[version_at:]) if version_at is not None else ""
        mode = "/".join(parts[1:version_at]) if version_at is not None else "/".join(parts[1:])
    return (_natural_key(engine), _mode_key(mode), _natural_key(version), row)


def _sorted_rows(rows):
    return sorted((row for row in rows if row), key=_row_sort_key)


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
    if result == "NO-RUN":
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
    deferred_reason = {}
    skip_reasons = {}
    done_exit = {}
    versions = {}
    specs = {}
    login_failed = {}
    hold = False
    held_reason = "未执行测试"

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
            deferred_reason[engine.lower()] = _clean_detail(line).split(":", 1)[-1].strip()[:80]
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
            held_reason = "环境不可用，跳过剩余引擎"
        elif "不再启动新引擎" in line:
            hold = True
            held_reason = "不再启动新引擎"
        dependency_skip = re.search(r"([A-Za-z0-9_.-]+)\s+v?\S+/\S+\s+依赖准备失败.*?跳过目标创建:\s*(.+)$", line)
        if dependency_skip:
            skip_reasons.setdefault(dependency_skip.group(1).lower(), dependency_skip.group(2).strip()[:80])
        environment_skip = re.search(r"([A-Za-z0-9_.-]+)\s+未启动.*?跳过", line)
        if environment_skip:
            skip_reasons.setdefault(environment_skip.group(1).lower(), "环境不可用，跳过剩余引擎")

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
            skip_reasons.setdefault(engine.lower(), deferred_reason.get(engine.lower(), "资源不足，延后执行"))
        elif engine in done_exit:
            status = "FAILED" if done_exit[engine] != 0 else "SKIPPED"
        elif engine not in started and hold:
            status = "SKIPPED"
            skip_reasons.setdefault(engine.lower(), held_reason)
        else:
            status = "FAILED"
        version = versions.get(engine, "")
        label = f"{engine}/{version}" if version else engine
        rows.append(f"{label}|[{status}]")

    out = ";".join(rows)
    if not SAFE_RE.fullmatch(out or ""):
        return ""
    return out


def parse_click_skip_reasons(text):
    """Return engine<TAB>reason for skipped or deferred engine modes."""
    reasons = {}
    current_engine = ""
    lines = text.splitlines()
    planned_engines = []
    active_engines = []
    completed_engines = set()
    for line_index, raw in enumerate(lines):
        line = raw.strip("\r")
        plan = PLAN_RE.match(line)
        if plan:
            current_engine = plan.group(1).lower()
            if current_engine not in planned_engines:
                planned_engines.append(current_engine)
            continue
        start = START_RE.match(line)
        if start:
            current_engine = start.group(1).lower()
            active_engines.append(current_engine)
            continue
        done = DONE_RE.match(line)
        if done:
            active_engines = [engine for engine in active_engines if engine != done.group(1).lower()]
            completed_engines.add(done.group(1).lower())
            continue
        if ("环境不可用" in line and "跳过剩余" in line) or "不再启动新引擎" in line:
            for engine in active_engines:
                reasons.setdefault(engine, "环境不可用，跳过剩余引擎")
            for engine in planned_engines:
                if engine not in completed_engines and engine not in active_engines:
                    reasons.setdefault(engine, "未启动：环境不可用，跳过剩余引擎")
            continue
        skip = SKIP_REASON_RE.match(_clean_detail(line))
        if skip:
            engine, reason = skip.groups()
            reasons.setdefault(engine.lower(), reason[:80])
            continue
        dependency_skip = re.search(r"([A-Za-z0-9_.-]+)\s+v?\S+/\S+\s+依赖准备失败.*?跳过目标创建:\s*(.+)$", line)
        if dependency_skip:
            reasons.setdefault(dependency_skip.group(1).lower(), dependency_skip.group(2).strip()[:80])
            continue
    return "".join(f"{engine}\t{reason}\n" for engine, reason in reasons.items())


def _mode_alias(mode):
    return MODE_ALIASES.get(mode, mode)


def _engine_name(engine):
    engine = engine.strip().lower()
    return ENGINE_NAME_ALIASES.get(engine, engine)


def _version_token(part):
    part = part.strip()
    return bool(
        _VERSION_RE.fullmatch(part)
        or (part.startswith("v") and _VERSION_RE.fullmatch(part[1:]))
    )


def _label_parts(label):
    """Split an engine/mode/version label without changing the display mode."""
    parts = label.split("/")
    engine = parts[0].strip().lower()
    raw_label = parts[0].strip()
    version_at = next(
        (index for index, part in enumerate(parts[1:], 1) if _version_token(part)),
        None,
    )
    # Legacy specs sometimes include the version in the engine column.
    if version_at is None:
        match = re.match(r"^([A-Za-z0-9_.-]+?)\s+(v?\d.*)$", raw_label)
        if match:
            engine, embedded_version = match.groups()
            parts = [engine, embedded_version]
            version_at = 1
    if version_at is None:
        return engine, "/".join(parts[1:]), ""
    return (
        engine,
        "/".join(parts[1:version_at]),
        "/".join(parts[version_at:]),
    )


def group_click_rows(text):
    """Group compact or detailed Click rows separated by semicolons or ##."""
    buckets = {name: [] for name, _members in ENGINE_GROUPS}
    buckets["Other"] = []
    for row in text.replace("##", ";").split(";"):
        row = row.strip()
        if not row or "|" not in row:
            continue
        fields = row.split("|")
        if len(fields) >= 8 and all(field.isdigit() for field in fields[1:4]):
            # engine|pass|fail|skip|version|mode|case|status
            engine = fields[0].strip().lower()
        else:
            engine = fields[0].split("/", 1)[0].strip().lower()
        buckets[_GROUP_OF.get(engine, "Other")].append(row)
    order = [name for name, _members in ENGINE_GROUPS] + ["Other"]
    for name in buckets:
        buckets[name] = _sorted_rows(buckets[name])
    return [(name, ";".join(buckets[name])) for name in order if buckets[name]]


def _clean_detail(text):
    text = re.sub(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:,\d+)?\s+", "", text.strip())
    text = re.sub(r"^(?:INFO|WARNING|WARN|ERROR|DEBUG)\s+", "", text)
    return re.sub(r"\s+", " ", text).strip()


def extract_first_failed_case(line: str, engine: str = "", mode: str = "", reason: str = "") -> str | None:
    """Extract the first failed or skipped case, including the skip reason."""
    line = line.strip()

    # 1. Structured TC- reports take precedence over incidental log warnings.
    case = REPORT_CASE_RE.match(line)
    if case:
        case_id, name, status = case.groups()
        detail = f"{case_id.strip()}: {name.strip()[:60]}"
        if status == "SKIP" and reason:
            detail += f" ({reason[:70]})"
        return detail

    # 2. New TC- with ❌ or explicit failure
    tc_match = TC_SKIP_RE.search(line)
    if tc_match and ("❌" in line or "失败" in line):
        tc_id, desc = tc_match.groups()
        return f"{tc_id}: {desc.strip()[:60]}"

    # 3. Inline save / button click failures (very common in current logs)
    if INLINE_SAVE_FAIL_RE.search(line) or BUTTON_FAIL_RE.search(line):
        # Try to extract preceding test step name (e.g. from [XX. 测试步骤])
        step_match = re.search(r"\[([^\]]+?)\]", line)
        step = step_match.group(1) if step_match else "UI操作"
        detail = "确认按钮点击失败" if "确认按钮" in line else "inline_save点击失败"
        return f"{step}: {detail}"

    # 4. Benchmark / specific test with ❌ count
    bench = BENCHMARK_FAIL_RE.search(line)
    if bench:
        return "基准测试 (性能/一致性校验) 失败"

    # 5. General failure steps with ❌ or 失败
    fail_step = FAILURE_STEP_RE.search(line)
    if fail_step:
        step_name = fail_step.group(1) or "未知步骤"
        return f"{step_name.strip()}: 执行失败"

    # 6. Generic failure keyword with context (fallback)
    gen_fail = GENERAL_FAIL_RE.search(line)
    if gen_fail and any(k in line.lower() for k in ("失败", "error", "❌", "异常")):
        desc = gen_fail.group(1).strip()
        if len(desc) > 15:  # avoid too generic matches
            prefix = f"{engine}/{mode}" if engine and mode else ""
            return f"{prefix} {desc[:55]}".strip()

    return None


def parse_click_full_results(text):
    """Enhanced version that robustly extracts first failed case from all known output formats.
    Supports legacy TC- reports, modern Playwright ✅❌ logs, inline_save warnings,
    benchmark failures, and generic error lines. Never misses a failure when failed > 0.
    """
    summaries = {}
    order = []
    first_failed = {}
    first_skipped = {}
    engine_skip_reasons = {}
    for reason_line in parse_click_skip_reasons(text).splitlines():
        if "\t" in reason_line:
            reason_engine, reason = reason_line.split("\t", 1)
            engine_skip_reasons.setdefault(reason_engine.lower(), reason)
    current_report = None
    pending_skip = None
    active_engines = []
    report_skip_reasons = {}

    for raw in text.splitlines():
        line = raw.strip("\r")
        summary = MODE_SUMMARY_RE.match(line)
        if summary:
            engine, mode, total, passed, failed, broken, skipped = summary.groups()
            summary_engine = _engine_name(engine)
            version = ""
            version_match = re.search(r"\bv?(\d+(?:\.\d+)+(?:[-+][A-Za-z0-9.]+)*)\b", engine)
            if version_match:
                version = version_match.group(1)
            mode_version = re.search(rf"(?:^|/)(v?{_VERSION_RE.pattern})(?:/|$)", mode)
            if mode_version:
                version = mode_version.group(1)
                mode = mode[:mode_version.start()].rstrip("/")
            key = (summary_engine, _mode_alias(mode))
            summaries[key] = {
                "total": int(total),
                "passed": int(passed),
                "failed": int(failed) + int(broken),
                "skipped": int(skipped),
                "version": version,
            }
            if key not in order:
                order.append(key)
            current_report = None
            last_engine_mode = key
            continue

        report = REPORT_HEADER_RE.match(line)
        if report:
            engine, mode, version, failed, broken = report.groups()
            key = (_engine_name(engine), _mode_alias(mode))
            if int(failed) + int(broken) == 0:
                current_report = key
                report_skip_reasons.setdefault(key, "")
                continue
            item = summaries.setdefault(key, {
                "total": 0, "passed": 0, "failed": 0, "skipped": 0,
                "version": version,
            })
            item["version"] = version
            if key not in order:
                order.append(key)
            current_report = key
            last_engine_mode = key
            continue

        start = START_RE.match(line)
        if start and start.group(1).lower() not in active_engines:
            active_engines.append(start.group(1).lower())
        done = DONE_RE.match(line)
        if done:
            active_engines = [engine for engine in active_engines if engine != done.group(1).lower()]
        skip_match = SKIP_REASON_RE.match(_clean_detail(line))
        if skip_match:
            skip_engine, reason = skip_match.groups()
            key = (_engine_name(skip_engine), "")
            engine_skip_reasons.setdefault(key[0], reason[:80])
            first_skipped.setdefault(key, reason[:80])
            pending_skip = {"key": key, "reason": reason[:80]}
            continue
        if "环境不可用" in line and "跳过剩余" in line:
            for engine in active_engines:
                engine_skip_reasons.setdefault(engine, "环境不可用，跳过剩余引擎")
            pending_skip = {"key": None, "reason": "环境不可用，跳过剩余引擎"}
            continue

        # Structured TC- reports are more useful than incidental log warnings.
        case = REPORT_CASE_RE.match(line)
        if case:
            case_id, name, status = case.groups()
            detail = f"{case_id.strip()}: {name.strip()[:60]}"
            target = first_failed if status != "SKIP" else first_skipped
            key = current_report
            if key and key not in target:
                reason = pending_skip["reason"] if status == "SKIP" and pending_skip and pending_skip["key"] in (None, key) else ""
                if status == "SKIP":
                    reason = reason or report_skip_reasons.get(key, "")
                    detail += f" ({reason[:70]})" if reason else ""
                target[key] = detail[:150]
            pending_skip = None
            continue

        if current_report in report_skip_reasons and not report_skip_reasons[current_report]:
            detail = _clean_detail(line)
            if detail and not detail.startswith(("DONE ", "=====")):
                report_skip_reasons[current_report] = detail[:80]
                if current_report in first_skipped and report_skip_reasons[current_report] not in first_skipped[current_report]:
                    first_skipped[current_report] += f" ({report_skip_reasons[current_report][:70]})"
                pending_skip = None
                continue

        if current_report:
            engine_ctx, mode_ctx = current_report
            failed_case = extract_first_failed_case(line, engine_ctx, mode_ctx)
            if failed_case and current_report not in first_failed:
                first_failed[current_report] = failed_case[:80]

    for label in parse_click_engines(text).split(";"):
        if not label or "|" not in label:
            continue
        engine_mode, status = label.split("|", 1)
        # Reuse one split for both log formats so Chinese display modes match
        # their English aliases in summaries and failure-report headers.
        engine, mode, version = _label_parts(engine_mode)
        item = summaries.get((engine, _mode_alias(mode)))
        if item and item.get("total"):
            item["status"] = status
            if version:
                item["version"] = version
            # An exact spec has authoritative counts; a later summary for the
            # same engine/mode must not overwrite a different version's result.
            item["total"] = -1
        key = (engine, _mode_alias(mode))
        item = summaries.setdefault(key, {
            "total": 0, "passed": 0, "failed": 0, "skipped": 0,
            "version": version,
        })
        item["version"] = version or item.get("version", "")
        if not item.get("total") or item.get("total") == -1:
            item["status"] = status
        if key not in order:
            order.append(key)

    # Failed-only report headers do not necessarily carry an engine status row.
    # Only synthesize a failure when a corresponding mode was actually reported.
    for key in list(first_failed.keys()):
        if key not in summaries:
            summaries[key] = {"failed": 1}
        elif not summaries[key].get("total") and summaries[key].get("failed", 0) == 0:
            summaries[key]["failed"] = 1

    # Preserve the display mode from the first matching spec. Report headers
    # normally use aliases such as replication/standalone.
    display_modes = {}
    _spec_details = {}
    for label in parse_click_engines(text).split(";"):
        if not label or "|" not in label:
            continue
        engine_mode, status = label.split("|", 1)
        engine, mode, version = _label_parts(engine_mode)
        if mode and not re.search(r"\d+(?:\.\d+)+", mode):
            display_modes.setdefault((engine, _mode_alias(mode)), mode)
        _spec_details[(engine, _mode_alias(mode), version)] = {
            "mode": mode,
            "status": status,
        }
        if status == "[SKIPPED]":
            reason = first_skipped.get((engine, "")) or engine_skip_reasons.get(engine)
            if reason:
                first_skipped[(engine, _mode_alias(mode))] = reason[:80]

    # Alias variants and repeated versions can create duplicate mode keys. Keep
    # the row with actual case counts, otherwise the most recent mode result.
    merged_order = []
    merged_indices = {}
    for key in order:
        identity = (key[0], _mode_alias(key[1]))
        if identity not in merged_indices:
            merged_indices[identity] = len(merged_order)
            merged_order.append(key)
            continue
        index = merged_indices[identity]
        duplicate = merged_order[index]
        duplicate_item = summaries[duplicate]
        current_item = summaries[key]
        current_total = current_item.get("total", 0)
        duplicate_total = duplicate_item.get("total", 0)
        spec = _spec_details.get((key[0], _mode_alias(key[1]), current_item.get("version", "")))
        if spec and current_total == 0:
            current_item["status"] = spec["status"]
            current_item["version"] = current_item.get("version", "")
            current_item["total"] = -1
            current_total = -1
        if current_total == -1:
            merged_order[index] = key
        elif current_total > 0 and duplicate_total <= 0:
            merged_order[index] = key
        elif duplicate_total <= 0 and current_total == 0:
            current_spec = _spec_details.get((key[0], _mode_alias(key[1]), current_item.get("version", "")))
            duplicate_spec = _spec_details.get((duplicate[0], _mode_alias(duplicate[1]), duplicate_item.get("version", "")))
            if current_spec and not duplicate_spec:
                merged_order[index] = key
        elif duplicate_item.get("failed", 0) == 0 and current_item.get("failed", 0) > 0:
            merged_order[index] = key

    rows = []
    # Detailed summaries may still contain a zero-count alias duplicate of a
    # spec row. Keep the record with real case counts for each engine/mode.
    detailed_best = {}
    for key in merged_order:
        item = summaries[key]
        identity = (key[0], _mode_alias(key[1]))
        candidate = (item.get("total", 0), item.get("failed", 0), key)
        if identity not in detailed_best or candidate[:2] > detailed_best[identity][:2]:
            detailed_best[identity] = candidate
    merged_order = [candidate[2] for candidate in detailed_best.values()]
    merged_order.sort(key=lambda key: (_natural_key(key[0]), _mode_key(key[1])))
    for key in merged_order:
        engine, mode = key
        item = summaries[key]
        spec = _spec_details.get((engine, _mode_alias(mode), item.get("version", "")))
        mode = spec["mode"] if spec else display_modes.get(key, mode)
        status = item.get("status")
        if not status:
            status = "[FAILED]" if item.get("failed", 0) > 0 else "[PASSED]" if item.get("passed", 0) > 0 else "[SKIPPED]"

        failed_desc = first_failed.get(key, "-")
        # Ultimate fallback: if we have failures but no description, synthesize one from context
        if failed_desc == "-" and item.get("failed", 0) > 0:
            failed_desc = "UI点击/基准测试/一致性失败 (详见报告)"
        if failed_desc == "-" and status == "[SKIPPED]":
            failed_desc = first_skipped.get(key) or first_skipped.get((engine, "")) \
                or engine_skip_reasons.get(engine) or report_skip_reasons.get(key) or "未执行测试"

        version = item.get("version", "")
        # Final cleanup: ensure Type is pure engine name, Version is separate
        if " " in engine or "v" in engine.lower():
            # e.g. "mysql v5.7.44" -> engine="mysql", version="5.7.44"
            match = re.match(r"([A-Za-z0-9_-]+?)\s*(?:v)?([0-9].+?)?$", engine.strip())
            if match:
                engine = match.group(1)
                if match.group(2) and not version:
                    version = match.group(2).strip()

        rows.append("|".join((
            engine,
            str(item.get("passed", 0)),
            str(item.get("failed", 0)),
            str(item.get("skipped", 0)),
            version,
            mode,
            failed_desc,
            status,
        )))
    return "\n".join(rows)


def main(argv):
    if len(argv) == 4 and argv[1] == "--summary":
        compact_rows, full_rows = argv[2], argv[3]
        modes = [mode for mode in compact_rows.split(";") if mode]
        counts = {"[PASSED]": 0, "[FAILED]": 0, "[SKIPPED]": 0}
        details = full_rows.splitlines()
        for mode in modes:
            status = mode.rsplit("|", 1)[-1]
            if status in counts:
                counts[status] += 1
        totals = [0, 0, 0]
        for row in details:
            fields = row.split("|")
            if len(fields) >= 8 and all(field.isdigit() for field in fields[1:4]):
                totals = [total + int(field) for total, field in zip(totals, fields[1:4])]
        print(f"共 {len(modes)} 个模式：通过 {counts['[PASSED]']}，失败 {counts['[FAILED]']}，"
              f"跳过 {counts['[SKIPPED]']}；用例 Pass|Fail|Skip = {totals[0]}|{totals[1]}|{totals[2]}")
        return 0
    if len(argv) == 2 and argv[1] == "--skip-reasons":
        print(parse_click_skip_reasons(sys.stdin.read()), end="")
        return 0
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