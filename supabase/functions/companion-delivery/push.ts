/** Only public status crosses APNs. Narration is fetched by the authenticated app. */
export type Job = { id: number; firebase_uid: string; installation_id: string; event_key: string;
  kind: "routine" | "urgent" | "end"; generated_at: string; expires_at: string; attempts: number; lease_id: string };
export type Device = { installation_id: string; firebase_uid: string; device_token: string | null;
  start_token: string | null; activity_token: string | null; activity_id: string | null;
  environment: "sandbox" | "production"; routine_enabled: boolean; urgent_enabled: boolean };
export type Push = { token: string; tokenColumn: "device_token" | "start_token" | "activity_token";
  topic: string; pushType: "alert" | "liveactivity"; collapseID: string; body: object };

export function makePush(job: Job, device: Device, bundle: string, now = Date.now()): Push | null {
  if (device.firebase_uid !== job.firebase_uid || device.installation_id !== job.installation_id ||
    Date.parse(job.expires_at) <= now || !Number.isFinite(Date.parse(job.generated_at))) return null;
  if (job.kind === "routine" && !device.routine_enabled || job.kind === "urgent" && !device.urgent_enabled) return null;
  const timestamp = Math.floor(now / 1000);
  const urgent = job.kind === "urgent";
  const state = { phase: urgent ? "urgentReady" : "summaryReady", appearance: "blue", motionEnabled: false };
  const title = urgent ? "An important update is ready" : "Your summary is ready";
  const content = { timestamp, "content-state": state, "stale-date": Math.floor(Date.parse(job.expires_at) / 1000) };
  const common = { topic: `${bundle}.push-type.liveactivity`, pushType: "liveactivity" as const,
    collapseID: `suzzme-${job.kind}` };
  if (device.activity_token) {
    return { ...common, token: device.activity_token, tokenColumn: "activity_token", body: { aps: {
      ...content, event: job.kind === "end" ? "end" : "update",
      ...(job.kind === "end" ? { "dismissal-date": timestamp } : urgent ? { alert: { title: "Suzzme", body: title, sound: "default" } } : {})
    } } };
  }
  if (job.kind === "end") return null;
  if (device.start_token) {
    return { ...common, token: device.start_token, tokenColumn: "start_token", body: { aps: {
      ...content, event: "start", "attributes-type": "SuzzmeLiveActivityAttributes",
      attributes: { startedAt: timestamp - 978307200 }, "input-push-token": 1,
      alert: { title: "Suzzme", body: title, sound: "default" }
    } } };
  }
  if (!device.device_token) return null;
  return { token: device.device_token, tokenColumn: "device_token", topic: bundle, pushType: "alert",
    collapseID: `suzzme-${job.kind}`, body: { aps: {
      alert: { title: "Suzzme", body: title }, sound: "default", "content-available": 1,
      "interruption-level": urgent ? "time-sensitive" : "active", "thread-id": "suzzme-summary"
    }, "suzzme.destination": "daily-summary" } };
}

export function retryDelay(attempts: number): number { return Math.min(3600, 15 * 2 ** Math.max(0, attempts - 1)); }
export function isInvalidToken(status: number, reason: string): boolean {
  return status === 410 || status === 400 && ["BadDeviceToken", "DeviceTokenNotForTopic"].includes(reason);
}
const base64url = (bytes: Uint8Array): string => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
export async function providerJWT(team: string, keyID: string, pem: string, now = Date.now()): Promise<string> {
  const encoder = new TextEncoder();
  const keyBytes = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", keyBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const input = `${base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyID })))}.${base64url(encoder.encode(JSON.stringify({ iss: team, iat: Math.floor(now / 1000) })))}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input));
  return `${input}.${base64url(new Uint8Array(signature))}`;
}
