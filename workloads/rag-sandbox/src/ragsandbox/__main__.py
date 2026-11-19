"""``python -m ragsandbox <command>``.

Commands (one image, SPEC-P4 §1): ``db-init``, ``bootstrap``, ``cleanup`` and
``serve`` (the reference app, ``serve.py``).

Exit codes: 0 success, 2 invalid input (name, tenant, configuration), 1 any
other failure. The platform commands print one JSON summary line on stdout;
errors go to stderr without secret values. ``serve`` runs until SIGTERM.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from . import commands
from .names import InvalidName
from .secretstore import store_from_env


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ragsandbox")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("db-init", help="once per window, master credential")
    for cmd in ("bootstrap", "cleanup"):
        p = sub.add_parser(cmd, help=f"{cmd} one sandbox, bootstrap credential")
        p.add_argument("--tenant", help="default: $SANDBOX_TENANT")
        p.add_argument("--name", help="default: $SANDBOX_NAME")
    sub.add_parser("serve", help="reference app: /healthz, /readyz, /query")
    args = parser.parse_args(argv)
    env = os.environ

    if args.command == "serve":
        from . import serve

        try:
            app = serve.app_from_env(env)
            port = int(env.get("PORT", "8080"))
        except (ValueError, RuntimeError) as exc:  # ConfigError is a ValueError
            print(f"ragsandbox serve: invalid configuration: {exc}", file=sys.stderr)
            return 2
        return serve.run(app, port)

    try:
        store = store_from_env(env)
        if args.command == "db-init":
            summary = commands.db_init(env, store)
        elif args.command == "bootstrap":
            summary = commands.bootstrap(env, store, args.tenant, args.name)
        else:
            summary = commands.cleanup(env, store, args.tenant, args.name)
    except InvalidName as exc:
        print(f"ragsandbox {args.command}: invalid input: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # report the type and message, never a traceback with locals
        print(f"ragsandbox {args.command}: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
