-- ACS transport. Owns SP_SEND_EMAIL.

create or replace security integration ACS_API_AUTH
    type                 = api_authentication
    auth_type            = oauth2
    oauth_client_id      = '${CLIENT_ID}'
    oauth_client_secret  = '${CLIENT_SECRET}'
    oauth_token_endpoint = 'https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token'
    oauth_grant          = client_credentials
    oauth_allowed_scopes = ('https://communication.azure.com/.default')
    enabled              = true;

create or replace network rule SENTIMENT.REPORTING.ACS_NETWORK_RULE
    mode       = egress
    type       = host_port
    value_list = ('${ACS_HOST}:443', 'login.microsoftonline.com:443');

create or replace secret SENTIMENT.REPORTING.ACS_OAUTH_SECRET
    type               = oauth2
    api_authentication = ACS_API_AUTH
    oauth_scopes       = ('https://communication.azure.com/.default');

create or replace external access integration ACS_ACCESS
    allowed_network_rules          = (SENTIMENT.REPORTING.ACS_NETWORK_RULE)
    allowed_authentication_secrets = (SENTIMENT.REPORTING.ACS_OAUTH_SECRET)
    enabled                        = true;

-- ACS authorises via RBAC at the resource, so `roles` is empty.
create or replace function SENTIMENT.REPORTING.ACS_TOKEN_INFO()
returns variant
language python
runtime_version = '3.11'
handler = 'info'
external_access_integrations = (ACS_ACCESS)
secrets = ('cred' = SENTIMENT.REPORTING.ACS_OAUTH_SECRET)
packages = ('requests')
as
$$
import base64
import json

import _snowflake


def info():
    token = _snowflake.get_oauth_access_token('cred')
    payload = token.split('.')[1]
    payload += '=' * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    return {
        'aud': claims.get('aud'),
        'tid': claims.get('tid'),
        'app_id': claims.get('appid') or claims.get('azp'),
        'roles': claims.get('roles', []),
    }
$$;

-- CREATE OR REPLACE leaves old arities as overloads; drop them.
drop function if exists SENTIMENT.REPORTING.SEND_ACS_EMAIL(varchar, varchar, array, varchar, varchar);
drop procedure if exists SENTIMENT.REPORTING.SP_SEND_EMAIL(varchar, array, varchar, varchar);

create or replace function SENTIMENT.REPORTING.SEND_ACS_EMAIL(
    ENDPOINT varchar, SENDER varchar, RECIPIENTS array, SUBJECT varchar, HTML varchar,
    ATTACHMENT_NAME varchar, ATTACHMENT_B64 varchar)
returns varchar
language python
runtime_version = '3.11'
handler = 'send'
external_access_integrations = (ACS_ACCESS)
secrets = ('cred' = SENTIMENT.REPORTING.ACS_OAUTH_SECRET)
packages = ('requests')
as
$$
import _snowflake
import requests


def send(endpoint, sender, recipients, subject, html, attachment_name, attachment_b64):
    token = _snowflake.get_oauth_access_token('cred')
    payload = {
        "senderAddress": sender,
        "content": {"subject": subject, "html": html},
        "recipients": {"to": [{"address": a} for a in recipients]},
    }
    if attachment_name and attachment_b64:
        payload["attachments"] = [{
            "name": attachment_name,
            "contentType": "text/csv",
            "contentInBase64": attachment_b64,
        }]
    resp = requests.post(
        f"https://{endpoint}/emails:send?api-version=2023-03-31",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
        timeout=30,
    )
    if resp.status_code not in (200, 202):
        raise RuntimeError(f"ACS {resp.status_code}: {resp.text[:300]}")
    return "SENT"
$$;

create or replace procedure SENTIMENT.REPORTING.SP_SEND_EMAIL(
    SENDER varchar, RECIPIENTS array, SUBJECT varchar, HTML varchar,
    ATTACHMENT_NAME varchar, ATTACHMENT_B64 varchar)
returns varchar
language sql
as
$$
declare
    v_endpoint varchar;
begin
    select value into :v_endpoint
      from SENTIMENT.REPORTING.REPORT_CONFIG where key = 'acs_endpoint';
    return (select SENTIMENT.REPORTING.SEND_ACS_EMAIL(
                :v_endpoint, :SENDER, :RECIPIENTS, :SUBJECT, :HTML,
                :ATTACHMENT_NAME, :ATTACHMENT_B64));
end;
$$;
