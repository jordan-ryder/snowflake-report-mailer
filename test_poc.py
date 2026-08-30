"""Exercise the reporting pipeline and dump the rendered HTML for inspection."""

import pathlib

from deploy import connect

OUT = pathlib.Path(__file__).parent / "out"


def main():
    cur = connect().cursor()

    for name in ("monthly_sentiment", "top_channels", "demo_blocked_recipient"):
        cur.execute(f"call SENTIMENT.REPORTING.SP_RUN_REPORT('{name}')")
        print(f"{name:24s} -> {cur.fetchone()[0]}")

    print("\ndispatch (only what is due this hour):")
    cur.execute("call SENTIMENT.REPORTING.SP_DISPATCH()")
    print("  ", cur.fetchone()[0])

    print("\noutbox:")
    cur.execute("""select name, row_count, status, coalesce(error, ''), length(html)
                     from SENTIMENT.REPORTING.REPORT_OUTBOX order by created_at""")
    for n, rc, st, err, ln in cur.fetchall():
        print(f"  {n:24s} rows={rc:<4} {st:<18} html={ln}b {err}")

    cur.execute("""select html from SENTIMENT.REPORTING.REPORT_OUTBOX
                    where name = 'monthly_sentiment' order by created_at desc limit 1""")
    html = cur.fetchone()[0]
    OUT.mkdir(exist_ok=True)
    (OUT / "monthly_sentiment.html").write_text(html)
    print(f"\nwrote out/monthly_sentiment.html ({len(html)} bytes)")
    print("\n--- first 400 chars ---")
    print(html[:400])


if __name__ == "__main__":
    main()
