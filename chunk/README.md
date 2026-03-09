# S3 Chunked Upload Test Scripts

This workspace contains three upload test scripts and one driver script.

## Test Scripts

- `test_s3_stream_unsigned_trailer.sh` runs unsigned trailer chunked upload.
- `test_s3_stream_sha256_trailer.sh` runs signed trailer chunked upload.
- `test_s3_stream_sha256_payload.sh` runs signed payload chunked upload.

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
- `S3_VERBOSE` (`1` or `0`, default: `1`)

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
