"""Apply sql/ to Snowflake, substituting ${NAME} from secrets.local.toml."""

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
    cfg.pop("authenticator", None)  # stored value forces a browser flow
    return snowflake.connector.connect(**cfg)


def secret(key):
    return tomllib.load(open(SECRETS, "rb"))[key]


def render(path):
    # str.replace, not string.Template - Template eats the SQL's $$ UDF bodies
    sql = path.read_text()
    placeholders = set(re.findall(r"\$\{(\w+)\}", sql))
    if not placeholders:
        return sql
    values = {k.upper(): str(v) for k, v in tomllib.load(open(SECRETS, "rb")).items()}
    for key in placeholders:
        sql = sql.replace("${" + key + "}", values[key])
    return sql


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="run one file by name fragment")
    ap.add_argument("--check", action="store_true", help="print current state and exit")
    args = ap.parse_args()

    conn = connect()

    if args.check:
        cur = conn.cursor()
        cur.execute("select * from SENTIMENT.REPORTING.REPORT_CONFIG")
        row = dict(zip([c[0] for c in cur.description], cur.fetchone()))
        print("REPORT_CONFIG:")
        for k, v in row.items():
            print(f"  {k.lower():20s} {v}")
        for label, sql in (("functions", "show user functions in schema SENTIMENT.REPORTING"),
                           ("procedures", "show procedures like 'SP\\_%' in schema SENTIMENT.REPORTING"),
                           ("tasks", "show tasks in schema SENTIMENT.REPORTING")):
            cur.execute(sql)
            print(f"{label}: {', '.join(r[1] for r in cur.fetchall())}")
        return

    files = sorted(f for f in SQL_DIR.glob("*.sql") if not args.file or args.file in f.name)

    for path in files:
        print(f"→ {path.name}")
        for cur in conn.execute_string(render(path)):
            for row in cur.fetchall() or []:
                print(f"   {row[0] if len(row) == 1 else row}")
    conn.close()
    print("\ndone")


if __name__ == "__main__":
    main()
