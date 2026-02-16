#!/usr/bin/env python3
"""
Upload a generated file to S3 using SigV4 + aws-chunked streaming
with: x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER

Env:
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN   (optional)

Usage:
    python3 s3_stream_unsigned_trailer.py my-bucket us-east-1 test/key.bin 1048576 [--endpoint http://host:port]

Creates a local file ./upload.bin of given size, then streams it.
"""

import argparse
import base64
import datetime as dt
import hashlib
import hmac
import os
import socket
import ssl
import sys
import urllib.parse
import zlib


EMPTY_SHA256_HEX = hashlib.sha256(b"").hexdigest()


def hmac_sha256(key: bytes, msg: bytes) -> bytes:
    return hmac.new(key, msg, hashlib.sha256).digest()


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def signing_key(secret: str, yyyymmdd: str, region: str, service: str) -> bytes:
    k_date = hmac_sha256(("AWS4" + secret).encode("utf-8"), yyyymmdd.encode("utf-8"))
    k_region = hmac_sha256(k_date, region.encode("utf-8"))
    k_service = hmac_sha256(k_region, service.encode("utf-8"))
    return hmac_sha256(k_service, b"aws4_request")


def canonical_headers(headers: dict) -> tuple[str, str]:
    """
    Returns (canonical_headers_string, signed_headers_string)
    headers: lower-case keys only
    """
    items = sorted((k.lower().strip(), " ".join(v.strip().split())) for k, v in headers.items())
    canon = "".join(f"{k}:{v}\n" for k, v in items)
    signed = ";".join(k for k, _ in items)
    return canon, signed


