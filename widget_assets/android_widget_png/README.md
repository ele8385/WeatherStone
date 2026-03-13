# Android widget PNG structure

Android `res` folders cannot contain arbitrary nested subfolders for drawable files,
so we keep two layers:

1. Source artwork folders in this directory for humans to edit and replace.
2. Final exported PNG files in `android/app/src/main/res/drawable-nodpi/` for the app.

Weather states

- `calm/`: static hanging stone with no active wind motion
- `windy_sequence/`: animated swinging frames for normal wind
- `rain/`: wet stone variant
- `snow/`: snow-covered stone variant
- `fog/`: fog-softened stone variant
- `heat/`: overheated red stone variant
- `typhoon/`: missing stone, rope only
- `severe_typhoon/`: rope only plus cracked-screen overlay source if needed

Recommended exported names

- Static state: `widget_stone_<state>.png`
- Animated windy frames: `widget_stone_windy_frame_00.png` ... `widget_stone_windy_frame_23.png`

How to work

1. Replace source PNG files inside the folders in this directory.
2. Run `python3 tool/export_widget_png_assets.py`.
3. Build the app again so Android picks up the updated `res/drawable-nodpi` assets.

Naming expectations for source folders

- Static folders: put one representative PNG in the folder. The exporter copies the first PNG it finds.
- `windy_sequence/`: put the animation frames in order. The exporter renames them to `widget_stone_windy_frame_00.png`, `01`, `02`, and so on.

Developer helpers

- `python3 tool/generate_widget_png_sequence.py` regenerates the current placeholder windy sequence into both:
  - `widget_assets/android_widget_png/windy_sequence/`
  - `android/app/src/main/res/drawable-nodpi/`
- `python3 tool/export_widget_png_assets.py` copies hand-made PNG assets from `widget_assets/` into Android `res`.

Current app wiring

- Android widget animation list: `android/app/src/main/res/drawable/widget_stone_animation.xml`
- Android exported frame folder: `android/app/src/main/res/drawable-nodpi/`
- PNG sequence generator: `tool/generate_widget_png_sequence.py`
- PNG exporter: `tool/export_widget_png_assets.py`
