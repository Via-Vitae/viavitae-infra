# ansible/roles/bitrix24

Install and configure Bitrix24 CRM on a host in the `bitrix24` and `dmz` groups.

The role is gated on ADR-007 conditions 7 and 8 (legal review and DPIA approval); it
refuses to run in production if the approvals are not present in the inventory.

Bitrix24 is a vendor LAMP stack; the database is on a separate host (crm-db-01) in the
dmz VLAN. The application server runs Apache + PHP only.

## What the role does not do

- It does not install Bitrix24 itself. The vendor installer must be run manually or via
  a separate playbook. This role configures the host for Bitrix24.
- It does not configure TLS termination. That is HAProxy's job.
- It does not configure the database. That is the `postgres` role's job on crm-db-01.
