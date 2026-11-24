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
    r".*\[([^/\]]+)/([^\]]+)\].*?总计\s*(\d+)\s+通过\s*(\d+)\s+"
    r"失败\s*(\d+)\s+异常\s*(\d+)\s+跳过\s*(\d+)"
)
REPORT_HEADER_RE = re.compile(
    r"^([A-Za-z0-9_.-]+)/([^/\s]+)/([^\s]+)\s+failed=(\d+)"
)
REPORT_CASE_RE = re.compile(
    r"^\s+(TC-[^|]+?)\s*\|\s*[^|]+\|\s*(.+?)\s*\|\s*(FAIL|BROKEN)\s*$"
)

# Enhanced failure patterns to catch current test output (Playwright + Chinese UI tests)
INLINE_SAVE_FAIL_RE = re.compile(r"_inline_save:.*确认按钮常规点击失败")
BUTTON_FAIL_RE = re.compile(r"确认按钮.*(?:点击|常规).*失败|翻页失败|inline_save.*失败")
TC_SKIP_RE = re.compile(r"(TC-[A-Z0-9-]+)\s*[⏭️⚠️❌]\s*(.+)")
FAILURE_STEP_RE = re.compile(r"\[(.*?)\]\s*✅.*?(?:❌(\d+)|失败|error|异常).*?(?:$|WARNING)", re.IGNORECASE)
BENCHMARK_FAIL_RE = re.compile(r"\[14\.\s*基准测试\].*?❌(\d+)")
GENERAL_FAIL_RE = re.compile(r"(?:失败|error|FAILED|❌|异常|WARNING.*失败|点击失败).*?([^\n]{10,80}?)", re.IGNORECASE)

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


def extract_first_failed_case(line: str, engine: str = "", mode: str = "") -> str | None:
    """Extract the most meaningful first failed case description from a line.
    Prioritizes specificity and keeps description under ~80 chars for Feishu card.
    """
    line = line.strip()

    # 1. Legacy TC- FAIL format (highest priority, backward compatible)
    case = REPORT_CASE_RE.match(line)
    if case:
        case_id, name, _status = case.groups()
        return f"{case_id.strip()}: {name.strip()[:60]}"

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
    current_report = None
    last_engine_mode = None  # track current context for better fallback

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
            last_engine_mode = key
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
            last_engine_mode = key
            continue

        # Try to extract first failed case using comprehensive matcher
        engine_ctx = last_engine_mode[0] if last_engine_mode else ""
        mode_ctx = last_engine_mode[1] if last_engine_mode else ""
        failed_case = extract_first_failed_case(line, engine_ctx, mode_ctx)

        if failed_case:
            key = last_engine_mode or current_report
            if key and key not in first_failed:
                first_failed[key] = failed_case[:80]  # safety limit for Feishu
                # Once we have one per engine/mode, we can stop collecting more for it
                continue

        case = REPORT_CASE_RE.match(line)
        if case and current_report and current_report not in first_failed:
            case_id, name, _status = case.groups()
            first_failed[current_report] = f"{case_id.strip()}: {name.strip()[:60]}"

    for label in parse_click_engines(text).split(";"):
        if not label or "|" not in label:
            continue
        engine_mode, status = label.split("|", 1)
        parts = engine_mode.split("/")
        # Clean split: Type = pure engine (mysql/postgresql), Version = version number
        raw_label = parts[0].strip()
        engine = raw_label.lower()
        version = ""

        # Extract version from "mysql v5.7.44", "postgresql v12.22.0", etc.
        ver_match = re.search(r"(?:^|[\s/])([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-.][A-Za-z0-9]+)?)", raw_label)
        if ver_match:
            version = ver_match.group(1)
            # Remove version from engine name
            engine = re.sub(r"\s*v?[0-9].*?$", "", raw_label).strip().lower()

        # Mode from remaining parts
        mode = ""
        if len(parts) > 1:
            for p in parts[1:]:
                p_clean = p.strip()
                if not p_clean:
                    continue
                if not version and (_VERSION_RE.fullmatch(p_clean) or (p_clean.startswith("v") and _VERSION_RE.fullmatch(p_clean[1:]))):
                    version = p_clean
                    continue
                if not mode:
                    mode = MODE_ALIASES.get(p_clean, p_clean)
                else:
                    mode += f"/{MODE_ALIASES.get(p_clean, p_clean)}"

        key = (engine, mode)
        item = summaries.setdefault(key, {
            "total": 0, "passed": 0, "failed": 0, "skipped": 0,
            "version": version,
        })
        item["version"] = item.get("version") or version
        if not item.get("total"):
            item["status"] = status
        if key not in order:
            order.append(key)

    # Final pass: ensure every failed test has a meaningful first_failed description
    for key in list(first_failed.keys()):
        if key not in summaries:
            summaries[key] = {"failed": 1}

    rows = []
    for key in order:
        engine, mode = key
        item = summaries[key]
        status = item.get("status")
        if not status:
            status = "[FAILED]" if item.get("failed", 0) > 0 else "[PASSED]" if item.get("passed", 0) > 0 else "[SKIPPED]"

        failed_desc = first_failed.get(key, "-")
        # Ultimate fallback: if we have failures but no description, synthesize one from context
        if failed_desc == "-" and item.get("failed", 0) > 0:
            failed_desc = f"UI点击/基准测试/一致性失败 (详见报告)"

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