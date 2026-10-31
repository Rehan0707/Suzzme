import { makePush, providerJWT, retryDelay, isInvalidToken, type Job, type Device } from "./push.ts";

// This worker is called only by the private cron secret, never by a mobile client.
// User operations use Firebase-verified PostgREST RPCs and row-level security.
Deno.serve(async (request: Request) => {
  const secret = Deno.env.get("COMPANION_WORKER_SECRET");
  if (!secret || request.headers.get("x-companion-worker-secret") !== secret) return new Response("Unauthorized", { status: 401 });
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const project = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const team = Deno.env.get("APNS_TEAM_ID"), keyID = Deno.env.get("APNS_KEY_ID"), pem = Deno.env.get("APNS_PRIVATE_KEY");
  const bundle = Deno.env.get("APNS_BUNDLE_ID");
  if (!project || !serviceKey || !team || !keyID || !pem || !bundle) return new Response("Push delivery is not configured", { status: 503 });
  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" };
  const db = async (path: string, method = "GET", body?: object) => {
    const response = await fetch(`${project}/rest/v1/${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("Delivery database unavailable");
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  };
  try {
    const jwt = await providerJWT(team, keyID, pem);
    const jobs: Job[] = await db("rpc/claim_companion_deliveries", "POST", {});
    let accepted = 0;
    // A small bounded batch stays within edge-worker runtime limits.
    await Promise.all(jobs.map(async (job) => {
      const finish = (state: string, error: string | null, delay = 0) => db(
        `companion_delivery_jobs?id=eq.${job.id}&lease_id=eq.${job.lease_id}`, "PATCH", {
          state, last_error: error, available_at: new Date(Date.now() + delay * 1000).toISOString()
        });
      try {
        const devices: Device[] = await db(`companion_devices?installation_id=eq.${encodeURIComponent(job.installation_id)}&firebase_uid=eq.${encodeURIComponent(job.firebase_uid)}&limit=1`);
        const device = devices[0];
        // Re-check sharing after claiming: deletion must cancel pending publication.
        const summaries = job.kind === "end" ? [true] : await db(`companion_summaries?firebase_uid=eq.${encodeURIComponent(job.firebase_uid)}&select=firebase_uid&limit=1`);
        const push = device && summaries.length ? makePush(job, device, bundle) : null;
        if (!push) { await finish("failed", "UnavailableOrExpired"); return; }
        const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
        const response = await fetch(`https://${host}/3/device/${push.token}`, { method: "POST", headers: {
          authorization: `bearer ${jwt}`, "apns-topic": push.topic, "apns-push-type": push.pushType,
          "apns-priority": "10", "apns-expiration": String(Math.floor(Date.parse(job.expires_at) / 1000)),
          "apns-collapse-id": push.collapseID, "content-type": "application/json"
        }, body: JSON.stringify(push.body), signal: AbortSignal.timeout(10000) });
        if (response.ok) { accepted++; await finish("sent", null); return; }
        const reason = String((await response.json().catch(() => ({}))).reason ?? "APNsRejected");
        const invalid = isInvalidToken(response.status, reason);
        if (invalid) {
          // Only invalidate the rejected token; a rotation during the send survives.
          await db(`companion_devices?installation_id=eq.${device.installation_id}&firebase_uid=eq.${encodeURIComponent(job.firebase_uid)}&${push.tokenColumn}=eq.${push.token}`, "PATCH",
            push.tokenColumn === "activity_token" ? { activity_token: null, activity_id: null } : { [push.tokenColumn]: null });
        }
        const retry = invalid || response.status === 429 || response.status >= 500;
        await finish(retry && job.attempts < 6 ? "pending" : "failed", /^[A-Za-z]{1,80}$/.test(reason) ? reason : "APNsRejected", retryDelay(job.attempts));
      } catch {
        await finish(job.attempts < 6 ? "pending" : "failed", "TemporaryDeliveryFailure", retryDelay(job.attempts));
      }
    }));
    return Response.json({ claimed: jobs.length, accepted });
  } catch { return new Response("Delivery temporarily unavailable", { status: 503 }); }
});
