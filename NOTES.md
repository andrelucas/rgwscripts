# NOTES for use of rgw dir

```sh
# Setup
$ ./setup-versioned.sh

$ ./setup-nonversioned.sh

# Check out what's been created.
$ ./aws.sh s3api list-buckets
+ aws --endpoint-url=http://127.0.0.1:8000 s3api list-buckets
{
    "Buckets": [
        {
            "Name": "testnv",
            "CreationDate": "2023-09-12T09:26:33.349Z"
        }
    ],
    "Owner": {
        "DisplayName": "M. Tester",
        "ID": "testid"
    }
}

# List a bucket.
$ ./aws.sh s3 ls s3://testnv
+ aws --endpoint-url=http://127.0.0.1:8000 s3 ls s3://testnv
                           PRE bigfile/
                           PRE rand/
2023-09-12 09:26:42       1024 rand
2023-09-12 09:26:44       1024 rand_subrand


# Run a ping.
$ ./sqcmd.sh "ping foo"
HTTP/1.1 200 OK
x-amz-request-id: tx00000e54eff4bb57d2bab-0065003318-1046-default
Content-Type: application/xml
Content-Length: 111
Date: Tue, 12 Sep 2023 09:44:56 GMT
Connection: Keep-Alive

<?xml version="1.0" encoding="UTF-8"><StoreQueryPingResult><request_id>foo</request_id></StoreQueryPingResult>

# Run an object_status command
$ ./sqcmd.sh "objectstatus" testnv/rand
HTTP/1.1 200 OK
x-amz-request-id: tx00000b0556968ada3b3c4-0065003339-1046-default
Content-Type: application/xml
Content-Length: 286
Date: Tue, 12 Sep 2023 09:45:29 GMT
Connection: Keep-Alive

<?xml version="1.0" encoding="UTF-8"?><StoreQueryObjectStatusResult><Object><bucket>testnv</bucket><key>rand</key><deleted>false</deleted><multipart_upload_in_progress>false</multipart_upload_in_progress><version_id></version_id><size>1024</size></Object></StoreQueryObjectStatusResult>%

``````
