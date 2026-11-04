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
- The escape kit (`gadgets.gd`, `rail.gd`):
  - **Railway**: a track across the middle of the city with a level crossing (flashing lights, barrier
    arms) on every road. A train comes out of a tunnel in one edge wall and goes into the other; the gates
    come down a few seconds before it. Beat it across and the police behind you meet the train; drive
    through a lowered arm and it snaps off.
  - **Spray shops**: drive-through booths over one lane. New paint, the dents gone, two stars less, and
    the police lose you for a few seconds.
  - **Safehouses**: a garage in each corner of the city. Drive in, the door comes down behind you: escaped.
  - **Spike strips**: from two stars the police lay them across the road ahead. Drive over one and you
    are on flat tyres (sparks, less grip, lower top speed) until a repair; police cars spin out on them too.
  - **Pickups**: EMP (every police car near you stalls), oil slick (dropped behind you; police spin out),
    shield (a few seconds of no damage and no BUSTED, police bounce off), and cash (in the air over every
    ramp, on every level crossing, around the city). The TOOL button (or T) uses the EMP or oil you carry.
  - **Combo**: cash, near misses, drifts, jumps, wrecks, train hits and spin-outs in a row multiply the points.

## Run

1. Install [Godot 4.4](https://godotengine.org).
2. Import `project.godot` and press F5.

Touch controls: left and right arrows on the left, GAS, BRAKE, DRIFT and NITRO on the right.
PC controls: W/S or Up/Down to accelerate and brake, A/D or Left/Right to steer, Shift for the handbrake, N for nitro, R to restart.

Steering feel is tuned by the `STEER_*` constants at the top of `car.gd`.

## Videos for YouTube (GitHub Actions)

An automatic driver can play the game while Godot's Movie Maker records it, for YouTube Shorts or normal videos.

The easy way is the studio page (`https://<owner>.github.io/<repo>/`, see *Studio page* under Story lab):
pick **🚓 Chase & action**, choose the options, press the button; the finished video, its thumbnail and
upload text show up on the same page. Or from GitHub:

1. Open the repository's **Actions** tab, choose **Record video**, then **Run workflow**.
2. Pick the options:
   - **mode**:
     - `escape` (the default): the escape kit in one run: a line of cash, a train timed to cross just behind
       the car (the police meet it), a spike strip the car slips past and the police drive into, the EMP, the
       spray shop, an oil slick, a shield through a roadblock, and as the finale the safehouse door coming down.
     - `chase`: 1 car vs a growing pack of police that come from behind, side streets and head-on; finale is a barrel trap for them.
     - `heli`: a police helicopter chases at street level; the finale is the car jumping off a tower top into it.
     - `rush`: dense traffic and cross traffic timed to pass just ahead of and behind the car; counts near misses.
     - `stunt`: tower-top to tower-top jumps, barrel corridors, a tower brought down as the car passes, ramps and gas stations.
     - `destroy`: smash as much of the city as possible, with a "% of the city destroyed" counter.
     - `survive`: 5 stars from the first second.
     - `race`: the car races a train along the railway-side road, hits a guaranteed ramp, then the finish camera shows both finish times and the winner.
   - **orientation**: `vertical` (1080x1920, Shorts) or `horizontal` (1920x1080).
   - **duration**, **fps**, **takes** (records several runs and keeps the most exciting), **teaser** (opens with a flash-forward of the biggest moment, then "EARLIER..."), **time** of day, the on-screen **title**, and an optional **seed**.
   - **overlay**: `clean` (the default) keeps only the hook title on screen: no "SWAT TRUCK INCOMING"-style
     pop-ups, no wanted stars, no stats line, BUSTED meter, health bar or minimap. `full` shows them all.
3. When the run finishes, download the `video-...` artifact from the run page: the MP4, a thumbnail, the run's stats and `...-upload.txt` with ready-to-paste YouTube title options, description, tags, hashtags and a pinned comment, filled in with that run's numbers. The same text is shown on the run's summary page. Replace the Play Store link placeholder before posting.

GitHub's machines have no graphics card, so frames are drawn on the CPU. The video is still smooth, but a 55 second clip takes a while to record.

How it works: the driver (`bot.gd`) presses the same controls a player does and plans its route on the road grid. The director (`director.gd`) stages the run: it picks the start, raises the wanted level on a schedule, builds stunt set pieces just ahead (`stunts.gd`), brings in the helicopter (`heli.gd`) or the cross traffic, shows story captions, and cuts between cameras. The run cannot end early, and when the car is boxed in by a pile of cars it shoves them away, so a clip never stalls. Some moments (the helicopter takedown, the timed cross traffic) are staged by the director, so call these videos gameplay, not a lucky accident.

Locally: `tools/record.sh path/to/godot out` (Linux, needs `xvfb` and `ffmpeg`; settings come from environment variables, see the script), or run the game with `-- --bot=chase --orientation=vertical --duration=55` to watch the bot live.

Every push runs **CI**: the bot plays every mode headless and the job fails on any script error, then a short half-size preview clip is recorded.

## Story lab (experiment)

Babu and Shona drive through the city in a pink convertible and act out an episode: pixel-art
faces that change with the emotion, voices, subtitles, props (a pizza that flies off on a jump),
and a real ending. When the story needs it they pull over and get out: they walk or run along the
pavement, sit, kneel (a proposal), fall over, hug, dance, and get back in to drive on, with their
own cameras for the scene on foot (`story/street.gd` is the stretch of pavement next to the car).
They can stop at a place: a park bench, an ice-cream cart or a chai stall, put up where the car
parks (`story/spots.gd`); the stalls have a vendor who talks, and things change hands (an ice
cream, a glass of chai, flowers, a ring ...). Each episode gets background music for its mood,
made from scratch by `tools/story/music.py` (no samples, so nothing to license), which dips under
the voices and comes up for the end card. The director runs in a scripted mode for this: nothing happens by itself;
the police, the helicopter, a jump or a roadblock only appear when the episode asks for them.
Everything is in `story/` and `tools/story/`; the game only reads `--story`, and `story/` is left
out of the Android build (`exclude_filter` in `export_presets.cfg`).

Episodes are no longer only a couple in a car:
- **Characters:** the screenplay's cast can have up to three side characters of its own (a cousin, goons, a
  parent ...), each with a look (boy, girl, man, woman, old, kid; hair style; slim or big; cap, hat, glasses,
  sunglasses, moustache, beard, mask, tie, scarf, bindi) and their own Gemini voice. The car has a roof and
  clear glass all round.
