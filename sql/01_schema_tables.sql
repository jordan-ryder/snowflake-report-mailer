-- Reporting machinery. Everything lives in SENTIMENT.REPORTING.
create schema if not exists SENTIMENT.REPORTING;

-- One row per report. Adding a report is an INSERT here, not a deploy.
create table if not exists SENTIMENT.REPORTING.REPORT_SUBSCRIPTION (
    subscription_id number identity primary key,
    name            varchar     not null unique,
    description     varchar,
    query_text      varchar     not null,
    order_by        varchar     not null,   -- sort expression; array_agg needs an explicit order
    columns         array       not null,   -- [{"key":"MONTH","label":"Month"}] drives column order + headers
    subject         varchar     not null,
    recipients      array       not null,
    frequency       varchar     not null,   -- HOURLY | DAILY | WEEKLY | MONTHLY
    hour_utc        number      default 13,
    day_of_week     number,                 -- 0=Sun..6=Sat, WEEKLY only
    day_of_month    number,                 -- MONTHLY only
    enabled         boolean     default true,
    last_sent_at    timestamp_ntz,
    created_at      timestamp_ntz default current_timestamp()
);

-- Every render lands here whether or not it is sent. Audit trail + POC inspection.
create table if not exists SENTIMENT.REPORTING.REPORT_OUTBOX (
    outbox_id       number identity primary key,
    subscription_id number,
    name            varchar,
    subject         varchar,
    recipients      array,
    html            varchar,
    row_count       number,
    csv             varchar,
    attachment_name varchar,
    status          varchar,    -- RENDERED | SENT | FAILED | SKIPPED_EMPTY | BLOCKED_RECIPIENT
    error           varchar,
    created_at      timestamp_ntz default current_timestamp()
);

create table if not exists SENTIMENT.REPORTING.REPORT_CONFIG (
    key   varchar primary key,
    value varchar
);


-- Migrations for tables created before the CSV attachment existed.
alter table SENTIMENT.REPORTING.REPORT_OUTBOX add column if not exists csv varchar;
alter table SENTIMENT.REPORTING.REPORT_OUTBOX add column if not exists attachment_name varchar;
