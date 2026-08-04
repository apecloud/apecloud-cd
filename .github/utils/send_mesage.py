#!/usr/bin/env python
# -*- coding:utf-8 -*-
import argparse
import requests
import json
import os
import re
import time


def parse_cli_args():
    parser = argparse.ArgumentParser(description='Send test result message')
    parser.add_argument('--title', '-t', help='test title', default="")
    parser.add_argument('--result', '-r', help='test result', default="")
    parser.add_argument('--url', '-u', help='webhook url', default="")
    parser.add_argument('--job-url', '-ju', help='github job url', default="")
    parser.add_argument('--send-type', '-st', help='test type', default="")
    return parser.parse_args()


def remove_ansi_escape_sequences(text):
    ansi_escape = re.compile(r'\x1B[@-_][0-?]*[ -/]*[@-~]')
    return ansi_escape.sub('', text)


def colorize_status(status_str):
    if "[PASSED]" in status_str:
        status_str = status_str.replace(f"[PASSED]", f"<font color='green'>[PASSED]</font>")
    elif "[FAILED]" in status_str:
        status_str = status_str.replace(f"[FAILED]", f"<font color='red'>[FAILED]</font>")
    else:
        pattern = r'(\d+)(Passed|Failed)'
        matches = re.findall(pattern, status_str)
        for match in matches:
            count, status = match
            if status == 'Passed':
                status_str = status_str.replace(f"{count}Passed", f"<font color='green'>{count}Passed</font>")
            elif status == 'Failed':
                status_str = status_str.replace(f"{count}Failed", f"<font color='red'>{count}Failed</font>")
    return status_str


def get_status_str_color(status_str):
    status_str = remove_ansi_escape_sequences(status_str)
    if "SUCCESS!" in status_str or "Passed" in status_str:
        status_str = status_str.replace(f"" + status_str + "",
                                        f"<font color='green'>" + status_str + "</font>")
    elif "FAIL!" in status_str or "Failed" in status_str:
        status_str = status_str.replace(f"" + status_str + "",
                                        f"<font color='red'>" + status_str + "</font>")
    elif "Pending" in status_str:
        status_str = status_str.replace(f"" + status_str + "",
                                        f"<font color='orange'>" + status_str + "</font>")
    elif "Skipped" in status_str:
        status_str = status_str.replace(f"" + status_str + "",
                                        f"<font color='blue'>" + status_str + "</font>")
    else:
        status_str = status_str.replace(f"" + status_str + "",
                                        f"<font color='grey'>" + status_str + "</font>")
    return status_str


def colorize_ginkgo_status(status_rets):
    status_str_ret = ""
    for i in range(len(status_rets)):
        status_str = status_rets[i]
        if "FAIL! --" in status_str or "SUCCESS! --" in status_str:
            status_strs = status_str.split("--")
            status_str_head = get_status_str_color(status_strs[0])
            status_str_end = get_status_str_color(status_strs[-1])
            status_str = status_str_head + "--" + status_str_end
        elif "Passed" in status_str or "Failed" in status_str or "Pending" in status_str or "Skipped" in status_str:
            status_str = get_status_str_color(status_str)
        else:
            continue
        if status_str_ret == "":
            status_str_ret = status_str
        else:
            status_str_ret = status_str_ret + "|" + status_str
    return status_str_ret


def send_message(url_v, result_v, title_v):
    print("send message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Test Type**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Test Result**",
                        "text_align": "center"
                    }
                ]
            }
        ]
    }
    json_results.append(json_ret)

    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                ret = results.split("|")
                if len(ret) < 3:
                    continue
                ret_4 = colorize_status(ret[1])
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[2] + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": ret_4,
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "blue",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_performance_message(url_v, result_v, title_v, job_url_v):
    print("send performance message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**THREADS**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**QPS**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**TPS**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Latency(ms)**",
                        "text_align": "center"
                    }
                ]
            }
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                ret = results.split("#")
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + job_url_v + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='green'>" + ret[1] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='green'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='green'>" + ret[3] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "blue",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_report_message(url_v, result_v, title_v):
    print("send report message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Report File**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 3,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Download Url**",
                        "text_align": "left"
                    }
                ]
            },
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                ret = results.split("|")
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='orange'>" + ret[0] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 3,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[1] + "'>" + ret[1] + "</a>",
                                    "text_align": "left"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "orange",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_e2e_message(url_v, result_v, title_v):
    print("Sending message to Feishu bot...")
    headers = {"Content-Type": "application/json"}
    test_type, passed, failed, pending, skipped = parse_result(result_v)
    message = {
        "msg_type": "interactive",
        "card": {
            "config": {
                "wide_screen_mode": True
            },
            "header": {
                "title": {
                    "tag": "plain_text",
                    "content": title_v
                },
                "template": "blue"
            },
            "elements": [
                {
                    "tag": "div",
                    "text": {
                        "tag": "lark_md",
                        "content": f"Test Type: [{test_type}]({url_v})"
                    }
                },
                {
                    "tag": "div",
                    "fields": [
                        {
                            "is_short": True,
                            "text": {
                                "tag": "lark_md",
                                "content": f"**Test Result:**\n:green_circle: {passed}\n:red_circle: {failed}\n:yellow_circle: {pending}\n:blue_circle: {skipped}"
                            }
                        }
                    ]
                }
            ]
        }
    }
    response = requests.post(url, headers=headers, json=message)
    print(response.text)


