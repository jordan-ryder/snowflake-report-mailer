# Snowflake report mailer

Scheduled HTML reports, built in SQL and sent from Snowflake via Azure Communication
Services. No orchestrator, no app server.

```
TASK_<REPORT>          one task per report, native cron
 └─ SP_RUN_REPORT      runs the query, logs the run
     └─ SEND_ACS_EMAIL Python UDF: renders the HTML and xlsx, POSTs to ACS
```

Snowflake's `API_AUTHENTICATION` integration owns the OAuth token, so the UDF just POSTs.

## Setup

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars    # subscription, client id, sender_domain
terraform init && terraform apply               # fails linking the domain - expected
# add the DNS records from the dns_records output, verify them in Azure
terraform apply                                 # links it

cd ..
cp secrets.local.toml.example secrets.local.toml  # fill from `terraform output`
python deploy.py
```

Then resume the tasks you want live:

```sql
alter task SENTIMENT.REPORTING.TASK_MONTHLY_SENTIMENT resume;
```

The Entra app needs no redirect URI - it's client credentials.

## Adding a report

```sql
insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION (name, query_text, subject, recipients)
select 'weekly_volume',
       $$select channel       as "Channel",
                sum(comments) as "Comments"
           from ... group by channel
          order by "Comments" desc$$,
       'Weekly volume', array_construct('someone@example.com');

create task SENTIMENT.REPORTING.TASK_WEEKLY_VOLUME
    warehouse = COMPUTE_WH
    schedule  = 'USING CRON 0 13 * * 1 UTC'
as
    call SENTIMENT.REPORTING.SP_RUN_REPORT('weekly_volume');
```

Column headers and their order come from the query itself, so alias them there.
`order_by` is an optional override for the rare case where the query's own
`ORDER BY` doesn't survive aggregation.

## Layout

| | |
|---|---|
| `sql/` | tables, ACS transport (renders the HTML and xlsx), the report procedure, seed |
| `infra/` | Terraform for the Azure side |
| `deploy.py` | applies `sql/`, substitutes `${...}` from `secrets.local.toml` |
| `test_reports.py` | sends both reports and fires a task |

## Notes

Values are HTML-escaped. Successful runs append to `REPORT_LOG`;
failures surface in `TASK_HISTORY`. Suspend a task to stop its report.
