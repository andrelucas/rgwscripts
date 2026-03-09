# S3 Chunked Upload Test Scripts

This workspace contains three upload test scripts and one driver script.

I've found that it's not easy to reliably test individual streaming upload
types (as opposed to multipart uploads), as boto seems to not support their
direct use. Everywhere I looked, it seems that the general advice is to not
rely on boto (or any other library) using a particular streaming type. 

Since Handoff Authentication has special code to support streaming uploads we
must be able test it. We simply can't rely on higher-level tests exercising
these pathways.

The streaming types are found in [Amazon's
Docs](https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-auth-using-authorization-header.html).
We don't support ECDSA because RGW doesn't support it at the time of writing.

## Test Scripts

| Script | x-amz-content-sha256 |
| --- | --- |
| `test_s3_stream_unsigned_trailer.sh` | `STREAMING-UNSIGNED-PAYLOAD-TRAILER` |
| `test_s3_stream_sha256_trailer.sh` | `STREAMING-AWS4-HMAC-SHA256-PAYLOAD-TRAILER` |
| `test_s3_stream_sha256_payload.sh` | `STREAMING-AWS4-HMAC-SHA256-PAYLOAD` |

Each test performs post-upload verification of object size and SHA256.

## Run All Tests

Run the driver script:

```bash
./test_all_s3_stream.sh
```

## Shared Size/Chunk Overrides

All test scripts and the driver accept:

- `S3_SIZE_BYTES`
- `S3_CHUNK_SIZE`
- `S3_VERBOSE` (`1` or `0`, default: `0`)

Convenience aliases are also supported:

- `SIZE_BYTES` (mapped to `S3_SIZE_BYTES`)
- `CHUNK_SIZE` (mapped to `S3_CHUNK_SIZE`)
- `VERBOSE` (mapped to `S3_VERBOSE`)

### Examples

```bash
S3_SIZE_BYTES=500000 S3_CHUNK_SIZE=131072 ./test_all_s3_stream.sh
SIZE_BYTES=500000 CHUNK_SIZE=131072 ./test_all_s3_stream.sh
S3_VERBOSE=0 ./test_all_s3_stream.sh
VERBOSE=0 ./test_all_s3_stream.sh
```

## Other Common Environment Variables

Additional supported environment variables:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `S3_BUCKET`
- `S3_REGION`
- `S3_KEY`
- `S3_ENDPOINT`

## Upload Verifier Helper

All test scripts use `verify_s3_upload.py` to validate uploaded object size and SHA256.

Usage:

```bash
python3 ./verify_s3_upload.py <endpoint> <region> <bucket> <key> <expected_size> [local_file_path]
```

Example:

```bash
python3 ./verify_s3_upload.py http://localhost:8000 us-east-1 testnv obj 100000 upload.bin
```

Default local file path (`upload.bin`):

```bash
python3 ./verify_s3_upload.py http://localhost:8000 us-east-1 testnv obj 100000
```

If `local_file_path` is omitted, the default is `upload.bin`.
