delete from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION where name in ('monthly_sentiment', 'top_channels');

insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
    (name, query_text, subject, recipients)
select
    'monthly_sentiment',
    $$select to_char(month, 'YYYY-MM')     as "Month",
             channel                       as "Channel",
             comments                      as "Comments",
             round(pct_positive, 1)        as "% Positive",
             round(pct_negative, 1)        as "% Negative"
        from SENTIMENT.ANALYTICS.MART_YOUTUBE_SENTIMENT_MONTHLY
       order by month desc, comments desc
       limit 15$$,
    'YouTube sentiment - monthly',
    array_construct('${REPORT_RECIPIENT}')
union all
select
    'top_channels',
    $$select channel                   as "Channel",
             sum(comments)             as "Comments",
             round(avg(pct_positive),1) as "Avg % Positive"
        from SENTIMENT.ANALYTICS.MART_YOUTUBE_SENTIMENT_MONTHLY
       group by channel
       order by "Comments" desc
       limit 10$$,
    'Top channels by volume',
    array_construct('${REPORT_RECIPIENT}');

-- One task per report. Created suspended.
create or replace task SENTIMENT.REPORTING.TASK_MONTHLY_SENTIMENT
    warehouse = COMPUTE_WH
    schedule  = 'USING CRON 0 13 1 * * UTC'
as
    call SENTIMENT.REPORTING.SP_RUN_REPORT('monthly_sentiment');

create or replace task SENTIMENT.REPORTING.TASK_TOP_CHANNELS
    warehouse = COMPUTE_WH
    schedule  = 'USING CRON 0 13 * * 1 UTC'
as
    call SENTIMENT.REPORTING.SP_RUN_REPORT('top_channels');
