-- Schedule predicate, extracted so it can be tested against arbitrary timestamps
-- rather than only against sysdate(). SP_DISPATCH passes sysdate() for NOW_UTC.
create or replace function SENTIMENT.REPORTING.IS_DUE(
    FREQUENCY    varchar,
    HOUR_UTC     number,
    DAY_OF_WEEK  number,        -- 0=Sunday .. 6=Saturday
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
    -- never re-send inside the same hourly dispatch window
    and (LAST_SENT_AT is null or LAST_SENT_AT < dateadd(minute, -50, NOW_UTC))
$$;
