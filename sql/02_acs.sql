-- Azure Communication Services transport. Renders the email and sends it.
-- Endpoint and sender are baked in at deploy time from secrets.local.toml.

create or replace security integration ACS_API_AUTH
    type                 = api_authentication
    auth_type            = oauth2
    oauth_client_id      = '${CLIENT_ID}'
    oauth_client_secret  = '${CLIENT_SECRET}'
    oauth_token_endpoint = 'https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token'
    oauth_grant          = client_credentials
    oauth_allowed_scopes = ('https://communication.azure.com/.default')
    enabled              = true;

-- Snowflake fetches the token itself, so the UDF only ever reaches ACS.
create or replace network rule SENTIMENT.REPORTING.ACS_NETWORK_RULE
    mode       = egress
    type       = host_port
    value_list = ('${ACS_HOST}:443');

create or replace secret SENTIMENT.REPORTING.ACS_OAUTH_SECRET
    type               = oauth2
    api_authentication = ACS_API_AUTH
    oauth_scopes       = ('https://communication.azure.com/.default');

create or replace external access integration ACS_ACCESS
    allowed_network_rules          = (SENTIMENT.REPORTING.ACS_NETWORK_RULE)
    allowed_authentication_secrets = (SENTIMENT.REPORTING.ACS_OAUTH_SECRET)
    enabled                        = true;

create or replace function SENTIMENT.REPORTING.SEND_ACS_EMAIL(
    RECIPIENTS array, SUBJECT varchar, REPORT_NAME varchar,
    DATA_ROWS array, DATA_COLS array)
returns varchar
language python
runtime_version = '3.11'
handler = 'send'
external_access_integrations = (ACS_ACCESS)
secrets = ('cred' = SENTIMENT.REPORTING.ACS_OAUTH_SECRET)
packages = ('requests', 'openpyxl')
as
$$
import base64
import html
import io
from datetime import datetime, timezone

import _snowflake
import openpyxl
import requests
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

# inline only; Outlook and Gmail strip <style>
TH = ("background:#1a4f8a;color:#ffffff;padding:10px 14px;text-align:left;"
      "font-weight:600;font-size:13px;white-space:nowrap;")
TD = "padding:9px 14px;border-bottom:1px solid #e5e9ee;"
TABLE = "border-collapse:collapse;font-size:14px;border:1px solid #d8dee4;"
PAGE = "font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1f2328;"

HEADER_FILL = PatternFill("solid", start_color="1A4F8A", end_color="1A4F8A")
HEADER_FONT = Font(color="FFFFFF", bold=True)
EDGE = Side(style="thin", color="C0C0C0")
BORDER = Border(left=EDGE, right=EDGE, top=EDGE, bottom=EDGE)


def cell(value):
    return html.escape("" if value is None else str(value))


def render_html(subject, rows, columns):
    head = "".join(f'<th style="{TH}">{html.escape(c)}</th>' for c in columns)
    body = "".join(
        '<tr style="background:{}">{}</tr>'.format(
            "#f6f8fa;" if i % 2 else "#ffffff;",
            "".join(f'<td style="{TD}">{cell(v)}</td>' for v in row))
        for i, row in enumerate(rows))
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    return (
        f'<div style="{PAGE}">'
        f'<h2 style="margin:0 0 4px;font-size:19px;color:#1a4f8a;">{html.escape(subject)}</h2>'
        f'<p style="margin:0 0 18px;color:#656d76;font-size:13px;">'
        f'{len(rows)} rows &middot; {stamp} UTC &middot; full data attached</p>'
        f'<table cellpadding="0" cellspacing="0" role="presentation" style="{TABLE}">'
        f'<thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'
    )


def render_xlsx(rows, columns):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(list(columns))
    for row in rows:
        ws.append(list(row))

    for c in ws[1]:
        c.fill = HEADER_FILL
        c.font = HEADER_FONT
        c.alignment = Alignment(horizontal="left")
    for row in ws.iter_rows():
        for c in row:
            c.border = BORDER
    for i, col in enumerate(ws.columns, start=1):
        width = max(len(str(c.value)) for c in col if c.value is not None)
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = min(width + 4, 50)

    ws.freeze_panes = "A2"
    buf = io.BytesIO()
    wb.save(buf)
    return base64.b64encode(buf.getvalue()).decode()


def send(recipients, subject, report_name, rows, columns):
    token = _snowflake.get_oauth_access_token('cred')
    resp = requests.post(
        "https://${ACS_HOST}/emails:send?api-version=2023-03-31",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "senderAddress": "${SENDER}",
            "content": {"subject": subject, "html": render_html(subject, rows, columns)},
            "recipients": {"to": [{"address": a} for a in recipients]},
            "attachments": [{
                "name": f"{report_name}_{datetime.now(timezone.utc):%Y-%m-%d}.xlsx",
                "contentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "contentInBase64": render_xlsx(rows, columns),
            }],
        },
        timeout=30,
    )
    if resp.status_code not in (200, 202):
        raise RuntimeError(f"ACS {resp.status_code}: {resp.text[:300]}")
    return "SENT"
$$;
