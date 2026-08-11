import {
  applyRetention,
  deleteParticipantData,
  deleteStudyPhotos,
  json,
  keyedHash,
  normalizeCode,
  parseJSON,
  PHOTO_BUCKET,
  randomCode,
  serviceClient,
} from "../_shared/pilot.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ code: "method_not_allowed" }, 405);
  if (!authorized(req)) return json({ code: "unauthorized" }, 401);
  const client = serviceClient();
  const route = routeName(req.url);
  try {
    if (route === "studies/create") return await createStudy(req, client);
    if (route === "invites/create") return await createInvites(req, client);
    if (route === "status") return await status(req, client);
    if (route === "export") return await exportData(req, client);
    if (route === "participants/delete") {
      return await deleteParticipant(req, client);
    }
    if (route === "studies/close") return await closeStudy(req, client);
    if (route === "retention/run") return json(await applyRetention(client));
    return json({ code: "not_found" }, 404);
  } catch (error) {
    const code = error instanceof Error
      ? error.message
      : "admin_request_failed";
    return json({
      code,
      message: "The researcher request could not be completed.",
    }, 400);
  }
});

async function createStudy(
  req: Request,
  client: ReturnType<typeof serviceClient>,
) {
  const body = await parseJSON(req);
  const name = String(body.name || "Evolv consistency pilot").trim();
  const durationDays = Math.max(
    1,
    Math.min(90, Number(body.duration_days || 90)),
  );
  const maxParticipants = Math.max(
    1,
    Math.min(500, Number(body.max_participants || 100)),
  );
  const activated = new Date();
  const closes = new Date(activated.getTime() + durationDays * 86_400_000);
  const { data, error } = await client.from("pilot_studies").insert({
    name,
    activated_at: activated.toISOString(),
    closes_at: closes.toISOString(),
    max_participants: maxParticipants,
    public_key_version: "pilot-p256-v1",
  }).select("id,name,activated_at,closes_at,max_participants,status").single();
  if (error || !data) throw new Error("study_create_failed");
  return json(data);
}

async function createInvites(
  req: Request,
  client: ReturnType<typeof serviceClient>,
) {
  const body = await parseJSON(req);
  const studyID = String(body.study_id || "");
  const count = Math.max(1, Math.min(20, Number(body.count || 5)));
  const { data: study } = await client.from("pilot_studies")
    .select("id,closes_at,status").eq("id", studyID).eq("status", "active")
    .maybeSingle();
  if (!study) throw new Error("study_unavailable");
  const invites = [];
  for (let index = 0; index < count; index++) {
    const code = randomCode(20);
    invites.push({
      study_id: studyID,
      invite_hash: await keyedHash(`invite:${normalizeCode(code)}`),
      expires_at: study.closes_at,
      code,
    });
  }
  const { error } = await client.from("pilot_invites")
    .insert(invites.map(({ code: _code, ...row }) => row));
  if (error) throw new Error("invite_create_failed");
  return json({ study_id: studyID, invites: invites.map((item) => item.code) });
}

async function status(req: Request, client: ReturnType<typeof serviceClient>) {
  const body = await parseJSON(req);
  const studyID = String(body.study_id || "");
  const { data: study } = await client.from("pilot_studies").select("*").eq(
    "id",
    studyID,
  ).single();
  if (!study) throw new Error("study_unavailable");
  const { data: participants } = await client.from("pilot_participants")
    .select("id,enrolled_at,status").eq("study_id", studyID).order(
      "enrolled_at",
    );
  const participantIDs = (participants || []).map((row) => row.id);
  const { data: submissions } = participantIDs.length === 0
    ? { data: [] }
    : await client.from("pilot_submissions")
      .select(
        "id,participant_id,status,expected_file_count,created_at,completed_at,pilot_sessions!inner(contribution_type)",
      )
      .in("participant_id", participantIDs).order("created_at");
  const submissionRows = submissions || [];
  const contributionType = (row: any): string => {
    const session = Array.isArray(row.pilot_sessions)
      ? row.pilot_sessions[0]
      : row.pilot_sessions;
    return session?.contribution_type || "consistency_test";
  };
  return json({
    study,
    participants: participants || [],
    submissions: submissionRows,
    completed_consistency_tests: submissionRows.filter((row) =>
      row.status === "completed" && contributionType(row) === "consistency_test"
    ).length,
    completed_progress_scans: submissionRows.filter((row) =>
      row.status === "completed" && contributionType(row) === "progress_scan"
    ).length,
  });
}

