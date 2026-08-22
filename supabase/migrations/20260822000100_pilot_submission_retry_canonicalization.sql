-- Retry identity must not depend on JSON object key iteration order. Existing
-- submissions may contain the legacy order-sensitive digest, so an exact
-- JSONB equality check provides a one-time fail-closed bridge to the canonical
-- digest. A changed payload or object count remains an idempotency conflict.

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
  v_existing_results jsonb;
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
    if v_existing.expected_file_count <> v_count then
      raise exception 'idempotency_conflict';
    end if;
    if v_existing.payload_sha256 <> p_payload_sha256 then
      select results_payload into v_existing_results
        from public.pilot_sessions
       where id = v_existing.session_id;
      if v_existing_results is distinct from p_results then
        raise exception 'idempotency_conflict';
      end if;
      update public.pilot_submissions
         set payload_sha256 = p_payload_sha256
       where id = v_existing.id;
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

revoke all on function public.pilot_initialize_submission(uuid, uuid, uuid, jsonb, jsonb, text, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.pilot_initialize_submission(uuid, uuid, uuid, jsonb, jsonb, text, jsonb, jsonb)
  to service_role;
