#!/usr/bin/env python
# -*- coding:utf-8 -*-
import sys
import re
import argparse
from dateutil.parser import parse
from datetime import datetime

parser = argparse.ArgumentParser(description='Test for argparse')
parser.add_argument('--ansi-str', '-a', help='ansi str', default="")

args = parser.parse_args()
ansi_str = args.ansi_str


def remove_ansi_escape_sequences(text):
    ansi_escape = re.compile(r'\x1B[@-_][0-?]*[ -/]*[@-~]')
    return ansi_escape.sub('', text)


if __name__ == '__main__':
    ansi_str = remove_ansi_escape_sequences(ansi_str)
    print(ansi_str)
