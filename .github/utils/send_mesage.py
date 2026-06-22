#!/usr/bin/env python
# -*- coding:utf-8 -*-
import argparse
import requests
import json
import re

parser = argparse.ArgumentParser(description='Test for argparse')
parser.add_argument('--title', '-t', help='test title', default="")
parser.add_argument('--result', '-r', help='test result', default="")
parser.add_argument('--url', '-u', help='webhook url', default="")
parser.add_argument('--job-url', '-ju', help='github job url', default="")
parser.add_argument('--send-type', '-st', help='test type', default="")

args = parser.parse_args()
title = args.title
result = args.result
url = args.url
job_url = args.job_url
send_type = args.send_type


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
        result_array = result_v.split("##")
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

def send_playwright_message(url_v, result_v, title_v, job_url_v=""):
    json_results = []
    header_ret = {
        "tag": "column_set", "flex_mode": "none", "background_style": "grey",
        "columns": [
            {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": "**Engine**", "text_align": "center"}]},
            {"tag": "column", "width": "weighted", "weight": 2, "vertical_align": "top", "elements": [{"tag": "markdown", "content": "**Test Spec**", "text_align": "center"}]},
            {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": "**Pass Rate**", "text_align": "center"}]},
            {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": "**Fail Ops**", "text_align": "center"}]},
        ]
    }
    json_results.append(header_ret)

    if result_v:
        stripped = result_v.lstrip("###")
        is_new = "@@@" in stripped

        if is_new:
            blocks = stripped.split("###")
            # Detect job URL injection (3 segments: ENG/RATE/JOB_URL@@@... vs 2: ENG/RATE@@@...)
            step = 2
            if len(blocks) >= 3 and "@@@" in blocks[2]:
                step = 3
            for i in range(0, len(blocks), step):
                if i + 1 >= len(blocks):
                    break
                engine_type = blocks[i]
                if step == 3:
                    pass_rate = blocks[i + 1]
                    url_data = blocks[i + 2]
                    job_url, rest = url_data.split("@@@", 1) if "@@@" in url_data else (url_data, "")
                else:
                    rest = blocks[i + 1]
                    if "@@@" in rest:
                        pass_rate, rest = rest.split("@@@", 1)
                        job_url = job_url_v or ""
                    else:
                        pass_rate = rest
                        rest = ""
                        job_url = job_url_v or ""
                parts = rest.split("@@@") if rest else ["", ""]
                specs_block = parts[0] if len(parts) > 0 else ""
                fail_ops_all = parts[1] if len(parts) > 1 else ""

                if len(json_results) > 1:
                    json_results.append({"tag": "markdown", "content": "---"})

                is_first = True
                for pair in specs_block.split("##"):
                    if not pair:
                        continue
                    ret = pair.split("|")
                    if len(ret) < 6:
                        continue
                    _, spec, succ, fail, skip, _ = ret[:6]
                    row_rate = ret[6] if len(ret) > 6 else pass_rate
                    fail_n = int(fail)
                    c = "red" if fail_n > 0 else "green"

                    if is_first:
                        if job_url:
                            ec = f"<a href='{job_url}'>{engine_type}</a>"
                        else:
                            ec = engine_type
                        is_first = False
                    else:
                        ec = ""
                    rc = f"<font color='{c}'>{row_rate}</font>"
                    fc = f"<font color='red'>{fail_ops_all}</font>" if fail_n > 0 and fail_ops_all else ""

                    sc = f"<font color='{c}'>{spec}</font>"

                    json_results.append({
                        "tag": "column_set", "flex_mode": "none",
                        "columns": [
                            {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": ec, "text_align": "center"}]},
                            {"tag": "column", "width": "weighted", "weight": 2, "vertical_align": "top", "elements": [{"tag": "markdown", "content": sc, "text_align": "center"}]},
                            {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": rc, "text_align": "center"}]},
                            {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": fc, "text_align": "center"}]},
                        ]
                    })
        else:
            parts_list = stripped.split("###")
            if len(parts_list) % 3 == 0:
                engine_blocks = zip(parts_list[0::3], parts_list[1::3], parts_list[2::3])
                for engine_type, job_url, specs_block in engine_blocks:
                    if len(json_results) > 1:
                        json_results.append({"tag": "markdown", "content": "---"})
                    is_first = True
                    for pair in specs_block.split("##"):
                        if not pair:
                            continue
                        ret = pair.split("|", 1)
                        if len(ret) != 2:
                            continue
                        spec, test_ret = ret[0], ret[1]
                        c = 'red' if "ERROR" in test_ret or "FAILED" in test_ret else 'green'
                        if is_first:
                            ec = f"<a href='{job_url}'>{engine_type}</a>"
                            is_first = False
                        else:
                            ec = ""
                        json_results.append({
                            "tag": "column_set", "flex_mode": "none",
                            "columns": [
                                {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": ec, "text_align": "center"}]},
                                {"tag": "column", "width": "weighted", "weight": 2, "vertical_align": "top", "elements": [{"tag": "markdown", "content": f"<font color='{c}'>{spec}</font>", "text_align": "center"}]},
                                {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": "", "text_align": "center"}]},
                                {"tag": "column", "width": "weighted", "weight": 1, "vertical_align": "top", "elements": [{"tag": "markdown", "content": f"<font color='{c}'>{test_ret}</font>", "text_align": "center"}]},
                            ]
                        })

    card = json.dumps({
        "header": {"template": "blue", "title": {"tag": "plain_text", "content": title_v}},
        "elements": json_results
    }, indent=2)
    body = json.dumps({"msg_type": "interactive", "card": card})
    headers = {"Content-Type": "application/json"}
    res = requests.post(url=url_v, data=body, headers=headers)
    print(res.text)

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

