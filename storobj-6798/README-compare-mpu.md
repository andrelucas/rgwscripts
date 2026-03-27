# compare-mpuploadlist.sh

[`compare-mpuploadlist.sh`](/home/andre/rgw/storobj-6798/compare-mpuploadlist.sh) compares StoreQuery `mpuploadlist` results against `aws s3api list-multipart-uploads` for a single bucket.

The goal is to make it easy to spot where StoreQuery starts missing in-flight multipart uploads, especially when pagination or continuation-token handling is wrong.

## What It Does

For each requested page size, the script:

- issues an AWS `list-multipart-uploads --max-uploads <page_size>` request
- counts how many uploads AWS actually returned on that page
- issues a StoreQuery `mpuploadlist <aws_count>` request for exactly that many uploads
- optionally follows continuation tokens and markers when `-f` is used
- compares the two result sets page by page
- records raw responses and normalized diffs to disk

It also prints the exact commands it runs, so you can replay or inspect a failing page manually.

## Usage

```bash
./compare-mpuploadlist.sh [-c context_n] [-f] [-n max_pages] [-o output_dir] [-p page_size]... [-s] <bucket>
```

Options:

- `-c context_n`: show `N` entries of context before and after a divergence
- `-f`: follow continuation tokens and AWS markers past the first page
- `-n max_pages`: when `-f` is active, stop after at most this many pages
- `-o output_dir`: write artifacts into this directory instead of a temporary one
- `-p page_size`: AWS max page size to test; repeat this option to test multiple sizes
- `-s`: stop immediately on the first non-matching page and exit non-zero

If `-p` is not provided, the script uses page size `1000`.
If `-c` is not provided, the script shows `10` entries of context before and after the divergence.

Important: `-p` controls the AWS request size. StoreQuery does not blindly use the same number. Instead, StoreQuery is asked for the exact number of uploads AWS actually returned on each page, so the comparison is like-for-like even when AWS returns fewer records than requested.

## Examples

Check only the first page with several page sizes:

```bash
./compare-mpuploadlist.sh -p 10 -p 100 -p 1000 mybucket
```

Follow pagination for up to five pages:

```bash
./compare-mpuploadlist.sh -f -n 5 -p 100 mybucket
```

Write all artifacts to a fixed directory:

```bash
./compare-mpuploadlist.sh -f -p 10 -p 50 -o /tmp/mpu-debug mybucket
```

Stop as soon as the first mismatch is found:

```bash
./compare-mpuploadlist.sh -f -s -p 100 mybucket
```

Show a larger context window when a mismatch is found:

```bash
./compare-mpuploadlist.sh -f -s -c 20 -p 100 mybucket
```

## Reading The Output

The script prints one summary line per page, for example:

```text
page=2 sq_req=97 sq=97 aws=97 status=CONTENT_MISMATCH missing_in_storequery=3 extra_in_storequery=0
```

Meaning:

- `sq_req`: number of uploads requested from StoreQuery for that page
- `sq`: number of uploads returned by StoreQuery on that page
- `aws`: number of uploads returned by AWS on that page
- `status=MATCH`: same items in the same order
- `status=ORDER_MISMATCH`: same items, different order
- `status=CONTENT_MISMATCH`: StoreQuery and AWS differ in actual items
- `status=CONTINUATION_MISMATCH`: page items matched, but the decoded StoreQuery continuation `key`/`uploadId` did not match AWS `NextKeyMarker`/`NextUploadIdMarker`

At the end of each page-size run, it prints a final result line like:

```text
result page_size=100 status=DIFF pages=3 sq_total=297 aws_total=300 sq_unique=297 aws_unique=300 missing_in_storequery=3 extra_in_storequery=0 first_mismatch_page=2 artifacts=/tmp/mpu-debug/page-size-100
```

The most useful fields are:

- `first_mismatch_page`: the first page where behavior diverged
- `missing_in_storequery`: uploads AWS saw that StoreQuery missed
- `extra_in_storequery`: uploads StoreQuery returned that AWS did not

When a first difference is detected, the script also prints:

- the continuation inputs used for the failing page
  StoreQuery input token, plus its decoded form
  AWS input `key-marker` and `upload-id-marker`
- the first differing entry position in the ordered page output
- the decoded StoreQuery entry at that position
- the decoded AWS entry at that position
- a context diff with zero-based current-page-relative indices and zero-based total indices
- if values have not diverged yet, boundary context from just before and after the start of the failing page

## Artifact Layout

For each tested page size, the script creates a directory like:

```text
<output_dir>/page-size-100/
```

Important files inside:

- `summary.txt`: page-by-page summary and final result
- `storequery.all.jsonl`: complete decoded StoreQuery result stream for the run
- `aws.all.jsonl`: complete decoded AWS result stream for the run
- `page-0001.storequery.json`: raw StoreQuery response
- `page-0001.aws.json`: raw AWS response
- `page-0001.meta.json`: per-page token and marker metadata
- `page-0001.missing-in-storequery.jsonl`: uploads missing from StoreQuery on that page
- `page-0001.extra-in-storequery.jsonl`: unexpected uploads only seen in StoreQuery on that page
- `missing-in-storequery.jsonl`: overall uploads AWS saw but StoreQuery missed
- `extra-in-storequery.jsonl`: overall uploads only StoreQuery returned

The JSONL files decode the key and upload ID for easier inspection.

## Debugging Continuation-Token Problems

The per-page [`meta.json`] files are useful when StoreQuery pagination seems wrong.

They include:

- the StoreQuery input token used for that page
- the StoreQuery `NextToken` returned
- the decoded StoreQuery continuation `key` and `uploadId`
- the StoreQuery token you would expect from the last returned item
- the AWS input markers used for that page
- the AWS next markers returned
- the StoreQuery-style token implied by the last AWS item

Useful patterns to watch for:

- the decoded StoreQuery continuation `key` / `uploadId` does not match AWS `NextKeyMarker` / `NextUploadIdMarker`
- StoreQuery starts missing uploads on page `N`, but page `N-1` already returned a suspicious token
- AWS shows truncation and valid next markers, but StoreQuery stops early
- StoreQuery repeats a token and appears stuck on one page boundary
- AWS returns fewer than the requested max page size, and StoreQuery still diverges even when asked for that same smaller count

## Typical Workflow

1. Run the tool with several page sizes around the suspected failure boundary.
2. Note the earliest `first_mismatch_page`.
3. Open that page’s `summary.txt`, raw JSON, and `meta.json`.
4. Compare StoreQuery `NextToken` to the expected token from the last item.
5. Inspect `missing-in-storequery.jsonl` to see which upload IDs were skipped.

## Notes

- The script compares against `aws s3api list-multipart-uploads`.
- It assumes [`../common.sh`](/home/andre/rgw/common.sh) sets the endpoint and StoreQuery URL.
- It operates on one bucket at a time.
