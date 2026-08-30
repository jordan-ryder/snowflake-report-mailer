-- Renders one subscription to an HTML email body and a CSV attachment, in SQL.
-- Column order and headers come from the subscription's `columns` config.
create or replace procedure SENTIMENT.REPORTING.SP_RENDER_REPORT(SUBSCRIPTION_NAME varchar)
returns variant
language sql
as
$$
declare
    v_query   varchar;
    v_order   varchar;
    v_cols    array;
    v_subject varchar;
    v_rows    array;
    v_head    varchar;
    v_body    varchar;
    v_html    varchar;
    v_csv_hdr varchar;
    v_csv_bdy varchar;
    v_sql     varchar;
    -- Inline styles only: Outlook and Gmail strip <style> blocks.
    th_style  varchar default 'background:#1a4f8a;color:#ffffff;padding:10px 14px;'
                           || 'text-align:left;font-weight:600;font-size:13px;'
                           || 'letter-spacing:.02em;white-space:nowrap;';
    td_style  varchar default 'padding:9px 14px;border-bottom:1px solid #e5e9ee;';
begin
    select query_text, order_by, columns, subject
      into :v_query, :v_order, :v_cols, :v_subject
      from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
     where name = :SUBSCRIPTION_NAME;

    -- array_agg has no inherent order, so the subscription must name a sort expression
    v_sql := 'select array_agg(object_construct(*)) within group (order by ' || v_order || ') as ROWS_JSON
                from (' || v_query || ')';

    let rs resultset := (execute immediate :v_sql);
    let cur cursor for rs;
    open cur;
    fetch cur into v_rows;
    close cur;
    v_rows := coalesce(v_rows, array_construct());

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
                           '</td>', '')
                     within group (order by col.index) as cells,
                   listagg(SENTIMENT.REPORTING.CSV_ESCAPE(
                               coalesce(get(r.value, col.value:key::string)::string, '')), ',')
                     within group (order by col.index) as csv_cells
              from table(flatten(input => :v_rows)) r
             cross join table(flatten(input => :v_cols)) col
             group by r.index
           );

    v_html := '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;'
           || 'color:#1f2328;padding:4px;">'
           || '<h2 style="margin:0 0 4px;font-size:19px;color:#1a4f8a;">'
           || SENTIMENT.REPORTING.HTML_ESCAPE(v_subject) || '</h2>'
           || '<p style="margin:0 0 18px;color:#656d76;font-size:13px;">'
           || array_size(v_rows) || ' rows &middot; generated '
           || to_char(sysdate(), 'YYYY-MM-DD HH24:MI') || ' UTC &middot; full data attached</p>'
           || '<table cellpadding="0" cellspacing="0" role="presentation" '
           || 'style="border-collapse:collapse;font-size:14px;border:1px solid #d8dee4;">'
           || '<thead><tr>' || coalesce(v_head, '') || '</tr></thead>'
           || '<tbody>' || v_body || '</tbody></table>'
           || '<p style="margin:18px 0 0;color:#8c959f;font-size:12px;">Sent by Snowflake &middot; '
           || SENTIMENT.REPORTING.HTML_ESCAPE(:SUBSCRIPTION_NAME) || '</p></div>';

    return object_construct(
        'html',      v_html,
        'csv',       v_csv_hdr || chr(10) || v_csv_bdy,
        'row_count', array_size(v_rows));
end;
$$;
