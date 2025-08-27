#!/usr/bin/env python3

# Based on:
#  https://github.com/awsdocs/aws-doc-sdk-examples/blob/3c396bc74bfc8c1d2503d316bd2b3be2d9630ae5/python/example_code/s3/s3-python-example-put-bucket-policy.py
# Linked from:
#  https://stackoverflow.com/questions/50400687/ceph-radosgw-bucket-policy-make-all-objects-public-read-by-default

# Copyright 2010-2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# This file is licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License. A copy of the
# License is located at
#
# http://aws.amazon.com/apache2.0/
#
# This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

import argparse
import boto3
import json

def set_policy(args):
    # Create an S3 client
    s3 = boto3.client('s3')

    bucket_name = args.bucket

    # Create the bucket policy
    bucket_policy = {
        'Version': '2012-10-17',
        'Statement': [{
            'Sid': 'AddPerm',
            'Effect': 'Allow',
            'Principal': '*',
            'Action': ['s3:GetObject'],
            'Resource': "arn:aws:s3:::%s/*" % bucket_name
        }]
    }

    # Convert the policy to a JSON string
    bucket_policy = json.dumps(bucket_policy)

    # Set the new policy on the given bucket
    s3.put_bucket_policy(Bucket=bucket_name, Policy=bucket_policy)


if __name__ == '__main__':
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True, help="Bucket name")
    
    args = parser.parse_args()
    set_policy(args)
