create schema if not exists SENTIMENT.REPORTING;

create or replace table SENTIMENT.REPORTING.REPORT_SUBSCRIPTION (
    subscription_id number identity primary key,
    name            varchar not null unique,
    description     varchar,
    query_text      varchar not null,
    order_by        varchar not null,
    columns         array   not null,   -- [{"key":"MONTH","label":"Month"}]
    subject         varchar not null,
    recipients      array   not null,
    created_at      timestamp_ntz default current_timestamp()
);

create or replace table SENTIMENT.REPORTING.REPORT_LOG (
    log_id          number identity primary key,
    subscription_id number,
    name            varchar,
    row_count       number,
    status          varchar,    -- SENT|FAILED|SKIPPED_EMPTY|BLOCKED_RECIPIENT|RENDERED
    error           varchar,
    created_at      timestamp_ntz default current_timestamp()
);

create table if not exists SENTIMENT.REPORTING.REPORT_CONFIG (
    key   varchar primary key,
    value varchar
);
