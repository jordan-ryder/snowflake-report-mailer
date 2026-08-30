create or replace procedure SENTIMENT.REPORTING.SP_RUN_REPORT(SUBSCRIPTION_NAME varchar)
returns varchar
language sql
as
$$
declare
    v_id         number;
    v_query      varchar;
    v_order      varchar;
    v_cols       array;
    v_subject    varchar;
    v_recipients array;
    v_rows       array;
    v_n          number;
    v_head       varchar;
    v_body       varchar;
    v_html       varchar;
    v_csv_hdr    varchar;
    v_csv_bdy    varchar;
    v_sender     varchar;
    v_endpoint   varchar;
    v_sql        varchar;
    v_result     varchar;
    -- inline only; Outlook and Gmail strip <style>
    th_style varchar default 'background:#1a4f8a;color:#ffffff;padding:10px 14px;'
                          || 'text-align:left;font-weight:600;font-size:13px;white-space:nowrap;';
    td_style varchar default 'padding:9px 14px;border-bottom:1px solid #e5e9ee;';
begin
    select subscription_id, query_text, order_by, columns, subject, recipients
      into :v_id, :v_query, :v_order, :v_cols, :v_subject, :v_recipients
      from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
     where name = :SUBSCRIPTION_NAME;

    select acs_endpoint, sender_mailbox
      into :v_endpoint, :v_sender
      from SENTIMENT.REPORTING.REPORT_CONFIG;

    v_sql := 'select array_agg(object_construct(*)) within group (order by ' || v_order || ')
                as rows_json from (' || v_query || ')';
    execute immediate :v_sql;
    -- reads the statement above; keep them adjacent
    select coalesce(rows_json, array_construct()) into :v_rows
      from table(result_scan(last_query_id()));
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
           || '<thead><tr>' || v_head || '</tr></thead>'
           || '<tbody>' || v_body || '</tbody></table></div>';

    select SENTIMENT.REPORTING.SEND_ACS_EMAIL(
               :v_endpoint, :v_sender, :v_recipients, :v_subject, :v_html,
               :SUBSCRIPTION_NAME || '_' || to_char(sysdate(), 'YYYY-MM-DD') || '.csv',
               base64_encode(to_binary(:v_csv_hdr || '\n' || :v_csv_bdy, 'UTF-8')))
      into :v_result;

    insert into SENTIMENT.REPORTING.REPORT_LOG (subscription_id, name, row_count)
    select :v_id, :SUBSCRIPTION_NAME, :v_n;

    return 'sent ' || v_n || ' rows';
end;
$$;
