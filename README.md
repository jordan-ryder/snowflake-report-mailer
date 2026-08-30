# Snowflake report mailer

Scheduled HTML reports, built in SQL and sent from Snowflake via Azure Communication
Services. No orchestrator, no app server. Adding a report is an `INSERT`.

```
TASK DISPATCH_REPORTS       hourly cron
 └─ SP_DISPATCH             picks subscriptions due now (IS_DUE)
     └─ SP_RUN_REPORT       guards recipients, writes outbox, sends
         ├─ SP_RENDER_REPORT   HTML + CSV, pure SQL
         └─ SP_SEND_EMAIL      → SEND_ACS_EMAIL (Python UDF → ACS)
```

Snowflake's `API_AUTHENTICATION` integration owns the OAuth token, so the UDF just POSTs.

## Setup

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars    # subscription + Entra client id
terraform init && terraform apply               # ACS, sending domain, scoped RBAC role

cd ..
cp secrets.local.toml.example secrets.local.toml  # fill from `terraform output`
python deploy.py                                  # sql/01-09
python deploy.py --file 91_acs_send               # transport
```

Then `alter task SENTIMENT.REPORTING.DISPATCH_REPORTS resume;`

The Entra app needs no redirect URI - it's client credentials.

## Adding a report

```sql
insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
    (name, query_text, order_by, columns, subject, recipients, frequency, hour_utc, day_of_week)
select 'weekly_volume',
       $$select channel, sum(comments) as comments from ... group by channel$$,
       'comments desc',
       array_construct(object_construct('key','CHANNEL', 'label','Channel'),
                       object_construct('key','COMMENTS','label','Comments')),
       'Weekly volume', array_construct('someone@example.com'),
       'WEEKLY', 13, 1;
```

`columns` sets order and headers. `order_by` is required - `array_agg` has no inherent order.

## Layout

| | |
|---|---|
| `sql/01-09` | tables, renderer, dispatch, task, config |
| `sql/91` | ACS objects + the `SP_SEND_EMAIL` seam |
| `infra/` | Terraform for the Azure side |
| `deploy.py` | applies `sql/`, substitutes `${...}` from `secrets.local.toml` |

`91` is separate because `deploy.py` skips `9x` by default, so redeploying the machinery
can't revert the live send path.

## Guardrails

`recipient_domains` is an allowlist - anything else is `BLOCKED_RECIPIENT`, never sent.
Values are HTML-escaped and CSV-quoted. Empty results are `SKIPPED_EMPTY`. Every render
lands in `REPORT_OUTBOX` whether sent or not.

## Tests

```bash
python test_schedule.py     # IS_DUE, no waiting
python test_scheduler.py    # drops task to 1min, waits for a real firing, restores
python test_poc.py          # renders everything to out/
```
