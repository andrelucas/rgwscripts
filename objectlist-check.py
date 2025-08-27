#!/usr/bin/env python3

# Check that objectlist returns the full list of objects when paginating.

import argparse
import boto3
from botocore.exceptions import ClientError
from difflib import context_diff
from functools import reduce
import json
import logging
import requests
import sys
import tempfile

squrl = "http://127.0.0.1:8000"
bucket = "test"
profile = "default"


def get_objects_using_boto(args):
    objs = []
    try:
        # See https://boto3.amazonaws.com/v1/documentation/api/latest/guide/paginators.html
        s3_client = boto3.client("s3")
        paginator = s3_client.get_paginator("list_objects_v2")
        page_iterator = paginator.paginate(Bucket=args.bucket)

        for page in page_iterator:
            for obj in page["Contents"]:
                objs.append(obj["Key"])

        return objs

    except ClientError as e:
        logging.error(e)
        return None


def objectlist(url, bucket, max_entries, token=None):
    try:
        sqcmd = f"objectlist {max_entries}"
        if token is not None:
            sqcmd += f" {token}"
        headers = {"x-rgw-storequery": sqcmd}
        response = requests.get(f"{url}/{bucket}", headers=headers)
        response.raise_for_status()
        return response

    except requests.exceptions.RequestException as e:
        logging.error(e)
        raise e


def get_objects_using_objectlist(args):
    objs = []
    max_entries = args.max_entries
    token = None
    pages = 0

    while True:
        print(f"objectlist query: max_entries={max_entries} token={token}")
        response = objectlist(squrl, args.bucket, max_entries, token)
        if response is None:
            raise Exception("objectlist failed with unexpected None response")

        pages += 1
        if args.max_pages != -1 and pages > args.max_pages:
            print(f"Reached max_pages limit of {args.max_pages}")
            break

        resp = response.json()
        for obj in resp["Objects"]:
            objs.append(obj["key"])
        if "NextToken" in resp:
            token = resp["NextToken"]
        else:
            break

    return objs


def diff_objects(A, B, fromfile, tofile):
    for line in context_diff(A, B, fromfile=fromfile, tofile=tofile):
        print(line)


def main(args):
    apilist = get_objects_using_boto(args)
    apilist.sort()
    print(f"API list contains {len(apilist)} objects.")
    objectlist = get_objects_using_objectlist(args)
    objectlist.sort()
    print(f"Objectlist contains {len(objectlist)} objects.")

    if apilist == objectlist:
        return True
    else:
        print("Lists are different.")
        if (args.dump):
            print("API list:", apilist)
            print("Objectlist:", objectlist)
        else:
            print("API list:", apilist[:10], "...")
            print("Objectlist:", objectlist[:10], "...")

        if args.max_pages == -1:
            diff_objects(apilist, objectlist, "API", "objectlist")
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("bucket", help="The bucket to list objects from.")
    parser.add_argument("--profile", help="The AWS profile to use.")
    parser.add_argument("--max-entries", help="The maximum number of entries to return.", default=1000)
    parser.add_argument("--dump", action="store_true", help="Dump the API and objectlist output to the console")
    parser.add_argument("--max-pages", type=int, help="The maximum number of pages to return (-1 means 'unlimited')", default=-1)
    args = parser.parse_args()

    if not main(args):
        sys.exit(1)

    sys.exit(0)
