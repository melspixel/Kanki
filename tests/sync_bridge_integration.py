#!/usr/bin/env python3
"""Exercise Kanki's typed sync ABI against the pinned Anki loopback server."""

import ctypes
import json
import os
import sys
import time
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


if len(sys.argv) != 9:
    raise SystemExit(
        f"usage: {sys.argv[0]} LIB COLLECTION_A MEDIA_A MEDIA_DB_A "
        "COLLECTION_B MEDIA_B MEDIA_DB_B ENDPOINT"
    )

(
    library_path,
    collection_a,
    media_a,
    media_db_a,
    collection_b,
    media_b,
    media_db_b,
) = map(Path, sys.argv[1:8])
endpoint = sys.argv[8]
username = os.environ.get("KANKI_SYNC_FIXTURE_USER", "")
password = os.environ.get("KANKI_SYNC_FIXTURE_PASSWORD", "")
require(bool(username and password), "synthetic sync credentials were not provided")

secrets = [username, password]
library = ctypes.CDLL(str(library_path.resolve()))
library.kanki_string_free.argtypes = [ctypes.c_void_p]
library.kanki_string_free.restype = None

for new_name in ("kanki_core_new", "kanki_sync_core_new"):
    function = getattr(library, new_name)
    function.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
    function.restype = ctypes.c_void_p
for free_name in ("kanki_core_free", "kanki_sync_core_free"):
    function = getattr(library, free_name)
    function.argtypes = [ctypes.c_void_p]
    function.restype = None

SIGNATURES = {
    "kanki_open_collection_json": [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
    ],
    "kanki_close_collection_json": [ctypes.c_void_p],
    "kanki_deck_tree_json": [ctypes.c_void_p],
    "kanki_set_deck_collapsed_json": [ctypes.c_void_p, ctypes.c_int64, ctypes.c_uint8],
    "kanki_sync_open_collection_json": [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
    ],
    "kanki_sync_close_collection_json": [ctypes.c_void_p],
    "kanki_sync_login_json": [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
    ],
    "kanki_sync_collection_json": [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_uint8,
    ],
    "kanki_sync_full_json": [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_uint8,
        ctypes.c_int32,
        ctypes.c_uint8,
    ],
    "kanki_sync_media_json": [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p],
    "kanki_sync_media_status_json": [ctypes.c_void_p],
    "kanki_sync_abort_json": [ctypes.c_void_p],
}
for function_name, argument_types in SIGNATURES.items():
    function = getattr(library, function_name)
    function.argtypes = argument_types
    function.restype = ctypes.c_void_p


def redacted(value) -> str:
    text = str(value)
    for secret in secrets:
        if secret:
            text = text.replace(secret, "[redacted]")
    return text


def call_json(label: str, function_name: str, *arguments):
    pointer = getattr(library, function_name)(*arguments)
    require(bool(pointer), f"{label} returned NULL")
    try:
        text = ctypes.string_at(pointer).decode("utf-8")
    finally:
        library.kanki_string_free(pointer)
    envelope = json.loads(text)
    require(envelope.get("ok") is True, f"{label} failed: {redacted(envelope.get('error'))}")
    return envelope.get("data")


def new_core(function_name: str) -> int:
    error_pointer = ctypes.c_void_p()
    core = getattr(library, function_name)(ctypes.byref(error_pointer))
    if not core:
        message = "unknown core initialization failure"
        if error_pointer.value:
            try:
                message = ctypes.string_at(error_pointer.value).decode("utf-8")
            finally:
                library.kanki_string_free(error_pointer.value)
        raise AssertionError(redacted(message))
    return core


def path_bytes(path: Path) -> bytes:
    return str(path).encode()


def open_sync(core: int, collection: Path, media: Path, media_db: Path, label: str) -> None:
    media.mkdir(parents=True, exist_ok=True)
    collection.parent.mkdir(parents=True, exist_ok=True)
    call_json(
        label,
        "kanki_sync_open_collection_json",
        core,
        path_bytes(collection),
        path_bytes(media),
        path_bytes(media_db),
    )


def close_sync(core: int, label: str) -> None:
    call_json(label, "kanki_sync_close_collection_json", core)


def open_review(core: int, collection: Path, media: Path, media_db: Path, label: str) -> None:
    call_json(
        label,
        "kanki_open_collection_json",
        core,
        path_bytes(collection),
        path_bytes(media),
        path_bytes(media_db),
    )


def close_review(core: int, label: str) -> None:
    call_json(label, "kanki_close_collection_json", core)


def find_deck(node, deck_id: int):
    if int(node.get("id", -1)) == deck_id:
        return node
    for child in node.get("children", []):
        match = find_deck(child, deck_id)
        if match is not None:
            return match
    return None


def wait_for_media(core: int, label: str) -> None:
    for _ in range(400):
        status = call_json(f"{label}_status", "kanki_sync_media_status_json", core)
        if not status.get("active"):
            print(f'{label}={{"active":false}}')
            return
        time.sleep(0.05)
    raise AssertionError(f"{label} did not become idle")


def sync_collection(core: int, hkey: str, label: str):
    result = call_json(
        label,
        "kanki_sync_collection_json",
        core,
        hkey.encode(),
        endpoint.encode(),
        0,
    )
    require(result.get("required") != "unknown", f"{label} returned an unknown sync decision")
    return result


