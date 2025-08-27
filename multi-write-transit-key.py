#!/usr/bin/env python3

import hvac
import os


def login() -> hvac.Client:
    kwargs = {}
    kwargs["url"] = os.environ["VAULT_ADDR"]
    kwargs["token"] = os.environ["VAULT_TOKEN"]
    if "VAULT_NAMESPACE" in os.environ:
        kwargs["namespace"] = os.environ["VAULT_NAMESPACE"]

    client = hvac.Client(**kwargs)

    if not client.is_authenticated():
        raise RuntimeError("Authentication failed")

    return client


def key(client: hvac.Client):
    # Create a new key
    key = client.secrets.transit.create_key(
        name="my-key",
        key_type="chacha20-poly1305",
        derived=True,
    )
    print(f"Key created: {key}")

    # Read the key
    read_key = client.secrets.transit.read_key(name="my-key")
    print(f"Key read: {read_key}")

    # # Delete the key
    # delete_key = client.secrets.transit.delete_key(name="my-key")
    # print(f"Key deleted: {delete_key}")


def main():
    client = login()
    key(client)
    key(client)


if __name__ == "__main__":
    main()
