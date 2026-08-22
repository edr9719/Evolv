import {
  canonicalJSONStringify,
  sha256,
  validateResultsPayload,
} from "./pilot.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function fiveSetPayload(): Record<string, unknown> {
  return {
    schema_version: 1,
    local_session_id: "10000000-0000-4000-8000-000000000001",
    session_result: "needsReview",
    started_at: "2026-08-21T10:00:00Z",
    completed_at: "2026-08-21T11:00:00Z",
    app_build: "19",
    analysis_version: 7,
    threshold_set_identifier: "engineering-v1",
    device_model: "iPhone",
    operating_system_version: "26.0",
    camera_position: "rear",
    lens_type: "wide",
    sets: Array.from({ length: 5 }, (_, offset) => {
      const setNumber = offset + 1;
      return {
        set_number: setNumber,
        completed_at: "2026-08-21T10:00:00Z",
        conditions_stayed_the_same: true,
        deviation_reason_codes: [],
        has_sufficient_core_evidence: setNumber === 1,
        processing_duration_milliseconds: 850,
        failure_reason_codes_by_pose: setNumber === 1 ? {} : {
          [`set_${setNumber}.back.hipLandmarks`]: "hip_landmarks_unavailable",
          [`set_${setNumber}.side.comparability`]: "pose_not_comparable",
        },
        regions: [
          {
            region: "waist",
            status: setNumber === 1 ? "stable" : "unavailable",
            fused_delta: setNumber === 1 ? 0 : null,
            unavailable_reason_code: setNumber === 1
              ? null
              : "required_pose_evidence_unavailable",
            contributions: [],
          },
        ],
      };
    }),
  };
}

Deno.test("full five-set payload accepts privacy-safe landmark reason labels", () => {
  const payload = fiveSetPayload();
  validateResultsPayload(payload);
  assert(Array.isArray(payload.sets), "fixture must retain all five sets");
  assert(payload.sets.length === 5, "fixture must exercise five sets");
});

Deno.test("progress payload accepts privacy-safe diagnostic reason map", () => {
  validateResultsPayload({
    schema_version: 1,
    contribution_type: "progress_scan",
    local_session_id: "10000000-0000-4000-8000-000000000002",
    analysis_version: 7,
    threshold_set_identifier: "engineering-v1",
    regions: [],
    failure_reason_codes_by_pose: {
      back_silhouette: "hip_landmarks_unavailable",
    },
  });
});

Deno.test("diagnostic map still rejects raw coordinates and nested Vision data", () => {
  const payload = fiveSetPayload();
  const sets = payload.sets as Array<Record<string, unknown>>;
  sets[1].failure_reason_codes_by_pose = {
    "set_2.back.hipLandmarks": { x: 0.4, y: 0.6 },
  };
  let code = "";
  try {
    validateResultsPayload(payload);
  } catch (error) {
    code = error instanceof Error ? error.message : "unknown";
  }
  assert(code === "invalid_results", "raw diagnostic objects must fail closed");
});

Deno.test("diagnostic map still rejects filenames and masks", () => {
  for (
    const [label, reason] of [
      ["set_2.back.image_filename", "hip_landmarks_unavailable"],
      ["set_2.back.hipLandmarks", "person_mask_unavailable"],
    ]
  ) {
    const payload = fiveSetPayload();
    const sets = payload.sets as Array<Record<string, unknown>>;
    sets[1].failure_reason_codes_by_pose = { [label]: reason };
    let code = "";
    try {
      validateResultsPayload(payload);
    } catch (error) {
      code = error instanceof Error ? error.message : "unknown";
    }
    assert(
      code === "forbidden_results_field",
      "private diagnostic terms must fail closed",
    );
  }
});

Deno.test("raw landmark schema fields remain forbidden outside reason maps", () => {
  const payload = fiveSetPayload();
  payload.landmark_coordinates = [{ x: 0.4, y: 0.6 }];
  let code = "";
  try {
    validateResultsPayload(payload);
  } catch (error) {
    code = error instanceof Error ? error.message : "unknown";
  }
  assert(
    code === "forbidden_results_field",
    "raw landmarks must remain forbidden",
  );
});

Deno.test("submission payload identity is independent of JSON object key order", async () => {
  const first = {
    sets: [{ set_number: 1, regions: [{ region: "waist", status: "stable" }] }],
    analysis_version: 7,
    schema_version: 1,
  };
  const reordered = {
    schema_version: 1,
    analysis_version: 7,
    sets: [{ regions: [{ status: "stable", region: "waist" }], set_number: 1 }],
  };
  const firstHash = await sha256(canonicalJSONStringify(first));
  const reorderedHash = await sha256(canonicalJSONStringify(reordered));
  assert(
    firstHash === reorderedHash,
    "equivalent JSON must have one retry identity",
  );
});

Deno.test("submission payload identity still changes for changed evidence", async () => {
  const stable = { analysis_version: 7, regions: [{ status: "stable" }] };
  const changed = { analysis_version: 7, regions: [{ status: "increase" }] };
  const stableHash = await sha256(canonicalJSONStringify(stable));
  const changedHash = await sha256(canonicalJSONStringify(changed));
  assert(
    stableHash !== changedHash,
    "materially changed results must conflict",
  );
});
