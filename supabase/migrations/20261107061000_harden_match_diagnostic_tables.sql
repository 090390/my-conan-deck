alter table private.match_diagnostic_sessions enable row level security;
alter table private.match_diagnostic_events enable row level security;
alter table private.match_diagnostic_errors enable row level security;
alter table private.match_diagnostic_admin_attempts enable row level security;

revoke all on all tables in schema private from public, anon, authenticated, service_role;

comment on schema private is 'Internal database objects; match diagnostic records are accessed only through authenticated or service-role checked functions.';
comment on table private.match_diagnostic_sessions is 'Independent match diagnostic sessions; room_id is intentionally not a foreign key so records survive game cleanup.';
comment on table private.match_diagnostic_errors is 'Diagnostic reports retained for exactly 60 days from reported_at.';