-- Phase 4 is deliberately forward-only. The original pilot migration may
-- already be recorded in a deployed database, so these columns and function
-- replacements must live in a new migration rather than relying on edits to
-- migration 001.

alter table public.pilot_studies
  add column if not exists max_participants integer not null default 100;

alter table public.pilot_sessions
  add column if not exists contribution_type text not null default 'consistency_test';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'pilot_studies_max_participants_check'
       and conrelid = 'public.pilot_studies'::regclass
  ) then
    alter table public.pilot_studies
      add constraint pilot_studies_max_participants_check
      check (max_participants between 1 and 500);
  end if;
  if not exists (
    select 1 from pg_constraint
     where conname = 'pilot_sessions_contribution_type_check'
       and conrelid = 'public.pilot_sessions'::regclass
  ) then
    alter table public.pilot_sessions
      add constraint pilot_sessions_contribution_type_check
      check (contribution_type in ('consistency_test', 'progress_scan'));
  end if;
end $$;

create index if not exists pilot_sessions_participant_contribution
  on public.pilot_sessions (participant_id, contribution_type, created_at desc);

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
  -- Locking the study row makes concurrent invite redemptions respect the
  -- exact cohort ceiling instead of racing past it.
  if (
    select count(*)
      from public.pilot_participants enrolled_participant
     where enrolled_participant.study_id = v_study.id
  ) >= v_study.max_participants then
    raise exception 'study_full';
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
  v_contribution_type text := coalesce(p_results->>'contribution_type', 'consistency_test');
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
  if v_contribution_type not in ('consistency_test', 'progress_scan') then
    raise exception 'invalid_contribution_type';
  end if;
  if (v_contribution_type = 'consistency_test' and p_consent->>'version' <> 'pilot-consent-v1') or
     (v_contribution_type = 'progress_scan' and p_consent->>'version' <> 'pilot-ongoing-v1') then
    raise exception 'invalid_consent';
  end if;
  if v_contribution_type = 'progress_scan' and not exists (
    select 1
      from public.pilot_sessions prior_session
      join public.pilot_submissions prior_submission on prior_submission.session_id = prior_session.id
     where prior_session.participant_id = p_participant_id
       and prior_session.contribution_type = 'consistency_test'
       and prior_submission.status = 'completed'
  ) then
    raise exception 'pilot_consistency_required';
  end if;
  if v_count < 0 or v_count > 15 then raise exception 'invalid_object_count'; end if;
  if v_contribution_type = 'progress_scan' and v_count > 3 then
    raise exception 'invalid_object_count';
  end if;
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
    participant_id, local_session_id, contribution_type, consent_id, result_status, started_at, completed_at,
    app_build, analysis_version, threshold_set_identifier, device_model,
    operating_system_version, camera_position, lens_type, results_payload
  ) values (
    p_participant_id, (p_results->>'local_session_id')::uuid, v_contribution_type, v_consent_id,
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
    if v_contribution_type = 'progress_scan' and (v_object->>'set_number')::integer <> 1 then
      raise exception 'invalid_object';
    end if;
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
