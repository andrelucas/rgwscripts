#!/usr/bin/env python3

import sys
import boto3
import random
import string

if __name__ == '__main__':

    bucketname = 'testv'
    s3 = boto3.client('s3')

    try:
        response = s3.create_bucket(Bucket=bucketname)
        print(f"Bucket '{bucketname}' created successfully.")

        # Enable bucket versioning
        versioning = s3.put_bucket_versioning(
            Bucket=bucketname,
            VersioningConfiguration={
                'Status': 'Enabled'
            }
        )
        print(f"Versioning enabled for bucket '{bucketname}'.")

        # Upload ten random files with the same object key name
        object_key = 'random-object'
        for i in range(10):
            random_data = ''.join(random.choices(string.ascii_letters + string.digits, k=100))
            s3.put_object(Bucket=bucketname, Key=object_key, Body=random_data)
            print(f"Uploaded version {i+1} of object '{object_key}'.")

        # Delete the object key
        s3.delete_object(Bucket=bucketname, Key=object_key)
        print(f"Object '{object_key}' deleted successfully.")

    except Exception as e:
        print(f"Error: {e}")

