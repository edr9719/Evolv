import { applyRetention, json, serviceClient } from "../_shared/pilot.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ code: "method_not_allowed" }, 405);
  const configured = Deno.env.get("PILOT_CRON_SECRET") || "";
  const supplied = (req.headers.get("authorization") || "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (!constantTimeEqual(configured, supplied)) {
    return json({ code: "unauthorized" }, 401);
  }
  try {
    return json(await applyRetention(serviceClient()));
  } catch {
    return json({ code: "retention_failed" }, 500);
  }
});

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length < 32 || left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}