def send_installer_message(url_v, result_v, title_v):
    print("send message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 2,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Test Type**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**K8s Version**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Test Result**",
                        "text_align": "center"
                    }
                ]
            }
        ]
    }
    json_results.append(json_ret)

    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                ret = results.split("|")
                ret_4 = colorize_status(ret[2])

                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 2,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[-1] + "'>" + ret[1] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='orange'>" + ret[0] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": ret_4,
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "blue",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_ginkgo_message(url_v, result_v, title_v):
    print("send message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Test Type**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 2,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Test Result**",
                        "text_align": "center"
                    }
                ]
            }
        ]
    }
    json_results.append(json_ret)

    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                ret = results.split("|")
                if len(ret) < 2:
                    continue
                if "FAIL! --" in results or "SUCCESS! --" in results:
                    ret_4 = colorize_ginkgo_status(ret)
                else:
                    ret_4 = colorize_status(ret[1])
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[-1] + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 2,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": ret_4,
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "blue",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_summary_message(url_v, result_v, title_v):
    print("send report message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**API Type**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Total**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Covered**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Coverage**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Deprecated**",
                        "text_align": "center"
                    }
                ]
            },
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                ret = results.split("|")
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[5] + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='orange'>" + ret[1] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='green'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='red'>" + ret[3] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='gray'>" + ret[4] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "orange",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_engine_summary_message(url_v, result_v, title_v):
    print("send report message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Engine**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Mode**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Version**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Operations**",
                        "text_align": "center"
                    }
                ]
            },
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                summary_color = "red"
                if "(100.0%)" in results:
                    summary_color = "green"

                ret = results.split("|")
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[5] + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[1] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[5] + "'>" + ret[3] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "orange",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_engine_summary_message2(url_v, result_v, title_v):
    print("send report message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Engine**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Mode**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Version**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Operations**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Fail Ops**",
                        "text_align": "center"
                    }
                ]
            },
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        for results in result_array:
            if results:
                summary_color = "red"
                if "(100.0%)" in results:
                    summary_color = "green"

                ret = results.split("|")
                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[6] + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[1] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[6] + "'>" + ret[3] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='red'>" + ret[4] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "orange",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_trivy_scan_message(url_v, result_v, title_v):
    print("send report message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 2,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Item**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 5,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Image**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Critical**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**High**",
                        "text_align": "center"
                    }
                ]
            },
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        item_name = ""
        for results in result_array:
            if results:
                ret = results.split("|")
                item_name_tmp = ret[0]
                if item_name == "" or item_name != item_name_tmp:
                    item_name = item_name_tmp
                else:
                    item_name_tmp = " "

                critical_color = "red"
                if ret[2] == "0":
                    critical_color = "green"

                high_color = "red"
                if ret[3] == "0":
                    high_color = "green"

                image_color = "orange"
                if ret[2] == "0" and ret[3] == "0":
                    image_color = "green"

                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 2,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[4] + "'>" + item_name_tmp + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 5,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + image_color + "'>" + ret[1] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + critical_color + "'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + high_color + "'>" + ret[3] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "orange",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def send_check_addon_version_message(url_v, result_v, title_v):
    print("send report message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Addon**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 4,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Image**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Comm.**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Ent.**",
                        "text_align": "center"
                    }
                ]
            },
        ]
    }
    json_results.append(json_ret)
    if result_v:
        result_array = result_v.split("##")
        item_name = ""
        for results in result_array:
            if results:
                ret = results.split("|")
                item_name_tmp = ret[0]
                if item_name == "" or item_name != item_name_tmp:
                    item_name = item_name_tmp
                else:
                    item_name_tmp = " "

                critical_color = "red"
                if ret[2] == "T":
                    critical_color = "green"

                high_color = "red"
                if ret[3] == "T":
                    high_color = "green"

                image_color = "red"
                if ret[2] == "T" or ret[3] == "T":
                    image_color = "green"

                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[4] + "'>" + item_name_tmp + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 4,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + image_color + "'>" + ret[1] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + critical_color + "'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "center",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + high_color + "'>" + ret[3] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "orange",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)


