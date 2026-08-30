"""Send each report and verify a task fires."""

import time

from deploy import connect


def main():
    cur = connect().cursor()
    failures = 0

    for name in ("monthly_sentiment", "top_channels"):
        cur.execute(f"call SENTIMENT.REPORTING.SP_RUN_REPORT('{name}')")
        got = cur.fetchone()[0]
        ok = got.startswith("sent")
        failures += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {name:22s} {got}")

    cur.execute("select count(*) from SENTIMENT.REPORTING.REPORT_LOG")
    before = cur.fetchone()[0]
    cur.execute("execute task SENTIMENT.REPORTING.TASK_TOP_CHANNELS")
    for _ in range(12):
        time.sleep(10)
        cur.execute("select count(*) from SENTIMENT.REPORTING.REPORT_LOG")
        after = cur.fetchone()[0]
        if after > before:
            break
    ok = after > before
    failures += not ok
    print(f"  {'PASS' if ok else 'FAIL'}  {'task fires':22s} log rows {before} -> {after}")

    print(f"\n{3 - failures}/3 passed")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
