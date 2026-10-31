# Step 18 remaining work

This first batch does not complete the entire visual/runtime mission.

| Priority | Remaining work | Evidence / prerequisite |
|---|---|---|
| P1 | Exercise the current iOS app and investigate any white screen from real rendered output | Retained QA simulator boot passed; baseline app install timed out after 45 seconds. No iOS runtime image has been accepted. No device was erased. |
| P1 | Verify confirmation targets and answer text in an actual native Mac presence panel | ImageRenderer fixtures omit ScrollView bodies despite supplied text. Do not infer a production fix from source or replace evidence with previews. |
| P2 | Complete Mac compact/large-window and iPhone compact/standard/large-width passes | The first batch exercises the regular Mac workspace; every size is not yet accepted. |
| P2 | Complete VoiceOver, focus traversal, preferred-text sizing, Increased Contrast, Reduce Transparency and Reduce Motion combinations | Semantic labels and reduced-motion guards are retained; manual assistive-technology acceptance is still needed. |
| P2 | Human voice end-to-end and interruption acceptance | Microphone, local recognition, real model response, speech output, interruption and output routes need a deliberate hardware session. Automated voice checks do not establish this. |
| P2 | Hardware notch, iPhone Live Activity/Dynamic Island, and physical haptics | Existing public-API implementations remain; physical sensation and system-owned presentation were not accepted by a simulator or still image. |
| P2 | Finish presentation refinements for Today, Daily Summary, Memory, Sources and secondary Settings where the audit identifies issues | These screens and all routes were retained. Dense summary paragraphs and form top-spacing observations remain open. |
| P3 | Review short information-sheet height and provider-button silhouette | Preserve original Face and SDK branding; do not claim account authentication is implemented. |

## Owner-required boundaries

- Input Monitoring remains unchanged, following the owner's explicit instruction. Cross-app Control–Option acceptance is excluded; do not request the same permission again without a new owner instruction.
- To verify real iPhone hardware behavior, an available provisioned device and the owner's device access are needed. Signing, provisioning, entitlements and app groups must not be altered without explicit approval.
- Google account/source configuration and browser deployment are still blocked by the earlier release audit. Registered public configuration and any necessary entitlement/app-group changes require separate authorized setup. No secret should be placed in screenshots, model context or reports.
- Final visual approval by the owner has not been recorded. The request authorizes implementation and testing of this batch, not a claim that the owner has already reviewed its final appearance.
