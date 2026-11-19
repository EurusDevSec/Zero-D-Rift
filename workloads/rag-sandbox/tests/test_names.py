import pytest

from ragsandbox.names import InvalidName, Sandbox, parse_sandbox, validate_name


@pytest.mark.parametrize("name", ["s", "s1", "docs-qa", "a" * 32, "a1-b2-c3"])
def test_valid_names(name):
    assert validate_name(name) == name


@pytest.mark.parametrize(
    "name",
    [
        "",
        "1abc",  # starts with a digit
        "-abc",
        "abc-",  # ends with a hyphen
        "a--b",  # double hyphen would map to the '__' separator
        "Abc",  # uppercase
        "a_b",  # underscore is not DNS-1123
        "a" * 33,  # too long
        'a";drop role x;--',  # injection attempt
        "a b",
        "a.b",
        None,
    ],
)
def test_invalid_names(name):
    with pytest.raises(InvalidName):
        validate_name(name)


@pytest.mark.parametrize("tenant", ["tenant-c", "zdr-platform", "default", "TENANT-A", ""])
def test_unknown_tenant_rejected(tenant):
    with pytest.raises(InvalidName):
        parse_sandbox(tenant, "s1")


def test_derived_names():
    sb = parse_sandbox("tenant-a", "docs-qa")
    assert sb.schema == sb.role == "rag_tenant_a__docs_qa"
    assert sb.secret_name == "zero-drift/rag/tenant-a/docs-qa"


def test_identifier_fits_postgres_limit():
    sb = parse_sandbox("tenant-b", "a" * 32)
    assert len(sb.ident.encode()) <= 63


def test_mapping_is_injective_across_tenants_and_names():
    seen = {}
    for tenant in ("tenant-a", "tenant-b"):
        for name in ("a-b", "ab", "a-b-c", "a", "b"):
            ident = Sandbox(tenant, name).ident
            assert ident not in seen, (ident, seen.get(ident))
            seen[ident] = (tenant, name)
