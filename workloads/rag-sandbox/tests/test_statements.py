from ragsandbox import statements as st


def render(stmt):
    return stmt.as_string(None)


SPEC = st.RoleSpec("rag_tenant_a__s1", createrole=False, connection_limit=10)


def test_identifiers_are_quoted():
    text = render(st.drop_schema("rag_tenant_a__s1"))
    assert text == 'DROP SCHEMA IF EXISTS "rag_tenant_a__s1" CASCADE'


def test_hostile_identifier_stays_one_identifier():
    # Names are validated first; this checks the second layer anyway.
    text = render(st.drop_schema('x" CASCADE; DROP ROLE postgres; --'))
    assert text == 'DROP SCHEMA IF EXISTS "x"" CASCADE; DROP ROLE postgres; --" CASCADE'


def test_password_is_a_quoted_literal():
    text = render(st.create_role(SPEC, "p'w"))
    assert text.endswith("PASSWORD 'p''w'")
    assert "NOSUPERUSER" in text and "NOCREATEROLE" in text and "NOCREATEDB" in text


def test_bootstrap_role_has_createrole_only():
    spec = st.RoleSpec("rag_bootstrap", createrole=True, connection_limit=5)
    text = render(st.create_role(spec, "x"))
    assert " CREATEROLE " in text
    assert "NOSUPERUSER" in text and "NOCREATEDB" in text and "NOBYPASSRLS" in text


def test_plan_new_role_creates_it():
    plan = [render(s) for s in st.plan_role(SPEC, "pw", role_exists=False, secret_created=True)]
    assert len(plan) == 1 and plan[0].startswith('CREATE ROLE "rag_tenant_a__s1"')


def test_plan_rerun_keeps_password():
    # Re-run: role and secret both exist -> attributes only, no PASSWORD clause.
    plan = [render(s) for s in st.plan_role(SPEC, "pw", role_exists=True, secret_created=False)]
    assert len(plan) == 1
    assert plan[0].startswith('ALTER ROLE "rag_tenant_a__s1" WITH LOGIN')
    assert "PASSWORD" not in plan[0]
    # A non-superuser may not restate these, even as NO (found on PostgreSQL 17.10).
    for attr in ("SUPERUSER", "REPLICATION", "BYPASSRLS", "CREATEDB", "CREATEROLE"):
        assert attr not in plan[0]


def test_plan_lost_secret_resets_password():
    plan = [render(s) for s in st.plan_role(SPEC, "pw", role_exists=True, secret_created=True)]
    assert len(plan) == 2
    assert plan[1] == "ALTER ROLE \"rag_tenant_a__s1\" WITH PASSWORD 'pw'"


def test_sandbox_grants_are_limited_to_its_schema():
    text = [render(s) for s in st.sandbox_grants("rag", "rag_tenant_a__s1", "rag_tenant_a__s1")]
    assert text == [
        'CREATE SCHEMA IF NOT EXISTS "rag_tenant_a__s1"',
        'REVOKE ALL ON SCHEMA "rag_tenant_a__s1" FROM PUBLIC',
        'GRANT USAGE, CREATE ON SCHEMA "rag_tenant_a__s1" TO "rag_tenant_a__s1"',
        'GRANT CONNECT ON DATABASE "rag" TO "rag_tenant_a__s1"',
        'ALTER ROLE "rag_tenant_a__s1" SET search_path TO "rag_tenant_a__s1", public',
    ]


def test_database_grants_revoke_public_first():
    text = [render(s) for s in st.database_grants("rag", "rag_bootstrap")]
    assert text[0] == 'REVOKE ALL ON DATABASE "rag" FROM PUBLIC'
    assert text[1:] == [
        'GRANT CONNECT ON DATABASE "rag" TO "rag_bootstrap" WITH GRANT OPTION',
        'GRANT CREATE ON DATABASE "rag" TO "rag_bootstrap"',
        'REVOKE GRANT OPTION FOR CREATE ON DATABASE "rag" FROM "rag_bootstrap"',
    ]


def test_drop_role_revokes_before_drop():
    text = [render(s) for s in st.drop_role("rag", "rag_tenant_a__s1")]
    assert text == [
        'REVOKE ALL ON DATABASE "rag" FROM "rag_tenant_a__s1"',
        'DROP ROLE "rag_tenant_a__s1"',
    ]
