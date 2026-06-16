#!/usr/bin/env python3
"""Generate test job YAML snippets for kubeblocks-e2e-test.yml.

Usage:
    python3 generate_engine_jobs.py <engine> <test-type> <version1,version2,...> [options]

Options:
    --needs JOB1,JOB2     Comma-separated prerequisite jobs (default: terraform-init-k8s,test-kubeblocks)
    --topology TOPO       Add --topology flag (e.g. combined_monitor, distribution)
    --replicas N          Add --replicas flag
    --output FILE         Write to file instead of stdout

Examples:
    python3 generate_engine_jobs.py clickhouse 29 25,24,22
    python3 generate_engine_jobs.py kafka-broker 7 3.9.0,3.8.1 --topology broker
    python3 generate_engine_jobs.py oceanbase-ent 44 4.2 --topology distribution --replicas 3
"""

import argparse
import sys


def sanitize_job_id(version: str) -> str:
    """Convert version to job-id suffix: dots -> hyphens."""
    return version.replace('.', '-')


def job_yaml(engine: str, test_type: str, version: str, needs: list[str], topology: str | None, replicas: int | None) -> str:
    ver_sanitized = sanitize_job_id(version)
    job_id = f"test-{engine}-{ver_sanitized}"
    test_type_name = f"{engine}-{ver_sanitized}"
    args = f"--service-version {version}"
    if topology:
        args += f" --topology {topology}"
    if replicas is not None:
        args += f" --replicas {replicas}"
    args += " ${{ inputs.ARGS }}"

    # Build condition
    # If engine has a hyphen and the last part looks like a version, the base engine is whatever the user passed
    condition_engine = engine
    negation = f"! contains(inputs.TEST_TYPE, '-{condition_engine}')"
    if "|" in condition_engine or condition_engine.endswith("-"):
        negation = ""
    cond = (
        f"${{{{ needs.terraform-init-k8s.result == 'success' && always() && "
        f"(inputs.TEST_TYPE == '' || contains(inputs.TEST_TYPE, '{condition_engine}|') || endsWith(inputs.TEST_TYPE, '{condition_engine}'))"
    )
    if negation:
        cond += f" && {negation}"
    cond += " }}"

    needs_str = ", ".join(needs)

    yaml_block = f"""  {job_id}:
    if: {cond}
    needs: [ {needs_str} ]
    uses: ./.github/workflows/kbcli-test.yml
    with:
      cloud-provider: ${{{{ inputs.CLOUD_PROVIDER }}}}
      region: ${{{{ inputs.REGION }}}}
      release-version: "${{{{ inputs.KB_VERSION }}}}"
      test-type: "{test_type}"
      test-type-name: "{test_type_name}"
      test-args: "{args}"
      k8s-cluster-name: ${{{{ needs.terraform-init-k8s.outputs.k8s-cluster-name }}}}
      artifact-name: cicd-${{{{ inputs.CLOUD_PROVIDER }}}}-${{{{ github.sha }}}}
      branch-name: ${{{{ inputs.BRANCH_NAME }}}}
      random-suffix: ${{{{ needs.test-kubeblocks.outputs.random-suffix }}}}
    secrets: inherit
"""
    return yaml_block


