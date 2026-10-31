interface Env {
  ASSEMBLYAI_API_KEY: { get(): Promise<string> };
  ELEVENLABS_API_KEY: { get(): Promise<string> };
  ELEVENLABS_VOICE_ID: string;
}

const firebaseProject = "suzzme-e70f2";

function decodeBase64URL(value: string): Uint8Array {
  const bytes = atob(value.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(bytes, character => character.charCodeAt(0));
}

async function authenticated(request: Request): Promise<boolean> {
  const match = /^Bearer (\S+)$/.exec(request.headers.get("authorization") ?? "");
  if (!match) return false;
  const parts = match[1].split(".");
  if (parts.length !== 3) return false;
  try {
    const header = JSON.parse(new TextDecoder().decode(decodeBase64URL(parts[0]))) as { alg?: string; kid?: string };
    const claims = JSON.parse(new TextDecoder().decode(decodeBase64URL(parts[1]))) as {
      aud?: string; iss?: string; sub?: string; exp?: number; iat?: number; auth_time?: number;
    };
    const now = Math.floor(Date.now() / 1000);
    if (header.alg !== "RS256" || !header.kid || claims.aud !== firebaseProject ||
        claims.iss !== `https://securetoken.google.com/${firebaseProject}` ||
        !claims.sub || claims.sub.length > 128 || !claims.exp || claims.exp <= now ||
        !claims.iat || claims.iat > now || !claims.auth_time || claims.auth_time > now) return false;
    const keysResponse = await fetch("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com");
    if (!keysResponse.ok) return false;
    const keySet = await keysResponse.json() as { keys?: Array<JsonWebKey & { kid?: string }> };
    const publicKey = keySet.keys?.find(key => key.kid === header.kid);
    if (!publicKey) return false;
    const key = await crypto.subtle.importKey("jwk", publicKey, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    return await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, decodeBase64URL(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  } catch { return false; }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    if (!(await authenticated(request))) return new Response("Unauthorized", { status: 401 });
    const path = new URL(request.url).pathname;
    if (path === "/transcribe-token") {
      const assemblyAIKey = await env.ASSEMBLYAI_API_KEY.get();
      if (!assemblyAIKey) return new Response("Not configured", { status: 503 });
      const upstream = await fetch("https://streaming.assemblyai.com/v3/token?expires_in_seconds=60", {
        headers: { authorization: assemblyAIKey },
      });
      if (!upstream.ok) {
        console.error("AssemblyAI token request failed", upstream.status);
        return new Response("Transcription unavailable", { status: 502 });
      }
      return new Response(upstream.body, { headers: { "content-type": "application/json", "cache-control": "no-store" } });
    }
    if (path === "/tts") {
      const elevenLabsKey = await env.ELEVENLABS_API_KEY.get();
      if (!elevenLabsKey || !env.ELEVENLABS_VOICE_ID) return new Response("Not configured", { status: 503 });
      let text: string;
      try {
        const body = await request.json() as { text?: unknown };
        text = typeof body.text === "string" ? body.text.trim() : "";
      } catch { return new Response("Invalid request", { status: 400 }); }
      if (!text || text.length > 6000) return new Response("Invalid text length", { status: 400 });
      const upstream = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(env.ELEVENLABS_VOICE_ID)}`, {
        method: "POST",
        headers: { "xi-api-key": elevenLabsKey, "content-type": "application/json", accept: "audio/mpeg" },
        body: JSON.stringify({ text, model_id: "eleven_flash_v2_5", voice_settings: { stability: 0.5, similarity_boost: 0.75 } }),
      });
      if (!upstream.ok) {
        console.error("ElevenLabs speech request failed", upstream.status);
        return new Response("Speech unavailable", { status: 502 });
      }
      return new Response(upstream.body, { headers: { "content-type": "audio/mpeg", "cache-control": "no-store" } });
    }
    return new Response("Not found", { status: 404 });
  },
};