def _natural_name_key(item):
    name = item.split("|", 1)[0]
    # Put install-kubeblocks at the top, then natural sort for the rest
    priority = 0 if name.lower().startswith("install-kubeblocks") else 1
    return (priority, re.sub(r'(\d+)', lambda m: m.group(1).zfill(8), name).lower())


def send_kbcli_message(url_v, result_v, title_v):
    print("send message")
    json_results = []
    json_ret = {
        "tag": "column_set",
        "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Type**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Pass|Fail|Skip**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Version**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Mode**",
                        "text_align": "center"
                    }
                ]
            },
            {
                "tag": "column",
                "width": "weighted",
                "weight": 1,
                "vertical_align": "top",
                "elements": [
                    {
                        "tag": "markdown",
                        "content": "**Failed Ops**",
                        "text_align": "center"
                    }
                ]
            }
        ]
    }
    json_results.append(json_ret)

    if result_v:
        result_array = sorted(
            (r for r in result_v.split("##") if r),
            key=_natural_name_key,
        )
        for results in result_array:
            if results:
                summary_color = "red"
                if "[PASSED]" in results:
                    summary_color = "green"
                ret_tmp = results.split("|")
                if len(ret_tmp) < 8:
                    ret = [ret_tmp[0], ret_tmp[1], "", "", "", "", "", "", ret_tmp[2]]
                else:
                    ret = ret_tmp

                if ret[4] == "":
                    result_status = "<font color='" + summary_color + "'>" + ret[1] + "</font>"
                else:
                    result_status = "<font color='" + summary_color + "'>" + ret[4] + " | " + ret[5] + " | " + ret[6] + "</font>"

                json_ret = {
                    "tag": "column_set",
                    "flex_mode": "none",
                    "background_style": "default",
                    "columns": [
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<a href='" + ret[8] + "'>" + ret[0] + "</a>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": result_status,
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[2] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[3] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        },
                        {
                            "tag": "column",
                            "width": "weighted",
                            "weight": 1,
                            "vertical_align": "top",
                            "elements": [
                                {
                                    "tag": "markdown",
                                    "content": "<font color='" + summary_color + "'>" + ret[7] + "</font>",
                                    "text_align": "center"
                                }
                            ]
                        }
                    ],
                }
                json_results.append(json_ret)

    card = json.dumps({
        "header": {
            "template": "blue",
            "title": {
                "tag": "plain_text",
                "content": title_v
            }
        },
        "elements": json_results
    })
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)

FEISHU_HARD_LIMIT_BYTES = 30_000
FEISHU_TARGET_BYTES = int(os.getenv("FEISHU_TARGET_BYTES", "27000"))
FEISHU_MAX_RETRIES = int(os.getenv("FEISHU_MAX_RETRIES", "3"))


class FeishuSizeError(RuntimeError):
    pass


def _playwright_col(content, weight=1):
    return {
        "tag": "column", "width": "weighted", "weight": weight,
        "vertical_align": "top",
        "elements": [{
            "tag": "markdown", "content": content, "text_align": "center"
        }],
    }


def _playwright_header():
    return {
        "tag": "column_set", "flex_mode": "none",
        "background_style": "grey",
        "columns": [
            _playwright_col("**Engine**", 1),
            _playwright_col("**Test Spec**", 2),
            _playwright_col("**Exec / Effective**", 1),
            _playwright_col("**Fail Ops**", 1),
            _playwright_col("**Report**", 1),
        ],
    }


def _serialize_feishu_card(title, elements):
    # Keep the existing webhook schema (card is a JSON string), but avoid
    # whitespace and ASCII escaping because the 30KB limit applies to body bytes.
    card = json.dumps({
        "header": {
            "template": "blue",
            "title": {"tag": "plain_text", "content": title},
        },
        "elements": elements,
    }, ensure_ascii=False, separators=(",", ":"))
    return json.dumps(
        {"msg_type": "interactive", "card": card},
        ensure_ascii=False,
        separators=(",", ":"),
    )


def _body_size(body):
    return len(body.encode("utf-8"))


def _response_error(response):
    try:
        payload = response.json()
    except ValueError:
        payload = {}
    code = payload.get("code", payload.get("StatusCode", 0))
    message = str(
        payload.get("msg")
        or payload.get("StatusMessage")
        or response.text
        or ""
    )
    if response.status_code >= 400:
        return message or f"HTTP {response.status_code}"
    if code not in (0, "0", None):
        return message or f"Feishu code={code}"
    return ""