def full_sync(core: int, hkey: str, upload: bool, status, label: str) -> None:
    call_json(
        label,
        "kanki_sync_full_json",
        core,
        hkey.encode(),
        endpoint.encode(),
        int(upload),
        int(status.get("server_media_usn", 0)),
        1,
    )
    wait_for_media(core, f"{label}_media")


media_filename = "kanki-sync-fixture.txt"
media_contents = b"Kanki pinned sync fixture\n"
media_a.mkdir(parents=True, exist_ok=True)
(media_a / media_filename).write_bytes(media_contents)

sync_a = new_core("kanki_sync_core_new")
try:
    open_sync(sync_a, collection_a, media_a, media_db_a, "client_a_open")
    login = call_json(
        "login",
        "kanki_sync_login_json",
        sync_a,
        username.encode(),
        password.encode(),
        endpoint.encode(),
    )
    hkey = login.get("hkey", "")
    require(bool(hkey), "login returned an empty host key")
    secrets.append(hkey)
    print('login={"authenticated":true,"endpoint":"loopback"}')

    upload_status = sync_collection(sync_a, hkey, "initial_upload_decision")
    require(
        upload_status.get("required") == "full_upload",
        f"empty server should require full upload, got {upload_status.get('required')}",
    )
    full_sync(sync_a, hkey, True, upload_status, "full_upload")
    print('full_upload={"decision":"full_upload","completed":true}')
    close_sync(sync_a, "client_a_close_after_upload")
finally:
    library.kanki_sync_core_free(sync_a)

sync_b = new_core("kanki_sync_core_new")
try:
    open_sync(sync_b, collection_b, media_b, media_db_b, "client_b_open")
    download_status = sync_collection(sync_b, hkey, "initial_download_decision")
    require(
        download_status.get("required") == "full_download",
        f"empty client should require full download, got {download_status.get('required')}",
    )
    full_sync(sync_b, hkey, False, download_status, "full_download")
    print('full_download={"decision":"full_download","completed":true}')
    close_sync(sync_b, "client_b_close_after_download")
finally:
    library.kanki_sync_core_free(sync_b)

require(
    (media_b / media_filename).read_bytes() == media_contents,
    "full-download media sync did not reproduce the fixture file",
)

review_b = new_core("kanki_core_new")
try:
    open_review(review_b, collection_b, media_b, media_db_b, "review_b_open_initial")
    initial_tree_b = call_json("review_b_tree_initial", "kanki_deck_tree_json", review_b)
    default_b = find_deck(initial_tree_b, 1)
    require(default_b is not None, "downloaded client is missing the default deck")
    require(default_b.get("collapsed") is True, "initial collapsed fixture state changed")
    close_review(review_b, "review_b_close_initial")
finally:
    library.kanki_core_free(review_b)

review_a = new_core("kanki_core_new")
try:
    open_review(review_a, collection_a, media_a, media_db_a, "review_a_open_mutation")
    call_json(
        "review_a_collapse_mutation",
        "kanki_set_deck_collapsed_json",
        review_a,
        1,
        0,
    )
    close_review(review_a, "review_a_close_mutation")
finally:
    library.kanki_core_free(review_a)

sync_a = new_core("kanki_sync_core_new")
try:
    open_sync(sync_a, collection_a, media_a, media_db_a, "client_a_open_normal")
    normal_a = sync_collection(sync_a, hkey, "client_a_normal")
    require(normal_a.get("required") == "no_changes", "client A normal sync did not complete")
    close_sync(sync_a, "client_a_close_normal")
finally:
    library.kanki_sync_core_free(sync_a)

sync_b = new_core("kanki_sync_core_new")
try:
    open_sync(sync_b, collection_b, media_b, media_db_b, "client_b_open_normal")
    normal_b = sync_collection(sync_b, hkey, "client_b_normal")
    require(normal_b.get("required") == "no_changes", "client B normal sync did not complete")
    call_json(
        "client_b_explicit_media",
        "kanki_sync_media_json",
        sync_b,
        hkey.encode(),
        endpoint.encode(),
    )
    wait_for_media(sync_b, "explicit_media")
    call_json("client_b_abort_idle", "kanki_sync_abort_json", sync_b)
    close_sync(sync_b, "client_b_close_normal")
finally:
    library.kanki_sync_core_free(sync_b)

review_b = new_core("kanki_core_new")
try:
    open_review(review_b, collection_b, media_b, media_db_b, "review_b_open_verify")
    final_tree_b = call_json("review_b_tree_verify", "kanki_deck_tree_json", review_b)
    default_b = find_deck(final_tree_b, 1)
    require(default_b is not None, "normal-sync client is missing the default deck")
    require(default_b.get("collapsed") is False, "normal sync did not propagate deck state")
    close_review(review_b, "review_b_close_verify")
finally:
    library.kanki_core_free(review_b)

print('normal_sync={"upload":true,"download":true,"deck_state_propagated":true}')
print('media_sync={"upload":true,"download":true,"explicit_status":true,"abort_idle":true}')
print("sync bridge integration: pass")
