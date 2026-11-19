#!/usr/bin/env python3
"""LAB ONLY: create the stand-in for the RDS-managed master secret.

On RDS, the master secret is created by RDS (Terraform manage_master_user_password)
and holds {"username", "password"}. In kind there is no AWS, so this init step
writes the same shape into the file store, plus a plain copy that the postgres
image reads through POSTGRES_PASSWORD_FILE. It reuses an existing secret.
"""
import os
import sys
from pathlib import Path

from ragsandbox.db import new_password
from ragsandbox.secretstore import FileSecretStore, get_or_create

root = os.environ.get("SECRET_DIR", "/secrets")
name = os.environ.get("MASTER_SECRET_ID", "lab/master")
value, created = get_or_create(
    FileSecretStore(root), name, lambda: {"username": "postgres", "password": new_password()}
)
plain = Path(root, "lab", "master.pw")
if not plain.exists():
    fd = os.open(plain, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(value["password"])
print(f"master secret {name}: {'created' if created else 'reused'}", file=sys.stderr)
