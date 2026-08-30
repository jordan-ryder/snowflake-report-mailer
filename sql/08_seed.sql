delete from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION where name in
    ('monthly_sentiment', 'top_channels', 'demo_blocked_recipient');

insert into SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
    (name, description, query_text, order_by, columns, subject, recipients,
     frequency, hour_utc, day_of_week, day_of_month, enabled)
select
    'monthly_sentiment',
    'Most recent months of YouTube sentiment by channel',
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
    array_construct('${REPORT_RECIPIENT}'),
    'MONTHLY', 13, null, 1, true
union all
select
    'top_channels',
    'Top channels by comment volume',
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
    array_construct('${REPORT_RECIPIENT}'),
    'WEEKLY', 13, 1, null, true
union all
-- Disabled. Exists to demonstrate the recipient-domain guard; run it by hand.
select
    'demo_blocked_recipient',
    'Deliberately targets a disallowed domain to prove the guard fires',
    $$select 1 as n$$,
    'n',
    array_construct(object_construct('key', 'N', 'label', 'N')),
    'Should never send',
    array_construct('someone@example.com'),
    'MONTHLY', 13, null, 1, false;
