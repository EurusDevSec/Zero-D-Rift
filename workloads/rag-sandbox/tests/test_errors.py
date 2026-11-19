"""safe_reason: no ARN, account ID or database host leaves the process."""

import psycopg
import pytest
from botocore.exceptions import ClientError, NoCredentialsError
from psycopg import errors as pgerr

from ragsandbox import __main__ as cli
from ragsandbox.errors import safe_reason

ARN = "arn:aws:sts::123456789012:assumed-role/zdr-platform-bootstrap/botocore-session-1"


def denied():
    message = f"User: {ARN} is not authorized to perform: secretsmanager:GetSecretValue"
    return ClientError({"Error": {"Code": "AccessDeniedException", "Message": message}}, "GetSecretValue")


@pytest.mark.parametrize(
    "exc, expected",
    [
        (denied(), "ClientError: AccessDeniedException"),
        (NoCredentialsError(), "NoCredentialsError"),
        (pgerr.InsufficientPrivilege("permission denied for schema rag_tenant_b__s2"),
         "InsufficientPrivilege: SQLSTATE 42501"),
        (psycopg.OperationalError('connection to server at "h.rds.amazonaws.com" (10.0.0.9), port 5432 '
                                  'failed: FATAL:  password authentication failed for user "rag_x"'),
         "OperationalError: authentication failed"),
        (psycopg.OperationalError("failed to resolve host 'zdr-p4.abc.rds.amazonaws.com': [Errno -2]"),
         "OperationalError: host not resolved"),
        (psycopg.OperationalError('connection to server at "h" (10.0.0.9), port 5432 failed: timeout expired'),
         "OperationalError: timeout"),
        (psycopg.OperationalError("something new from 10.0.0.9"), "OperationalError"),
        (RuntimeError("secret zero-drift/rag/tenant-a/s1 not found"),
         "RuntimeError: secret zero-drift/rag/tenant-a/s1 not found"),
    ],
)
def test_safe_reason(exc, expected):
    assert safe_reason(exc) == expected


def test_cli_error_line_has_code_not_arn(monkeypatch, capsys):
    def boom(env, store):
        raise denied()

    monkeypatch.setattr(cli.commands, "db_init", boom)
    monkeypatch.setenv("SECRET_BACKEND", "file")
    monkeypatch.setenv("SECRET_DIR", "/nonexistent")
    assert cli.main(["db-init"]) == 1
    err = capsys.readouterr().err
    assert err.strip() == "ragsandbox db-init: ClientError: AccessDeniedException"
    assert "123456789012" not in err
