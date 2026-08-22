import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export const PHOTO_BUCKET = "pilot-photo-ciphertext";
export const MAX_PAYLOAD_BYTES = 524_288;
export const MAX_OBJECT_BYTES = 5_242_880;
export const MAX_OBJECTS = 15;
export const CURRENT_ANALYSIS_VERSION = 7;
export const MINIMUM_SUPPORTED_ANALYSIS_VERSION = 4;

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("service_not_configured");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "X-Client-Info": "evolv-pilot-edge/1" } },
  });
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

export async function parseJSON(
  req: Request,
): Promise<Record<string, unknown>> {
  const declared = Number(req.headers.get("content-length") || "0");
  if (declared > MAX_PAYLOAD_BYTES) throw new Error("payload_too_large");
  const raw = await req.text();
  if (new TextEncoder().encode(raw).byteLength > MAX_PAYLOAD_BYTES) {
    throw new Error("payload_too_large");
  }
  const parsed = JSON.parse(raw || "{}") as unknown;
  if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new Error("invalid_json");
  }
  return parsed as Record<string, unknown>;
}

export function normalizeCode(value: unknown): string {
  return String(value || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export async function keyedHash(value: string): Promise<string> {
  const pepper = Deno.env.get("PILOT_INVITE_PEPPER");
  if (!pepper) throw new Error("service_not_configured");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(value),
  );
  return hex(new Uint8Array(signature));
}

export async function sha256(value: string | Uint8Array): Promise<string> {
  const source = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  // Copy into an ArrayBuffer-backed view. Newer TypeScript lib definitions
  // correctly reject a possibly SharedArrayBuffer-backed Uint8Array here.
  const bytes = new Uint8Array(source.byteLength);
  bytes.set(source);
  return hex(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes.buffer)),
  );
}

