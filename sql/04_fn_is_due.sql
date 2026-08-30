create or replace function SENTIMENT.REPORTING.IS_DUE(
    FREQUENCY    varchar,
    HOUR_UTC     number,
    DAY_OF_WEEK  number,        -- 0=Sun..6=Sat
    DAY_OF_MONTH number,
    LAST_SENT_AT timestamp_ntz,
    NOW_UTC      timestamp_ntz)
returns boolean
language sql
as
$$
    case FREQUENCY
        when 'HOURLY'  then true
        when 'DAILY'   then hour(NOW_UTC) = HOUR_UTC
        when 'WEEKLY'  then hour(NOW_UTC) = HOUR_UTC and dayofweek(NOW_UTC) = DAY_OF_WEEK
        when 'MONTHLY' then hour(NOW_UTC) = HOUR_UTC and dayofmonth(NOW_UTC) = DAY_OF_MONTH
        else false
    end
    and (LAST_SENT_AT is null or LAST_SENT_AT < dateadd(minute, -50, NOW_UTC))
$$;
