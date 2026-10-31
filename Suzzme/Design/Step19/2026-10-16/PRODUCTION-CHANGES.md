# Step 19 production implementation

Five production SwiftUI files changed relative to the Step 19 source snapshot. Existing unrelated working-tree changes were preserved. `production-changes.diff` and `source-change-manifest.json` describe only this pass.

| File under Suzzme/Suzzme | Change |
|---|---|
| Features/Home/AskSuzzmeView.swift | Latest message control, shared Reduce Motion-aware scroll transition, passes the existing follow binding into the reusable scroll component. Request/conversation/confirmation/voice ownership unchanged. |
| DesignSystem/Components/SuzzmeAssistantComponents.swift | Native bottom-marker visibility on iOS 18+/macOS 15+, prior lifecycle fallback on older systems; end marker placed outside padded transcript. Important-state accessibility announcements while active. Existing composer, message rows, notices and attribution retained. |
| Features/Briefing/BriefingView.swift | Narration uses the existing 600-point companion measure and 8-point line spacing; neutral separators distinguish existing dated items. Stored/generated/spoken narration and source limitations unchanged. |
| DesignSystem/Layout/SuzzmePage.swift | Existing Mac collection modifier gets 24-point top padding; native forms/lists retain scrolling, row height, semantic surfaces and readable width. iOS collection layout unchanged. |
| DesignSystem/Components/SuzzmeInteractionFeedback.swift | Existing selection feedback extension delegates to a private scene-aware modifier; inactive scenes do not request haptics. Platform APIs, preference and hardware guards retained. |

No changes to startup routing, model configuration, Core, stores, action policy, Foundation Models, integrations, signing, entitlements, app groups, provisioning, Face/logo or color assets.

## Evidence-driven corrections

The first Latest message implementation used the old marker lifecycle callbacks, which remained active while the marker was offscreen. A coordinate-based implementation then kept the button visible at the bottom because native insets affected its measurement. Native scroll visibility correctly detected manual scrolling. Runtime then exposed the existing target's placement inside bottom padding; the final marker is outside that padded transcript so its anchor corresponds to the actual scroll end.

The first native collection content-margin change did not move the section header in the observed Mac list. It was replaced by explicit shared top padding. These intermediate attempts remain in iteration folders and build logs; they are not accepted as final screenshots.

The reported iOS white screen was not reproduced: installation succeeded but launch and a simulator process query stalled. No speculative startup rewrite was made. See IOS-STARTUP.md for exact failures and owner-run acceptance.

## Preserved behavior

Real on-device answers, multi-turn history, cancellation, capability availability, response attribution, context routing, destructive-action review, local privacy gates and source truthfulness remain under their original owners. The 600-point Mac Assistant sheet and named Sources link from Step 18 remain. Native iPhone keyboard-safe insets and accessible-size scrolling remain, with runtime acceptance still blocked by simulator infrastructure.
