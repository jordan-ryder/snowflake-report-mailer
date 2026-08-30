-- Minimal HTML escaping. Report values are data, not markup.
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

-- RFC 4180 field: always quote, double any embedded quote.
create or replace function SENTIMENT.REPORTING.CSV_ESCAPE(S varchar)
returns varchar
language sql
as
$$
    '"' || replace(coalesce(S, ''), '"', '""') || '"'
$$;
