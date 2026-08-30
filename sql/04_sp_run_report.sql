-- Renders a subscription to HTML + CSV and sends it.
create or replace procedure SENTIMENT.REPORTING.SP_RUN_REPORT(SUBSCRIPTION_NAME varchar)
returns varchar
language sql
as
$$
declare
    v_id           number;
    v_query        varchar;
    v_order        varchar;
    v_cols         array;
    v_subject      varchar;
    v_recipients   array;
    v_rows         array;
    v_n            number;
    v_head         varchar;
    v_body         varchar;
    v_html         varchar;
    v_csv_hdr      varchar;
    v_csv_bdy      varchar;
    v_att_name     varchar;
    v_status       varchar;
    v_error        varchar default null;
    v_result       varchar;
    v_send_enabled boolean;
    v_sender       varchar;
    v_endpoint     varchar;
    v_domains      varchar;
    v_bad          number;
    v_sql          varchar;
    -- inline only; Outlook and Gmail strip <style>
    th_style varchar default 'background:#1a4f8a;color:#ffffff;padding:10px 14px;'
                          || 'text-align:left;font-weight:600;font-size:13px;white-space:nowrap;';
    td_style varchar default 'padding:9px 14px;border-bottom:1px solid #e5e9ee;';
begin
    select subscription_id, query_text, order_by, columns, subject, recipients
      into :v_id, :v_query, :v_order, :v_cols, :v_subject, :v_recipients
      from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
     where name = :SUBSCRIPTION_NAME;

    select max(iff(key = 'send_enabled',      value, null))::boolean,
           max(iff(key = 'sender_mailbox',    value, null)),
           max(iff(key = 'acs_endpoint',      value, null)),
           max(iff(key = 'recipient_domains', value, null))
      into :v_send_enabled, :v_sender, :v_endpoint, :v_domains
      from SENTIMENT.REPORTING.REPORT_CONFIG;

    v_sql := 'select array_agg(object_construct(*)) within group (order by ' || v_order || ')
                from (' || v_query || ')';
    let rs resultset := (execute immediate :v_sql);
    let cur cursor for rs;
    open cur;
    fetch cur into v_rows;
    close cur;
    v_rows := coalesce(v_rows, array_construct());
    v_n := array_size(v_rows);

    select listagg('<th style="' || :th_style || '">' ||
                   SENTIMENT.REPORTING.HTML_ESCAPE(col.value:label::string) || '</th>', '')
             within group (order by col.index),
           listagg(SENTIMENT.REPORTING.CSV_ESCAPE(col.value:label::string), ',')
             within group (order by col.index)
      into :v_head, :v_csv_hdr
      from table(flatten(input => :v_cols)) col;

    select coalesce(listagg('<tr style="background:' || iff(ridx % 2 = 1, '#f6f8fa', '#ffffff') ||
                            ';">' || cells || '</tr>', '') within group (order by ridx), ''),
           coalesce(listagg(csv_cells, '\n') within group (order by ridx), '')
      into :v_body, :v_csv_bdy
      from (
            select r.index as ridx,
                   listagg('<td style="' || :td_style || '">' ||
                           SENTIMENT.REPORTING.HTML_ESCAPE(
                               coalesce(get(r.value, col.value:key::string)::string, '')) ||
                           '</td>', '') within group (order by col.index) as cells,
                   listagg(SENTIMENT.REPORTING.CSV_ESCAPE(
                               coalesce(get(r.value, col.value:key::string)::string, '')), ',')
                     within group (order by col.index) as csv_cells
              from table(flatten(input => :v_rows)) r
             cross join table(flatten(input => :v_cols)) col
             group by r.index
           );

    v_html := '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1f2328;">'
           || '<h2 style="margin:0 0 4px;font-size:19px;color:#1a4f8a;">'
           || SENTIMENT.REPORTING.HTML_ESCAPE(v_subject) || '</h2>'
           || '<p style="margin:0 0 18px;color:#656d76;font-size:13px;">'
           || v_n || ' rows &middot; ' || to_char(sysdate(), 'YYYY-MM-DD HH24:MI')
           || ' UTC &middot; full data attached</p>'
           || '<table cellpadding="0" cellspacing="0" role="presentation" '
           || 'style="border-collapse:collapse;font-size:14px;border:1px solid #d8dee4;">'
           || '<thead><tr>' || coalesce(v_head, '') || '</tr></thead>'
           || '<tbody>' || v_body || '</tbody></table></div>';

    v_att_name := :SUBSCRIPTION_NAME || '_' || to_char(sysdate(), 'YYYY-MM-DD') || '.csv';

    select count(*) into :v_bad
      from table(flatten(input => :v_recipients)) r
     where lower(split_part(r.value::string, '@', 2)) not in (
               select lower(trim(s.value)) from table(split_to_table(:v_domains, ',')) s);

    if (v_bad > 0) then
        v_status := 'BLOCKED_RECIPIENT';
        v_error  := v_bad || ' recipient(s) outside ' || v_domains;
    elseif (v_n = 0) then
        v_status := 'SKIPPED_EMPTY';
    elseif (not v_send_enabled) then
        v_status := 'RENDERED';
    else
        begin
            select SENTIMENT.REPORTING.SEND_ACS_EMAIL(
                       :v_endpoint, :v_sender, :v_recipients, :v_subject, :v_html,
                       :v_att_name, base64_encode(to_binary(:v_csv_hdr || '\n' || :v_csv_bdy, 'UTF-8')))
              into :v_result;
            v_status := 'SENT';
        exception
            when other then
                v_status := 'FAILED';
                v_error  := sqlerrm;
        end;
    end if;

    insert into SENTIMENT.REPORTING.REPORT_LOG (subscription_id, name, row_count, status, error)
    select :v_id, :SUBSCRIPTION_NAME, :v_n, :v_status, :v_error;

    return v_status || ' (' || v_n || ' rows)';
end;
$$;
