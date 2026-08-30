"""Send each report, check the recipient guard, and verify a task fires."""

import time

from deploy import connect, secret

BAD = "guard_check"


def main():
    conn = connect()
    cur = conn.cursor()
    failures = 0

    for name in ("monthly_sentiment", "top_channels"):
        cur.execute(f"call SENTIMENT.REPORTING.SP_RUN_REPORT('{name}')")
        got = cur.fetchone()[0]
        ok = got.startswith("SENT")
        failures += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {name:22s} {got}")

    cur.execute("""
        insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
            (name, query_text, order_by, columns, subject, recipients)
        select %s, $$select 1 as n$$, 'n',
               array_construct(object_construct('key','N','label','N')),
               'never sent', array_construct('someone@not-allowed.example')
    """, (BAD,))
    cur.execute(f"call SENTIMENT.REPORTING.SP_RUN_REPORT('{BAD}')")
    got = cur.fetchone()[0]
    ok = got.startswith("BLOCKED_RECIPIENT")
    failures += not ok
    print(f"  {'PASS' if ok else 'FAIL'}  {'recipient guard':22s} {got}")
    cur.execute("delete from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION where name = %s", (BAD,))

    cur.execute("select count(*) from SENTIMENT.REPORTING.REPORT_LOG")
    before = cur.fetchone()[0]
    cur.execute("execute task SENTIMENT.REPORTING.TASK_TOP_CHANNELS")
    for _ in range(12):
        time.sleep(10)
        cur.execute("select count(*) from SENTIMENT.REPORTING.REPORT_LOG")
        if cur.fetchone()[0] > before:
            break
    cur.execute("""select name, status from SENTIMENT.REPORTING.REPORT_LOG
                    order by created_at desc limit 1""")
    name, status = cur.fetchone()
    ok = status == "SENT"
    failures += not ok
    print(f"  {'PASS' if ok else 'FAIL'}  {'task fires':22s} {name} {status}")

    print(f"\n{4 - failures}/4 passed")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
