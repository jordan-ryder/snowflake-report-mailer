create or replace function SENTIMENT.REPORTING.HTML_ESCAPE(S varchar)
returns varchar
language sql
as
$$
    replace(replace(replace(replace(coalesce(S, ''),
        '&', '&amp;'),
        '<', '&lt;'),
        '>', '&gt;'),
        '"', '&quot;')
$$;

-- RFC 4180 field.
create or replace function SENTIMENT.REPORTING.CSV_ESCAPE(S varchar)
returns varchar
language sql
as
$$
    '"' || replace(coalesce(S, ''), '"', '""') || '"'
$$;
