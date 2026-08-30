"""Probe Snowflake connectivity and list what the credential can see."""

import sys
import tomllib
from pathlib import Path

import snowflake.connector
from snowflake.connector.errors import Error as SnowflakeError

CONNECTIONS = Path.home() / ".snowflake" / "connections.toml"
PROFILE = sys.argv[1] if len(sys.argv) > 1 else "ai_sentiment"


def load_profile(name):
    with CONNECTIONS.open("rb") as fh:
        data = tomllib.load(fh)
    if name not in data:
        sys.exit(f"profile {name!r} not in {CONNECTIONS} (have: {', '.join(data)})")
    return data[name]


def auth_variants(base):
    """Auth shapes to try, headless PAT first."""
    secret = base.get("password")
    common = {k: v for k, v in base.items() if k not in ("password", "authenticator")}
    yield "PAT as password (no authenticator)", {**common, "password": secret}
    yield "PROGRAMMATIC_ACCESS_TOKEN", {
        **common,
        "password": secret,
        "authenticator": "PROGRAMMATIC_ACCESS_TOKEN",
    }
    yield "OAUTH bearer token", {
        **common,
        "authenticator": "OAUTH",
        "token": secret,
    }
    yield "as configured in connections.toml", dict(base)


def rows(cur, sql):
    cur.execute(sql)
    return cur.description, cur.fetchall()


def show(cur, title, sql, cols):
    try:
        desc, data = rows(cur, sql)
    except SnowflakeError as exc:
        print(f"\n{title}: not permitted ({exc.errno})")
        return
    names = [d[0].upper() for d in desc]
    idx = [names.index(c.upper()) for c in cols if c.upper() in names]
    print(f"\n{title} ({len(data)}):")
    for row in data:
        print("  " + " | ".join(str(row[i]) for i in idx))


def main():
    base = load_profile(PROFILE)
    print(f"profile={PROFILE} account={base.get('account')} user={base.get('user')}")

    conn = None
    for label, kwargs in auth_variants(base):
        try:
            conn = snowflake.connector.connect(login_timeout=20, **kwargs)
            print(f"connected via: {label}")
            break
        except Exception as exc:
            first = str(exc).strip().splitlines()[0][:160]
            print(f"  [fail] {label}: {first}")
    if conn is None:
        sys.exit("\nNo auth variant succeeded.")

    with conn, conn.cursor() as cur:
        _, ctx = rows(
            cur,
            "select current_account(), current_user(), current_role(), "
            "current_warehouse(), current_database(), current_version()",
        )
        acct, user, role, wh, db, ver = ctx[0]
        print(f"\naccount={acct} user={user} role={role} warehouse={wh} db={db} v{ver}")

        show(cur, "ROLES", "show roles", ["name"])
        show(cur, "WAREHOUSES", "show warehouses", ["name", "state", "size"])
        show(cur, "DATABASES", "show databases", ["name", "owner", "origin"])

        _, dbs = rows(cur, "select database_name from information_schema.databases")
        for (name,) in dbs:
            show(
                cur,
                f"SCHEMAS in {name}",
                f'show schemas in database "{name}"',
                ["name", "owner"],
            )


if __name__ == "__main__":
    main()
