import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './index.ts';

// Helper to create valid RS256 RSA keys for testing Firebase JWT validation
async function generateTestKeys() {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"]
  );
  const jwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
  jwk.kid = "test-kid-1";
  return { keyPair, jwk };
}

function base64url(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64url");
}

async function createSignedFirebaseJWT(sub: string, keyPair: CryptoKeyPair, kid: string, overrides: Record<string, any> = {}) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", kid };
  const claims = {
    aud: "suzzme-e70f2",
    iss: "https://securetoken.google.com/suzzme-e70f2",
    sub,
    iat: now - 10,
    auth_time: now - 10,
    exp: now + 3600,
    ...overrides,
  };

  const enc = new TextEncoder();
  const headerB64 = base64url(enc.encode(JSON.stringify(header)));
  const claimsB64 = base64url(enc.encode(JSON.stringify(claims)));
  const dataToSign = enc.encode(`${headerB64}.${claimsB64}`);

  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", keyPair.privateKey, dataToSign);
  return `${headerB64}.${claimsB64}.${base64url(new Uint8Array(signature))}`;
}

test('Voice Gateway - rejects non-POST requests', async () => {
  const env = {
    ASSEMBLYAI_API_KEY: { get: async () => "dummy-assembly-key" },
    ELEVENLABS_API_KEY: { get: async () => "dummy-eleven-key" },
    ELEVENLABS_VOICE_ID: "hpp4J3VqNfWAUOO0d1Us"
  };
  const res = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/transcribe-token", { method: "GET" }), env);
  assert.equal(res.status, 405);
});

test('Voice Gateway - rejects unauthenticated requests', async () => {
  const env = {
    ASSEMBLYAI_API_KEY: { get: async () => "dummy-assembly-key" },
    ELEVENLABS_API_KEY: { get: async () => "dummy-eleven-key" },
    ELEVENLABS_VOICE_ID: "hpp4J3VqNfWAUOO0d1Us"
  };
  const res = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/transcribe-token", { method: "POST" }), env);
  assert.equal(res.status, 401);
});

test('Voice Gateway - rejects invalid or expired JWT tokens', async () => {
  const { keyPair, jwk } = await generateTestKeys();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url: any) => {
    if (String(url).includes("googleapis.com/service_accounts/v1/jwk/securetoken")) {
      return Response.json({ keys: [jwk] });
    }
    return originalFetch(url);
  };

  try {
    const env = {
      ASSEMBLYAI_API_KEY: { get: async () => "dummy-assembly-key" },
      ELEVENLABS_API_KEY: { get: async () => "dummy-eleven-key" },
      ELEVENLABS_VOICE_ID: "hpp4J3VqNfWAUOO0d1Us"
    };

    // Expired token
    const expiredToken = await createSignedFirebaseJWT("user123", keyPair, "test-kid-1", {
      exp: Math.floor(Date.now() / 1000) - 100
    });
    const res1 = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/transcribe-token", {
      method: "POST",
      headers: { authorization: `Bearer ${expiredToken}` }
    }), env);
    assert.equal(res1.status, 401);

    // Wrong audience
    const wrongAudToken = await createSignedFirebaseJWT("user123", keyPair, "test-kid-1", {
      aud: "wrong-project-id"
    });
    const res2 = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/transcribe-token", {
      method: "POST",
      headers: { authorization: `Bearer ${wrongAudToken}` }
    }), env);
    assert.equal(res2.status, 401);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Voice Gateway - /transcribe-token succeeds with valid Firebase token', async () => {
  const { keyPair, jwk } = await generateTestKeys();
  const originalFetch = globalThis.fetch;
  let assemblyCalled = false;

  globalThis.fetch = async (url: any, init: any) => {
    const urlStr = String(url);
    if (urlStr.includes("googleapis.com/service_accounts/v1/jwk/securetoken")) {
      return Response.json({ keys: [jwk] });
    }
    if (urlStr.includes("streaming.assemblyai.com/v3/token")) {
      assemblyCalled = true;
      assert.equal(init?.headers?.authorization, "mock-assembly-key");
      return Response.json({ token: "assembly-ephemeral-token" });
    }
    return originalFetch(url, init);
  };

  try {
    const env = {
      ASSEMBLYAI_API_KEY: { get: async () => "mock-assembly-key" },
      ELEVENLABS_API_KEY: { get: async () => "mock-eleven-key" },
      ELEVENLABS_VOICE_ID: "hpp4J3VqNfWAUOO0d1Us"
    };

    const validToken = await createSignedFirebaseJWT("alice123", keyPair, "test-kid-1");
    const res = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/transcribe-token", {
      method: "POST",
      headers: { authorization: `Bearer ${validToken}` }
    }), env);

    assert.equal(res.status, 200);
    assert.equal(res.headers.get("content-type"), "application/json");
    const json = await res.json() as any;
    assert.equal(json.token, "assembly-ephemeral-token");
    assert.equal(assemblyCalled, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Voice Gateway - /tts validates text and proxies ElevenLabs streaming response', async () => {
  const { keyPair, jwk } = await generateTestKeys();
  const originalFetch = globalThis.fetch;
  let elevenLabsCalled = false;

  globalThis.fetch = async (url: any, init: any) => {
    const urlStr = String(url);
    if (urlStr.includes("googleapis.com/service_accounts/v1/jwk/securetoken")) {
      return Response.json({ keys: [jwk] });
    }
    if (urlStr.includes("api.elevenlabs.io/v1/text-to-speech")) {
      elevenLabsCalled = true;
      assert.equal(init?.headers?.["xi-api-key"], "mock-eleven-key");
      const reqBody = JSON.parse(init.body);
      assert.equal(reqBody.text, "Good morning, Rehan! Here is your Daily Summary.");
      assert.equal(reqBody.model_id, "eleven_flash_v2_5");
      return new Response(new Uint8Array([0xFF, 0xFB, 0x90, 0x44]), {
        headers: { "content-type": "audio/mpeg" }
      });
    }
    return originalFetch(url, init);
  };

  try {
    const env = {
      ASSEMBLYAI_API_KEY: { get: async () => "mock-eleven-key" },
      ELEVENLABS_API_KEY: { get: async () => "mock-eleven-key" },
      ELEVENLABS_VOICE_ID: "hpp4J3VqNfWAUOO0d1Us"
    };

    const validToken = await createSignedFirebaseJWT("alice123", keyPair, "test-kid-1");
    
    // Test empty text validation
    const emptyRes = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/tts", {
      method: "POST",
      headers: {
        authorization: `Bearer ${validToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ text: "   " })
    }), env);
    assert.equal(emptyRes.status, 400);

    // Test valid TTS request
    const validRes = await worker.fetch(new Request("https://suzzme-voice.suzzmeai.workers.dev/tts", {
      method: "POST",
      headers: {
        authorization: `Bearer ${validToken}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({ text: "Good morning, Rehan! Here is your Daily Summary." })
    }), env);

    assert.equal(validRes.status, 200);
    assert.equal(validRes.headers.get("content-type"), "audio/mpeg");
    assert.equal(elevenLabsCalled, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
