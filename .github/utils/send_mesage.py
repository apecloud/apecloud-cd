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
    else:
        send_message(url, result, title)

