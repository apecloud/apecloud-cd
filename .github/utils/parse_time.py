#!/usr/bin/env python
# -*- coding:utf-8 -*-
import argparse
from dateutil.parser import parse
from datetime import datetime

parser = argparse.ArgumentParser(description='Test for argparse')
parser.add_argument('--release-date', '-d', help='release date', default="")

args = parser.parse_args()
release_date = args.release_date


def send_message(date_v):
    now = datetime.now()
    try:
        target_date = parse(date_v)

        target_date = target_date.replace(tzinfo=None)

        days = (now - target_date).days

        if days > 30:
            print(1)
        else:
            print(0)
    except ValueError:
        print(0)


if __name__ == '__main__':
    send_message(release_date)
