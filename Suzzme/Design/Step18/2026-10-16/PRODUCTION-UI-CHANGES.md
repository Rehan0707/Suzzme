# Step 18 production UI changes — first bounded batch

The batch refines existing production SwiftUI views. The original Face, assets, navigation destinations, Core, Foundation Models requests, persistence, voice controller, conversation ownership, attribution, cancellation and confirmation callbacks remain in place.

| Modified production file | Change | Behavior retained |
|---|---|---|
| `Suzzme/Features/Home/AskSuzzmeView.swift` | A shared 600-point minimum Mac reading surface; native fitted presentation on macOS 15+; named, secondary Sources link; smaller vertical composer padding; borderless Mac voice action | Existing text binding, real request dispatch, follow-ups, response routes, cancellation, voice ownership, action review, keyboard and Dynamic Type fallback |
| `Suzzme/Features/Settings/IntegrationsView.swift` | Search follows the heading; detailed data-flow explanation moves into How access works; catalog-only entries are optional while search includes every entry; single results have a singular accessibility count | All 121 directory records, actual account/permission statuses, links, authorization owners, setup routes, catalog honesty, and external-write restrictions |
| `Suzzme/Features/Settings/VoiceSettingsView.swift` | One visible pace label/value above its labeled slider; iOS selection feedback after editing ends; optional Mac trackpad feedback setting | Same speech-rate binding, range, default/reset, voices, previews, permission handling and iPhone hardware fallback |
| `Suzzme/App/LaunchExperience.swift` | Neutral semantic onboarding background; existing step transitions use the shared disclosure token | Original Face, seven steps, local profile, explicit permission buttons and completion |
| `Suzzme/DesignSystem/Theme/SuzzmeTheme.swift` | Named Assistant minimum-width token and Reduce Motion-aware disclosure token | Existing semantic colors, spacing, radii, type roles and presence motion tokens |
| `Suzzme/DesignSystem/Components/SuzzmeInteractionFeedback.swift` | Best-effort AppKit confirmation/completion feedback using the existing event owner and preference | Existing iOS capability guard and UIKit feedback; visual state remains authoritative |

## Production and preview inventory

`SuzzmeAssistantComposer`, `SuzzmeAssistantStatusIndicator`, `SuzzmeResponseAttribution`, `SuzzmeAssistantConversationScroll`, and `SuzzmeAssistantNotice` already participate in production Ask. They were retained rather than duplicated. `SuzzmeAssistantComponents.swift` itself required no change in this batch.

`MacRootView` owns the native split-view/sidebar; `MobileRootView` owns compact native navigation. Their existing routes and environment stay intact. Home is declared in `CompanionHomeView.swift`; the Today content is `DailyContextView` in `HomeView.swift`.

`AssistantDesignConcepts`, `AssistantResponsiveDesignLab`, `ApprovedAssistantDesignGallery`, `AssistantPreviewFixtures`, and `PresenceMotionLabView` are DEBUG-only. Their demo conversations and simulated phases were not promoted. A prepared adaptive layout was not inserted alongside the existing native navigation owner.

`MacAssistantNotchSurface` and iOS Live Activity ownership are production implementations. The 48 supplied presence images are ImageRenderer fixtures. Missing target/response text in those images is an unresolved capture/runtime distinction, not a confirmed production fix.

## Sheet sizing correction

The first native run exposed clipping when wider content remained inside the platform’s default form-sized presentation. That rejected capture is retained as `evidence/diagnostic-clipped-sheet.jpg`. The correction adds availability-gated native fitted presentation sizing, preserving a fallback on macOS 14. Apple documents fitted sheets as content-sized and user-resizable when minimum/maximum frames are used: [Apple fitted sizing documentation](https://developer.apple.com/documentation/swiftui/presentationsizing/fitted).

A compiler-detected Slider argument-order error was also corrected before the successful batch builds. Initial failed attempt logs remain in evidence.

No signing, provisioning, entitlement, app-group, or brand configuration was intentionally changed. No owner data was reset or simulator erased. This is a first production batch, not acceptance of the entire Step 18 mission.
