# Snowflake report mailer

Scheduled HTML reports, built and sent from Snowflake via Azure Communication Services.
No orchestrator, no app server.

```
TASK_<REPORT>          one task per report, native cron
 └─ SP_RUN_REPORT      runs the query, logs the run
     └─ SEND_ACS_EMAIL Python UDF: renders the HTML and xlsx, POSTs to ACS
```

Snowflake's `API_AUTHENTICATION` integration holds the Entra credentials and does the
OAuth exchange, so the UDF just asks for a token and POSTs.

## Setup

Register an Entra app first. No redirect URI - this is client credentials. Note its
client id and create a secret.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars    # subscription, client id, sender_domain
terraform init && terraform apply               # fails linking the domain - expected
# add the DNS records from the dns_records output, verify them in Azure
terraform apply                                 # links it

cd ..
cp secrets.local.toml.example secrets.local.toml  # fill from `terraform output`
python deploy.py
alter task SENTIMENT.REPORTING.TASK_MONTHLY_SENTIMENT resume;
```

Use a dedicated subdomain for `sender_domain`. ACS verifies SPF by exact string match,
so it needs `v=spf1 include:spf.protection.outlook.com -all` alone on that hostname -
which would clash with any SPF already on your root domain.

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

Headers and their order come from the query, so alias columns there. Quote the aliases
or they arrive uppercase.

## Layout

| | |
|---|---|
| `sql/01_tables` | two tables: subscriptions and a run log |
| `sql/02_acs` | ACS integration objects and the UDF that renders and sends |
| `sql/03_sp_run_report` | the procedure a task calls |
| `sql/04_seed` | example reports and their tasks |
| `infra/` | Terraform for the Azure side |
| `deploy.py` | applies `sql/`, substituting `${...}` from `secrets.local.toml` |
| `test_reports.py` | sends both reports and fires a task |

## Notes

Successful runs append to `REPORT_LOG`; failures surface in `TASK_HISTORY`. Suspend a
task to stop its report.

`order_by` on a subscription is an optional override. A plain `ORDER BY` in the query
survives aggregation in practice but isn't guaranteed, so it's there if you need it.

Credentials live in `secrets.local.toml`, which is gitignored. `deploy.py` substitutes
them at deploy time; nothing is committed and Snowflake won't read the secret back out.