async function exportData(
  req: Request,
  client: ReturnType<typeof serviceClient>,
) {
  const body = await parseJSON(req);
  const studyID = String(body.study_id || "");
  const includePhotos = body.include_photos === true;
  const { data: participants } = await client.from("pilot_participants").select(
    "id",
  ).eq("study_id", studyID);
  const ids = (participants || []).map((row) => row.id);
  if (ids.length === 0) return json({ study_id: studyID, submissions: [] });
  const { data: sessions, error } = await client.from("pilot_sessions")
    .select(
      "id,participant_id,local_session_id,contribution_type,result_status,started_at,completed_at,app_build,analysis_version,threshold_set_identifier,device_model,operating_system_version,camera_position,lens_type,results_payload,results_delete_at,pilot_consents(version,share_scope,selected_photo_count,accepted_at),pilot_submissions(id,status,expected_file_count,wrapped_key,completed_at,pilot_receipts(receipt_code))",
    )
    .in("participant_id", ids).order("created_at");
  if (error) throw new Error("export_failed");
  const output: any[] = [];
  for (const session of sessions || []) {
    const submission = Array.isArray(session.pilot_submissions)
      ? session.pilot_submissions[0]
      : session.pilot_submissions;
    const entry: Record<string, unknown> = { ...session };
    if (includePhotos && submission?.id && submission.expected_file_count > 0) {
      const { data: objects } = await client.from("pilot_objects")
        .select(
          "id,set_number,pose,storage_path,ciphertext_sha256,ciphertext_byte_count",
        )
        .eq("submission_id", submission.id).is("deleted_at", null);
      const photos = [];
      for (const item of objects || []) {
        const { data } = await client.storage.from(PHOTO_BUCKET)
          .createSignedUrl(item.storage_path, 900, { download: true });
        photos.push({ ...item, signed_url: data?.signedUrl || null });
      }
      entry.encrypted_photos = photos;
    }
    output.push(entry);
  }
  return json({
    study_id: studyID,
    includes_encrypted_photos: includePhotos,
    submissions: output,
  });
}

async function deleteParticipant(
  req: Request,
  client: ReturnType<typeof serviceClient>,
) {
  const body = await parseJSON(req);
  await deleteParticipantData(
    client,
    String(body.participant_id || ""),
    "researcher",
  );
  return json({ deleted: true });
}

async function closeStudy(
  req: Request,
  client: ReturnType<typeof serviceClient>,
) {
  const body = await parseJSON(req);
  const studyID = String(body.study_id || "");
  const now = new Date().toISOString();
  const { error } = await client.from("pilot_studies")
    .update({ status: "closed", closes_at: now }).eq("id", studyID);
  if (error) throw new Error("study_close_failed");
  const deletedPhotoCount = await deleteStudyPhotos(client, studyID);
  return json({ closed: true, deleted_photo_count: deletedPhotoCount });
}

function authorized(req: Request): boolean {
  const configured = Deno.env.get("PILOT_ADMIN_SECRET") || "";
  const supplied = (req.headers.get("authorization") || "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (configured.length < 32 || supplied.length !== configured.length) {
    return false;
  }
  let difference = 0;
  for (let index = 0; index < configured.length; index++) {
    difference |= configured.charCodeAt(index) ^ supplied.charCodeAt(index);
  }
  return difference === 0;
}
function routeName(rawURL: string): string {
  const parts = new URL(rawURL).pathname.split("/").filter(Boolean);
  const index = parts.lastIndexOf("pilot-admin");
  return index >= 0 ? parts.slice(index + 1).join("/") : "";
}
