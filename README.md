# Suzme

Native, privacy-first personal assistant for iPhone, iPad and Mac. The existing Xcode project and identifiers remain `Suzzme` / `rehan.Suzzme`.

See [app architecture and build instructions](Suzzme/README.md), [product vision](Suzzme/PRODUCT_VISION.md), and [current release evidence and remaining acceptance gates](Suzzme/LAUNCH_READINESS.md).

| Location | Purpose |
| --- | --- |
| [`Suzzme/Suzzme/`](Suzzme/Suzzme/) | App composition, core services, features, design system and platform adapters |
| [`Suzzme/Suzzme.xcodeproj/`](Suzzme/Suzzme.xcodeproj/) | Shared iOS and macOS application and extension targets |
| [`Suzzme/Packages/`](Suzzme/Packages/) | Local speech and watched-link transport packages |
| [`Suzzme/PresenceShared/`](Suzzme/PresenceShared/), [`Suzzme/SuzzmePresenceWidget/`](Suzzme/SuzzmePresenceWidget/) | Shared Live Activity models and WidgetKit extension |
| [`Suzzme/ShareShared/`](Suzzme/ShareShared/), [`Suzzme/SuzzmeShareExtension/`](Suzzme/SuzzmeShareExtension/) | Shared URL inbox and native Share extension |
| [`Suzzme/BrowserExtension/`](Suzzme/BrowserExtension/), [`Suzzme/BrowserNativeHost/`](Suzzme/BrowserNativeHost/) | Chrome bridge and macOS native messaging helpers |
| [`Suzzme/ConnectorServer/`](Suzzme/ConnectorServer/) | Optional connector service, configuration templates and server tests |
| [`Suzzme/Validation/`](Suzzme/Validation/README.md) | Validation guide, executable checks and historical store fixtures |
| [`Suzzme/Release/`](Suzzme/Release/README.md) | Distribution instructions and export templates |
| [`App-Screenshots/`](App-Screenshots/README.md) | Labeled app screenshots and browsable gallery |
| [`Suzzme/Design/`](Suzzme/Design/README.md) | Historical specifications, prototypes and original visual evidence |
| [`Suzzme/ReferenceSource/`](Suzzme/ReferenceSource/CONVERSION.md) | Third-party reference snapshot, provenance and license; outside the app target |

Keep generated builds, compiler caches and deployment bundles out of source directories. The [validation guide](Suzzme/Validation/README.md) explains where checks write output and which files must be retained.

Release acceptance is incomplete. Build success, simulator verification, physical-device acceptance and distribution readiness are separate gates.
