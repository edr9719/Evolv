create extension if not exists pgcrypto with schema extensions;

create table if not exists public.pilot_studies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  status text not null default 'active' check (status in ('active', 'closed')),
  activated_at timestamptz not null default now(),
  closes_at timestamptz not null default (now() + interval '90 days'),
  public_key_version text not null default 'pilot-p256-v1',
  created_at timestamptz not null default now(),
  check (closes_at > activated_at)
);

create table if not exists public.pilot_invites (
  id uuid primary key default gen_random_uuid(),
  study_id uuid not null references public.pilot_studies(id) on delete cascade,
  invite_hash text not null unique check (invite_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  participant_id uuid
);

create table if not exists public.pilot_participants (
  id uuid primary key default gen_random_uuid(),
  study_id uuid not null references public.pilot_studies(id) on delete cascade,
  participant_token_hash text not null unique check (participant_token_hash ~ '^[0-9a-f]{64}$'),
  recovery_code_hash text not null unique check (recovery_code_hash ~ '^[0-9a-f]{64}$'),
  enrolled_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  status text not null default 'active' check (status in ('active', 'withdrawn'))
);

alter table public.pilot_invites
  drop constraint if exists pilot_invites_participant_id_fkey;
alter table public.pilot_invites
  add constraint pilot_invites_participant_id_fkey
  foreign key (participant_id) references public.pilot_participants(id) on delete set null;

create table if not exists public.pilot_consents (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.pilot_participants(id) on delete cascade,
  version text not null,
  share_scope text not null check (share_scope in ('results_only', 'results_and_selected_photos')),
  adult_confirmed boolean not null check (adult_confirmed),
  selected_photo_count integer not null default 0 check (selected_photo_count between 0 and 15),
  accepted_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    (share_scope = 'results_only' and selected_photo_count = 0) or
    (share_scope = 'results_and_selected_photos' and selected_photo_count > 0)
  )
);

create table if not exists public.pilot_sessions (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.pilot_participants(id) on delete cascade,
  local_session_id uuid not null,
  consent_id uuid not null references public.pilot_consents(id) on delete cascade,
  result_status text not null,
  started_at timestamptz not null,
  completed_at timestamptz,
  app_build text not null,
  analysis_version integer,
  threshold_set_identifier text,
  device_model text not null,
  operating_system_version text not null,
  camera_position text not null,
  lens_type text,
  results_payload jsonb not null,
  results_delete_at timestamptz not null default (now() + interval '12 months'),
  created_at timestamptz not null default now(),
  unique (participant_id, local_session_id),
  check (octet_length(results_payload::text) <= 524288)
);

create table if not exists public.pilot_submissions (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.pilot_participants(id) on delete cascade,
  session_id uuid not null unique references public.pilot_sessions(id) on delete cascade,
  client_submission_id uuid not null,
  idempotency_key uuid not null,
  status text not null default 'initialized' check (status in ('initialized', 'completed')),
  expected_file_count integer not null check (expected_file_count between 0 and 15),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  wrapped_key jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (participant_id, client_submission_id),
  unique (participant_id, idempotency_key),
  check (
    (expected_file_count = 0 and wrapped_key is null) or
    (expected_file_count > 0 and wrapped_key is not null)
  )
);

create table if not exists public.pilot_objects (
  id uuid primary key,
  submission_id uuid not null references public.pilot_submissions(id) on delete cascade,
  set_number integer not null check (set_number between 1 and 5),
  pose text not null check (pose in ('front', 'side', 'back')),
  storage_path text not null unique,
  ciphertext_sha256 text not null check (ciphertext_sha256 ~ '^[0-9a-f]{64}$'),
  ciphertext_byte_count integer not null check (ciphertext_byte_count between 1 and 5242880),
  uploaded_at timestamptz,
  deleted_at timestamptz,
  unique (submission_id, set_number, pose)
);

create table if not exists public.pilot_receipts (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.pilot_participants(id) on delete cascade,
  submission_id uuid not null unique references public.pilot_submissions(id) on delete cascade,
  receipt_code text not null unique,
  issued_at timestamptz not null default now()
);

create table if not exists public.pilot_request_events (
  id bigint generated always as identity primary key,
  rate_key text not null check (rate_key ~ '^[0-9a-f]{64}$'),
  endpoint text not null,
  occurred_at timestamptz not null default now()
);

create index if not exists pilot_request_events_lookup
  on public.pilot_request_events (rate_key, endpoint, occurred_at desc);
create index if not exists pilot_sessions_retention
  on public.pilot_sessions (results_delete_at);
create index if not exists pilot_objects_submission
  on public.pilot_objects (submission_id);

