create or replace procedure SENTIMENT.REPORTING.SP_RUN_REPORT(SUBSCRIPTION_NAME varchar)
returns varchar
language sql
as
$$
declare
    v_query      varchar;
    v_order      varchar;
    v_cols       array;
    v_subject    varchar;
    v_recipients array;
    v_rows       array;
    v_n          number;
    v_sql        varchar;
begin
    select query_text, order_by, columns, subject, recipients
      into :v_query, :v_order, :v_cols, :v_subject, :v_recipients
      from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
     where name = :SUBSCRIPTION_NAME;

    v_sql := 'select array_agg(object_construct(*)) within group (order by ' || v_order || ')
                as rows_json from (' || v_query || ')';
    execute immediate :v_sql;
    -- reads the statement above; keep them adjacent
    select coalesce(rows_json, array_construct()) into :v_rows
      from table(result_scan(last_query_id()));
    v_n := array_size(v_rows);

    select SENTIMENT.REPORTING.SEND_ACS_EMAIL(
               :v_recipients, :v_subject, :SUBSCRIPTION_NAME, :v_rows, :v_cols);

    insert into SENTIMENT.REPORTING.REPORT_LOG (name, row_count)
    select :SUBSCRIPTION_NAME, :v_n;

    return 'sent ' || v_n || ' rows';
end;
$$;
