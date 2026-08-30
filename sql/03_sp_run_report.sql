create or replace procedure SENTIMENT.REPORTING.SP_RUN_REPORT(SUBSCRIPTION_NAME varchar)
returns varchar
language sql
as
$$
declare
    v_query      varchar;
    v_order      varchar;
    v_subject    varchar;
    v_recipients array;
    v_qid        varchar;
    v_cols       array;
    v_rows       array;
    v_n          number;
    v_sql        varchar;
begin
    select query_text, order_by, subject, recipients
      into :v_query, :v_order, :v_subject, :v_recipients
      from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
     where name = :SUBSCRIPTION_NAME;

    -- run it once; column names and rows both come out of the same result
    execute immediate :v_query;
    v_qid := last_query_id();

    execute immediate 'describe result ''' || v_qid || '''';
    select array_agg("name") into :v_cols from table(result_scan(last_query_id()));

    -- order_by only when set; otherwise the query's own ORDER BY carries through
    v_sql := 'select array_agg(array_construct(*)) '
          || coalesce('within group (order by ' || nullif(v_order, '') || ') ', '')
          || 'as rows_json from table(result_scan(''' || v_qid || '''))';
    execute immediate :v_sql;
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
