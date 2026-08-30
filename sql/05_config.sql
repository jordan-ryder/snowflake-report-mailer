insert overwrite into SENTIMENT.REPORTING.REPORT_CONFIG
    (acs_endpoint, sender_mailbox, recipient_domains, send_enabled)
select '${ACS_HOST}', '${SENDER}', '${RECIPIENT_DOMAINS}', true;
