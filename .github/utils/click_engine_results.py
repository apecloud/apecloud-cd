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
SAFE_RE = re.compile(r"^[\w./|;\[\]-]*$")
_VERSION_RE = re.compile(r"v?\d+(?:\.\d+)+")

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
    compact = re.sub(r"\s+", "", spec)
    matched = re.match(r"^(.*?)/(?:[^/]+/)*?(" + _VERSION_RE.pattern + r")$", compact)
    if not matched:
        return _clean_mode(compact), ""
    return _clean_mode(matched.group(1)), matched.group(2)


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
    done_exit = {}
    versions = {}
    specs = {}
    hold = False

    def add_planned(engine):
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
        spec = SPEC_RE.match(line)
        if spec and not line[:1].isdigit():
            engine, spec_text, result = spec.group(1), spec.group(2), spec.group(3)
            # Ignore the discovery list and other prose; spec rows have no timestamp.
            if engine in seen or engine in started:
                specs.setdefault(engine, []).append((_split_spec(spec_text), result))
            continue
        if "环境不可用" in line and "跳过剩余" in line:
            hold = True
        elif "不再启动新引擎" in line:
            hold = True

    rows = []
    for engine in planned:
        spec_rows = specs.get(engine) or []
        if spec_rows and engine not in watchdog:
            exit_code = done_exit.get(engine)
            for (mode, spec_version), result in spec_rows:
                version = spec_version or versions.get(engine, "")
                rows.append(f"{_label(engine, mode, version)}|[{_mode_status(result, exit_code)}]")
            continue
        if engine in watchdog:
            status = "FAILED"
        elif engine in done_exit:
            status = "PASSED" if done_exit[engine] == 0 else "FAILED"
        elif engine not in started and hold:
            status = "SKIPPED"
        else:
            # Started, or planned and the pod ended without a DONE line.
            if engine not in started and engine not in done_exit and not specs.get(engine):
                status = "FAILED"
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


def main(argv):
    if len(argv) == 3 and argv[1] == "--group":
        for name, rows in group_click_rows(argv[2]):
            print(f"{name}\t{rows}")
        return 0
    if len(argv) != 2:
        print("usage: click_engine_results.py <pod-log>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8", errors="replace") as handle:
        print(parse_click_engines(handle.read()))
    return 0


def _check():
    mysql = """
plan:
  - mysql slots=2 modes=replication,standalone
START mysql pid=327 slots=2/4 active_slots=2/8
mysql                            主备/8.0.46                        PASSED     0
mysql                            单机/8.0.46                        PASSED     0
PLAYWRIGHT TEST SUCCESS!
DONE mysql (2 mode(s)) ver=8.0.46 exit=0 total=27 pass=23 fail=0 skip=4
"""
    many = """
plan:
  - mysql slots=2 modes=replication,standalone
  - postgresql slots=2 modes=standalone
  - redis slots=1 modes=standalone
  - kafka slots=1 modes=default
START mysql pid=1 slots=2/2 active_slots=2/8
START postgresql pid=2 slots=2/2 active_slots=4/8
mysql                            主备/8.0.46                        PASSED     0
postgresql                       单机/16.2                          FAILED     1
DONE mysql (1 mode(s)) ver=8.0.46 exit=0 total=27 pass=23 fail=0 skip=4
DONE postgresql (1 mode(s)) ver=16.2 exit=1 total=10 pass=1 fail=2 skip=0
环境不可用：跳过剩余 1 个引擎
WATCHDOG DONE kafka killed after 99s (0 combo(s) recorded, 1 timeout)
"""
    assert parse_click_engines(mysql) == (
        "mysql/主备/8.0.46|[PASSED];mysql/单机/8.0.46|[PASSED]"
    )
    assert parse_click_engines(many) == (
        "mysql/主备/8.0.46|[PASSED];postgresql/单机/16.2|[FAILED];redis|[SKIPPED];kafka|[FAILED]"
    )
    polardb = """
plan:
  - polardb-pg slots=4 modes=replication,standalone
START polardb-pg pid=9
polardb-pg                       主备 / pg/2.0.16                   PASSED     2
polardb-pg                       单机 / pg/2.0.16                   PASSED     2
DONE polardb-pg (2 mode(s)) ver=2.0.16 exit=0 total=12 pass=7 fail=0 skip=3
"""
    hive = """
plan:
  - hive slots=33 modes=default
START hive pid=1
hive                             集群版                              NO-RUN     0
DONE hive (1 mode(s)) ver= exit=2 total=1 pass=0 fail=0 skip=1
"""
    kafka = """
plan:
  - kafka slots=13 modes=combined,zookeeper-mode
START kafka pid=1
kafka                            组合/3.9.0                         FAILED     0
kafka                            Zookeeper模式/2.8.2                FAILED     0
DONE kafka (2 mode(s)) ver=2.8.2 exit=1 total=28 pass=22 fail=1 skip=5
"""
    assert parse_click_engines(polardb) == (
        "polardb-pg/主备/2.0.16|[PASSED];polardb-pg/单机/2.0.16|[PASSED]"
    )
    assert parse_click_engines(hive) == "hive/集群版|[FAILED]"
    assert parse_click_engines(kafka) == (
        "kafka/组合/3.9.0|[FAILED];kafka/Zookeeper模式/2.8.2|[FAILED]"
    )
    assert parse_click_engines("DONE $(rm -rf) (1 mode(s)) ver=1 exit=0\n") == ""
    assert parse_click_engines("") == ""
    # A spec line before the engine is planned must not invent a row.
    assert parse_click_engines("notanengine spec PASSED 0\n") == ""
    grouped = group_click_rows(
        "mysql/8.0.46|[PASSED];redis|[FAILED];minio|[PASSED];greatsql|[FAILED]"
    )
    assert grouped == [
        ("Relational", "mysql/8.0.46|[PASSED]"),
        ("NoSQL", "redis|[FAILED]"),
        ("Storage", "minio|[PASSED]"),
        ("Other", "greatsql|[FAILED]"),
    ]
    assert group_click_rows("oracle/主备/19.3.0|[FAILED];oracle/单机/19.3.0|[PASSED]") == [
        ("Relational", "oracle/主备/19.3.0|[FAILED];oracle/单机/19.3.0|[PASSED]"),
    ]
    assert sum(len(members) for _name, members in ENGINE_GROUPS) == 44
    assert group_click_rows("") == []
    print("ok")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        _check()
    else:
        sys.exit(main(sys.argv))
