# Suzzme landing page

Local, dependency-free marketing site inspired by the native Suzzme app and the companion design studies. Reuses the existing cloud companion artwork.

Run from this directory:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Open http://localhost:4173. All assets are local. No build step, external fonts, analytics, or network services are required.

The context/summary/plan tabs and companion state controls are interactive. Both sequences support playback and pause. Motion respects the OS preference and the footer control; playback stops when the tab is hidden. The content is illustrative, and the device surfaces are browser previews rather than native ActivityKit implementations.