create table if not exists public.pilot_deletion_audit (
  id bigint generated always as identity primary key,
  participant_reference_hash text not null check (participant_reference_hash ~ '^[0-9a-f]{64}$'),
  reason text not null check (reason in ('withdrawal', 'recovery_code', 'researcher', 'retention', 'pilot_close')),
  deleted_submission_count integer not null,
  deleted_object_count integer not null,
  deleted_at timestamptz not null default now()
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pilot-photo-ciphertext', 'pilot-photo-ciphertext', false, 5242880, array['application/octet-stream'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pilot_studies', 'pilot_invites', 'pilot_participants', 'pilot_consents',
    'pilot_sessions', 'pilot_submissions', 'pilot_objects', 'pilot_receipts',
    'pilot_request_events', 'pilot_deletion_audit'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
  end loop;
end $$;

revoke all on table storage.objects from public, anon, authenticated;

create or replace function public.pilot_redeem_invite(
  p_invite_hash text,
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
  v_participant_id uuid;
begin
  select * into v_invite from public.pilot_invites
   where invite_hash = p_invite_hash
   for update;
  if not found or v_invite.used_at is not null or v_invite.expires_at <= now() then
    raise exception 'invite_unavailable';
  end if;
  select * into v_study from public.pilot_studies
   where id = v_invite.study_id
   for update;
  if v_study.status <> 'active' or v_study.closes_at <= now() then
    raise exception 'study_closed';
  end if;
  insert into public.pilot_participants (study_id, participant_token_hash, recovery_code_hash)
  values (v_study.id, p_participant_token_hash, p_recovery_code_hash)
  returning id into v_participant_id;
  update public.pilot_invites
     set used_at = now(), participant_id = v_participant_id
   where id = v_invite.id;
  return query select
    v_participant_id,
    v_study.id,
    v_study.name,
    v_study.closes_at,
    now() + interval '12 months';
end;
$$;

create or replace function public.pilot_initialize_submission(
  p_participant_id uuid,
  p_client_submission_id uuid,
  p_idempotency_key uuid,
  p_consent jsonb,
  p_results jsonb,
  p_payload_sha256 text,
  p_wrapped_key jsonb,
  p_objects jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.pilot_submissions%rowtype;
  v_consent_id uuid;
  v_session_id uuid;
  v_submission_id uuid := gen_random_uuid();
  v_object jsonb;
  v_count integer := jsonb_array_length(coalesce(p_objects, '[]'::jsonb));
  v_scope text := p_consent->>'share_scope';
  v_study_id uuid;
begin
  select * into v_existing from public.pilot_submissions
   where participant_id = p_participant_id
     and (client_submission_id = p_client_submission_id or idempotency_key = p_idempotency_key);
  if found then
    if v_existing.payload_sha256 <> p_payload_sha256 or v_existing.expected_file_count <> v_count then
      raise exception 'idempotency_conflict';
    end if;
    return v_existing.id;
  end if;
  select participant.study_id into v_study_id
    from public.pilot_participants participant
    join public.pilot_studies study on study.id = participant.study_id
   where participant.id = p_participant_id
     and participant.status = 'active'
     and study.status = 'active'
     and study.closes_at > now();
  if v_study_id is null then raise exception 'participant_unavailable'; end if;
  if coalesce((p_consent->>'adult_confirmed')::boolean, false) is not true then
    raise exception 'adult_confirmation_required';
  end if;
  if p_consent->>'version' <> 'pilot-consent-v1' then
    raise exception 'invalid_consent';
  end if;
  if v_count < 0 or v_count > 15 then raise exception 'invalid_object_count'; end if;
  if (v_scope = 'results_only' and (v_count <> 0 or p_wrapped_key is not null)) or
     (v_scope = 'results_and_selected_photos' and (v_count = 0 or p_wrapped_key is null)) then
    raise exception 'consent_object_mismatch';
  end if;
  insert into public.pilot_consents (
    participant_id, version, share_scope, adult_confirmed, selected_photo_count, accepted_at
  ) values (
    p_participant_id, p_consent->>'version', v_scope, true, v_count,
    (p_consent->>'accepted_at')::timestamptz
  ) returning id into v_consent_id;
  insert into public.pilot_sessions (
    participant_id, local_session_id, consent_id, result_status, started_at, completed_at,
    app_build, analysis_version, threshold_set_identifier, device_model,
    operating_system_version, camera_position, lens_type, results_payload
  ) values (
    p_participant_id, (p_results->>'local_session_id')::uuid, v_consent_id,
    p_results->>'session_result', (p_results->>'started_at')::timestamptz,
    nullif(p_results->>'completed_at', '')::timestamptz,
    p_results->>'app_build', nullif(p_results->>'analysis_version', '')::integer,
    p_results->>'threshold_set_identifier', p_results->>'device_model',
    p_results->>'operating_system_version', p_results->>'camera_position',
    p_results->>'lens_type', p_results
  ) returning id into v_session_id;
  insert into public.pilot_submissions (
    id, participant_id, session_id, client_submission_id, idempotency_key,
    expected_file_count, payload_sha256, wrapped_key
  ) values (
    v_submission_id, p_participant_id, v_session_id, p_client_submission_id,
    p_idempotency_key, v_count, p_payload_sha256, p_wrapped_key
  );
  for v_object in select * from jsonb_array_elements(coalesce(p_objects, '[]'::jsonb)) loop
    insert into public.pilot_objects (
      id, submission_id, set_number, pose, storage_path,
      ciphertext_sha256, ciphertext_byte_count
    ) values (
      (v_object->>'object_id')::uuid, v_submission_id,
      (v_object->>'set_number')::integer, v_object->>'pose',
      v_study_id::text || '/' || p_participant_id::text || '/' || v_submission_id::text || '/' || (v_object->>'object_id') || '.bin',
      v_object->>'sha256', (v_object->>'byte_count')::integer
    );
  end loop;
  return v_submission_id;
end;
$$;

revoke all on function public.pilot_redeem_invite(text, text, text) from public, anon, authenticated;
revoke all on function public.pilot_initialize_submission(uuid, uuid, uuid, jsonb, jsonb, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.pilot_redeem_invite(text, text, text) to service_role;
grant execute on function public.pilot_initialize_submission(uuid, uuid, uuid, jsonb, jsonb, text, jsonb, jsonb) to service_role;
