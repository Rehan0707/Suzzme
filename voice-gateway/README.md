# Suzzme voice gateway

Authenticated proxy for AssemblyAI live transcription tokens and ElevenLabs speech. Provider keys stay in Cloudflare secrets. The app sends its Firebase ID token to this gateway; the gateway validates it with Firebase before issuing a short lived transcription token or synthesizing speech. No audio is stored by this worker.

Deployed Worker: `https://suzzme-voice.suzzmeai.workers.dev`

The provider keys are stored as `ASSEMBLYAI_API_KEY` and `ELEVENLABS_API_KEY` in Cloudflare Secrets Store and bound through `wrangler.toml`. The gateway verifies Firebase ID tokens using Google's public signing keys for the Suzzme Firebase project. The checked-in public voice ID is the one from Clicky's reference worker. Deploy the Worker, then add its HTTPS origin to the app's `SUZZME_VOICE_GATEWAY_URL` Xcode build setting, which fills `SuzzmeVoiceGatewayURL` in Info.plist. Do not set it to Clicky's placeholder worker URL.

Voice sends microphone audio directly to AssemblyAI after token issuance. Spoken response text goes through this gateway to ElevenLabs. The app displays a clear error and offers typing when the gateway is unavailable.
