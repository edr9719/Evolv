import {
  authenticateParticipant,
  deleteParticipantData,
  enforceRateLimit,
  json,
  keyedHash,
  MAX_OBJECT_BYTES,
  MAX_OBJECTS,
  normalizeCode,
  parseJSON,
  PHOTO_BUCKET,
  randomCode,
  randomToken,
  serviceClient,
  sha256,
  validateResultsPayload,
} from "../_shared/pilot.ts";

const allowedPoses = new Set(["front", "side", "back"]);

type RedeemedInvite = {
  participant_id: string;
  study_id: string;
  study_name: string;
  pilot_closes_at: string;
  results_delete_after: string;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ code: "method_not_allowed" }, 405);
  const route = routeName(req.url);
  try {
    const client = serviceClient();
    if (route === "health") return await health(client);
    if (route === "enroll") return await enroll(req, client);
    if (route === "submissions/init") return await initialize(req, client);
    if (route === "submissions/complete") return await complete(req, client);
    if (route === "submissions/cancel") return await cancel(req, client);
    if (route === "status") return await status(req, client);
    if (route === "withdraw") return await withdraw(req, client);
    if (route === "delete") return await deleteWithCode(req, client);
    return json({ code: "not_found", message: "Endpoint not found." }, 404);
  } catch (error) {
    const code = error instanceof Error ? error.message : "request_failed";
    const statusCode = code === "rate_limited"
      ? 429
      : code.includes("unauthorized")
      ? 401
      : code.includes("invite") || code === "study_closed" ||
          code === "study_full"
      ? 409
      : code.includes("too_large")
      ? 413
      : code === "service_not_configured" || code === "service_unavailable"
      ? 503
      : 400;
    return json({ code, message: publicMessage(code) }, statusCode);
  }
});

async function health(
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  // Exercise both the original and Phase 4 schema without exposing study,
  // participant, or submission data. A deployment is not healthy when the
  // Edge Function exists but its migrations or database connection do not.
  const [studies, sessions] = await Promise.all([
    client.from("pilot_studies").select("id", { head: true }).limit(1),
    client.from("pilot_sessions").select(
      "contribution_type",
      { head: true },
    ).limit(1),
  ]);
  if (studies.error || sessions.error) throw new Error("service_unavailable");
  return json({
    status: "ok",
    service: "evolv-pilot",
    schemaVersion: 2,
    analysisVersion: 5,
    consentVersions: ["pilot-consent-v1", "pilot-ongoing-v1"],
  });
}

async function enroll(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const body = await parseJSON(req);
  const inviteCode = normalizeCode(body.invite_code);
  if (inviteCode.length < 16 || inviteCode.length > 64) {
    throw new Error("invite_unavailable");
  }
  const inviteHash = await keyedHash(`invite:${inviteCode}`);
  await enforceRateLimit(
    client,
    await keyedHash("global:enroll"),
    "enroll_global",
    500,
    30,
  );
  await enforceRateLimit(client, inviteHash, "enroll", 5, 30);
  const participantToken = randomToken(32);
  const deletionCode = randomCode(20);
  const { data, error } = await client.rpc("pilot_redeem_invite", {
    p_invite_hash: inviteHash,
    p_participant_token_hash: await keyedHash(`token:${participantToken}`),
    p_recovery_code_hash: await keyedHash(
      `recovery:${normalizeCode(deletionCode)}`,
    ),
  }).single();
  if (error) {
    if (error.message.includes("study_full")) throw new Error("study_full");
    if (error.message.includes("study_closed")) throw new Error("study_closed");
    throw new Error("invite_unavailable");
  }
  if (!data) throw new Error("invite_unavailable");
  const redeemed = data as unknown as RedeemedInvite;
  return json({
    participant_id: redeemed.participant_id,
    study_id: redeemed.study_id,
    study_name: redeemed.study_name,
    pilot_closes_at: redeemed.pilot_closes_at,
    results_delete_after: redeemed.results_delete_after,
    participant_token: participantToken,
    deletion_code: deletionCode,
  });
}

