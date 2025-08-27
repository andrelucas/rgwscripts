#!/usr/bin/env python3

# Started as:
#   https://gist.github.com/weavenet/f40b09847ac17dd99d16

import argparse
import sys
import boto3


def delete(args):
    # Cribbed from:
    #   https://stackoverflow.com/questions/46819590/delete-all-versions-of-an-object-in-s3-using-python
    bucket = args.bucket
    s3_client = boto3.client('s3')
    object_response_paginator = s3_client.get_paginator('list_object_versions')

    delete_marker_list = []
    version_list = []

    for object_response_itr in object_response_paginator.paginate(Bucket=bucket):
        if 'DeleteMarkers' in object_response_itr:
            for delete_marker in object_response_itr['DeleteMarkers']:
                delete_marker_list.append({'Key': delete_marker['Key'], 'VersionId': delete_marker['VersionId']})

        if 'Versions' in object_response_itr:
            for version in object_response_itr['Versions']:
                version_list.append({'Key': version['Key'], 'VersionId': version['VersionId']})

    print(f'Found {len(delete_marker_list)} delete markers and {len(version_list)} versions.')

    for i in range(0, len(delete_marker_list), 1000):
        print('Removing delete markers')
        response = s3_client.delete_objects(
            Bucket=bucket,
            Delete={
                'Objects': delete_marker_list[i:i+1000],
                'Quiet': True
            }
        )
        print(f'delete markers: {response}')

    for i in range(0, len(version_list), 1000):
        print('Removing versions')
        response = s3_client.delete_objects(
            Bucket=bucket,
            Delete={
                'Objects': version_list[i:i+1000],
                'Quiet': True
            }
        )
        print(f'versions: {response}')

    # Delete the bucket
    s3_client.delete_bucket(Bucket=bucket)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description='Delete an S3 bucket and all its contents.')
    p.add_argument('--bucket', required=True, help='Name of the S3 bucket to delete')
    p.add_argument('--i-mean-it', action='store_true', help='Force deletion without confirmation')
    args = p.parse_args()

    if not args.i_mean_it:
        print(f"Are you sure you want to delete the bucket '{args.bucket}' and all its contents? "
              "This action cannot be undone. Use --i-mean-it to confirm.")
        confirm = input("Type 'yes' to confirm: ")
        if confirm.lower() != 'yes':
            print("Not deleting.")
            exit(1)

    delete(args)
    # session = boto3.Session()
    # s3 = session.resource(service_name='s3')
    # bucket = s3.Bucket(args.bucket)
    # versions = bucket.object_versions
    # for v in versions.all():
    #     v.delete()

    # bucket.delete()
