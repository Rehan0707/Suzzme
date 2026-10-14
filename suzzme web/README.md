# Suzzme web

A responsive product and demo website for Suzzme. It uses HTML, CSS, JavaScript, a progressively enhanced Three.js hero, and Python’s standard library; no package installation is required.

## Preview

From this folder:

```sh
python3 server.py
```

Open http://127.0.0.1:4173. The product site itself is static and can be deployed to any static host.

## Files

- `dist/index.html`: product story, interactive product film, capabilities, privacy, build guide, contributors, and FAQs.
- `dist/site.css`: the current responsive visual system and product-demo styling.
- `dist/site.js`: the Three.js hero, interactive film, Presence states, and navigation behavior.
- `dist/styles.css`: app-preview layout and base design tokens.
- `dist/refinement.css`: editorial typography, frosted navigation, responsive feature panels and accessibility preferences.
- `dist/experience.css`: lavender colour grading, hero and preview motion, and reduced-motion support.
- `dist/ux.css`: mobile navigation, readable phone preview, responsive refinements, atmospheric hero, and switchable product story.
- `dist/suzzme-app-icon.png`: the exact supplied Suzzme iOS app icon, used for the website brand and favicon.
- `dist/fonts/`: bundled Inter fonts and license.
- `dist/app.js`: retained legacy experience script; the current site uses `site.js`.
- `server.py`: serves the site and saves email, chosen device, and join time in SQLite.

## Product and design grounding

Copy is based on `Suzzme/PRODUCT_VISION.md`, `Suzzme/README.md`, and the app implementation. The app icon matches the supplied iOS app asset. The face in the illustrative UI reproduces the normalized coordinates from `SuzzmeFace.swift`; the accent is the app's light-mode `AccentColor` (#744575). The typography uses native Apple system fonts with locally bundled Inter (SIL Open Font License) as the fallback on other systems. No analytics, external fonts, or third-party scripts are included. Signup storage is handled by the local Python server.

Product previews contain fictional example data; they are HTML illustrations rather than app screenshots. Public release remains labelled in development. Sync is not advertised as available. The waitlist is open in the local preview; no automatic email is sent.

Research references:

- https://linear.app — product-first storytelling and detailed interface previews.
- https://www.raycast.com — concise product framing and feature demonstrations.
- https://www.notta.ai — use-case-led explanation of an AI product.

The layout, copy, and illustrations are original to Suzzme. This local website has not been publicly deployed.

September 2026 visual refresh references:

- https://www.apple.com/in/apps/ — clear editorial hierarchy and spacious product sections.
- https://www.heyclicky.com — companion-led personality and desktop-inspired product presentation.

## Waitlist operation

The site stores one row per email address. Repeat signups return the same confirmation without creating another row. To inspect signups locally:

```sh
python3 - <<'PYREAD'
import sqlite3
with sqlite3.connect('data/waitlist.sqlite3') as db:
    for row in db.execute('SELECT email, platform, joined_at FROM signups ORDER BY joined_at'):
        print(*row, sep='\t')
PYREAD
```

The current server binds to `127.0.0.1`, so only this computer can use the form. For a public waitlist, deploy the site with a persistent server and database, or adapt the `/api/waitlist` endpoint to the chosen host’s database. A static-only deployment cannot accept signups.

Reference for the waitlist interaction: https://hearly.live/ — prominent calls to action opening a short signup dialog. Suzzme uses its own copy, styling, and supported-device choices.

October 2026 UX update: visitors can explore Today, Ask, Memory, and Actions across the Mac and iPhone previews. The explanation below the devices follows the selected view. Mobile section links are visible, and the device choice in the waitlist is optional.

LineLens reference: https://linelens.in/ — its spacious hero and switchable product demonstration informed the Suzzme hero and four-part preview. Suzzme uses its own visual identity, content, and product examples.

The current design includes a dedicated iPhone section and an interactive MacBook presence showcase. Mac presence PNGs in `dist/native-presence/` are rendered from the actual SwiftUI component using `scripts/NativePresenceRender.swift`; the iPhone and other app previews are illustrative HTML. `dist/redesign.css` contains the latest visual refinements.

October 2026 rebuild: the site was rebuilt iPhone-first around the Suzzme Face mascot. The brand system follows the app icon (violet to white with dark strokes); plum (#744575) is used only inside app screens, where it is the real accent. Sections: iPhone hero with a looping voice question, scroll-driven flow diagram (sources → understanding → outcomes), sticky iPhone request lifecycle, a day on iPhone, the Mac Presence demo below the notch, Face states, privacy, build, FAQs and the waitlist dialog (posts to `/api/waitlist`). Everything is in `dist/index.html`, `dist/site.css` and `dist/site.js`, with an inline SVG icon sprite and no third-party scripts. All motion respects Reduce Motion, and the autoplaying demos pause when off-screen and have a Pause control. The previous version is in git history; the older stylesheets and `app.js` are no longer loaded. `assets/suzzme-icon-64.png`, `assets/suzzme-icon-180.png` and `assets/suzzme-context-field-v2.jpg` are resized copies of the original images.
