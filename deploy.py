"""Deploy Snowflake reporting objects.

    python deploy.py                     # everything except 9x files
    python deploy.py --file 91_acs_send  # one file, including 9x
    python deploy.py --check             # print REPORT_CONFIG and object inventory

`${NAME}` placeholders in the SQL are substituted from secrets.local.toml, with keys
uppercased. Plain str.replace, not string.Template: Template reads the SQL's `$$`
dollar-quoted UDF bodies as escaped dollars and destroys them.
"""

import argparse
import pathlib
import re
import tomllib

import snowflake.connector

HERE = pathlib.Path(__file__).parent
SQL_DIR = HERE / "sql"
SECRETS = HERE / "secrets.local.toml"


def connect():
    cfg = tomllib.load(open(pathlib.Path.home() / ".snowflake/connections.toml", "rb"))["ai_sentiment"]
    cfg.pop("authenticator", None)  # stored value forces a browser flow; the PAT works as a password
    return snowflake.connector.connect(**cfg)


def secret(key):
    """One value from secrets.local.toml, for scripts that need the same config."""
    return tomllib.load(open(SECRETS, "rb"))[key]


def render(path):
    sql = path.read_text()
    placeholders = set(re.findall(r"\$\{(\w+)\}", sql))
    if not placeholders:
        return sql
    values = {k.upper(): str(v) for k, v in tomllib.load(open(SECRETS, "rb")).items()}
    missing = placeholders - values.keys()
    if missing:
        raise SystemExit(f"{path.name}: no value in {SECRETS.name} for {sorted(missing)}")
    for key in placeholders:
        sql = sql.replace("${" + key + "}", values[key])
    return sql


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="run one file by name fragment, 9x included")
    ap.add_argument("--check", action="store_true", help="print current state and exit")
    args = ap.parse_args()

    conn = connect()

    if args.check:
        cur = conn.cursor()
        cur.execute("select key, value from SENTIMENT.REPORTING.REPORT_CONFIG order by key")
        print("REPORT_CONFIG:")
        for k, v in cur.fetchall():
            print(f"  {k:20s} {v}")
        for label, sql in (("functions", "show user functions in schema SENTIMENT.REPORTING"),
                           ("procedures", "show procedures like 'SP\\_%' in schema SENTIMENT.REPORTING"),
                           ("tasks", "show tasks in schema SENTIMENT.REPORTING")):
            cur.execute(sql)
            print(f"{label}: {', '.join(r[1] for r in cur.fetchall())}")
        return

    if args.file:
        files = sorted(f for f in SQL_DIR.glob("*.sql") if args.file in f.name)
        if not files:
            raise SystemExit(f"no sql file matching {args.file!r}")
    else:
        files = sorted(f for f in SQL_DIR.glob("*.sql") if not re.match(r"9\d_", f.name))

    for path in files:
        print(f"→ {path.name}")
        for cur in conn.execute_string(render(path)):
            for row in cur.fetchall() or []:
                print(f"   {row[0] if len(row) == 1 else row}")
    conn.close()
    print("\ndone")


if __name__ == "__main__":
    main()
