"""Dump live schema DDL to snapshot/, to diff against sql/.

Integrations and secrets are account-level and have no GET_DDL; see sql/91_acs_send.sql.
"""

import pathlib

from deploy import connect

OUT = pathlib.Path(__file__).parent / "snapshot"


def main():
    cur = connect().cursor()
    cur.execute("select get_ddl('schema', 'SENTIMENT.REPORTING', true)")
    ddl = cur.fetchone()[0]
    OUT.mkdir(exist_ok=True)
    target = OUT / "deployed_schema.sql"
    target.write_text(ddl)
    print(f"wrote {target.relative_to(pathlib.Path.cwd())} ({len(ddl)} bytes)")


if __name__ == "__main__":
    main()
