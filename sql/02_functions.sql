create or replace function SENTIMENT.REPORTING.HTML_ESCAPE(S varchar)
returns varchar
language sql
as
$$
    replace(replace(replace(replace(coalesce(S, ''),
        '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;')
$$;

