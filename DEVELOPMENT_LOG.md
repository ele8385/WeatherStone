# WeatherStone Development Log

Last updated: 2026-03-13
Current branch: `main`
Latest checked commit at the time of writing: `29d2592`

## Product summary

- App name: `날씨 알려주는 돌`
- Stack: Flutter app + Android AppWidget + iOS WidgetKit extension scaffold
- Core concept: a hanging transparent-background stone that changes appearance based on real weather
- The main app supports richer motion and visual effects than the home-screen widget

## Current project state

- Android app runs successfully on a Galaxy S20 (`SM G981N`, adb id `R3CN20KBCAD`)
- Android home widget animation is working using `AnimationDrawable + ProgressBar`
- Android widget animation now uses PNG frame sequences instead of vector XML frames
- Widget PNG source management and export workflow are set up
- iOS widget code exists, but full iOS build verification was blocked on this machine because full Xcode is not installed

## Important commits so far

- `5e3ab1d` `Initial commit`
- `b577e23` `Restore static widget behavior`
- `741f55c` `Add animated widget stone prototype`
- `eef0dfb` `Switch widget animation to PNG sequence`
- `29d2592` `Add widget PNG asset export workflow`

## Weather logic

Defined in [lib/main.dart](/Users/a11/Documents/GitHub/WeatherStone/lib/main.dart).

State thresholds:

- `isRainy`: weather codes `51,53,55,56,57,61,63,65,66,67,80,81,82,95,96,99`
- `isSnowy`: weather codes `71,73,75,77,85,86`
- `isFoggy`: weather codes `45,48`
- `isSunny`: weather codes `0,1`, or `2` during daytime
- `isWindy`: wind speed `>= 10 m/s`
- `isTyphoon`: wind speed `>= 24 m/s`
- `isSevereTyphoon`: wind speed `>= 33 m/s`
- `isOverheated`: apparent temperature `>= 33 C` and sunny
- `showHeatShimmer`: apparent temperature `>= 31 C` and sunny

Widget state priority:

1. `초강풍`
2. `태풍급 바람`
3. `눈 쌓임`
4. `비에 젖음`
5. `안개`
6. `뜨겁게 익는 중`
7. `흔들림`
8. `고요함`

Widget animation rule:

- Animate when `isWindy && !isTyphoon`
- Force-animate when the in-app switch `위젯 애니메이션 테스트` is enabled

## App vs widget behavior

App:

- Uses Flutter rendering and real animation
- Supports stronger motion and richer effects
- Accessories are rendered in the app and reflected to the widget data

Android widget:

- Uses `AnimationDrawable + ProgressBar(indeterminateDrawable)`
- Animated windy state uses PNG frames in `android/app/src/main/res/drawable-nodpi/`
- Non-windy states are expected to use single PNGs such as `widget_stone_rain.png`

iOS widget:

- Uses `TimelineProvider` and shared widget data
- Full build not verified on this machine due missing full Xcode installation

## Key files

App and weather logic:

- [lib/main.dart](/Users/a11/Documents/GitHub/WeatherStone/lib/main.dart)

Android widget:

- [android/app/src/main/kotlin/com/a11/weatherstone/weatherstone/WeatherStoneWidgetProvider.kt](/Users/a11/Documents/GitHub/WeatherStone/android/app/src/main/kotlin/com/a11/weatherstone/weatherstone/WeatherStoneWidgetProvider.kt)
- [android/app/src/main/res/layout/weatherstone_widget.xml](/Users/a11/Documents/GitHub/WeatherStone/android/app/src/main/res/layout/weatherstone_widget.xml)
- [android/app/src/main/res/drawable/widget_stone_animation.xml](/Users/a11/Documents/GitHub/WeatherStone/android/app/src/main/res/drawable/widget_stone_animation.xml)
- [android/app/src/main/res/drawable-nodpi](/Users/a11/Documents/GitHub/WeatherStone/android/app/src/main/res/drawable-nodpi)

Widget PNG workflow:

- [widget_assets/android_widget_png/README.md](/Users/a11/Documents/GitHub/WeatherStone/widget_assets/android_widget_png/README.md)
- [tool/generate_widget_png_sequence.py](/Users/a11/Documents/GitHub/WeatherStone/tool/generate_widget_png_sequence.py)
- [tool/export_widget_png_assets.py](/Users/a11/Documents/GitHub/WeatherStone/tool/export_widget_png_assets.py)

iOS widget:

- [ios/WeatherStoneWidget/WeatherStoneWidget.swift](/Users/a11/Documents/GitHub/WeatherStone/ios/WeatherStoneWidget/WeatherStoneWidget.swift)

## PNG asset workflow

There are two layers:

1. Source PNG folders for humans to edit:
   - [widget_assets/android_widget_png](/Users/a11/Documents/GitHub/WeatherStone/widget_assets/android_widget_png)
2. Final Android resource PNGs used by the app:
   - [android/app/src/main/res/drawable-nodpi](/Users/a11/Documents/GitHub/WeatherStone/android/app/src/main/res/drawable-nodpi)

Source folders:

- `calm/`
- `windy_sequence/`
- `rain/`
- `snow/`
- `fog/`
- `heat/`
- `typhoon/`
- `severe_typhoon/`

Expected exported names:

- Static states: `widget_stone_<state>.png`
- Windy frames: `widget_stone_windy_frame_00.png` to `widget_stone_windy_frame_23.png`

Commands:

- Generate placeholder windy sequence:
  - `python3 tool/generate_widget_png_sequence.py`
- Export source PNGs into Android res:
  - `python3 tool/export_widget_png_assets.py`

## Why source PNG edits do not auto-apply by themselves

- Android widgets load files from `res/drawable-nodpi`
- The `widget_assets/` folders are source-of-truth folders for editing
- After replacing a source PNG, you must run:
  - `python3 tool/export_widget_png_assets.py`
- Then rebuild the app for Android to package updated resources

## Known constraints

- Android widget real-time animation is limited. The current PNG sequence approach is the practical workaround that actually worked on the Galaxy S20.
- The previous `AlarmManager + frame index update` approach was unreliable on the Samsung device.
- The current PNGs are procedurally generated placeholders, not final photoreal assets.
- Stone edges are slightly translucent because the PNG generator intentionally uses soft alpha on the edges. This is not mainly a resolution problem.

## Credits / cost note

- Current local PNG generation and export do not consume OpenAI image credits
- The current scripts run locally in Python and copy local files
- Costs would only appear if an external image-generation API or design tool is used later

## Recommended next steps

1. Replace placeholder weather PNGs with more realistic source assets in `widget_assets/android_widget_png/`
2. Wire static weather states into the Android widget provider so rainy/snow/fog/heat/typhoon states use dedicated static PNGs
3. Tune alpha edges on generated PNGs if transparency on bright wallpapers is distracting
4. Validate iOS widget build on a machine with full Xcode installed

## Session handoff note

If a new session starts, the most important thing to know is:

- Android widget animation currently works with PNG sequence assets
- The asset source folders are in `widget_assets/android_widget_png/`
- The actual packaged Android widget assets are in `android/app/src/main/res/drawable-nodpi/`
- Use `python3 tool/export_widget_png_assets.py` after editing source PNGs
- Current latest workflow commit before this log was `29d2592`
