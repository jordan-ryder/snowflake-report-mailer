"""Unit tests for the IS_DUE schedule predicate.

Evaluates it against a fixed NOW rather than sysdate(), so every branch is checked
without waiting for real time to pass.
"""

from deploy import connect

NOW = "'2026-08-29 13:00:00'::timestamp_ntz"  # hour 13, day-of-month 29

# label, frequency, hour_utc, day_of_week, day_of_month, last_sent_at, expected
CASES = [
    ("hourly, never sent",            "HOURLY",  "13", "null", "null", "null",                                  True),
    ("hourly, sent 10m ago",          "HOURLY",  "13", "null", "null", f"dateadd(minute,-10,{NOW})",             False),
    ("hourly, sent 60m ago",          "HOURLY",  "13", "null", "null", f"dateadd(minute,-60,{NOW})",             True),
    ("daily, matching hour",          "DAILY",   "13", "null", "null", "null",                                   True),
    ("daily, wrong hour",             "DAILY",   "14", "null", "null", "null",                                   False),
    ("daily, right hour but recent",  "DAILY",   "13", "null", "null", f"dateadd(minute,-5,{NOW})",              False),
    ("weekly, matching hour+dow",     "WEEKLY",  "13", f"dayofweek({NOW})",   "null", "null",                    True),
    ("weekly, wrong dow",             "WEEKLY",  "13", f"dayofweek({NOW})+1", "null", "null",                    False),
    ("weekly, wrong hour",            "WEEKLY",  "12", f"dayofweek({NOW})",   "null", "null",                    False),
    ("monthly, matching hour+dom",    "MONTHLY", "13", "null", "29",   "null",                                   True),
    ("monthly, wrong dom",            "MONTHLY", "13", "null", "28",   "null",                                   False),
    ("monthly, wrong hour",           "MONTHLY", "12", "null", "29",   "null",                                   False),
    ("unknown frequency",             "NEVER",   "13", "null", "null", "null",                                   False),
]


def main():
    parts = [
        f"select '{label}' as label, {expected} as expected, "
        f"SENTIMENT.REPORTING.IS_DUE('{freq}', {hr}, {dow}, {dom}, {last}, {NOW}) as actual"
        for label, freq, hr, dow, dom, last, expected in CASES
    ]
    cur = connect().cursor()
    cur.execute(" union all ".join(parts))

    failures = 0
    for label, expected, actual in cur.fetchall():
        ok = expected == actual
        failures += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {label:32s} expected={expected} actual={actual}")

    print(f"\n{len(CASES) - failures}/{len(CASES)} passed")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