- **Action** (`story/action.gd`, `story/van.gd`): the villains' van drives up, goons get out and carry somebody
  off, the van speeds away and the couple's car chases it (jumps included) until it is cornered; then a fist
  fight with comic "DHISHUM!" pops and knock-outs.
- **Drama:** episodes can start on the pavement; people walk together, stare at each other, and the camera does
  a push-in on a shocked face (with a "dun dun DUNNN" in the music) or looks over a shoulder.
- **Acting:** faces with brows and eyes that look about (neutral, smug, love, shock, angry, sad, happy,
  laugh, cry, shy, scared, think; a blink hides each change), body language for each feeling (slumped when
  sad, arms crossed when smug, hands to the face when crying ...), breathing, nods while listening. The
  camera eases in and out on springs, moves in slowly on emotional lines, holds on the listener's
  reaction after a big line (with a beat before the next one), and each mood gets its own colour grade
  and vignette (`story/grade.gd`).
- **Music and sound effects** (`tools/story/score.py`, `tools/story/sfx.py`): after the recording, the score
  follows the story from the game's log: the episode's music, then romance for love, tension when things
  go wrong, action for a chase or a fight, a dropout before a shock, silence under the punchline and a
  finale for the end card. Comedy gets its effects on the moment: a boing when somebody falls, the sad
  trombone, a record scratch on a shock, crickets after an awkward line, a rimshot after the punchline;
  fights get punches and a bonk on the knock-out. Everything is made from scratch (nothing to license).
  Screenplays can ask for a change with `{"music": "tension"}` or an effect with `{"sfx": "ding"}`. Every
  run also gives `story_nomusic.mp4`, to put a trending sound under it in Instagram or YouTube.
- **Dark humour:** the `dark` mood asks the AI writer for deadpan dark comedy (terrible things taken
  absurdly calmly, misplaced priorities, karma, savage but loving roasts), with a hard list of topics
  it never touches. A second Gemini pass reads the draft against that list and rewrites what breaks it,
  and a word check (for every mood) never lets a banned word out: the saved episode is used instead.
  Its own music (a sly minor-key tiptoe) and a pale, high-contrast grade.