def _post_feishu_body(url, body):
    if _body_size(body) >= FEISHU_HARD_LIMIT_BYTES:
        raise FeishuSizeError(
            f"Feishu body is {_body_size(body)} bytes, exceeding 30KB"
        )
    for attempt in range(1, FEISHU_MAX_RETRIES + 1):
        response = requests.post(
            url=url,
            data=body.encode("utf-8"),
            headers={"Content-Type": "application/json; charset=utf-8"},
            timeout=20,
        )
        error = _response_error(response)
        if not error:
            print(response.text)
            return
        if "size limit" in error.lower() or "30kb" in error.lower():
            raise FeishuSizeError(error)
        retryable = response.status_code == 429 or "rate" in error.lower()
        if retryable and attempt < FEISHU_MAX_RETRIES:
            time.sleep(2 ** (attempt - 1))
            continue
        raise RuntimeError(f"Feishu webhook failed: {error}")


def _is_report_url(value):
    return value.startswith(("http://", "https://", "oss://"))


def _is_job_url(value):
    return "github.com" in value or "/actions/runs/" in value


def _safe_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _playwright_row(engine, spec, rate, status, fail_ops, report_url, job_url):
    color = "red" if status == "FAILED" else (
        "orange" if status == "BROKEN" else "green"
    )
    engine_content = (
        f"<a href='{job_url}'>{engine}</a>" if job_url else engine
    )
    report_content = (
        f"<a href='{report_url}'>Report</a>" if report_url else ""
    )
    fail_content = ""
    if fail_ops:
        # A single row must never monopolize a page.
        fail_content = (
            f"<font color='red'>{str(fail_ops)[:500]}</font>"
        )
    return {
        "tag": "column_set", "flex_mode": "none",
        "columns": [
            _playwright_col(engine_content, 1),
            _playwright_col(
                f"<font color='{color}'>{str(spec)[:300]}</font>", 2
            ),
            _playwright_col(
                f"<font color='{color}'>{str(rate)[:80]}</font>", 1
            ),
            _playwright_col(fail_content, 1),
            _playwright_col(report_content, 1),
        ],
    }


def _parse_playwright_rows(result_v, job_url_v=""):
    rows = []
    stripped = result_v.lstrip("###")
    if not stripped:
        return rows

    if "@@@" in stripped:
        blocks = stripped.split("###")
        i = 0
        while i < len(blocks):
            if not blocks[i]:
                i += 1
                continue
            if i + 1 >= len(blocks):
                break
            engine = blocks[i]
            pass_rate = blocks[i + 1]
            i += 2
            job_url = job_url_v or ""
            report_url = ""
            rest = ""
            url_segments = []
            if "@@@" in pass_rate:
                pass_rate, rest = pass_rate.split("@@@", 1)
            else:
                while i < len(blocks):
                    segment = blocks[i]
                    i += 1
                    if "@@@" in segment:
                        prefix, rest = segment.split("@@@", 1)
                        if prefix:
                            url_segments.append(prefix)
                        break
                    url_segments.append(segment)
            for segment in url_segments:
                if _is_job_url(segment):
                    job_url = segment
                elif _is_report_url(segment):
                    report_url = segment
            parts = rest.split("@@@") if rest else ["", ""]
            specs_block = parts[0] if parts else ""
            fail_ops = parts[1] if len(parts) > 1 else ""
            for pair in specs_block.split("##"):
                if not pair:
                    continue
                values = pair.split("|")
                if len(values) < 8:
                    continue
                row_engine, spec, row_rate, status = values[:4]
                fail = values[5]
                broken = _safe_int(values[7])
                blocked = _safe_int(values[8]) if len(values) > 8 else 0
                unsupported = _safe_int(values[9]) if len(values) > 9 else 0
                not_reached = _safe_int(values[10]) if len(values) > 10 else 0
                issue_parts = []
                if _safe_int(fail) > 0 and fail_ops:
                    issue_parts.append(fail_ops)
                if broken:
                    issue_parts.append(f"Broken {broken}")
                if blocked:
                    issue_parts.append(f"Blocked {blocked}")
                if not_reached:
                    issue_parts.append(f"Not reached {not_reached}")
                if unsupported and status != "PASSED":
                    issue_parts.append(f"Unsupported {unsupported}")
                rows.append(_playwright_row(
                    engine=row_engine or engine,
                    spec=spec,
                    rate=row_rate or pass_rate,
                    status=status,
                    fail_ops=" · ".join(issue_parts),
                    report_url=report_url,
                    job_url=job_url,
                ))
    else:
        parts = stripped.split("###")
        if len(parts) % 3 == 0:
            for engine, job_url, specs_block in zip(
                parts[0::3], parts[1::3], parts[2::3]
            ):
                for pair in specs_block.split("##"):
                    if not pair:
                        continue
                    values = pair.split("|", 1)
                    if len(values) != 2:
                        continue
                    spec, test_result = values
                    status = (
                        "FAILED"
                        if "ERROR" in test_result or "FAILED" in test_result
                        else "PASSED"
                    )
                    rows.append(_playwright_row(
                        engine=engine,
                        spec=spec,
                        rate="",
                        status=status,
                        fail_ops=test_result if status == "FAILED" else "",
                        report_url="",
                        job_url=job_url,
                    ))
    return rows


