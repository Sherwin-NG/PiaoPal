# Pet motion review

Build from the project directory:

```sh
swiftc Engine/Simulation/PetMotion.swift Tools/ReviewPetMotion/main.swift -o build/review-pet-motion
```

The existing comparison mode needs an immutable `before-piaopiao.png` in its output directory:

```sh
build/review-pet-motion . build/animation-audit
```

## Moving artwork review

This mode needs only a walking atlas. It moves existing sprite pixels across a fixed 16 pt ground grid at actual 1× and 2× size; it never redraws or interpolates limbs. The default speed and base stride come from `PetAnimationTiming`.

```sh
build/review-pet-motion . build/animation-art-v4/moving --moving-only --cycles 10
```

For an unpublished candidate, pass a 256×512 atlas or a 256×64 four-frame strip. A strip must specify exactly one direction. Trial values affect only this export:

```sh
build/review-pet-motion . build/animation-art-v4/e-trial --moving-only \
  --walk-atlas /absolute/path/to/e-candidate.png --directions E \
  --stride-pixels 16 --speed 48 --cycles 10 --fps 30
```

Outputs:

- `index-moving.html`: native-size GIFs without responsive shrinking. Use horizontal scrolling if needed.
- `moving/*.gif`: genuine translation; the restart at the end of the requested cycles is an export loop, not a gait transition.
- `moving/*.png`: every authored-pose change, retaining the world ground grid.
- `moving-review.json`: timing, sprite origin and world position for each change. A foot at atlas-cell `(x,y)` is at `worldSpriteLeft + x*scale, worldSpriteTop + y*scale`.

The tool is a constant-speed art bench using production pose sampling and the production distance/stride policy, including the 5 cycles/s readability ceiling. It isolates foot contact; it does not simulate acceleration, turning or arrival. `Tests/MacMotion` covers those behaviors. Below that ceiling, a 2× pet has twice the world stride and takes twice as long per cycle. At high speeds or small sizes the effective stride grows; the JSON records both authored and effective world stride. Check 1× moving footage explicitly; an enlarged in-place preview cannot establish ground contact quality.

GIF delays use whole centiseconds. Export is capped at 50 fps so no frame is shorter than 20 ms; delays are distributed to round the complete duration once instead of accumulating per-frame rounding errors. The JSON records both requested and encoded duration. Re-exporting a run replaces its earlier transition PNGs.