def send_message_yaml(engine: str, job_ids: list[str], condition_filter: str) -> str:
    """Generate a send-message job snippet."""
    needs_str = ", ".join(job_ids)
    lines = []
    for jid in job_ids:
        name = jid.replace("test-", "")
        lines.append(f'            TEST_RESULT+="##{name}|${{{{ needs.{jid}.outputs.test-result }}}}"')
        lines.append(f'            cmd="${{cmd_head}} \\"${{{{ needs.{jid}.outputs.test-result-report }}}}\\" "')
        lines.append(f'            TEST_RESULT+=$(eval "$cmd")')

    body = "\n".join(lines)

    yaml_block = f"""  send-message-{engine}:
    if: ${{{{ always() && (inputs.TEST_TYPE == '' || {condition_filter}) }}}}
    runs-on: ubuntu-latest
    outputs:
      test-date: ${{{{ steps.upload_test_result.outputs.test-date }}}}
    needs: [ {needs_str} ]
    steps:
      - uses: actions/checkout@v4
        with:
          repository: apecloud/apecloud-cd
          path: ./
          ref: ${{{{ inputs.APECD_REF }}}}

      - name: send message
        run: |
          TEST_TYPE="${{{{ inputs.TEST_TYPE }}}}"
          cmd_head="bash .github/utils/utils.sh --type 36 --test-result "
          TEST_RESULT=""
{body}

          TEST_RESULT=$( bash .github/utils/utils.sh --type 12 \\
            --github-repo "${{{{ github.repository }}}}" \\
            --github-token "${{{{ env.GITHUB_TOKEN }}}}" \\
            --test-result "${{TEST_RESULT}}" \\
            --run-id "$GITHUB_RUN_ID" )

          export TZ='Asia/Shanghai'
          date_ret=$(date +%Y-%m-%d-%T)
          test_title="[${{{{ inputs.KB_VERSION }}}}] KubeBlocks Test All Versions on ${{{{ inputs.CLOUD_PROVIDER }}}}:${{{{ inputs.CLUSTER_VERSION }}}}:${{{{ inputs.INSTANCE_TYPE }}}} [${{date_ret}}]"

          echo $TEST_RESULT
          python3 .github/utils/send_mesage.py \\
            --send-type kbcli \\
            --url "${{{{ vars.TEST_BOT_WEBHOOK }}}}" \\
            --title "$test_title" \\
            --result "$TEST_RESULT"

      - name: Setup ossutil
        if: ${{{{ ! contains(inputs.ARGS, 'only-kubectl') }}}}
        uses: manyuanrong/setup-ossutil@v2.0
        with:
          access-key-id: "${{{{ env.OSS_KEY_ID }}}}"
          access-key-secret: "${{{{ env.OSS_KEY_SECRET }}}}"
          endpoint: "${{{{ env.OSS_ENDPOINT }}}}"

      - name: Upload test result log to oss
        if: ${{{{ ! contains(inputs.ARGS, 'only-kubectl') }}}}
        id: upload_test_result
        run: |
          export TZ='Asia/Shanghai'
          TEST_DATE="$(date +%Y%m%d)"
          echo test-date=${{TEST_DATE}} >> $GITHUB_OUTPUT

          KUBEBLOCKS_VERSION="${{{{ inputs.KB_VERSION }}}}"
          OSS_DIR="oss://${{{{ env.OSS_BUCKET }}}}/reports/kubeblocks/${{KUBEBLOCKS_VERSION}}/${{TEST_DATE}}"
          upload_file_name="TEST_RESULT_LOGS.txt"

          for i in $(seq 1 3); do
              ossutil cp -rf "${{OSS_DIR}}/${{upload_file_name}}" ./
              download_ret=$?
              if [[ $download_ret -eq 0 ]]; then
                  break
              fi
              sleep 1
          done

          test_result_report_output_file_log="test-result-report-output.log"
          if [[ -f ${{test_result_report_output_file_log}} ]]; then
              cat ${{test_result_report_output_file_log}}
              if [[ ! -f ${{upload_file_name}} ]]; then
                  touch ${{upload_file_name}}
              else
                  echo "" >> ${{upload_file_name}}
              fi
              cat ${{test_result_report_output_file_log}} >> ${{upload_file_name}}

              for i in $(seq 1 3); do
                  ossutil cp -rf "${{upload_file_name}}" "${{OSS_DIR}}/${{upload_file_name}}"
                  upload_ret=$?
                  if [[ $upload_ret -eq 0 ]]; then
                      echo "$(tput -T xterm setaf 2)upload ${{upload_file_name}} to oss successfully$(tput -T xterm sgr0)"
                      break
                  else
                      echo "$(tput -T xterm setaf 3)::warning title=upload ${{upload_file_name}} to oss failure$(tput -T xterm sgr0)"
                  fi
                  sleep 1
              done
          fi

      - name: send message
        if: ${{{{ ! contains(inputs.ARGS, 'only-kubectl') }}}}
        run: |
          TEST_DATE=${{{{ steps.upload_test_result.outputs.test-date }}}}
          KUBEBLOCKS_VERSION="${{{{ inputs.KB_VERSION }}}}"
          OSS_URL="https://${{{{ env.OSS_BUCKET }}}}.${{{{ env.OSS_ENDPOINT }}}}/reports/kubeblocks/${{KUBEBLOCKS_VERSION}}/${{TEST_DATE}}"
          test_result_file_name="TEST_RESULT_LOGS.txt"
          TEST_RESULT="${{test_result_file_name}}|${{OSS_URL}}/${{test_result_file_name}}"

          REPORT_BOT_WEBHOOK="${{{{ vars.REPORT_BOT_WEBHOOP }}}}"
          test_title="[${{KUBEBLOCKS_VERSION}}] KubeBlocks Test All Versions Report on ${{{{ inputs.CLOUD_PROVIDER }}}}:${{{{ inputs.CLUSTER_VERSION }}}}:${{{{ inputs.INSTANCE_TYPE }}}} [${{TEST_DATE}}]"
          python3 .github/utils/send_mesage.py \\
              --url "${{REPORT_BOT_WEBHOOK}}" \\
              --title "$test_title" \\
              --result "$TEST_RESULT" \\
              --send-type "report"
"""
    return yaml_block


def main():
    parser = argparse.ArgumentParser(description="Generate KubeBlocks E2E test job YAML")
    parser.add_argument("engine", help="Engine name (e.g. clickhouse, redis-cluster)")
    parser.add_argument("test_type", help="Numeric test-type for kbcli-test")
    parser.add_argument("versions", help="Comma-separated versions")
    parser.add_argument("--needs", default="terraform-init-k8s,test-kubeblocks",
                        help="Comma-separated prerequisite jobs")
    parser.add_argument("--topology", default=None, help="Topology name if applicable")
    parser.add_argument("--replicas", type=int, default=None, help="Replica count if applicable")
    parser.add_argument("--output", default=None, help="Output file path")
    parser.add_argument("--send-message", action="store_true",
                        help="Also generate a matching send-message job")
    parser.add_argument("--condition-filter", default=None,
                        help="Filter expression for send-message if condition")
    args = parser.parse_args()

    needs = [n.strip() for n in args.needs.split(",")]
    versions = [v.strip() for v in args.versions.split(",")]

    out = []
    job_ids = []
    for ver in versions:
        block = job_yaml(args.engine, args.test_type, ver, needs, args.topology, args.replicas)
        out.append(block)
        job_ids.append(f"test-{args.engine}-{sanitize_job_id(ver)}")

    if args.send_message:
        if not args.condition_filter:
            args.condition_filter = f"contains(inputs.TEST_TYPE, '{args.engine}')"
        out.append(send_message_yaml(args.engine, job_ids, args.condition_filter))

    result = "\n".join(out)

    if args.output:
        with open(args.output, "w") as f:
            f.write(result)
        print(f"Written to {args.output}")
    else:
        print(result)


if __name__ == "__main__":
    main()
