#!/usr/bin/env python3

"""Extract one entry from a remote ZIP using HTTP range requests."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import struct
import tempfile
import urllib.request
import zlib


EOCD_SIGNATURE = b"PK\x05\x06"
CENTRAL_SIGNATURE = b"PK\x01\x02"
LOCAL_SIGNATURE = b"PK\x03\x04"
EOCD_MAX_SIZE = 65_557
REQUEST_HEADERS = {"User-Agent": "pfr-netlify-build/1.0"}


def request_bytes(url: str, start: int, end: int) -> bytes:
    request = urllib.request.Request(
        url, headers={**REQUEST_HEADERS, "Range": f"bytes={start}-{end}"}
    )
    with urllib.request.urlopen(request) as response:
        if response.status != 206:
            raise RuntimeError(f"server returned HTTP {response.status} instead of 206")
        return response.read()


def remote_size_and_url(url: str) -> tuple[int, str]:
    request = urllib.request.Request(url, headers=REQUEST_HEADERS, method="HEAD")
    with urllib.request.urlopen(request) as response:
        size = response.headers.get("Content-Length")
        if size is None:
            raise RuntimeError("remote archive did not report Content-Length")
        return int(size), response.geturl()


def find_entry(url: str, archive_size: int, entry_name: str) -> tuple[int, int, int, int, int]:
    tail_start = max(0, archive_size - EOCD_MAX_SIZE)
    tail = request_bytes(url, tail_start, archive_size - 1)
    eocd_offset = tail.rfind(EOCD_SIGNATURE)
    if eocd_offset < 0:
        raise RuntimeError("ZIP end-of-central-directory record not found")

    eocd = struct.unpack_from("<4s4H2LH", tail, eocd_offset)
    entry_count = eocd[4]
    central_size = eocd[5]
    central_offset = eocd[6]
    if entry_count == 0xFFFF or central_size == 0xFFFFFFFF or central_offset == 0xFFFFFFFF:
        raise RuntimeError("ZIP64 archives are not supported")

    central = request_bytes(url, central_offset, central_offset + central_size - 1)
    offset = 0
    for _ in range(entry_count):
        header = struct.unpack_from("<4s6H3L5H2L", central, offset)
        if header[0] != CENTRAL_SIGNATURE:
            raise RuntimeError("invalid ZIP central-directory record")

        method = header[4]
        crc32 = header[7]
        compressed_size = header[8]
        uncompressed_size = header[9]
        name_length = header[10]
        extra_length = header[11]
        comment_length = header[12]
        local_offset = header[16]
        name_start = offset + 46
        name = central[name_start : name_start + name_length].decode("utf-8")
        if name == entry_name:
            return local_offset, method, crc32, compressed_size, uncompressed_size
        offset = name_start + name_length + extra_length + comment_length

    raise RuntimeError(f"{entry_name!r} was not found in the remote archive")


def extract_entry(url: str, entry_name: str) -> bytes:
    archive_size, resolved_url = remote_size_and_url(url)
    local_offset, method, expected_crc, compressed_size, uncompressed_size = find_entry(
        resolved_url, archive_size, entry_name
    )

    local_header = request_bytes(resolved_url, local_offset, local_offset + 29)
    header = struct.unpack("<4s5H3L2H", local_header)
    if header[0] != LOCAL_SIGNATURE:
        raise RuntimeError("invalid ZIP local-file record")
    name_length = header[9]
    extra_length = header[10]
    data_offset = local_offset + 30 + name_length + extra_length
    compressed = request_bytes(resolved_url, data_offset, data_offset + compressed_size - 1)

    if method == 0:
        extracted = compressed
    elif method == 8:
        extracted = zlib.decompress(compressed, -zlib.MAX_WBITS)
    else:
        raise RuntimeError(f"unsupported ZIP compression method: {method}")

    if len(extracted) != uncompressed_size:
        raise RuntimeError("extracted entry size did not match the ZIP directory")
    if zlib.crc32(extracted) & 0xFFFFFFFF != expected_crc:
        raise RuntimeError("extracted entry failed its ZIP CRC check")
    return extracted


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("entry")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args()

    extracted = extract_entry(args.url, args.entry)
    digest = hashlib.sha256(extracted).hexdigest()
    if digest != args.sha256.lower():
        raise RuntimeError(f"SHA-256 mismatch: expected {args.sha256}, got {digest}")

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(dir=args.destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as temporary_file:
            temporary_file.write(extracted)
        os.replace(temporary_name, args.destination)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


if __name__ == "__main__":
    main()
