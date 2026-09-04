# Credits / Лицензии

All third-party files vendored in `assets/` are permissively licensed (CC0 or CC-BY).
No commercial racing-game data (Assetto Corsa, BeamNG, Forza, etc.) is included.

Все сторонние файлы в `assets/` имеют свободные лицензии (CC0 или CC-BY).
Данные коммерческих симуляторов не используются.

---

## 3D models / 3D-модели

### Kenney — Car Kit 3.1
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://kenney.nl/assets/car-kit
- Direct zip: https://kenney.nl/media/pages/assets/car-kit/1a312ec241-1775131960/kenney_car-kit.zip
- Files: `assets/models/cars/*.glb`, `assets/models/props/cone*.glb`
- Author: Kenney (www.kenney.nl)

### Kenney — Nature Kit
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://kenney.nl/assets/nature-kit
- Direct zip: https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip
- Files: `assets/models/nature/*.glb`
- Author: Kenney (www.kenney.nl)

### Kenney — Racing Kit
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://kenney.nl/assets/racing-kit
- Direct zip: https://kenney.nl/media/pages/assets/racing-kit/933b8fd9fd-1677580949/kenney_racing-kit.zip
- Files: `assets/models/track/*` (OBJ barriers, pylons, grandstand, flags, lights)
- Author: Kenney (www.kenney.nl)

Original Kenney `License.txt` copies: `assets/licenses/`.

---

## Textures & HDRI / Текстуры и HDRI

### Poly Haven — Kloofendal 43d Clear (2K HDR)
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://polyhaven.com/a/kloofendal_43d_clear
- File: `assets/hdri/kloofendal_43d_clear_2k.hdr`
- Author: Greg Zaal

### Poly Haven — Asphalt 02 (1K)
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://polyhaven.com/a/asphalt_02
- Files: `assets/textures/asphalt_02_*.jpg`

### Poly Haven — Aerial Grass Rock (1K)
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://polyhaven.com/a/aerial_grass_rock
- Files: `assets/textures/aerial_grass_rock_*.jpg`

---

## Audio / Звук

### Engine loops
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://opengameart.org/content/racing-car-engine-sound-loops
- Author: domasx2 (derived from a public-domain pdsounds.org recording)
- Files: `assets/audio/engine_loop_0.wav`, `assets/audio/engine_loop_3.wav`

### Tire squeal / skid loop
- License: [CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/)
- Source: https://opengameart.org/content/car-tire-squeal-skid-loop
- Author: audible-edge (Tom Haigh), submitted by qubodup
- File: `assets/audio/tires_squal_loop.wav`
- Attribution: Tire squeal by Tom Haigh (audible-edge) / CC-BY 3.0

### Crash / impact hits
- License: [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Source: https://kenney.nl/assets/impact-sounds (Kenney Impact Sounds)
- Files: `assets/audio/crash_metal_0.ogg`, `assets/audio/crash_metal_1.ogg`, `assets/audio/crash_plate_0.ogg`
- Author: Kenney (www.kenney.nl)
- License copy: `assets/licenses/kenney_impact-sounds_License.txt`

---

## Generated in-repo / Сгенерировано в репозитории

- `assets/textures/smoke.png` — soft particle disc (original, CC0 as part of this project)
- `assets/textures/checker.png` — start/finish checkers (original)
- `assets/textures/skid.png` — tire-mark streak (original, CC0 as part of this project)
- Procedural seated low-poly **driver**, cabin **steering wheel**, **dash/hood** for FPS, and **visual damage panels** (built in `scripts/car.gd`, original CC0)
- Cliff / apron / infield meshes built at runtime by `scripts/world_builder.gd`
- `icon.svg` — app icon (original)

---

## Engine

- [Godot Engine](https://godotengine.org/) 4.4.1 — MIT License

---

## Procedural / code-only (v1.3.3)

- FPS cockpit: Kenney sedan GLB body fully hidden in first-person (yellow shell occlusion fix); procedural steering wheel + dash retained.

- FPS steering wheel (rim, spokes, hub, logo disc): generated in `scripts/car.gd` — no external mesh download.
