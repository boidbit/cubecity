# Cube City Chase

A mobile car-chase and destruction game made in Godot 4. Everything (city, cars, buildings, sounds, effects) is generated in code. There are no external models, textures or plugins.

## Features

- A 1.1 km road-grid city with districts: downtown glass towers, brick and concrete mid-rises, suburbs, industrial blocks and parks.
- Destructible voxel buildings. Drive through them, blow them up, and bring them down in a full collapse.
- Arcade car physics built on `VehicleBody3D`: steering assist, handbrake drifts, nitro and drift boost.
- Damage model with dents, parts that fly off, smoke and fire.
- Police that follow the roads, PIT manoeuvres, roadblocks, a helicopter with a spotlight and a SWAT truck boss.
- Street life: trees, street lamps, parked cars and traffic that drives on the left.
- Chain explosions from barrels, parked cars and gas stations.
- Slow motion on big moments and a cinematic camera when a tower collapses.
- Day/night cycle, rain, minimap, and touch controls (left-side steering joystick).

## Run

1. Install [Godot 4.4](https://godotengine.org).
2. Import `project.godot` and press F5.

PC controls: W/S to accelerate and brake, A/D to steer, Shift for the handbrake, N for nitro, Space to blast, R to restart.

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
| `main.gd` | Game loop, camera, wanted level, police, SWAT, traffic, slow motion, events |
| `car.gd` | Player and police vehicles, handling assists, damage, police AI |
| `carmesh.gd` | Procedural car body meshes |
| `civcar.gd` | Parked cars and traffic |
| `world.gd` | City generation, chunk streaming, ramps, flyovers, debris, routing |
| `building.gd` | Destructible building data, meshes and collapse |
| `props.gd` | Trees, lamps, barrels, gas stations, pickups, rooftop props |
| `fx.gd` | Particles, skid marks, synthesized sounds |
| `hud.gd` | HUD, minimap, touch controls |
| `shaders.gd` | Facade, ground, car and debris shaders |
