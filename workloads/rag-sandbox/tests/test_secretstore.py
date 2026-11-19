import os
import stat

import pytest

from ragsandbox.secretstore import (
    AwsSecretStore,
    FileSecretStore,
    get_or_create,
    parse_tags,
    require,
    store_from_env,
)


def test_file_store_roundtrip(tmp_path):
    store = FileSecretStore(tmp_path)
    name = "zero-drift/rag/tenant-a/s1"
    assert store.get(name) is None
    assert store.create(name, {"username": "u", "password": "p"}) is True
    assert store.create(name, {"username": "other", "password": "x"}) is False  # exclusive
    assert store.get(name) == {"username": "u", "password": "p"}
    assert store.delete(name) is True
    assert store.delete(name) is False


@pytest.mark.skipif(os.name != "posix", reason="POSIX file modes")
def test_file_store_mode_0600(tmp_path):
    store = FileSecretStore(tmp_path)
    store.create("a/b", {"username": "u", "password": "p"})
    assert stat.S_IMODE((tmp_path / "a" / "b.json").stat().st_mode) == 0o600


@pytest.mark.parametrize("bad", ["../etc/passwd", "a/../../b", "/abs", "a//b", "a b", ""])
def test_file_store_rejects_bad_names(tmp_path, bad):
    with pytest.raises(ValueError):
        FileSecretStore(tmp_path).get(bad)


def test_get_or_create_reuses_existing(tmp_path):
    store = FileSecretStore(tmp_path)
    store.create("s", {"username": "u", "password": "first"})
    value, created = get_or_create(store, "s", lambda: {"username": "u", "password": "second"})
    assert (value["password"], created) == ("first", False)


def test_get_or_create_creates_once(tmp_path):
    store = FileSecretStore(tmp_path)
    value, created = get_or_create(store, "s", lambda: {"username": "u", "password": "new"})
    assert (value["password"], created) == ("new", True)


class _RaceStore:
    """get() misses once, create() loses the race, second get() sees the winner."""

    def __init__(self):
        self.calls = 0

    def get(self, name):
        self.calls += 1
        return None if self.calls == 1 else {"username": "u", "password": "winner"}

    def create(self, name, value):
        return False

    def delete(self, name):
        return False


def test_get_or_create_lost_race_uses_winner():
    value, created = get_or_create(_RaceStore(), "s", lambda: {"username": "u", "password": "loser"})
    assert (value["password"], created) == ("winner", False)


def test_require_checks_fields(tmp_path):
    store = FileSecretStore(tmp_path)
    store.create("s", {"username": "u"})
    with pytest.raises(RuntimeError, match="no password"):
        require(store, "s")
    with pytest.raises(RuntimeError, match="not found"):
        require(store, "missing")


class _ClientError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class _FakeSecretsManager:
    def __init__(self):
        self.data = {}
        self.deleted_with = None

    def get_secret_value(self, SecretId):
        if SecretId not in self.data:
            raise _ClientError("ResourceNotFoundException")
        return {"SecretString": self.data[SecretId]}

    def create_secret(self, Name, SecretString, Tags=None):
        if Name in self.data:
            raise _ClientError("ResourceExistsException")
        self.data[Name] = SecretString
        self.tags = Tags

    def delete_secret(self, SecretId, ForceDeleteWithoutRecovery):
        if SecretId not in self.data:
            raise _ClientError("ResourceNotFoundException")
        self.deleted_with = ForceDeleteWithoutRecovery
        del self.data[SecretId]


def test_aws_store_maps_errors_and_force_deletes():
    client = _FakeSecretsManager()
    store = AwsSecretStore(client=client, tags={"Project": "Zero-D-Rift"})
    assert store.get("s") is None
    assert store.create("s", {"username": "u", "password": "p"}) is True
    assert store.create("s", {"username": "u", "password": "q"}) is False
    assert store.get("s") == {"username": "u", "password": "p"}
    assert client.tags == [{"Key": "Project", "Value": "Zero-D-Rift"}]
    assert store.delete("s") is True and client.deleted_with is True
    assert store.delete("s") is False


def test_aws_store_reraises_other_errors():
    class Denied:
        def get_secret_value(self, SecretId):
            raise _ClientError("AccessDeniedException")

    with pytest.raises(_ClientError):
        AwsSecretStore(client=Denied()).get("s")


def test_parse_tags():
    assert parse_tags("") == {}
    assert parse_tags("Project=Zero-D-Rift, RunId=r1") == {"Project": "Zero-D-Rift", "RunId": "r1"}
    with pytest.raises(ValueError):
        parse_tags("novalue")


def test_store_from_env(tmp_path):
    assert isinstance(store_from_env({"SECRET_BACKEND": "file", "SECRET_DIR": str(tmp_path)}), FileSecretStore)
    with pytest.raises(RuntimeError):
        store_from_env({"SECRET_BACKEND": "file"})
    with pytest.raises(RuntimeError):
        store_from_env({"SECRET_BACKEND": "k8s"})
