-- Runtime configuration. Declarative: re-running resets values to what is here.
-- ${ACS_HOST} and ${SENDER} are substituted from secrets.local.toml at deploy time.
merge into SENTIMENT.REPORTING.REPORT_CONFIG t
using (
    select 'acs_endpoint'      as key, '${ACS_HOST}' as value
    union all select 'sender_mailbox',    '${SENDER}'
    union all select 'send_enabled',      'true'
    union all select 'recipient_domains', '${RECIPIENT_DOMAINS}'
) s on t.key = s.key
when matched then update set value = s.value
when not matched then insert (key, value) values (s.key, s.value);
