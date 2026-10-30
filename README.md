# Cube City Chase

A mobile car-chase and destruction game made in Godot 4. The city, cars, buildings and effects are generated in code; there are no external models, textures or plugins. The only recorded assets are a few sound effects in `audio/` (credits in `audio/CREDITS.md`); if a file is missing, the game plays a synthesized sound instead.

## Features

- A 1.1 km road-grid city with districts: downtown glass towers, brick and concrete mid-rises, suburbs, industrial blocks and parks.
- Destructible voxel buildings. Drive through them and bring them down in a full collapse.
- Arcade car physics built on `VehicleBody3D`: steering assist, handbrake drifts, nitro and drift boost.
- Damage model with dents, parts that fly off, smoke and fire.
- Wanted level from 0 to 5 stars. Your first crime brings the police; stay out of sight to lose them.
- Police that follow the roads, PIT manoeuvres, roadblocks, a helicopter with a spotlight, a SWAT truck boss, and sirens.
- BUSTED meter: stay boxed in by police for 7 seconds and you are arrested.
- Street life: trees, street lamps, parked cars and traffic that drives on the left.
- Chain explosions from barrels, parked cars and gas stations.
- Slow motion on big moments and a cinematic camera when a tower collapses.
- Day/night cycle, rain, minimap and touch controls.

## Run

1. Install [Godot 4.4](https://godotengine.org).
2. Import `project.godot` and press F5.

Touch controls: left and right arrows on the left, GAS, BRAKE, DRIFT and NITRO on the right.
PC controls: W/S or Up/Down to accelerate and brake, A/D or Left/Right to steer, Shift for the handbrake, N for nitro, R to restart.

Steering feel is tuned by the `STEER_*` constants at the top of `car.gd`.

## Videos for YouTube (GitHub Actions)

An automatic driver can play the game while Godot's Movie Maker records it, for YouTube Shorts or normal videos.

1. Open the repository's **Actions** tab, choose **Record video**, then **Run workflow**.
2. Pick the options:
   - **mode**:
     - `chase`: 1 car vs a growing pack of police that come from behind, side streets and head-on; finale is a barrel trap for them.
     - `heli`: a police helicopter chases at street level; the finale is the car jumping off a tower top into it.
     - `rush`: dense traffic and cross traffic timed to pass just ahead of and behind the car; counts near misses.
     - `stunt`: tower-top to tower-top jumps, barrel corridors, a tower brought down as the car passes, ramps and gas stations.
     - `destroy`: smash as much of the city as possible, with a "% of the city destroyed" counter.
     - `survive`: 5 stars from the first second.
   - **orientation**: `vertical` (1080x1920, Shorts) or `horizontal` (1920x1080).
   - **duration**, **fps**, **takes** (records several runs and keeps the most exciting), **teaser** (opens with a flash-forward of the biggest moment, then "EARLIER..."), **time** of day, the on-screen **title**, and an optional **seed**.
3. When the run finishes, download the `video-...` artifact from the run page: the MP4, a thumbnail, the run's stats and `...-upload.txt` with ready-to-paste YouTube title options, description, tags, hashtags and a pinned comment, filled in with that run's numbers. The same text is shown on the run's summary page. Replace the Play Store link placeholder before posting.

GitHub's machines have no graphics card, so frames are drawn on the CPU. The video is still smooth, but a 55 second clip takes a while to record.

How it works: the driver (`bot.gd`) presses the same controls a player does and plans its route on the road grid. The director (`director.gd`) stages the run: it picks the start, raises the wanted level on a schedule, builds stunt set pieces just ahead (`stunts.gd`), brings in the helicopter (`heli.gd`) or the cross traffic, shows story captions, and cuts between cameras. The run cannot end early, and when the car is boxed in by a pile of cars it shoves them away, so a clip never stalls. Some moments (the helicopter takedown, the timed cross traffic) are staged by the director, so call these videos gameplay, not a lucky accident.

Locally: `tools/record.sh path/to/godot out` (Linux, needs `xvfb` and `ffmpeg`; settings come from environment variables, see the script), or run the game with `-- --bot=chase --orientation=vertical --duration=55` to watch the bot live.

Every push runs **CI**: the bot plays every mode headless and the job fails on any script error, then a short half-size preview clip is recorded.

## Android build

The project uses the Compatibility (OpenGL ES 3) renderer so it runs on more phones.

### Automatic (GitHub Actions)

Every push to `main` builds an APK with `.github/workflows/android.yml`:

1. Open the **Actions** tab and click the latest **Build Android APK** run.
2. Under **Artifacts**, download `cube-city-chase-apk` (a zip that contains the APK).

You can also start a build by hand with **Run workflow**. If you push a tag such as `v3.1`, the APK is attached to a GitHub release for that tag.

**Signing:** without a secret, each run signs the APK with a new key. Android then refuses to install the new APK over the old one until you uninstall the old one. To keep one key across builds:

```bash
keytool -genkey -v -keystore debug.keystore -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
base64 -w0 debug.keystore
```

Add the printed text as a repository secret named `ANDROID_DEBUG_KEYSTORE_BASE64` (Settings > Secrets and variables > Actions).

### Manual

1. In Godot, install the export templates.
2. Set the Android SDK, JDK and a debug keystore in Editor Settings > Export > Android.
3. Go to Project > Export > Android and export an APK (arm64-v8a).

## Files

| File | What it does |
| --- | --- |
| `main.gd` | Game loop, cameras, wanted level, BUSTED meter, police, SWAT, traffic, slow motion, events |
| `car.gd` | Player and police vehicles, steering feel, handling assists, damage, police AI, sirens |
| `bot.gd` | Bot driver for recorded videos: route planning, ramps, smashes, dodging |
| `director.gd` | Stages video runs: modes, beats, story captions, camera cuts, overlay text, run summary |
| `stunts.gd` | Stunt set pieces: tower-top jump, barrel corridor, tower fall |
| `heli.gd` | The police helicopter: model, low chase, rotor wash, crash |
| `carmesh.gd` | Procedural car body meshes |
| `civcar.gd` | Parked cars and traffic |
| `world.gd` | City generation, chunk streaming, ramps, flyovers, debris, routing |
| `building.gd` | Destructible building data, meshes and collapse |
| `props.gd` | Trees, lamps, barrels, gas stations, pickups, rooftop props |
| `fx.gd` | Particles, skid marks, sound (recorded files from `audio/` with synthesized fallbacks) |
| `audio/` | Sound effects (Ogg Vorbis): siren and rotor loops, crashes, boom, tyre screech |
| `hud.gd` | HUD, minimap, touch controls, video overlay |
| `shaders.gd` | Facade, ground, car and debris shaders |
| `tools/` | Scripts used by the workflows: install Godot, smoke test, record, add the teaser hook, pick the best take, write the upload text |
