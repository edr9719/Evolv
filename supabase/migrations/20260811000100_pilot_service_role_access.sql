-- The pilot tables are private and never exposed to anon/authenticated users.
-- Edge Functions use the service-role client, which bypasses RLS but still
-- requires ordinary SQL privileges. Keep these grants explicit and scoped to
-- the pilot schema surface rather than granting access to all public tables.

grant select, insert, update, delete on table
  public.pilot_studies,
  public.pilot_invites,
  public.pilot_participants,
  public.pilot_consents,
  public.pilot_sessions,
  public.pilot_submissions,
  public.pilot_objects,
  public.pilot_receipts,
  public.pilot_request_events,
  public.pilot_deletion_audit
to service_role;

grant usage, select on sequence
  public.pilot_request_events_id_seq,
  public.pilot_deletion_audit_id_seq
to service_role;

revoke all on sequence
  public.pilot_request_events_id_seq,
  public.pilot_deletion_audit_id_seq
from public, anon, authenticated;
