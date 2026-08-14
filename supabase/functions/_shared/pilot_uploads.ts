export type PilotStoredObject = {
  bucketId?: string;
  name?: string;
  size?: number;
  metadata?: { size?: number } | null;
};

export type PilotStorageError = {
  code?: string;
  message?: string;
  status?: number;
  statusCode?: string | number;
};

export type PilotStorageInfoResult = {
  data: PilotStoredObject | null;
  error: PilotStorageError | null;
};

export type PilotObjectStorageState =
  | { kind: "missing" }
  | { kind: "ready"; byteCount: number }
  | { kind: "wrong_size"; byteCount: number };

export interface PilotStorageBucket {
  info(path: string): Promise<PilotStorageInfoResult>;
}

/**
 * Uses Supabase Storage's supported object-info API. The storage schema is not
 * exposed through PostgREST in production, even to the service-role client.
 */
export async function inspectPilotObject(
  bucket: PilotStorageBucket,
  bucketID: string,
  path: string,
  expectedByteCount: number,
): Promise<PilotObjectStorageState> {
  const { data, error } = await bucket.info(path);
  if (error) {
    if (isMissingObject(error)) return { kind: "missing" };
    throw new Error("storage_verification_failed");
  }
  if (!data || data.bucketId !== bucketID || data.name !== path) {
    throw new Error("storage_verification_failed");
  }
  const rawSize = data.size ?? data.metadata?.size;
  const byteCount = Number(rawSize);
  if (!Number.isSafeInteger(byteCount) || byteCount < 0) {
    throw new Error("storage_verification_failed");
  }
  return byteCount === expectedByteCount
    ? { kind: "ready", byteCount }
    : { kind: "wrong_size", byteCount };
}

function isMissingObject(error: PilotStorageError): boolean {
  return error.code === "NoSuchKey" || String(error.statusCode) === "404";
}
