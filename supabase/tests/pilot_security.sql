begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

select has_table('public', 'pilot_participants', 'participant table exists');
select has_table('public', 'pilot_submissions', 'submission table exists');
select has_table('public', 'pilot_deletion_audit', 'deletion audit exists');
select ok((select relrowsecurity from pg_class where oid = 'public.pilot_participants'::regclass), 'participant RLS enabled');
select ok((select relforcerowsecurity from pg_class where oid = 'public.pilot_participants'::regclass), 'participant RLS forced');
select ok(not has_table_privilege('anon', 'public.pilot_participants', 'select'), 'anon cannot read participants');
select ok(not has_table_privilege('authenticated', 'public.pilot_sessions', 'select'), 'authenticated cannot read results');
select ok(
  not exists (
    select 1
    from unnest(array[
      'pilot_studies', 'pilot_invites', 'pilot_participants', 'pilot_consents',
      'pilot_sessions', 'pilot_submissions', 'pilot_objects', 'pilot_receipts',
      'pilot_request_events', 'pilot_deletion_audit'
    ]) as pilot_table(name)
    where not has_table_privilege(
      'service_role',
      format('public.%I', pilot_table.name),
      'select,insert,update,delete'
    )
  ),
  'service role can operate every private pilot table'
);
select ok(
  has_sequence_privilege('service_role', 'public.pilot_request_events_id_seq', 'usage')
  and has_sequence_privilege('service_role', 'public.pilot_deletion_audit_id_seq', 'usage'),
  'service role can allocate private audit and rate-limit identities'
);
select ok(
  not has_sequence_privilege('anon', 'public.pilot_request_events_id_seq', 'usage')
  and not has_sequence_privilege('authenticated', 'public.pilot_deletion_audit_id_seq', 'usage'),
  'client roles cannot allocate private pilot identities'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'storage.objects'::regclass)
  and not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and ('anon' = any(roles) or 'public' = any(roles))
  ),
  'storage RLS has no anonymous read policy'
);
select is((select public from storage.buckets where id = 'pilot-photo-ciphertext'), false, 'photo ciphertext bucket is private');
select is((select file_size_limit from storage.buckets where id = 'pilot-photo-ciphertext'), 5242880::bigint, 'bucket file limit is five MiB');

insert into public.pilot_studies (id, name, activated_at, closes_at)
values ('10000000-0000-4000-8000-000000000001', 'Database test pilot', now(), now() + interval '90 days');
insert into public.pilot_invites (study_id, invite_hash, expires_at)
values ('10000000-0000-4000-8000-000000000001', repeat('a', 64), now() + interval '7 days');

select lives_ok(
  $$select * from public.pilot_redeem_invite(repeat('a',64), repeat('b',64), repeat('c',64))$$,
  'one-use invite can be redeemed once'
);
select is((select count(*) from public.pilot_participants), 1::bigint, 'redemption creates one participant');
select throws_ok(
  $$select * from public.pilot_redeem_invite(repeat('a',64), repeat('d',64), repeat('e',64))$$,
  'P0001', 'invite_unavailable', 'used invite cannot be replayed'
);

select lives_ok(
  $$select public.pilot_initialize_submission(
    (select id from public.pilot_participants limit 1),
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '{"version":"pilot-consent-v1","share_scope":"results_only","adult_confirmed":true,"accepted_at":"2026-08-10T00:00:00Z"}'::jsonb,
    '{"schema_version":1,"local_session_id":"40000000-0000-4000-8000-000000000001","session_result":"consistent","started_at":"2026-08-10T00:00:00Z","completed_at":"2026-08-10T00:20:00Z","app_build":"test","analysis_version":5,"threshold_set_identifier":"engineering-v1","device_model":"test","operating_system_version":"test","camera_position":"front","lens_type":"wide","sets":[]}'::jsonb,
    repeat('f',64), null, '[]'::jsonb
  )$$,
  'results-only submission initializes without any object'
);
select is((select expected_file_count from public.pilot_submissions limit 1), 0, 'results-only expected file count is zero');
select is(
  (select contribution_type from public.pilot_sessions limit 1),
  'consistency_test',
  'legacy consistency payload is classified as a consistency test'
);
select throws_ok(
  $$select public.pilot_initialize_submission(
    (select id from public.pilot_participants limit 1),
    '20000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    '{"version":"pilot-consent-v1","share_scope":"results_only","adult_confirmed":true,"accepted_at":"2026-08-10T00:00:00Z"}'::jsonb,
    '{"schema_version":1,"local_session_id":"40000000-0000-4000-8000-000000000002","session_result":"consistent","started_at":"2026-08-10T00:00:00Z","app_build":"test","device_model":"test","operating_system_version":"test","camera_position":"front","sets":[]}'::jsonb,
    repeat('1',64), '{"algorithm":"forged"}'::jsonb,
    '[{"object_id":"50000000-0000-4000-8000-000000000001","set_number":1,"pose":"front","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","byte_count":100}]'::jsonb
  )$$,
  'P0001', 'consent_object_mismatch', 'results-only consent cannot create a photo object'
);

