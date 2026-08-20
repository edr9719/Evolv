-- Build 19: retry-safe enrollment, non-consuming invitation validation, and
-- a guarded operational recovery path for enrollment responses lost by a client.

alter table public.pilot_participants
  add column if not exists enrollment_idempotency_key uuid,
  add column if not exists enrollment_invite_hash text,
  add column if not exists credential_version text not null default 'server_hmac_v1';

create unique index if not exists pilot_participants_enrollment_idempotency
  on public.pilot_participants (enrollment_idempotency_key)
  where enrollment_idempotency_key is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'pilot_participants_enrollment_invite_hash_check'
       and conrelid = 'public.pilot_participants'::regclass
  ) then
    alter table public.pilot_participants
      add constraint pilot_participants_enrollment_invite_hash_check
      check (enrollment_invite_hash is null or enrollment_invite_hash ~ '^[0-9a-f]{64}$');
  end if;
  if not exists (
    select 1 from pg_constraint
     where conname = 'pilot_participants_credential_version_check'
       and conrelid = 'public.pilot_participants'::regclass
  ) then
    alter table public.pilot_participants
      add constraint pilot_participants_credential_version_check
      check (credential_version in ('server_hmac_v1', 'client_verifier_v2'));
  end if;
end $$;

create table if not exists public.pilot_enrollment_recovery_audit (
  id bigint generated always as identity primary key,
  study_id uuid not null,
  participant_reference_hash text not null check (participant_reference_hash ~ '^[0-9a-f]{64}$'),
  action text not null check (action = 'orphan_removed_invite_reset'),
  recovered_at timestamptz not null default now()
);

alter table public.pilot_enrollment_recovery_audit enable row level security;
alter table public.pilot_enrollment_recovery_audit force row level security;
revoke all on table public.pilot_enrollment_recovery_audit from public, anon, authenticated;
revoke all on sequence public.pilot_enrollment_recovery_audit_id_seq from public, anon, authenticated;
grant select, insert, update, delete on table public.pilot_enrollment_recovery_audit to service_role;
grant usage, select on sequence public.pilot_enrollment_recovery_audit_id_seq to service_role;