/// Produces a stable JSON representation for retry identity. Parsed request
/// payloads contain only JSON values, so sorting every object key makes the
/// digest independent of encoder/dictionary iteration order while preserving
/// array order and scalar values exactly.
export function canonicalJSONStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSONStringify).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  return `{${
    Object.keys(record).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJSONStringify(record[key])}`
    ).join(",")
  }}`;
}

/// UUID text is case-insensitive, but Swift's encoder emits uppercase hex and
/// PostgreSQL returns lowercase. Normalize only after UUID syntax validation.
export function canonicalUUIDString(value: string): string {
  return value.toLowerCase();
}

export function randomToken(byteCount = 32): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteCount));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export function randomCode(byteCount = 15): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(byteCount));
  let output = "";
  for (const byte of bytes) output += alphabet[byte % alphabet.length];
  return output.match(/.{1,5}/g)?.join("-") || output;
}

export async function enforceRateLimit(
  client: SupabaseClient,
  rateKey: string,
  endpoint: string,
  limit: number,
  windowMinutes = 10,
): Promise<void> {
  const cutoff = new Date(Date.now() - windowMinutes * 60_000).toISOString();
  const { count, error } = await client
    .from("pilot_request_events")
    .select("id", { count: "exact", head: true })
    .eq("rate_key", rateKey)
    .eq("endpoint", endpoint)
    .gte("occurred_at", cutoff);
  if (error) throw new Error("rate_limit_unavailable");
  if ((count || 0) >= limit) throw new Error("rate_limited");
  const { error: insertError } = await client
    .from("pilot_request_events")
    .insert({ rate_key: rateKey, endpoint });
  if (insertError) throw new Error("rate_limit_unavailable");
}

export async function authenticateParticipant(
  req: Request,
  client: SupabaseClient,
): Promise<{ id: string; study_id: string }> {
  const token = req.headers.get("x-evolv-participant-token") || "";
  if (token.length < 32 || token.length > 128) {
    throw new Error("participant_unauthorized");
  }
  const tokenHash = await keyedHash(`token:${token}`);
  const verifierHash = await keyedHash(`token-verifier:${await sha256(token)}`);
  await enforceRateLimit(
    client,
    await keyedHash("global:participant"),
    "participant_global",
    2_000,
  );
  await enforceRateLimit(client, tokenHash, "participant", 40);
  const { data, error } = await client
    .from("pilot_participants")
    .select("id,study_id")
    .or(
      `participant_token_hash.eq.${tokenHash},participant_token_hash.eq.${verifierHash}`,
    )
    .eq("status", "active")
    .limit(2);
  if (error || !data || data.length !== 1) {
    throw new Error("participant_unauthorized");
  }
  return data[0] as { id: string; study_id: string };
}

export function validateResultsPayload(
  results: unknown,
): asserts results is Record<string, unknown> {
  if (!results || Array.isArray(results) || typeof results !== "object") {
    throw new Error("invalid_results");
  }
  const root = results as Record<string, unknown>;
  if (root.schema_version !== 1 || typeof root.local_session_id !== "string") {
    throw new Error("invalid_results");
  }
  if (
    typeof root.analysis_version !== "number" ||
    !Number.isInteger(root.analysis_version) ||
    Number(root.analysis_version) < MINIMUM_SUPPORTED_ANALYSIS_VERSION ||
    Number(root.analysis_version) > CURRENT_ANALYSIS_VERSION ||
    typeof root.threshold_set_identifier !== "string" ||
    root.threshold_set_identifier.length < 1 ||
    root.threshold_set_identifier.length > 80
  ) {
    throw new Error("unsupported_analysis_version");
  }
  const contributionType = String(root.contribution_type || "consistency_test");
  if (contributionType === "consistency_test") {
    if (!Array.isArray(root.sets)) throw new Error("invalid_results");
  } else if (contributionType === "progress_scan") {
    if (
      !Array.isArray(root.regions) || !root.failure_reason_codes_by_pose ||
      Array.isArray(root.failure_reason_codes_by_pose) ||
      typeof root.failure_reason_codes_by_pose !== "object"
    ) {
      throw new Error("invalid_results");
    }
  } else {
    throw new Error("invalid_contribution_type");
  }
  const forbidden = [
    "photo",
    "image",
    "filename",
    "landmark",
    "mask",
    "email",
    "name",
    "location",
    "advertising",
    "height",
    "weight",
    "measurement",
    "tape",
  ];

  // These dictionaries contain privacy-safe diagnostic labels, not schema
  // fields. Dynamic labels such as `set_2.back.hipLandmarks` must not be
  // mistaken for raw landmark data, while arbitrary values, paths, filenames,
  // coordinates, masks, or nested objects must still fail closed.
  const validateReasonCodeMap = (value: unknown): void => {
    if (!value || Array.isArray(value) || typeof value !== "object") {
      throw new Error("invalid_results");
    }
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length > 80) throw new Error("invalid_results");
    const consistencyLabel =
      /^set_[1-5]\.(front|side|back)\.(photoLoading|poseExtraction|hipLandmarks|segmentation|silhouette|regionFeatures|comparability)$/;
    const progressLabel =
      /^(front|side|back|frontDoubleBicep|sideChest|backDoubleBicep|mostMuscular|relaxedAesthetic|legs)(_silhouette)?$/;
    const allowedReasons = new Set([
      "photo_load_failed",
      "image_decode_failed",
      "hip_landmarks_unavailable",
      "shoulder_landmarks_unavailable",
      "body_pose_unavailable",
      "person_segmentation_unavailable",
      "torso_scale_unavailable",
      "silhouette_evidence_unavailable",
      "required_region_feature_unavailable",
      "unexpected_pose_processing_error",
      "unexpected_silhouette_processing_error",
      "side_angle_differs_from_baseline",
      "pose_alignment_differs_from_baseline",
      "pose_alignment_unavailable",
      "camera_configuration_changed",
      "cross_pose_evidence_conflict",
      "pose_not_comparable",
      "camera_configuration_unknown",
      "no_supported_regions",
      "noImage",
      "noSegmentation",
      "noObservation",
      "hipsUnavailable",
      "shouldersUnavailable",
      "insufficientLandmarks",
      "invalidReferenceScale",
      "insufficientEvidence",
    ]);
    for (const [label, reason] of entries) {
      const lowerLabel = label.toLowerCase();
      const lowerReason = typeof reason === "string"
        ? reason.toLowerCase()
        : "";
      if (
        lowerLabel.includes("filename") || lowerLabel.includes("mask") ||
        lowerReason.includes("filename") || lowerReason.includes("mask")
      ) {
        throw new Error("forbidden_results_field");
      }
      if (
        label.length < 1 || label.length > 160 ||
        (!consistencyLabel.test(label) && !progressLabel.test(label)) ||
        typeof reason !== "string" || reason.length < 1 ||
        reason.length > 100 || !allowedReasons.has(reason)
      ) {
        throw new Error("invalid_results");
      }
    }
  };
  const walk = (value: unknown): void => {
    if (Array.isArray(value)) return value.forEach(walk);
    if (!value || typeof value !== "object") return;
    for (
      const [key, child] of Object.entries(value as Record<string, unknown>)
    ) {
      const lower = key.toLowerCase();
      if (lower === "failure_reason_codes_by_pose") {
        validateReasonCodeMap(child);
        continue;
      }
      if (forbidden.some((term) => lower.includes(term))) {
        throw new Error(
          "forbidden_results_field",
        );
      }
      walk(child);
    }
  };
  walk(root);
}

export async function deleteParticipantData(
  client: SupabaseClient,
  participantID: string,
  reason:
    | "withdrawal"
    | "recovery_code"
    | "researcher"
    | "retention"
    | "pilot_close",
): Promise<void> {
  const { data: submissions, error: submissionError } = await client
    .from("pilot_submissions")
    .select("id")
    .eq("participant_id", participantID);
  if (submissionError) throw new Error("participant_delete_query_failed");
  const submissionIDs = (submissions || []).map((row: { id: string }) =>
    row.id
  );
  let paths: string[] = [];
  if (submissionIDs.length > 0) {
    const { data: objects, error: objectError } = await client
      .from("pilot_objects")
      .select("storage_path")
      .in("submission_id", submissionIDs);
    if (objectError) throw new Error("participant_delete_query_failed");
    paths = (objects || []).map((row: { storage_path: string }) =>
      row.storage_path
    );
  }
  for (let index = 0; index < paths.length; index += 100) {
    const { error } = await client.storage.from(PHOTO_BUCKET).remove(
      paths.slice(index, index + 100),
    );
    if (error) throw new Error("object_delete_failed");
  }
  const reference = await keyedHash(`participant:${participantID}`);
  const { error: participantError } = await client
    .from("pilot_participants")
    .delete()
    .eq("id", participantID);
  if (participantError) throw new Error("participant_delete_failed");
  const { error: auditError } = await client.from("pilot_deletion_audit")
    .insert({
      participant_reference_hash: reference,
      reason,
      deleted_submission_count: submissionIDs.length,
      deleted_object_count: paths.length,
    });
  if (auditError) throw new Error("deletion_audit_failed");
}

export async function deleteStudyPhotos(
  client: SupabaseClient,
  studyID: string,
): Promise<number> {
  const { data: participants, error: participantError } = await client
    .from("pilot_participants").select("id").eq("study_id", studyID);
  if (participantError) throw new Error("photo_retention_query_failed");
  const participantIDs = (participants || []).map((row: { id: string }) =>
    row.id
  );
  if (participantIDs.length === 0) return 0;
  const { data: submissions, error: submissionError } = await client
    .from("pilot_submissions").select("id").in(
      "participant_id",
      participantIDs,
    );
  if (submissionError) throw new Error("photo_retention_query_failed");
  const submissionIDs = (submissions || []).map((row: { id: string }) =>
    row.id
  );
  if (submissionIDs.length === 0) return 0;
  const { data: objects, error: objectError } = await client.from(
    "pilot_objects",
  )
    .select("id,storage_path").in("submission_id", submissionIDs).is(
      "deleted_at",
      null,
    );
  if (objectError) throw new Error("photo_retention_query_failed");
  const rows = objects || [];
  for (let index = 0; index < rows.length; index += 100) {
    const { error } = await client.storage.from(PHOTO_BUCKET)
      .remove(rows.slice(index, index + 100).map((row) => row.storage_path));
    if (error) throw new Error("object_delete_failed");
  }
  if (rows.length > 0) {
    const { error } = await client.from("pilot_objects")
      .update({ deleted_at: new Date().toISOString() })
      .in("id", rows.map((row) => row.id));
    if (error) throw new Error("object_mark_delete_failed");
  }
  return rows.length;
}

export async function applyRetention(
  client: SupabaseClient,
): Promise<{ photos: number; sessions: number }> {
  const now = new Date().toISOString();
  const { data: closedStudies, error: studyError } = await client.from(
    "pilot_studies",
  )
    .select("id").lte("closes_at", now);
  if (studyError) throw new Error("retention_query_failed");
  let photos = 0;
  for (const study of closedStudies || []) {
    photos += await deleteStudyPhotos(client, study.id);
  }

  const { data: expired, error: sessionError } = await client.from(
    "pilot_sessions",
  )
    .select("id,participant_id,consent_id").lte("results_delete_at", now);
  if (sessionError) throw new Error("retention_query_failed");
  for (const session of expired || []) {
    const { data: submission, error: submissionError } = await client.from(
      "pilot_submissions",
    )
      .select("id").eq("session_id", session.id).maybeSingle();
    if (submissionError) throw new Error("retention_query_failed");
    let deletedObjectCount = 0;
    if (submission) {
      const { data: objects, error: objectError } = await client.from(
        "pilot_objects",
      )
        .select("storage_path").eq("submission_id", submission.id).is(
          "deleted_at",
          null,
        );
      if (objectError) throw new Error("retention_query_failed");
      const paths = (objects || []).map((row) => row.storage_path);
      if (paths.length > 0) {
        const { error: storageError } = await client.storage.from(PHOTO_BUCKET)
          .remove(paths);
        if (storageError) throw new Error("object_delete_failed");
        deletedObjectCount = paths.length;
      }
    }
    const reference = await keyedHash(`participant:${session.participant_id}`);
    // Each consent belongs to one submission. Removing it cascades through the
    // expired session and submission so consent cannot outlive its result.
    const { error: deleteError } = await client.from("pilot_consents").delete()
      .eq("id", session.consent_id);
    if (deleteError) throw new Error("retention_delete_failed");
    const { error: auditError } = await client.from("pilot_deletion_audit")
      .insert({
        participant_reference_hash: reference,
        reason: "retention",
        deleted_submission_count: submission ? 1 : 0,
        deleted_object_count: deletedObjectCount,
      });
    if (auditError) throw new Error("deletion_audit_failed");
  }

  for (const study of closedStudies || []) {
    const { data: participants, error: participantError } = await client
      .from("pilot_participants").select("id").eq("study_id", study.id);
    if (participantError) throw new Error("retention_query_failed");
    for (const participant of participants || []) {
      const { count, error: countError } = await client.from("pilot_sessions")
        .select("id", { count: "exact", head: true })
        .eq("participant_id", participant.id);
      if (countError) throw new Error("retention_query_failed");
      if ((count || 0) === 0) {
        await deleteParticipantData(client, participant.id, "retention");
      }
    }
  }
  const { error: eventError } = await client.from("pilot_request_events")
    .delete()
    .lt("occurred_at", new Date(Date.now() - 24 * 60 * 60_000).toISOString());
  if (eventError) throw new Error("retention_event_cleanup_failed");
  return { photos, sessions: (expired || []).length };
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
