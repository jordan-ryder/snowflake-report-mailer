create or replace procedure SENTIMENT.REPORTING.SP_DISPATCH()
returns varchar
language sql
as
$$
declare
    v_n     number default 0;
    v_names varchar default '';
    v_name  varchar;
begin
    let cur cursor for
        select name
          from SENTIMENT.REPORTING.REPORT_SUBSCRIPTION
         where enabled
           and SENTIMENT.REPORTING.IS_DUE(frequency, hour_utc, day_of_week,
                                          day_of_month, last_sent_at, sysdate());

    for rec in cur do
        -- rec.name is not bindable directly
        v_name := rec.name;
        call SENTIMENT.REPORTING.SP_RUN_REPORT(:v_name);
        v_n := v_n + 1;
        v_names := v_names || iff(v_names = '', '', ', ') || v_name;
    end for;

    return 'dispatched ' || v_n || iff(v_n = 0, '', ': ' || v_names);
end;
$$;