def make_authorization(
    access_key: str,
    secret_key: str,
    session_token: str | None,
    method: str,
    canonical_uri: str,
    host: str,
    region: str,
    amz_date: str,
    date_scope: str,
    extra_headers: dict,
    payload_hash_header_value: str,
) -> tuple[dict, bytes]:
    """
    Builds headers including Authorization. Returns (headers, signing_key_bytes).
    """
    # Required headers (lowercase for canonicalization)
    headers = {
        "host": host,
        "x-amz-date": amz_date,
        "x-amz-content-sha256": payload_hash_header_value,
        **{k.lower(): v for k, v in extra_headers.items()},
    }
    if session_token:
        headers["x-amz-security-token"] = session_token

    canon_headers, signed_headers = canonical_headers(headers)

    canonical_request = (
        f"{method}\n"
        f"{canonical_uri}\n"
        f"\n"
        f"{canon_headers}\n"
        f"{signed_headers}\n"
        f"{payload_hash_header_value}"
    )

    scope = f"{date_scope}/{region}/s3/aws4_request"
    string_to_sign = (
        "AWS4-HMAC-SHA256\n"
        f"{amz_date}\n"
        f"{scope}\n"
        f"{sha256_hex(canonical_request.encode('utf-8'))}"
    )

    key = signing_key(secret_key, date_scope, region, "s3")
    sig = hmac.new(key, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    auth = (
        "AWS4-HMAC-SHA256 "
        f"Credential={access_key}/{scope},"
        f"SignedHeaders={signed_headers},"
        f"Signature={sig}"
    )

    # Return headers in original case for HTTP send (S3 is case-insensitive, but keep typical casing)
    send_headers = {k: v for k, v in headers.items()}
    send_headers["authorization"] = auth
    return send_headers, key


def chunk_string_to_sign(amz_date: str, scope: str, previous_sig: str, chunk_data_hash_hex: str) -> str:
    # Per AWS streaming SigV4 format: includes previous signature + empty hash + current chunk hash
    return (
        "AWS4-HMAC-SHA256-PAYLOAD\n"
        f"{amz_date}\n"
        f"{scope}\n"
        f"{previous_sig}\n"
        f"{EMPTY_SHA256_HEX}\n"
        f"{chunk_data_hash_hex}"
    )


def trailer_string_to_sign(amz_date: str, scope: str, previous_sig: str, trailer_canon_hash_hex: str) -> str:
    return (
        "AWS4-HMAC-SHA256-TRAILER\n"
        f"{amz_date}\n"
        f"{scope}\n"
        f"{previous_sig}\n"
        f"{trailer_canon_hash_hex}"
    )


def b64_crc32(data: bytes) -> str:
    # CRC32 as 4 bytes big-endian, base64 encoded
    crc = zlib.crc32(data) & 0xFFFFFFFF
    raw = crc.to_bytes(4, "big")
    return base64.b64encode(raw).decode("ascii")


def aws_chunked_content_length(
    decoded_len: int,
    chunk_size: int,
    checksum_header_name: str,
    checksum_b64: str,
) -> int:
    def chunk_frame_len(data_len: int) -> int:
        return len(f"{data_len:x};chunk-signature=") + 64 + 2 + data_len + 2

    full_chunks, remainder = divmod(decoded_len, chunk_size)
    total = full_chunks * chunk_frame_len(chunk_size)
    if remainder:
        total += chunk_frame_len(remainder)

    total += len("0;chunk-signature=") + 64 + 2
    total += len(f"{checksum_header_name}:{checksum_b64}\r\n")
    total += len("x-amz-trailer-signature:") + 64 + 2
    total += 2
    return total


def main():
    parser = argparse.ArgumentParser(
        description="Upload a generated file to S3 using SigV4 aws-chunked streaming with unsigned payload trailer."
    )
    parser.add_argument("bucket")
    parser.add_argument("region")
    parser.add_argument("key")
    parser.add_argument("size_bytes", type=int)
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=64 * 1024,
        help="AWS-chunked data chunk size in bytes (default: 65536).",
    )
    parser.add_argument(
        "--endpoint",
        default="http://127.0.0.1:8000",
        help="Target endpoint URL, e.g. http://127.0.0.1:8000 or https://s3.example.com:443.",
    )
    args = parser.parse_args()

    bucket, region, key = args.bucket, args.region, args.key
    size = args.size_bytes
    chunk_size = args.chunk_size

    if chunk_size <= 0:
        print("--chunk-size must be > 0", file=sys.stderr)
        sys.exit(2)

    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")
    session_token = os.environ.get("AWS_SESSION_TOKEN")

    if not access_key or not secret_key:
        print("Missing AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in environment", file=sys.stderr)
        sys.exit(2)

    # 1) Create file
    path = "upload.bin"
    with open(path, "wb") as f:
        f.write(os.urandom(size))

    # Precompute trailer checksum (CRC32 of decoded payload)
    with open(path, "rb") as f:
        payload = f.read()
    checksum_b64 = b64_crc32(payload)

    # 2) Prepare request
    now = dt.datetime.utcnow()
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_scope = now.strftime("%Y%m%d")

    endpoint = urllib.parse.urlparse(args.endpoint)
    if endpoint.scheme not in {"http", "https"}:
        print("Endpoint must use http or https scheme", file=sys.stderr)
        sys.exit(2)
    if not endpoint.hostname or endpoint.port is None:
        print("Endpoint must include host and port, e.g. http://127.0.0.1:8000", file=sys.stderr)
        sys.exit(2)

    use_tls = endpoint.scheme == "https"
    endpoint_host = endpoint.hostname
    endpoint_port = endpoint.port
    connect_host = endpoint_host
    connect_port = endpoint_port
    host = f"{bucket}.{endpoint_host}:{endpoint_port}"
    key_path = "/".join([part for part in key.split("/") if part])
    canonical_uri = f"/{key_path}"

    # S3/rgw expects aws-chunked framing in the payload body itself.
    # Send explicit Content-Length for the encoded aws-chunked stream.
    decoded_len = size

    # Unsigned streaming w/ trailer indicator:
    payload_hash_header_value = "STREAMING-UNSIGNED-PAYLOAD-TRAILER"

    # Trailer headers we'll send after the 0-size chunk
    checksum_header_name = "x-amz-checksum-crc32"
    content_length = aws_chunked_content_length(decoded_len, chunk_size, checksum_header_name, checksum_b64)

    extra_headers = {
        "content-encoding": "aws-chunked",
        "content-length": str(content_length),
        "x-amz-decoded-content-length": str(decoded_len),
        "x-amz-sdk-checksum-algorithm": "CRC32",
        "x-amz-trailer": checksum_header_name,
    }

    headers, sig_key = make_authorization(
        access_key=access_key,
        secret_key=secret_key,
        session_token=session_token,
        method="PUT",
        canonical_uri=canonical_uri,
        host=host,
        region=region,
        amz_date=amz_date,
        date_scope=date_scope,
        extra_headers=extra_headers,
        payload_hash_header_value=payload_hash_header_value,
    )

    # Extract the seed signature from Authorization (last Signature=...)
    auth = headers["authorization"]
    seed_sig = auth.split("Signature=", 1)[1]
    scope = f"{date_scope}/{region}/s3/aws4_request"

    # 3) Send request using raw socket for full control
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        if use_tls:
            ctx = ssl.create_default_context()
            sock = ctx.wrap_socket(sock, server_hostname=connect_host)
        
        sock.connect((connect_host, connect_port))
        
        # Send HTTP request line and headers
        sock.sendall(f"PUT {canonical_uri} HTTP/1.1\r\n".encode("utf-8"))
        sock.sendall(f"Host: {host}\r\n".encode("utf-8"))
        sock.sendall(f"x-amz-date: {amz_date}\r\n".encode("utf-8"))
        sock.sendall(f"x-amz-content-sha256: {payload_hash_header_value}\r\n".encode("utf-8"))
        sock.sendall(b"Content-Encoding: aws-chunked\r\n")
        sock.sendall(f"Content-Length: {content_length}\r\n".encode("utf-8"))
        sock.sendall(f"x-amz-decoded-content-length: {decoded_len}\r\n".encode("utf-8"))
        sock.sendall(b"x-amz-sdk-checksum-algorithm: CRC32\r\n")
        sock.sendall(f"x-amz-trailer: {checksum_header_name}\r\n".encode("utf-8"))
        if session_token:
            sock.sendall(f"x-amz-security-token: {session_token}\r\n".encode("utf-8"))
        sock.sendall(f"Authorization: {auth}\r\n".encode("utf-8"))
        sock.sendall(b"\r\n")  # End of headers

        # Stream file in chunks, creating aws-chunked metadata and chunk signatures.
        # For the "UNSIGNED" variant, we deliberately avoid hashing the chunk bytes into the
        # last line of the chunk string-to-sign, using the literal UNSIGNED-PAYLOAD.
        previous_sig = seed_sig

        with open(path, "rb") as f:
            while True:
                data = f.read(chunk_size)
                if not data:
                    break

                chunk_data_hash_hex = "UNSIGNED-PAYLOAD"
                sts = chunk_string_to_sign(amz_date, scope, previous_sig, chunk_data_hash_hex)
                sig = hmac.new(sig_key, sts.encode("utf-8"), hashlib.sha256).hexdigest()
                previous_sig = sig

                prefix = f"{len(data):x};chunk-signature={sig}\r\n".encode("utf-8")
                sock.sendall(prefix)
                sock.sendall(data)
                sock.sendall(b"\r\n")

        # Final 0-size chunk (with signature extension)
        final_chunk_data_hash_hex = "UNSIGNED-PAYLOAD"
        sts0 = chunk_string_to_sign(amz_date, scope, previous_sig, final_chunk_data_hash_hex)
        sig0 = hmac.new(sig_key, sts0.encode("utf-8"), hashlib.sha256).hexdigest()
        previous_sig = sig0
        sock.sendall(f"0;chunk-signature={sig0}\r\n".encode("utf-8"))

        # HTTP trailers: checksum header + trailer signature
        trailer_line = f"{checksum_header_name}:{checksum_b64}\n".encode("utf-8")
        trailer_canon_hash_hex = sha256_hex(trailer_line)

        tsts = trailer_string_to_sign(amz_date, scope, previous_sig, trailer_canon_hash_hex)
        trailer_sig = hmac.new(sig_key, tsts.encode("utf-8"), hashlib.sha256).hexdigest()

        trailers = (
            f"{checksum_header_name}:{checksum_b64}\r\n"
            f"x-amz-trailer-signature:{trailer_sig}\r\n"
            "\r\n"
        ).encode("utf-8")
        sock.sendall(trailers)

        # Read response
        sock.shutdown(socket.SHUT_WR)
        response_data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response_data += chunk
        
        # Parse and print response
        response_str = response_data.decode("utf-8", errors="replace")
        lines = response_str.split("\r\n", 1)
        print(lines[0])
        if len(lines) > 1:
            print(lines[1])
    finally:
        sock.close()


if __name__ == "__main__":
    main()
