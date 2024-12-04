#!/usr/bin/env bash


TEST_RESULT_MD_DIR=${1:-""}

get_test_period() {
    test_period=$(python3 -c "
from datetime import datetime, timedelta
fmt = '%b %d, %Y'
today = datetime.today()
begin_date = today - timedelta(days=15)
print(f'{begin_date.strftime(fmt)} - {today.strftime(fmt)}')
")
    TEST_PERIOD="$test_period"
    echo "test period: $TEST_PERIOD"

    test_period_cn=$(python3 -c "
import locale
from datetime import datetime, timedelta
locale.setlocale(locale.LC_TIME, 'zh_CN.UTF-8')
fmt = '%Y年%m月%d日'
today = datetime.today()
begin_date = today - timedelta(days=15)
print(f'{begin_date.strftime(fmt)} - {today.strftime(fmt)}')
")
    TEST_PERIOD_CN="$test_period_cn"
    echo "test period（CN）: $TEST_PERIOD_CN"
}

set_test_period() {
    for md_file in $(find "${TEST_RESULT_MD_DIR}" -name "*.md" | (grep -v "html" || true)); do
        if [[ "$UNAME" == "Darwin" ]]; then
            sed -i '' "s/^<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">Test Period:.*/<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">Test Period: ${TEST_PERIOD}<\/span><\/center>/" "${md_file}"
            sed -i '' "s/^<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">测试时间:.*/<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">测试时间: ${TEST_PERIOD_CN}<\/span><\/center>/" "${md_file}"
        else
            sed -i "s/^<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">Test Period:.*/<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">Test Period: ${TEST_PERIOD}<\/span><\/center>/" "${md_file}"
            sed -i "s/^<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">测试时间:.*/<center><span style=\"font-size: 36px; line-height: 2; letter-spacing: 2px; text-align: center;\">测试时间: ${TEST_PERIOD_CN}<\/span><\/center>/" "${md_file}"
        fi
    done
}

main() {
    if [[ -z "${TEST_RESULT_MD_DIR}" || ! -d "${TEST_RESULT_MD_DIR}" ]]; then
        echo "Usage: $0 <test_result_md_dir>"
        return
    fi
    local TEST_PERIOD=""
    local TEST_PERIOD_CN=""
    local UNAME="$(uname -s)"

    get_test_period

    set_test_period
}

main "$@"
