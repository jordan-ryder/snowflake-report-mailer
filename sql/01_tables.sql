create schema if not exists SENTIMENT.REPORTING;

create table if not exists SENTIMENT.REPORTING.REPORT_SUBSCRIPTION (
    name       varchar primary key,
    query_text varchar,
    order_by   varchar,
    columns    array,      -- [{"key":"MONTH","label":"Month"}]
    subject    varchar,
    recipients array
);

create table if not exists SENTIMENT.REPORTING.REPORT_LOG (
    name       varchar,
    row_count  number,
    created_at timestamp_ntz default current_timestamp()
);
