delete from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION where name in ('monthly_sentiment', 'top_channels');

insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
    (name, query_text, order_by, columns, subject, recipients)
select
    'monthly_sentiment',
    $$select to_char(month, 'YYYY-MM') as month, channel, comments,
             round(pct_positive, 1) as pct_positive,
             round(pct_negative, 1) as pct_negative
        from SENTIMENT.ANALYTICS.MART_YOUTUBE_SENTIMENT_MONTHLY
      qualify row_number() over (order by month desc, comments desc) <= 15$$,
    'month desc, comments desc',
    array_construct(
        object_construct('key', 'MONTH',        'label', 'Month'),
        object_construct('key', 'CHANNEL',      'label', 'Channel'),
        object_construct('key', 'COMMENTS',     'label', 'Comments'),
        object_construct('key', 'PCT_POSITIVE', 'label', '% Positive'),
        object_construct('key', 'PCT_NEGATIVE', 'label', '% Negative')),
    'YouTube sentiment - monthly',
    array_construct('${REPORT_RECIPIENT}')
union all
select
    'top_channels',
    $$select channel, sum(comments) as comments,
             round(avg(pct_positive), 1) as avg_pct_positive
        from SENTIMENT.ANALYTICS.MART_YOUTUBE_SENTIMENT_MONTHLY
       group by channel
      qualify row_number() over (order by sum(comments) desc) <= 10$$,
    'comments desc',
    array_construct(
        object_construct('key', 'CHANNEL',          'label', 'Channel'),
        object_construct('key', 'COMMENTS',         'label', 'Comments'),
        object_construct('key', 'AVG_PCT_POSITIVE', 'label', 'Avg % Positive')),
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