select throws_ok(
  $$select public.pilot_initialize_submission(
    (select id from public.pilot_participants limit 1),
    '20000000-0000-4000-8000-000000000004',
    '30000000-0000-4000-8000-000000000004',
    '{"version":"pilot-ongoing-v1","share_scope":"results_only","adult_confirmed":true,"accepted_at":"2026-08-10T00:30:00Z"}'::jsonb,
    '{"schema_version":1,"contribution_type":"progress_scan","local_session_id":"40000000-0000-4000-8000-000000000004","session_result":"comparable","started_at":"2026-08-10T00:30:00Z","completed_at":"2026-08-10T00:31:00Z","app_build":"test","analysis_version":5,"threshold_set_identifier":"engineering-v1","device_model":"test","operating_system_version":"test","camera_position":"front","lens_type":"wide","regions":[],"failure_reason_codes_by_pose":{}}'::jsonb,
    repeat('3',64), null, '[]'::jsonb
  )$$,
  'P0001', 'pilot_consistency_required', 'ongoing contribution requires a completed consistency submission'
);

update public.pilot_submissions
   set status = 'completed', completed_at = now();
select lives_ok(
  $$select public.pilot_initialize_submission(
    (select id from public.pilot_participants limit 1),
    '20000000-0000-4000-8000-000000000005',
    '30000000-0000-4000-8000-000000000005',
    '{"version":"pilot-ongoing-v1","share_scope":"results_only","adult_confirmed":true,"accepted_at":"2026-08-10T00:30:00Z"}'::jsonb,
    '{"schema_version":1,"contribution_type":"progress_scan","local_session_id":"40000000-0000-4000-8000-000000000005","session_result":"comparable","started_at":"2026-08-10T00:30:00Z","completed_at":"2026-08-10T00:31:00Z","app_build":"test","analysis_version":5,"threshold_set_identifier":"engineering-v1","device_model":"test","operating_system_version":"test","camera_position":"front","lens_type":"wide","regions":[],"failure_reason_codes_by_pose":{}}'::jsonb,
    repeat('4',64), null, '[]'::jsonb
  )$$,
  'completed pilot participants can initialize a future progress contribution'
);
select is(
  (select count(*) from public.pilot_sessions where contribution_type = 'progress_scan'),
  1::bigint,
  'progress contribution is classified separately'
);

update public.pilot_studies
   set status = 'closed'
 where id = '10000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.pilot_initialize_submission(
    (select id from public.pilot_participants limit 1),
    '20000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000003',
    '{"version":"pilot-consent-v1","share_scope":"results_only","adult_confirmed":true,"accepted_at":"2026-08-10T00:00:00Z"}'::jsonb,
    '{"schema_version":1,"local_session_id":"40000000-0000-4000-8000-000000000003","session_result":"consistent","started_at":"2026-08-10T00:00:00Z","app_build":"test","device_model":"test","operating_system_version":"test","camera_position":"front","sets":[]}'::jsonb,
    repeat('2',64), null, '[]'::jsonb
  )$$,
  'P0001', 'participant_unavailable', 'closed pilot cannot accept a new submission'
);

insert into public.pilot_studies (id, name, activated_at, closes_at, max_participants)
values ('10000000-0000-4000-8000-000000000002', 'Capacity test pilot', now(), now() + interval '90 days', 1);
insert into public.pilot_invites (study_id, invite_hash, expires_at)
values
  ('10000000-0000-4000-8000-000000000002', repeat('5', 64), now() + interval '7 days'),
  ('10000000-0000-4000-8000-000000000002', repeat('6', 64), now() + interval '7 days');
select lives_ok(
  $$select * from public.pilot_redeem_invite(repeat('5',64), repeat('7',64), repeat('8',64))$$,
  'first participant can fill the configured cohort capacity'
);
select throws_ok(
  $$select * from public.pilot_redeem_invite(repeat('6',64), repeat('9',64), repeat('0',64))$$,
  'P0001', 'study_full', 'concurrent-safe cohort ceiling rejects later enrollment'
);

select * from finish();
rollback;
