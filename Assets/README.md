# PaneSpace visual identity

`PaneSpace-AppIcon.png` is the 1254 × 1254 transparent raster master. `PaneSpace.icns` contains the standard macOS 16, 32, 128, 256, 512, and 1024-point representations generated from that master.

## Design rationale

- Three overlapping panes represent simultaneous file locations and column browsing.
- The front folded corner anchors the mark in file management without relying on a generic folder silhouette.
- Indigo and cyan distinguish PaneSpace from Finder while remaining legible in light and dark environments.
- The centered silhouette and limited interior detail remain recognizable at small Dock and Finder sizes.

## Regeneration

Create a temporary `PaneSpace.iconset` directory, resize the master into the standard `icon_<size>.png` and `icon_<size>@2x.png` files with `sips`, then run:

```bash
iconutil -c icns PaneSpace.iconset -o Assets/PaneSpace.icns
```

After replacing the icon, run `make app` and confirm the built application contains `Contents/Resources/PaneSpace.icns` before verifying its code signature.