create or replace function public.pilot_validate_invite(
  p_invite_hash text
) returns table (
  validation_status text,
  study_name text,
  pilot_closes_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.pilot_invites%rowtype;
  v_study public.pilot_studies%rowtype;
begin
  select * into v_invite
    from public.pilot_invites
   where invite_hash = p_invite_hash;
  if not found then
    return query select 'invite_invalid'::text, null::text, null::timestamptz;
    return;
  end if;
  select * into v_study from public.pilot_studies where id = v_invite.study_id;
  if v_invite.used_at is not null then
    return query select 'invite_used'::text, v_study.name, v_study.closes_at;
    return;
  elsif v_invite.expires_at <= now() then
    return query select 'invite_expired'::text, v_study.name, v_study.closes_at;
    return;
  elsif not found or v_study.status <> 'active' or v_study.closes_at <= now() then
    return query select 'study_closed'::text, v_study.name, v_study.closes_at;
    return;
  elsif (
    select count(*) from public.pilot_participants participant
     where participant.study_id = v_study.id
  ) >= v_study.max_participants then
    return query select 'study_full'::text, v_study.name, v_study.closes_at;
    return;
  end if;
  return query select 'valid'::text, v_study.name, v_study.closes_at;
end;
$$;

create or replace function public.pilot_redeem_invite_v2(
  p_invite_hash text,
  p_enrollment_idempotency_key uuid,
  p_participant_token_hash text,
  p_recovery_code_hash text
) returns table (
  participant_id uuid,
  study_id uuid,
  study_name text,
  pilot_closes_at timestamptz,
  results_delete_after timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.pilot_invites%rowtype;
  v_study public.pilot_studies%rowtype;
  v_existing public.pilot_participants%rowtype;
  v_participant public.pilot_participants%rowtype;
begin
  if p_enrollment_idempotency_key is null or
     p_invite_hash !~ '^[0-9a-f]{64}$' or
     p_participant_token_hash !~ '^[0-9a-f]{64}$' or
     p_recovery_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_enrollment_request';
  end if;

  -- Serialize by client operation identity before locking an invitation. This
  -- prevents one key racing across two invitations in the same or another study.
  perform pg_advisory_xact_lock(hashtextextended(p_enrollment_idempotency_key::text, 0));

  select * into v_existing from public.pilot_participants
   where enrollment_idempotency_key = p_enrollment_idempotency_key
   for update;
  if found then
    if v_existing.enrollment_invite_hash <> p_invite_hash or
       v_existing.participant_token_hash <> p_participant_token_hash or
       v_existing.recovery_code_hash <> p_recovery_code_hash or
       v_existing.credential_version <> 'client_verifier_v2' or
       not exists (
         select 1 from public.pilot_invites existing_invite
          where existing_invite.invite_hash = p_invite_hash
            and existing_invite.participant_id = v_existing.id
            and existing_invite.study_id = v_existing.study_id
            and existing_invite.used_at is not null
       ) then
      raise exception 'enrollment_idempotency_conflict';
    end if;
    select * into v_study from public.pilot_studies where id = v_existing.study_id;
    return query select
      v_existing.id,
      v_study.id,
      v_study.name,
      v_study.closes_at,
      v_existing.enrolled_at + interval '12 months';
    return;
  end if;

  select * into v_invite from public.pilot_invites
   where invite_hash = p_invite_hash
   for update;
  if not found then raise exception 'invite_invalid'; end if;
  if v_invite.used_at is not null then raise exception 'invite_used'; end if;
  if v_invite.expires_at <= now() then raise exception 'invite_expired'; end if;

  select * into v_study from public.pilot_studies
   where id = v_invite.study_id
   for update;
  if not found or v_study.status <> 'active' or v_study.closes_at <= now() then
    raise exception 'study_closed';
  end if;
  if (
    select count(*) from public.pilot_participants participant
     where participant.study_id = v_study.id
  ) >= v_study.max_participants then
    raise exception 'study_full';
  end if;

  insert into public.pilot_participants (
    study_id, participant_token_hash, recovery_code_hash,
    enrollment_idempotency_key, enrollment_invite_hash, credential_version
  ) values (
    v_study.id, p_participant_token_hash, p_recovery_code_hash,
    p_enrollment_idempotency_key, p_invite_hash, 'client_verifier_v2'
  ) returning * into v_participant;

  update public.pilot_invites
     set used_at = now(), participant_id = v_participant.id
   where id = v_invite.id;

  return query select
    v_participant.id,
    v_study.id,
    v_study.name,
    v_study.closes_at,
    v_participant.enrolled_at + interval '12 months';
end;
$$;

create or replace function public.pilot_recover_orphaned_enrollment(
  p_study_id uuid,
  p_invite_hash text,
  p_participant_id uuid,
  p_participant_reference_hash text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.pilot_invites%rowtype;
  v_participant public.pilot_participants%rowtype;
begin
  select * into v_invite from public.pilot_invites
   where study_id = p_study_id and invite_hash = p_invite_hash
   for update;
  if not found or v_invite.participant_id <> p_participant_id or v_invite.used_at is null then
    raise exception 'orphan_recovery_mismatch';
  end if;
  select * into v_participant from public.pilot_participants
   where id = p_participant_id and study_id = p_study_id
   for update;
  if not found or
     exists (select 1 from public.pilot_consents where participant_id = p_participant_id) or
     exists (select 1 from public.pilot_sessions where participant_id = p_participant_id) or
     exists (select 1 from public.pilot_submissions where participant_id = p_participant_id) then
    raise exception 'participant_not_orphaned';
  end if;

  delete from public.pilot_participants where id = p_participant_id;
  update public.pilot_invites
     set used_at = null, participant_id = null
   where id = v_invite.id;
  insert into public.pilot_enrollment_recovery_audit (
    study_id, participant_reference_hash, action
  ) values (
    p_study_id, p_participant_reference_hash, 'orphan_removed_invite_reset'
  );
  return true;
end;
$$;

revoke all on function public.pilot_validate_invite(text) from public, anon, authenticated;
revoke all on function public.pilot_redeem_invite_v2(text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.pilot_recover_orphaned_enrollment(uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function public.pilot_validate_invite(text) to service_role;
grant execute on function public.pilot_redeem_invite_v2(text, uuid, text, text) to service_role;
grant execute on function public.pilot_recover_orphaned_enrollment(uuid, text, uuid, text) to service_role;
