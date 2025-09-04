#!/usr/bin/env python3

import os
from rgwadmin import RGWAdmin
import argparse
import json
import logging
import sys


def get_bucket(args, rgw):
    try:
        logging.info(f"get_bucket: bucket {args.bucket} uid {args.uid}")
        kwargs = {}
        if args.uid:
            kwargs["uid"] = args.uid
        if args.bucket:
            kwargs["bucket"] = args.bucket
        if args.stats:
            kwargs["stats"] = True
        result = rgw.get_bucket(**kwargs)
        print(json.dumps(result, indent=4))
    except Exception as e:
        print("Error: {}".format(e))
        return False
    return True


def delete_bucket(args, rgw):
    if not args.bucket:
        print("Error: bucket name is required")
        return False
    try:
        logging.info(f"Removing bucket {args.bucket} uid {args.uid}")
        print(rgw.remove_bucket(bucket=args.bucket, purge_objects=args.purge))
    except Exception as e:
        print("Error: {}".format(e))
        return False
    return True


def usage(args, rgw):
    try:
        logging.info(f"Getting usage for uid {args.uid}")
        result = rgw.get_usage(uid=args.uid, show_entries=True, show_summary=True)
        print(json.dumps(result, indent=4))
    except Exception as e:
        print("Error: {}".format(e))
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description="RGW Admin bucket delete")
    parser.add_argument("-a", "--access-key", help="RGW Access Key")
    parser.add_argument("-s", "--secret-key", help="RGW Secret Key")
    parser.add_argument("-b", "--bucket", help="Bucket name")
    parser.add_argument("-u", "--uid", help="User ID")
    parser.add_argument("-e", "--endpoint", help="RGW endpoint HOST[:PORT]")
    parser.add_argument("--purge", action="store_true", help="Purge bucket")
    parser.add_argument("--stats", action="store_true",
                        help="Show bucket stats")

    parser.add_argument(
        "command", choices=["delete", "get_bucket", "usage"], help="Command to execute"
    )

    args = parser.parse_args()

    if not args.access_key:
        if 'AWS_ACCESS_KEY_ID' in os.environ:
            args.access_key = os.environ['AWS_ACCESS_KEY_ID']
        else:
            args.access_key = "0555b35654ad1656d804"
    if not args.secret_key:
        if 'AWS_SECRET_ACCESS_KEY' in os.environ:
            args.secret_key = os.environ['AWS_SECRET_ACCESS_KEY']
        else:
            args.secret_key = "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q=="
    if not args.endpoint:
        if 'AWS_ENDPOINT_URL' in os.environ:
            args.endpoint = os.environ['AWS_ENDPOINT_URL']
        else:
            args.endpoint = "localhost:8000"

    logging.basicConfig(level=logging.INFO)

    rgw = RGWAdmin(
        access_key=args.access_key,
        secret_key=args.secret_key,
        server=args.endpoint,
        secure=False,
        verify=False,
    )

    # logging.info("Get all buckets")
    # print(rgw.get_buckets())
    # logging.info(f"Get bucket {args.bucket}")
    # print(rgw.get_bucket(bucket=args.bucket))

    if args.command == "delete":
        success = delete_bucket(args, rgw)
    elif args.command == "get_bucket":
        success = get_bucket(args, rgw)
    elif args.command == "usage":
        success = usage(args, rgw)
    if success:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