async function initialize(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const participant = await authenticateParticipant(req, client);
  const body = await parseJSON(req);
  const consent = object(body.consent, "invalid_consent");
  const results = object(body.results, "invalid_results");
  const objects = array(body.objects, "invalid_objects");
  validateResultsPayload(results);
  const contributionType = String(
    results.contribution_type || "consistency_test",
  );
  const expectedConsentVersion = contributionType === "progress_scan"
    ? "pilot-ongoing-v1"
    : "pilot-consent-v1";
  if (
    consent.version !== expectedConsentVersion ||
    consent.adult_confirmed !== true
  ) {
    throw new Error("invalid_consent");
  }
  const maximumObjects = contributionType === "progress_scan" ? 3 : MAX_OBJECTS;
  if (objects.length > maximumObjects) throw new Error("invalid_objects");
  const seen = new Set<string>();
  for (const raw of objects) {
    const item = object(raw, "invalid_object");
    const objectID = String(item.object_id || "");
    const key = `${item.set_number}:${item.pose}`;
    if (
      !uuid(objectID) || !Number.isInteger(item.set_number) ||
      Number(item.set_number) < 1 || Number(item.set_number) > 5 ||
      (contributionType === "progress_scan" && Number(item.set_number) !== 1) ||
      !allowedPoses.has(String(item.pose)) || seen.has(key) ||
      !/^[0-9a-f]{64}$/.test(String(item.sha256 || "")) ||
      !Number.isInteger(item.byte_count) || Number(item.byte_count) < 1 ||
      Number(item.byte_count) > MAX_OBJECT_BYTES
    ) {
      throw new Error("invalid_object");
    }
    seen.add(key);
  }
  const scope = String(consent.share_scope || "");
  if (
    (scope === "results_only" && objects.length !== 0) ||
    (scope === "results_and_selected_photos" && objects.length === 0) ||
    !["results_only", "results_and_selected_photos"].includes(scope)
  ) {
    throw new Error("consent_object_mismatch");
  }
  const wrappedKey = body.wrapped_key ?? null;
  if ((objects.length === 0) !== (wrappedKey === null)) {
    throw new Error("consent_object_mismatch");
  }
  const payloadHash = await sha256(JSON.stringify(results));
  const { data: submissionID, error } = await client.rpc(
    "pilot_initialize_submission",
    {
      p_participant_id: participant.id,
      p_client_submission_id: body.client_submission_id,
      p_idempotency_key: body.idempotency_key,
      p_consent: consent,
      p_results: results,
      p_payload_sha256: payloadHash,
      p_wrapped_key: wrappedKey,
      p_objects: objects,
    },
  );
  if (error || !submissionID) throw new Error("submission_rejected");
  const { data: rows, error: objectError } = await client
    .from("pilot_objects")
    .select("id,storage_path")
    .eq("submission_id", submissionID);
  if (objectError || (rows || []).length !== objects.length) {
    throw new Error("submission_rejected");
  }
  const uploads = [];
  for (const row of rows || []) {
    const { data, error: signedError } = await client.storage
      .from(PHOTO_BUCKET)
      .createSignedUploadUrl(row.storage_path, { upsert: false });
    if (signedError || !data?.signedUrl) {
      throw new Error("upload_authorization_failed");
    }
    uploads.push({ object_id: row.id, signed_url: data.signedUrl });
  }
  return json({ submission_id: submissionID, uploads });
}

async function complete(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const participant = await authenticateParticipant(req, client);
  const body = await parseJSON(req);
  const submissionID = String(body.submission_id || "");
  const idempotencyKey = String(body.idempotency_key || "");
  if (!uuid(submissionID) || !uuid(idempotencyKey)) {
    throw new Error("invalid_completion");
  }
  const { data: submission } = await client
    .from("pilot_submissions")
    .select("id,status,expected_file_count,session_id")
    .eq("id", submissionID)
    .eq("participant_id", participant.id)
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();
  if (!submission) throw new Error("submission_unavailable");
  const existingReceipt = await receiptFor(client, submissionID);
  if (submission.status === "completed" && existingReceipt) {
    return json(existingReceipt);
  }

  const { data: expected, error: expectedError } = await client
    .from("pilot_objects")
    .select("id,storage_path,ciphertext_byte_count")
    .eq("submission_id", submissionID);
  if (
    expectedError || (expected || []).length !== submission.expected_file_count
  ) {
    throw new Error("incomplete_upload");
  }
  if ((expected || []).length > 0) {
    const paths = expected!.map((row) => row.storage_path);
    const { data: stored, error: storageError } = await client
      .schema("storage")
      .from("objects")
      .select("name,metadata")
      .eq("bucket_id", PHOTO_BUCKET)
      .in("name", paths);
    if (storageError || (stored || []).length !== expected!.length) {
      throw new Error("incomplete_upload");
    }
    const storedByPath = new Map((stored || []).map((row) => [row.name, row]));
    for (const item of expected!) {
      const size = Number(
        storedByPath.get(item.storage_path)?.metadata?.size || 0,
      );
      if (size !== item.ciphertext_byte_count) {
        throw new Error("upload_size_mismatch");
      }
    }
  }
  const now = new Date().toISOString();
  const { error: updateError } = await client
    .from("pilot_submissions")
    .update({ status: "completed", completed_at: now })
    .eq("id", submissionID)
    .eq("status", "initialized");
  if (updateError) throw new Error("completion_failed");
  if ((expected || []).length > 0) {
    await client.from("pilot_objects").update({ uploaded_at: now }).eq(
      "submission_id",
      submissionID,
    );
  }
  const receiptCode = randomCode(10);
  const { error: receiptError } = await client.from("pilot_receipts").insert({
    participant_id: participant.id,
    submission_id: submissionID,
    receipt_code: receiptCode,
  });
  if (receiptError) {
    const raced = await receiptFor(client, submissionID);
    if (raced) return json(raced);
    throw new Error("completion_failed");
  }
  const receipt = await receiptFor(client, submissionID);
  if (!receipt) throw new Error("completion_failed");
  return json(receipt);
}

