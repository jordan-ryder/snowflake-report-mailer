-- Created suspended.
create or replace task SENTIMENT.REPORTING.DISPATCH_REPORTS
    warehouse = COMPUTE_WH
    schedule  = 'USING CRON 0 * * * * UTC'
as
    call SENTIMENT.REPORTING.SP_DISPATCH();
