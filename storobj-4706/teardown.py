#!/usr/bin/env python3

import boto3

if __name__ == '__main__':
    bucketname = 'testv'
    s3 = boto3.client('s3')

    try:
        # Delete all versions of all objects in the bucket
        versions = s3.list_object_versions(Bucket=bucketname).get('Versions', [])
        for version in versions:
            s3.delete_object(Bucket=bucketname, Key=version['Key'], VersionId=version['VersionId'])
            print(f"Deleted object '{version['Key']}' version '{version['VersionId']}'.")

        # Remove delete markers
        delete_markers = s3.list_object_versions(Bucket=bucketname).get('DeleteMarkers', [])
        for marker in delete_markers:
            s3.delete_object(Bucket=bucketname, Key=marker['Key'], VersionId=marker['VersionId'])
            print(f"Deleted delete marker for object '{marker['Key']}' version '{marker['VersionId']}'.")

        # Delete the bucket
        print(f"Deleting bucket '{bucketname}'...")
        s3.delete_bucket(Bucket=bucketname)
        print(f"Bucket '{bucketname}' deleted successfully.")
    except Exception as e:
        print(f"Error: {e}")
