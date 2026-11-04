# Suzzme landing page

Local, dependency-free marketing site inspired by the native Suzzme app and the companion design studies. Reuses the existing cloud companion artwork.

Run from this directory:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Open http://localhost:4173. All assets are local. No build step, external fonts, analytics, or network services are required.

The context/summary/plan tabs and companion state controls are interactive. Both sequences support playback and pause. Motion respects the OS preference and the footer control; playback stops when the tab is hidden. The content is illustrative, and the device surfaces are browser previews rather than native ActivityKit implementations.

## Reference-inspired layout

The hero uses the supplied video’s framed dark canvas, centered masthead, editorial serif headline, illustration-led right column, pill actions, and bottom information rail. The original blue Suzzme companion is retained throughout the site, including the device demos. No third-party mascot is used. The hero combines the existing mascot with an illustrated scene based on the supplied video frame and SVG strings. `reference.css` contains the visual layer for this layout; `style.css` contains the established components.

The supplied video frame was used to create `assets/hero-scene.webp`, a clean reference-matched background plate. Suzzme and the strings share an SVG coordinate system so the companion can animate while the copy stays selectable and accessible.


## Desktop layout and theme

Designed for desktop browser widths of 1024px and above. The hero preserves the reference frame’s 1.62 aspect ratio and scales its typography, illustration, and information rail together. Below 1024px the desktop canvas is retained rather than switching to a phone layout.

The whole page uses a dark teal palette, cream serif headings, muted warm accents, and a local SVG engraving texture. The outer frame is solid dark teal; the earlier yellow gradient has been removed. The day demo, device showcase, privacy cards, closing section, and footer share this theme. The illustrated phone is a product showcase on the desktop page.

Validated at 1024, 1280, and 1752px widths, with working summary/plan controls, companion states, and reduced-motion control. There is no downloadable app artifact configured; the calls to action open the interactive demo.