async function status(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const participant = await authenticateParticipant(req, client);
  const { data: sessions } = await client
    .from("pilot_sessions")
    .select("contribution_type,pilot_submissions!inner(status)")
    .eq("participant_id", participant.id)
    .eq("pilot_submissions.status", "completed");
  const rows = sessions || [];
  return json({
    status: "active",
    completed_submissions: rows.length,
    completed_consistency_tests: rows.filter((row) =>
      row.contribution_type === "consistency_test"
    ).length,
    completed_progress_scans:
      rows.filter((row) => row.contribution_type === "progress_scan").length,
  });
}

async function cancel(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const participant = await authenticateParticipant(req, client);
  const body = await parseJSON(req);
  const submissionID = String(body.submission_id || "");
  if (!uuid(submissionID)) throw new Error("submission_unavailable");
  const { data: submission } = await client.from("pilot_submissions")
    .select("id,session_id,status")
    .eq("id", submissionID)
    .eq("participant_id", participant.id)
    .maybeSingle();
  if (!submission) return json({ deleted: true });
  if (submission.status !== "initialized") {
    throw new Error("completed_submission_cannot_cancel");
  }
  const { data: objects } = await client.from("pilot_objects")
    .select("storage_path").eq("submission_id", submissionID);
  const paths = (objects || []).map((row) => row.storage_path);
  if (paths.length > 0) {
    const { error: storageError } = await client.storage.from(PHOTO_BUCKET)
      .remove(paths);
    if (storageError) throw new Error("object_delete_failed");
  }
  const { data: session, error: sessionError } = await client.from(
    "pilot_sessions",
  )
    .select("consent_id").eq("id", submission.session_id).maybeSingle();
  if (sessionError || !session) throw new Error("submission_cancel_failed");
  // Consent is owned by this one submission. Deleting it cascades through the
  // session, submission, receipt, and object metadata in one database action.
  const { error } = await client.from("pilot_consents").delete().eq(
    "id",
    session.consent_id,
  );
  if (error) throw new Error("submission_cancel_failed");
  return json({ deleted: true });
}

async function withdraw(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const participant = await authenticateParticipant(req, client);
  await deleteParticipantData(client, participant.id, "withdrawal");
  return json({ deleted: true });
}

async function deleteWithCode(
  req: Request,
  client: ReturnType<typeof serviceClient>,
): Promise<Response> {
  const body = await parseJSON(req);
  const code = normalizeCode(body.deletion_code);
  if (code.length < 16 || code.length > 64) {
    throw new Error("deletion_code_unavailable");
  }
  const hash = await keyedHash(`recovery:${code}`);
  await enforceRateLimit(
    client,
    await keyedHash("global:delete"),
    "delete_global",
    500,
    60,
  );
  await enforceRateLimit(client, hash, "delete", 5, 60);
  const { data } = await client
    .from("pilot_participants")
    .select("id")
    .eq("recovery_code_hash", hash)
    .maybeSingle();
  if (!data) throw new Error("deletion_code_unavailable");
  await deleteParticipantData(client, data.id, "recovery_code");
  return json({ deleted: true });
}

async function receiptFor(
  client: ReturnType<typeof serviceClient>,
  submissionID: string,
) {
  const { data: receipt } = await client
    .from("pilot_receipts")
    .select("receipt_code,submission_id")
    .eq("submission_id", submissionID)
    .maybeSingle();
  if (!receipt) return null;
  const { data: submission } = await client.from("pilot_submissions")
    .select("session_id").eq("id", submissionID).single();
  const { data: session } = await client.from("pilot_sessions")
    .select("results_delete_at,participant_id").eq(
      "id",
      submission?.session_id || "",
    ).single();
  const { data: participant } = await client.from("pilot_participants")
    .select("study_id").eq("id", session?.participant_id || "").single();
  const { data: study } = await client.from("pilot_studies")
    .select("closes_at").eq("id", participant?.study_id || "").single();
  return {
    submission_id: receipt.submission_id,
    receipt_code: receipt.receipt_code,
    photo_delete_at: study?.closes_at || null,
    results_delete_at: session?.results_delete_at,
  };
}

function object(value: unknown, code: string): Record<string, any> {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    throw new Error(code);
  }
  return value as Record<string, any>;
}
function array(value: unknown, code: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(code);
  return value;
}
function uuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}
function routeName(rawURL: string): string {
  const parts = new URL(rawURL).pathname.split("/").filter(Boolean);
  const index = parts.lastIndexOf("pilot-api");
  return index >= 0 ? parts.slice(index + 1).join("/") : "";
}
function publicMessage(code: string): string {
  if (code === "study_full") {
    return "This pilot has reached its participant limit.";
  }
  if (code === "invite_unavailable" || code === "study_closed") {
    return "That invite code is invalid, expired, or already used.";
  }
  if (code === "rate_limited") {
    return "Too many attempts. Please wait and try again.";
  }
  if (code === "participant_unauthorized") {
    return "Pilot access on this iPhone is no longer valid.";
  }
  if (code.startsWith("deletion_code")) {
    return "That deletion code could not be verified.";
  }
  if (code.includes("upload")) {
    return "The encrypted upload is incomplete. Please retry.";
  }
  return "The pilot request could not be completed.";
}
