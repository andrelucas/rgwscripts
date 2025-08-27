#!/usr/bin/env python3

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


def main():
    parser = argparse.ArgumentParser(description="RGW Admin bucket delete")
    parser.add_argument("-a", "--access-key", required=True, help="RGW Access Key")
    parser.add_argument("-s", "--secret-key", required=True, help="RGW Secret Key")
    parser.add_argument("-b", "--bucket", help="Bucket name")
    parser.add_argument("-u", "--uid", help="User ID")
    parser.add_argument("--host", required=True, help="RGW host")
    parser.add_argument("--purge", action="store_true", help="Purge bucket")
    parser.add_argument("--stats", action="store_true", help="Show bucket stats")

    parser.add_argument(
        "command", choices=["delete", "get_bucket"], help="Command to execute"
    )

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    rgw = RGWAdmin(
        access_key=args.access_key,
        secret_key=args.secret_key,
        server=args.host,
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
    if success:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
