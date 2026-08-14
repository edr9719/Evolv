import { inspectPilotObject, PilotStorageInfoResult } from "./pilot_uploads.ts";

function bucket(result: PilotStorageInfoResult) {
  return { info: async (_path: string) => result };
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("exact expected object is ready", async () => {
  const state = await inspectPilotObject(
    bucket({
      data: {
        bucketId: "pilot-photo-ciphertext",
        name: "study/participant/submission/object.bin",
        size: 128,
      },
      error: null,
    }),
    "pilot-photo-ciphertext",
    "study/participant/submission/object.bin",
    128,
  );
  assert(state.kind === "ready", "exact object should be ready");
});

Deno.test("missing expected object remains missing", async () => {
  const state = await inspectPilotObject(
    bucket({
      data: null,
      error: {
        code: "NoSuchKey",
        message: "Object not found",
        status: 400,
        statusCode: "404",
      },
    }),
    "pilot-photo-ciphertext",
    "expected.bin",
    128,
  );
  assert(state.kind === "missing", "missing object must not pass");
});

Deno.test("incorrect encrypted byte count is rejected", async () => {
  const state = await inspectPilotObject(
    bucket({
      data: {
        bucketId: "pilot-photo-ciphertext",
        name: "expected.bin",
        metadata: { size: 127 },
      },
      error: null,
    }),
    "pilot-photo-ciphertext",
    "expected.bin",
    128,
  );
  assert(state.kind === "wrong_size", "wrong size must not pass");
});

Deno.test("unexpected object identity fails closed", async () => {
  let code = "";
  try {
    await inspectPilotObject(
      bucket({
        data: {
          bucketId: "pilot-photo-ciphertext",
          name: "another-participant/object.bin",
          size: 128,
        },
        error: null,
      }),
      "pilot-photo-ciphertext",
      "expected-participant/object.bin",
      128,
    );
  } catch (error) {
    code = error instanceof Error ? error.message : "unknown";
  }
  assert(code === "storage_verification_failed", "identity mismatch must fail");
});

Deno.test("non-not-found storage failures do not become missing", async () => {
  let code = "";
  try {
    await inspectPilotObject(
      bucket({
        data: null,
        error: { code: "DatabaseTimeout", status: 500 },
      }),
      "pilot-photo-ciphertext",
      "expected.bin",
      128,
    );
  } catch (error) {
    code = error instanceof Error ? error.message : "unknown";
  }
  assert(
    code === "storage_verification_failed",
    "storage errors must fail closed",
  );
});
