-- Azure Communication Services transport. Endpoint and sender are baked in at
-- deploy time from secrets.local.toml.

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
    RECIPIENTS array, SUBJECT varchar, HTML varchar,
    ATTACHMENT_NAME varchar, DATA_ROWS array, DATA_COLS array)
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
import io

import _snowflake
import openpyxl
import requests
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

HEADER_FILL = PatternFill("solid", start_color="1A4F8A", end_color="1A4F8A")
HEADER_FONT = Font(color="FFFFFF", bold=True)
EDGE = Side(style="thin", color="C0C0C0")
BORDER = Border(left=EDGE, right=EDGE, top=EDGE, bottom=EDGE)


def workbook(rows, columns):
    keys = [c["key"] for c in columns]
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append([c["label"] for c in columns])
    for row in rows:
        ws.append([row.get(k) for k in keys])

    for cell in ws[1]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="left")
    for row in ws.iter_rows():
        for cell in row:
            cell.border = BORDER

    for i, col in enumerate(ws.columns, start=1):
        width = max(len(str(c.value)) for c in col if c.value is not None)
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = min(width + 4, 50)

    ws.freeze_panes = "A2"
    buf = io.BytesIO()
    wb.save(buf)
    return base64.b64encode(buf.getvalue()).decode()


def send(recipients, subject, html, attachment_name, rows, columns):
    token = _snowflake.get_oauth_access_token('cred')
    resp = requests.post(
        "https://${ACS_HOST}/emails:send?api-version=2023-03-31",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "senderAddress": "${SENDER}",
            "content": {"subject": subject, "html": html},
            "recipients": {"to": [{"address": a} for a in recipients]},
            "attachments": [{
                "name": attachment_name,
                "contentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "contentInBase64": workbook(rows, columns),
            }],
        },
        timeout=30,
    )
    if resp.status_code not in (200, 202):
        raise RuntimeError(f"ACS {resp.status_code}: {resp.text[:300]}")
    return "SENT"
$$;