def _paginate_playwright_rows(rows, title, target_bytes=None):
    if target_bytes is None:
        target_bytes = FEISHU_TARGET_BYTES
    pages = []
    current = []
    for row in rows:
        candidate = current + [row]
        candidate_body = _serialize_feishu_card(
            f"{title} [999/999]",
            [_playwright_header(), *candidate],
        )
        if current and _body_size(candidate_body) > target_bytes:
            pages.append(current)
            current = [row]
        else:
            current = candidate
    if current or not pages:
        pages.append(current)
    return pages


def send_playwright_message(url_v, result_v, title_v, job_url_v="", failed=False):
    print("send playwright message")
    rows = _parse_playwright_rows(result_v, job_url_v)
    if not rows:
        rows = [_playwright_row(
            engine="workflow",
            spec="run",
            rate="0.0% / 0.0%",
            status="BROKEN",
            fail_ops="No structured test result was collected",
            report_url="",
            job_url=job_url_v,
        )]
    pages = _paginate_playwright_rows(rows, title_v)
    total = len(pages)
    def send_page(page_rows, page_title):
        body = _serialize_feishu_card(
            page_title,
            [_playwright_header(), *page_rows],
        )
        size = _body_size(body)
        if size >= FEISHU_HARD_LIMIT_BYTES:
            raise FeishuSizeError(
                f"Feishu page is {size} bytes after pagination"
            )
        try:
            _post_feishu_body(url_v, body)
            return 1
        except FeishuSizeError:
            if len(page_rows) <= 1:
                raise
            midpoint = len(page_rows) // 2
            sent = send_page(page_rows[:midpoint], f"{page_title} [a/2]")
            time.sleep(0.4)
            return sent + send_page(
                page_rows[midpoint:],
                f"{page_title} [b/2]",
            )

    for index, page_rows in enumerate(pages, start=1):
        page_title = title_v if total == 1 else f"{title_v} [{index}/{total}]"
        body = _serialize_feishu_card(
            page_title,
            [_playwright_header(), *page_rows],
        )
        size = _body_size(body)
        if size >= FEISHU_HARD_LIMIT_BYTES:
            raise FeishuSizeError(
                f"Feishu page {index}/{total} is {size} bytes after pagination"
            )
        print(f"send Feishu page {index}/{total}, bytes={size}")
        send_page(page_rows, page_title)
        if index < total:
            time.sleep(0.4)

def parse_result(result_v):
    print(result_v)
    parts = result_v.split('|')
    test_type = parts[0].strip()
    passed = parts[1].strip()
    failed = parts[2].strip()
    pending = parts[3].strip()
    skipped = parts[4].strip()
    return test_type, passed, failed, pending, skipped


if __name__ == '__main__':
    args = parse_cli_args()
    title = args.title
    result = args.result
    url = args.url
    job_url = args.job_url
    send_type = args.send_type
    if send_type == "performance":
        send_performance_message(url, result, title, job_url)
    elif send_type == "report":
        send_report_message(url, result, title)
    elif send_type == "e2e":
        send_e2e_message(url, result, title)
    elif send_type == "installer":
        send_installer_message(url, result, title)
    elif send_type == "ginkgo":
        send_ginkgo_message(url, result, title)
    elif send_type == "summary":
        send_summary_message(url, result, title)
    elif send_type == "engine-summary":
        send_engine_summary_message(url, result, title)
    elif send_type == "engine-summary2":
        send_engine_summary_message2(url, result, title)
    elif send_type == "trivy":
        send_trivy_scan_message(url, result, title)
    elif send_type == "check-addon-version":
        send_check_addon_version_message(url, result, title)
    elif send_type == "kbcli":
        send_kbcli_message(url, result, title)
    elif send_type == "playwright":
        send_playwright_message(url, result, title, job_url)
    else:
        send_message(url, result, title)
