#!/usr/bin/env python
# -*- coding:utf-8 -*-
import sys
import re


def remove_ansi_escape_sequences(file_path_input):
    log_content = ""
    with open(file_path_input, 'r') as file:
        log_content = file.read()

    ansi_escape = re.compile(r'\x1B[@-_][0-?]*[ -/]*[@-~]')
    return ansi_escape.sub('', log_content)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 remove_ansi_file.py <ginkgo_log_file>")
        sys.exit(1)

    file_path = sys.argv[1]

    ansi_str = remove_ansi_escape_sequences(file_path)
    print(ansi_str)
