# Snowflake report mailer

Scheduled HTML reports, generated and sent entirely from Snowflake. No orchestrator,
no application server, no ETL job. A Snowflake task builds the report in SQL and hands
it to Azure Communication Services to deliver.

Adding a new report is an `INSERT`, not a deploy.

## Why this shape

The usual approaches all put the report logic somewhere other than the database:

| Approach | Cost |
|---|---|
| Airflow / Logic Apps / Functions | An orchestrator to run, patch, and pay for |
| Snowflake native email | Only sends to verified users **in the account** - useless for external recipients, and no attachments |
| BI tool subscriptions | Works well, but that is a second product to buy and administer |

This keeps the report next to the data. The only code outside SQL is a ~20-line Python
UDF that POSTs to an HTTP endpoint, and Snowflake handles the OAuth token for it.

## Architecture

```
TASK DISPATCH_REPORTS            hourly cron, native Snowflake scheduler
 └─ SP_DISPATCH()                selects subscriptions due now via IS_DUE()
     └─ SP_RUN_REPORT(name)      guards recipients, records to outbox, sends
         ├─ SP_RENDER_REPORT()   builds the HTML table and CSV in pure SQL
         └─ SP_SEND_EMAIL()      seam -> SEND_ACS_EMAIL (Python UDF -> ACS REST)
```

Authentication is an Entra app registration holding an RBAC role scoped to a single
ACS resource. Snowflake's `SECURITY INTEGRATION ... TYPE = API_AUTHENTICATION` performs
the client-credentials exchange and refresh, so the UDF never handles a token lifecycle.

Egress is denied by default: `SEND_ACS_EMAIL` can reach only the two hosts named in
`ACS_NETWORK_RULE`.

## Layout

```
sql/01-09          transport-agnostic machinery: tables, render, dispatch, task, config
sql/91_acs_send    the transport: ACS integration objects and the SP_SEND_EMAIL seam
infra/             Terraform for the Azure side (ACS + email domain + role assignment)
deploy.py          applies sql/, substituting ${...} from secrets.local.toml
test_schedule.py   unit tests for the schedule predicate
test_scheduler.py  live test that the task actually fires
test_poc.py        renders every subscription and dumps the HTML locally
```

`91` is separate on purpose: `deploy.py` skips `9x` by default, so a routine redeploy of
the machinery can never silently revert the live send path.

## Setup

1. **Azure.** Register an Entra app (no redirect URI - this is client credentials), create
   a client secret, then:

   ```bash
   cd infra
   cp terraform.tfvars.example terraform.tfvars   # fill in subscription + client id
   terraform init && terraform apply
   ```

   This creates the Communication Services resource, an Azure-managed sending domain, and
   grants the app `Communication and Email Service Owner` scoped to that resource only.

2. **Config.** `cp secrets.local.toml.example secrets.local.toml` and fill in, using
   `terraform output` for the ACS values.

3. **Deploy.**

   ```bash
   python deploy.py                     # machinery
   python deploy.py --file 91_acs_send  # transport
   python deploy.py --check             # verify
   ```

4. **Go live.** `alter task SENTIMENT.REPORTING.DISPATCH_REPORTS resume;`

## Adding a report

```sql
insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
    (name, query_text, order_by, columns, subject, recipients,
     frequency, hour_utc, day_of_week)
select 'weekly_volume',
       $$select channel, sum(comments) as comments from ... group by channel$$,
       'comments desc',
       array_construct(object_construct('key','CHANNEL', 'label','Channel'),
                       object_construct('key','COMMENTS','label','Comments')),
       'Weekly volume',
       array_construct('someone@example.com'),
       'WEEKLY', 13, 1;
```

`columns` drives both column order and header labels. `order_by` is required: `array_agg`
has no inherent row order, so each subscription names its own sort expression.

## Guardrails

- `REPORT_CONFIG.recipient_domains` is an allowlist. A subscription targeting anything
  else is recorded as `BLOCKED_RECIPIENT` and never sent, so one bad `INSERT` cannot mail
  the internet from your tenant.
- All values are HTML-escaped and CSV-quoted.
- Empty result sets are `SKIPPED_EMPTY` rather than mailing a blank table.
- `SP_DISPATCH` will not re-run a subscription within 50 minutes of its last send.
- Every render is recorded in `REPORT_OUTBOX` with its HTML and CSV, sent or not.

## Notes

- `REPORT_OUTBOX.outbox_id` is an `IDENTITY` column. Snowflake guarantees uniqueness but
  **not** monotonicity, so `order by outbox_id desc` does not give you the latest row.
  Order by `created_at`.
- Cursor fields must be bound: `call SP(:v)` after `v := rec.name`. Using `rec.name`
  directly inside a SQL statement fails with `invalid identifier 'REC.NAME'`.
- `LISTAGG` needs a literal delimiter; `chr(10)` is rejected as non-constant.
- Snowflake network rules do not wildcard across multiple labels, so the ACS hostname is
  listed exactly rather than as `*.communication.azure.com`.
- Entra client secrets expire (24 months max). Put rotation on a calendar.
