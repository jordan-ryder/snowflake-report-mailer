"""Drop the task to 1min, wait for a real firing, restore."""

import time

from deploy import connect, secret

SMOKE = "scheduler_smoke_test"
CRON = "USING CRON 0 * * * * UTC"


def main():
    conn = connect()
    cur = conn.cursor()

    def sql(stmt):
        cur.execute(stmt)
        return cur.fetchall()

    def task_state():
        cur.execute("show tasks like 'DISPATCH_REPORTS' in schema SENTIMENT.REPORTING")
        cols = [c[0] for c in cur.description]
        row = cur.fetchall()[0]
        d = dict(zip(cols, row))
        return d.get("schedule"), d.get("state")

    # window resolved in SQL; sysdate() (UTC) into a TIMESTAMP_LTZ param skews it
    t0 = time.time()

    try:
        cur.execute("delete from SENTIMENT.REPORTING.REPORT_OUTBOX where name = %s", (SMOKE,))
        cur.execute("delete from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION where name = %s", (SMOKE,))
        cur.execute("""
            insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
                (name, description, query_text, order_by, columns, subject,
                 recipients, frequency, hour_utc, enabled)
            select %s, 'Scheduler smoke test',
                   $$select current_timestamp() as fired_at, count(*) as channels
                       from SENTIMENT.ANALYTICS.MART_YOUTUBE_SENTIMENT_MONTHLY$$,
                   'fired_at',
                   array_construct(object_construct('key','FIRED_AT','label','Fired At'),
                                   object_construct('key','CHANNELS','label','Rows In Mart')),
                   'Scheduler smoke test', array_construct(%s),
                   'HOURLY', 0, true
        """, (SMOKE, secret("report_recipient")))
        print(f"seeded {SMOKE} (HOURLY, always due)")

        sql("alter task SENTIMENT.REPORTING.DISPATCH_REPORTS suspend")
        sql("alter task SENTIMENT.REPORTING.DISPATCH_REPORTS set schedule = '1 MINUTE'")
        sql("alter task SENTIMENT.REPORTING.DISPATCH_REPORTS resume")
        sched, st = task_state()
        print(f"task -> schedule={sched} state={st}")
        print("waiting for a run scheduled after now...")

        deadline = time.time() + 240
        while time.time() < deadline:
            time.sleep(20)
            window = int(time.time() - t0) + 5
            runs = sql(f"""
                select scheduled_time, state, coalesce(error_message, ''), return_value
                  from table(information_schema.task_history(
                           task_name => 'DISPATCH_REPORTS',
                           scheduled_time_range_start =>
                               dateadd(second, -{window}, current_timestamp())))
                 order by scheduled_time desc limit 5""")
            done = [r for r in runs if r[1] in ("SUCCEEDED", "FAILED")]
            print(f"  [{int(deadline - time.time())}s left] runs={len(runs)} finished={len(done)}")
            if done:
                for ts, st, err, rv in done:
                    print(f"    {ts:%H:%M:%S} {st} return={rv} {err[:120]}")
                break
        else:
            print("  no firing observed within the window")

        rows = sql(f"""select name, status, row_count, created_at
                         from SENTIMENT.REPORTING.REPORT_OUTBOX
                        where name = '{SMOKE}' order by created_at desc limit 3""")
        print("\noutbox for smoke test:")
        for n, st, rc, ts in rows:
            print(f"  {n} {st} rows={rc} {ts}")

    finally:
        sql("alter task SENTIMENT.REPORTING.DISPATCH_REPORTS suspend")
        sql(f"alter task SENTIMENT.REPORTING.DISPATCH_REPORTS set schedule = '{CRON}'")
        cur.execute("update SENTIMENT.REPORTING.REPORT_SUBSCRIPTION set enabled = false where name = %s", (SMOKE,))
        sched, st = task_state()
        print(f"\nrestored: schedule={sched} state={st}, {SMOKE} disabled")
        conn.close()


if __name__ == "__main__":
    main()
