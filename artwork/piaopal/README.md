# PiaoPal artwork sources

Approved direction: A illustration app icon and B pixel PiaoPiao pet. No slogan.

The subject is the user's real female cat, PiaoPiao (飘飘). Original reference photographs are not included in this repository. The artwork was created using the built-in `image_gen.imagegen` tool, with actual prompts recorded in `icon-prompts.json` and `sprite-prompts.json`.

- `icon-source.png`: selected illustration icon source.
- `piaopiao-atlas-v2.png`: generated 32-pose main source.
- `piaopiao-nw-sleep-patch-v1.png`: generated correction for NW and sleeping frames.
- `crop-manifest.json`: source-relative bounding boxes and shared scales for deterministic packing.

`Tools/PreparePiaoPalAssets/main.swift` compiles these sources into runtime assets using cropping and resizing only. Generated alpha is preserved, including near-transparent pixels. The Metal renderer uses premultiplied-alpha blending.

These files contain design outputs, not the user's photo library. New assets do not replace the copyright attribution for OnekoMac or its existing sprites. See the repository LICENSE and `docs/piaopal-macos.md`.
