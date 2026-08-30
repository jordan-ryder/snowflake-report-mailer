-- Created suspended. ALTER TASK ... RESUME when you are ready to go live.
create or replace task SENTIMENT.REPORTING.DISPATCH_REPORTS
    warehouse = COMPUTE_WH
    schedule  = 'USING CRON 0 * * * * UTC'
as
    call SENTIMENT.REPORTING.SP_DISPATCH();
