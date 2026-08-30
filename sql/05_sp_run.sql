-- Render one subscription, record it in the outbox, and send if enabled.
create or replace procedure SENTIMENT.REPORTING.SP_RUN_REPORT(SUBSCRIPTION_NAME varchar)
returns varchar
language sql
as
$$
declare
    v_id           number;
    v_subject      varchar;
    v_recipients   array;
    v_render       variant;
    v_html         varchar;
    v_csv          varchar;
    v_rows         number;
    v_att_name     varchar;
    v_att_b64      varchar;
    v_status       varchar;
    v_error        varchar default null;
    v_send_enabled boolean;
    v_sender       varchar;
    v_domains      varchar;
    v_bad          number;
    v_send_result  varchar;
begin
    select subscription_id, subject, recipients
      into :v_id, :v_subject, :v_recipients
      from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
     where name = :SUBSCRIPTION_NAME;

    select to_boolean(value) into :v_send_enabled
      from SENTIMENT.REPORTING.REPORT_CONFIG where key = 'send_enabled';
    select value into :v_sender
      from SENTIMENT.REPORTING.REPORT_CONFIG where key = 'sender_mailbox';
    select value into :v_domains
      from SENTIMENT.REPORTING.REPORT_CONFIG where key = 'recipient_domains';

    -- One bad INSERT should not be able to mail the entire internet from the tenant.
    select count(*) into :v_bad
      from table(flatten(input => :v_recipients)) r
     where lower(split_part(r.value::string, '@', 2)) not in (
               select lower(trim(s.value))
                 from table(split_to_table(:v_domains, ',')) s
           );

    call SENTIMENT.REPORTING.SP_RENDER_REPORT(:SUBSCRIPTION_NAME);
    select $1 into :v_render from table(result_scan(last_query_id()));
    v_html := v_render:html::varchar;
    v_csv  := v_render:csv::varchar;
    v_rows := v_render:row_count::number;

    v_att_name := :SUBSCRIPTION_NAME || '_' || to_char(sysdate(), 'YYYY-MM-DD') || '.csv';
    v_att_b64  := base64_encode(to_binary(v_csv, 'UTF-8'));

    if (v_bad > 0) then
        v_status := 'BLOCKED_RECIPIENT';
        v_error  := v_bad || ' recipient(s) outside allowed domains: ' || v_domains;
    elseif (v_rows = 0) then
        v_status := 'SKIPPED_EMPTY';
    elseif (not v_send_enabled) then
        v_status := 'RENDERED';
    else
        begin
            call SENTIMENT.REPORTING.SP_SEND_EMAIL(
                :v_sender, :v_recipients, :v_subject, :v_html, :v_att_name, :v_att_b64);
            select $1 into :v_send_result from table(result_scan(last_query_id()));
            v_status := 'SENT';
        exception
            when other then
                v_status := 'FAILED';
                v_error  := sqlerrm;
        end;
    end if;

    insert into SENTIMENT.REPORTING.REPORT_OUTBOX
        (subscription_id, name, subject, recipients, html, csv, attachment_name,
         row_count, status, error)
    select :v_id, :SUBSCRIPTION_NAME, :v_subject, :v_recipients, :v_html, :v_csv,
           :v_att_name, :v_rows, :v_status, :v_error;

    if (v_status in ('SENT', 'RENDERED')) then
        update SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
           set last_sent_at = sysdate()
         where subscription_id = :v_id;
    end if;

    return v_status || ' (' || v_rows || ' rows)';
end;
$$;
