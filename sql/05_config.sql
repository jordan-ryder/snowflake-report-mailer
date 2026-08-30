insert overwrite into SENTIMENT.REPORTING.REPORT_CONFIG (acs_endpoint, sender_mailbox)
select '${ACS_HOST}', '${SENDER}';