- **Templates:** the workflow's `template` input (kidnap_rescue, jealous_reveal, date, proposal) gives the AI
  writer a recipe; `ep5_kidnap` and `ep6_cousin` are saved examples.

- **Make an episode:** Actions -> "Story video (experiment)" -> Run workflow. Pick the mood
  (funny, romantic, cringe, happy, sad, action, twist), type an idea if you have one, and Gemini
  writes the episode, the characters get Gemini voices, the game stages it, and the run attaches
  the MP4, a thumbnail, the upload text and the screenplay. The run page shows the script.
- **Studio page** (`site/`, on GitHub Pages): a web page to do all of this from the phone, for both
  kinds of video: a **Story** (this workflow) or a **Chase & action** video (the "Record video"
  workflow: chase, helicopter, rush hour, stunts, destroy, survive). It shows the
  workflow's options as a form (read from `story.yml` / `record.yml` when the page is built, so it stays in step),
  starts the run, follows it step by step (cancel, "why did it fail?", run again), and lists the
  finished videos with a player (with or without music), the titles, description and hashtags with
  copy buttons, the lines, downloads, "same settings" to make another one, and delete. Every run
  started by hand is published as a pre-release, `story-<run id>` with the MP4s, thumbnail, upload
  text and screenplay (`tools/story/release.py` writes its notes) or `chase-<run id>` with the best
  take, its thumbnail and upload text (`tools/release_notes.py`), by `tools/publish.sh`; releases
  of a public repository are public. A run whose video is not on the page (an older run, or one whose
  publish step failed) gets a "📤 Put on this page" button: the "Publish a video to the studio page"
  workflow (`publish.yml`) takes that run's uploaded files, so nothing is recorded again and no
  Gemini quota is used (story runs keep their files 14 days, chase runs 30).
  - One-time setup: Settings -> Pages -> Build and deployment -> Source: **GitHub Actions**; the
    "Studio page" workflow (`.github/workflows/pages.yml`) then puts it at
    `https://<owner>.github.io/<repo>/` on every push to main that changes it.
  - Starting videos needs a fine-grained token for this repository with **Actions: Read and write**
    (and **Contents: Read and write** to delete videos). The page keeps it in the browser (only for
    the tab, unless you tick "Remember") and sends it only to api.github.com. Watching and
    downloading need no token.
  - Build it locally: `pip install pyyaml && tools/site/build.py _site`, then serve `_site/`.
- **Gemini keys:** add them as repository secrets `GEMINI_API_KEY` or `GEMINI_API_KEY_1` ... `_5`
  (Settings -> Secrets and variables -> Actions); when one runs out of quota the next is used.
  Without a key the saved episode and the free Edge voices are used.
- **Gemini voices and quota:** the free plan allows about 10 speech requests a day per key. The
  two main characters are spoken as one conversation in a single request and cut into lines
  (`tools/story/dialogue.py`), police lines are one request each, and every clip is cached, so an
  episode costs about 2-4 requests. The raw conversation is in the run's `story-out/dialogue.wav`.
- **Keep an episode:** copy `screenplay.json` from the run into `story/screenplays/` and add its
  name to the `script` choice in `.github/workflows/story.yml`.
- **Screenplay format:** see the top of `story/story.gd` (lines, actions, endings, props).
- **Try it locally:** `godot -- --bot=chase --duration=70 --story=1`

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
| `gadgets.gd` | Spray shops, safehouses, spike strips, EMP, oil slick, shield, cash and the combo |
| `rail.gd` | The railway: track, level crossings with lights and barrier arms, the train |
| `fx.gd` | Particles, skid marks, sound (recorded files from `audio/` with synthesized fallbacks) |
| `audio/` | Sound effects (Ogg Vorbis): siren and rotor loops, crashes, boom, tyre screech |
| `hud.gd` | HUD, minimap, touch controls, video overlay |
| `shaders.gd` | Facade, ground, car and debris shaders |
| `story/` | Story lab: blocky characters, the open-top car, the story scheduler, screenplays |
| `site/` | The studio page (GitHub Pages): start story videos, follow the runs, watch and download the videos |
| `tools/` | Scripts used by the workflows: install Godot, smoke test, record, add the teaser hook, pick the best take, write the upload text |
