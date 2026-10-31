# Cloud app icon

Created 25 October 2026 with the built-in ImageGen tool, using the user-supplied original blue character as the identity reference. The generated master was inspected and copied into the repository at `Suzzme/Design/Character/SuzzmeAppIcon-Master.png`.

The actual in-app mascot and all eight supplied color/speaking variants use the user's original assets. The generated image is reserved for the opaque app-icon canvas. `Suzzme/Design/Character/export-icons.swift` exports the master to the existing iOS 1024-pixel icon and all seven Mac icon sizes (16–1024 pixels), with opaque RGB output. The iOS default also supplies the system's fallback for unprovided dark/tinted artwork. No old mark remains in those PNGs.

## Final generation prompt

> Use case: compositing. Asset type: production Suzzme iOS and macOS app icon, one 1024 by 1024 square image. Input: supplied blue cloud character is the identity source and compositing subject. Preserve that same character: rounded sky-blue cloud silhouette, huge cream eyes with dark pupils, friendly small smile, eyebrows, small arms raised near cheeks, two little feet, smooth soft 3D shading. Keep its existing pose, proportions and recognizable face; do not redesign or invent a new mascot. Center the complete character on a clean very pale cool-white background with a barely perceptible blue tint. Character should fill about 82 percent of square width and 82 percent height, have sufficient safe margin, no clipped limbs, no extra objects. The only intended change from the reference is fitting the same character into a clean opaque app icon canvas with crisp antialiased edges and no cyan halo. Square edge-to-edge background: no baked rounded corners, no borders, no surrounding device, no text, no letters, no monogram, no watermark, no sparkle, no old three-stroke/chevron face. Soft professional Apple-native icon finish. Output a single flat square app icon image.

Re-export from the repository root:

```sh
xcrun swift -module-cache-path /tmp/SuzzmeMascotIconCache Suzzme/Design/Character/export-icons.swift "$PWD/Suzzme"
```
