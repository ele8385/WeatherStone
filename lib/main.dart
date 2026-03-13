import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _androidWidgetProvider =
    'com.a11.weatherstone.weatherstone.WeatherStoneWidgetProvider';
const _iosWidgetKind = 'WeatherStoneWidget';
const _iosAppGroup = 'group.com.a11.weatherstone.weatherstone';
const _androidInterstitialAdUnit = 'ca-app-pub-3940256099942544/1033173712';
const _iosInterstitialAdUnit = 'ca-app-pub-3940256099942544/4411468910';
const _widgetFramePhases = [0.0, 0.08, 0.16, 0.24, 0.5, 0.58, 0.66, 0.74];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  final preferences = await SharedPreferences.getInstance();
  runApp(WeatherStoneApp(storage: AppStorage(preferences)));
}

class WeatherStoneApp extends StatelessWidget {
  const WeatherStoneApp({super.key, required this.storage});

  final AppStorage storage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '날씨 알려주는 돌',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C1116),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7A8E80),
          brightness: Brightness.dark,
          primary: const Color(0xFFE6D5B3),
          secondary: const Color(0xFF7AA6A1),
          surface: const Color(0xFF121A21),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.4),
        ),
      ),
      home: WeatherStoneHomePage(storage: storage),
    );
  }
}

class WeatherStoneHomePage extends StatefulWidget {
  const WeatherStoneHomePage({super.key, required this.storage});

  final AppStorage storage;

  @override
  State<WeatherStoneHomePage> createState() => _WeatherStoneHomePageState();
}

class _WeatherStoneHomePageState extends State<WeatherStoneHomePage>
    with TickerProviderStateMixin {
  late final AnimationController _sceneController;
  late final AdService _adService;
  final WeatherService _weatherService = WeatherService();

  WeatherSnapshot? _weather;
  String? _weatherError;
  Accessory _selectedAccessory = accessories.first;
  bool _forceWidgetAnimation = false;
  bool _loadingWeather = true;
  bool _showingGuide = false;
  bool _isApplyingAccessory = false;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _sceneController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _adService = AdService()..preloadInterstitial();
    _selectedAccessory = widget.storage.loadAccessory();
    _forceWidgetAnimation = widget.storage.forceWidgetAnimation;
    _boot();
  }

  Future<void> _boot() async {
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(_iosAppGroup);
    }
    await _refreshWeather();
    if (!mounted) {
      return;
    }
    if (!widget.storage.hasSeenGuide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openGuide(markAsSeen: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _sceneController.dispose();
    _adService.dispose();
    super.dispose();
  }

  Future<void> _refreshWeather() async {
    setState(() {
      _loadingWeather = true;
      _weatherError = null;
    });

    try {
      final weather = await _weatherService.fetchCurrentWeather();
      if (!mounted) {
        return;
      }
      setState(() {
        _weather = weather;
        _lastUpdated = DateTime.now();
      });
      await _syncWidget();
    } on WeatherException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherError = '현재 날씨를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingWeather = false;
        });
      }
    }
  }

  Future<void> _syncWidget() async {
    final weather = _weather;
    if (weather == null || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    final shouldAnimate = _forceWidgetAnimation || weather.shouldAnimateWidget;
    final widgetPhases = shouldAnimate
        ? _widgetFramePhases
        : List<double>.filled(_widgetFramePhases.length, 0.25);

    String? firstFramePath;
    for (var i = 0; i < widgetPhases.length; i++) {
      final framePath = await HomeWidget.renderFlutterWidget(
        WidgetStoneCapture(
          weather: weather,
          accessory: _selectedAccessory,
          phase: widgetPhases[i],
        ),
        key: 'stone_frame_$i',
        logicalSize: const Size(340, 420),
        pixelRatio: 3,
      );
      firstFramePath ??= framePath;
      await HomeWidget.saveWidgetData<String>('stone_frame_$i', framePath);
    }

    if (firstFramePath != null) {
      await HomeWidget.saveWidgetData<String>('stone_image', firstFramePath);
    }
    await HomeWidget.saveWidgetData<bool>('animate_widget', shouldAnimate);
    await HomeWidget.saveWidgetData<int>(
      'frame_count',
      _widgetFramePhases.length,
    );
    await HomeWidget.saveWidgetData<int>('frame_index', 0);
    await HomeWidget.saveWidgetData<String>(
      'location_label',
      weather.locationLabel,
    );
    await HomeWidget.saveWidgetData<String>(
      'temperature_label',
      weather.temperatureLabel,
    );
    await HomeWidget.saveWidgetData<String>(
      'condition_label',
      _forceWidgetAnimation
          ? '${weather.widgetStatus} · 테스트 흔들림'
          : weather.widgetStatus,
    );
    await HomeWidget.saveWidgetData<String>(
      'accessory_label',
      _selectedAccessory.name,
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: _androidWidgetProvider,
      iOSName: _iosWidgetKind,
    );
  }

  Future<void> _applyAccessory(Accessory accessory) async {
    if (_selectedAccessory.id == accessory.id || _isApplyingAccessory) {
      return;
    }

    setState(() {
      _isApplyingAccessory = true;
    });

    await _adService.showAccessoryInterstitial(() async {
      widget.storage.saveAccessory(accessory.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAccessory = accessory;
      });
      await _syncWidget();
    });

    if (mounted) {
      setState(() {
        _isApplyingAccessory = false;
      });
    }
  }

  Future<void> _openGuide({bool markAsSeen = false}) async {
    if (_showingGuide) {
      return;
    }
    _showingGuide = true;
    if (markAsSeen) {
      await widget.storage.markGuideSeen();
    }
    if (!mounted) {
      _showingGuide = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121A21),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: const Text('위젯 추가 방법'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('이 앱은 홈 화면에 매달린 돌 위젯을 올려두고, 실제 현재 날씨에 맞춰 상태가 바뀌도록 설계했어요.'),
              SizedBox(height: 16),
              Text('안드로이드'),
              SizedBox(height: 6),
              Text('1. 홈 화면의 빈 곳을 길게 눌러요.'),
              Text('2. 위젯 메뉴에서 날씨 알려주는 돌을 찾아요.'),
              Text('3. 원하는 크기로 배치하면 투명 배경 돌이 매달려 보여요.'),
              SizedBox(height: 14),
              Text('iPhone'),
              SizedBox(height: 6),
              Text('1. 홈 화면을 길게 누른 뒤 왼쪽 위의 + 버튼을 눌러요.'),
              Text('2. 날씨 알려주는 돌을 선택하고 위젯 추가를 눌러요.'),
              Text('3. 액세서리를 바꾸면 같은 모습이 위젯에도 반영돼요.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
            if (Platform.isAndroid)
              FilledButton(
                onPressed: () async {
                  final supported =
                      await HomeWidget.isRequestPinWidgetSupported() ?? false;
                  if (!context.mounted) {
                    return;
                  }
                  if (supported) {
                    await HomeWidget.requestPinWidget(
                      qualifiedAndroidName: _androidWidgetProvider,
                    );
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('런처가 허용하면 위젯 추가 창이 열려요.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('이 런처에서는 직접 위젯 메뉴에서 추가해 주세요.'),
                      ),
                    );
                  }
                  Navigator.of(context).pop();
                },
                child: const Text('안드로이드에서 바로 추가'),
              ),
          ],
        );
      },
    );

    _showingGuide = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weather = _weather;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111A21), Color(0xFF090D11)],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshWeather,
            color: const Color(0xFFE6D5B3),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '날씨 알려주는 돌',
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '실제 현재 날씨에 따라 젖고, 얼고, 흔들리고, 사라지는 돌을 홈 화면에 매달아 두세요.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: '위젯 안내 다시 보기',
                      onPressed: _openGuide,
                      icon: const Icon(Icons.question_mark_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildHeroCard(weather),
                const SizedBox(height: 20),
                _buildWeatherSummary(weather),
                const SizedBox(height: 20),
                _buildAccessorySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(WeatherSnapshot? weather) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18242C), Color(0xFF0C1116)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 420,
            child: AnimatedBuilder(
              animation: _sceneController,
              builder: (context, _) {
                return StoneScene(
                  weather: weather,
                  accessory: _selectedAccessory,
                  phase: _sceneController.value,
                  loading: _loadingWeather,
                  showBackground: true,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          if (_weatherError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF24161A),
                border: Border.all(color: const Color(0xFF7D3940)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '날씨를 가져오지 못했어요',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(_weatherError!),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _refreshWeather,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _InfoPill(
                    label: '현재 위치',
                    value: weather?.locationLabel ?? '불러오는 중',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoPill(
                    label: '업데이트',
                    value: _lastUpdated == null
                        ? '곧 반영'
                        : DateFormat('HH:mm').format(_lastUpdated!),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWeatherSummary(WeatherSnapshot? weather) {
    final cards = [
      (
        '돌 상태',
        weather?.statusHeadline ?? (_loadingWeather ? '판독 중' : '대기 중'),
        Icons.visibility_rounded,
      ),
      ('온도', weather?.temperatureLabel ?? '--', Icons.thermostat_rounded),
      ('바람', weather?.windLabel ?? '--', Icons.air_rounded),
      ('습도', weather?.humidityLabel ?? '--', Icons.water_drop_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '지금 돌 상태',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (weather != null)
          Text(
            weather.longDescription,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.45,
            ),
          )
        else if (_loadingWeather)
          Text(
            '위치와 현재 날씨를 확인하는 동안 돌이 잠시 숨을 고르고 있어요.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: const Color(0xFF101820),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(card.$3, color: const Color(0xFFE6D5B3)),
                  Text(
                    card.$1,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    card.$2,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101820),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '위젯 애니메이션 테스트',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '현재 바람이 없어도 홈 위젯에서 강제로 살짝 흔들리게 합니다.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: _forceWidgetAnimation,
                onChanged: (value) => _setForceWidgetAnimation(value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setForceWidgetAnimation(bool value) async {
    await widget.storage.setForceWidgetAnimation(value);
    if (!mounted) {
      return;
    }
    setState(() {
      _forceWidgetAnimation = value;
    });
    await _syncWidget();
  }

  Widget _buildAccessorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '액세서리 30종',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            if (_isApplyingAccessory)
              Text(
                '광고 준비 중...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '하나를 적용할 때마다 전면 광고가 뜨고, 적용 결과는 앱과 홈 위젯 양쪽에 같이 반영됩니다.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: accessories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          itemBuilder: (context, index) {
            final accessory = accessories[index];
            final selected = _selectedAccessory.id == accessory.id;
            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _applyAccessory(accessory),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: selected
                      ? LinearGradient(
                          colors: [
                            accessory.color.withValues(alpha: 0.28),
                            const Color(0xFF141E25),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: selected ? null : const Color(0xFF0F171D),
                  border: Border.all(
                    color: selected
                        ? accessory.color.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.06),
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accessory.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(accessory.icon, color: accessory.color),
                        ),
                        const Spacer(),
                        if (selected)
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFFE6D5B3),
                          ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          accessory.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          accessory.shortNote,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101820),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFFE6D5B3)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '현재 광고와 앱 ID는 구글 테스트용 값으로 넣어두었습니다. 실제 출시 전에는 본인 AdMob ID로 교체해 주세요.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class WidgetStoneCapture extends StatelessWidget {
  const WidgetStoneCapture({
    super.key,
    required this.weather,
    required this.accessory,
    required this.phase,
  });

  final WeatherSnapshot weather;
  final Accessory accessory;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      height: 420,
      color: Colors.transparent,
      child: StoneScene(
        weather: weather,
        accessory: accessory,
        phase: phase,
        loading: false,
        showBackground: false,
        exaggerateMotion: true,
      ),
    );
  }
}

class StoneScene extends StatelessWidget {
  const StoneScene({
    super.key,
    required this.weather,
    required this.accessory,
    required this.phase,
    required this.loading,
    required this.showBackground,
    this.exaggerateMotion = false,
  });

  final WeatherSnapshot? weather;
  final Accessory accessory;
  final double phase;
  final bool loading;
  final bool showBackground;
  final bool exaggerateMotion;

  @override
  Widget build(BuildContext context) {
    final snapshot = weather;
    final isMissing = snapshot?.isTyphoon ?? false;
    final isCracked = snapshot?.isSevereTyphoon ?? false;
    final hasWind = snapshot?.isWindy ?? false;
    final windPower = snapshot == null
        ? 0.2
        : hasWind
        ? (snapshot.windSpeed / 18).clamp(0.45, 1.25)
        : 0.22;
    final baseWave = math.sin(phase * math.pi * 2);
    final gustWave = math.sin((phase * math.pi * 2) + 1.1);
    final fastWave = math.sin((phase * math.pi * 4.6) - 0.35);
    final motionBoost = exaggerateMotion ? 2.35 : 1.0;
    final ropeSwing =
        ((baseWave * (hasWind ? 0.06 : 0.025)) +
            (gustWave * 0.03 * windPower)) *
        motionBoost;
    final swing = isMissing
        ? 0.0
        : ((baseWave * (hasWind ? 0.11 : 0.035)) +
                  (gustWave * 0.04 * windPower) +
                  (fastWave * (hasWind ? 0.09 : 0.018))) *
              motionBoost;
    final floatOffset =
        ((baseWave * (hasWind ? 8 : 4)) + (fastWave * (hasWind ? 3.5 : 1.4))) *
        (exaggerateMotion ? 1.8 : 1.0);
    final accessoryFlutter = hasWind
        ? math.sin((phase * math.pi * 2.8) + 0.6) *
              (exaggerateMotion ? 0.3 : 0.14)
        : 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(showBackground ? 28 : 0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showBackground)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [Color(0xFF29353D), Color(0x00000000)],
                ),
              ),
            ),
          if (snapshot?.isFoggy ?? false)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (isCracked)
            Positioned.fill(
              child: CustomPaint(painter: CrackPainter(strength: 1)),
            ),
          Align(
            alignment: Alignment.topCenter,
            child: Transform.translate(
              offset: Offset(0, floatOffset * 0.5),
              child: SizedBox(
                width: 280,
                height: 360,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: 0,
                      child: Transform.rotate(
                        angle: ropeSwing,
                        origin: const Offset(0, -100),
                        child: CustomPaint(
                          size: const Size(12, 170),
                          painter: RopePainter(
                            missingStone: isMissing,
                            stormy: snapshot?.isWindy ?? false,
                          ),
                        ),
                      ),
                    ),
                    if (!isMissing)
                      Positioned(
                        top: 104 + floatOffset,
                        child: Transform.rotate(
                          angle: swing,
                          child: Opacity(
                            opacity: snapshot?.isFoggy ?? false ? 0.78 : 1,
                            child: SizedBox(
                              width: 240,
                              height: 230,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: StonePainter(
                                        wet: snapshot?.isRainy ?? false,
                                        hot: snapshot?.isOverheated ?? false,
                                        loading: loading,
                                      ),
                                    ),
                                  ),
                                  if (snapshot?.isSnowy ?? false)
                                    const Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: SnowCapPainter(),
                                        ),
                                      ),
                                    ),
                                  if (snapshot?.showHeatShimmer ?? false)
                                    const Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: HeatWavePainter(),
                                        ),
                                      ),
                                    ),
                                  if (snapshot?.isRainy ?? false)
                                    const Positioned.fill(
                                      child: StoneDroplets(),
                                    ),
                                  Positioned.fill(
                                    child: AccessoryOverlay(
                                      accessory: accessory,
                                      phase: phase,
                                      flutterAmount: accessoryFlutter,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isMissing)
                      Positioned(
                        top: 150,
                        child: Column(
                          children: [
                            Text(
                              snapshot?.isSevereTyphoon ?? false
                                  ? '돌이 날아갔어요'
                                  : '끈만 남았어요',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snapshot?.isSevereTyphoon ?? false
                                  ? '강풍이 너무 심해서 화면까지 금이 갔어요.'
                                  : '태풍급 바람이 돌을 날려 보냈어요.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (snapshot?.isFoggy ?? false)
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(color: Colors.white.withValues(alpha: 0.03)),
                ),
              ),
            ),
          if (loading)
            const Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Color(0x3327302F),
                valueColor: AlwaysStoppedAnimation(Color(0xFFE6D5B3)),
              ),
            ),
        ],
      ),
    );
  }
}

class StoneDroplets extends StatelessWidget {
  const StoneDroplets({super.key});

  @override
  Widget build(BuildContext context) {
    final droplets = [
      (28.0, 74.0, 18.0),
      (174.0, 58.0, 14.0),
      (62.0, 148.0, 15.0),
      (188.0, 130.0, 11.0),
      (118.0, 172.0, 13.0),
    ];
    return IgnorePointer(
      child: Stack(
        children: [
          for (final droplet in droplets)
            Positioned(
              left: droplet.$1,
              top: droplet.$2,
              child: Container(
                width: droplet.$3,
                height: droplet.$3 * 1.4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.72),
                      const Color(0x667ACEE8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: const Color(0x447ACEE8), blurRadius: 10),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AccessoryOverlay extends StatelessWidget {
  const AccessoryOverlay({
    super.key,
    required this.accessory,
    required this.phase,
    required this.flutterAmount,
  });

  final Accessory accessory;
  final double phase;
  final double flutterAmount;

  Widget _animatedAccessory({required Widget child, bool dramatic = false}) {
    final drift =
        math.sin((phase * math.pi * 3.2) + 0.45) *
        (dramatic ? 6.5 : 2.4) *
        flutterAmount.abs();
    return Transform.translate(
      offset: Offset(drift, 0),
      child: Transform.rotate(
        angle: dramatic ? flutterAmount : flutterAmount * 0.45,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (accessory.visual == AccessoryVisual.none)
          const SizedBox.shrink()
        else if (accessory.visual == AccessoryVisual.headphones) ...[
          Positioned(
            left: 40,
            top: 16,
            right: 40,
            child: _animatedAccessory(
              child: SizedBox(
                height: 70,
                child: CustomPaint(
                  painter: HeadphonesPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.winterHat) ...[
          Positioned(
            left: 44,
            top: -4,
            right: 44,
            child: _animatedAccessory(
              child: SizedBox(
                height: 90,
                child: CustomPaint(
                  painter: BeaniePainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.sunglasses) ...[
          Positioned(
            left: 44,
            right: 44,
            top: 78,
            child: _animatedAccessory(
              child: SizedBox(
                height: 54,
                child: CustomPaint(
                  painter: GlassesPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.piercing) ...[
          Positioned(
            right: 52,
            top: 114,
            child: _animatedAccessory(
              child: SizedBox(
                width: 24,
                height: 34,
                child: CustomPaint(
                  painter: PiercingPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.cap) ...[
          Positioned(
            left: 26,
            right: 36,
            top: 10,
            child: _animatedAccessory(
              child: SizedBox(
                height: 92,
                child: CustomPaint(painter: CapPainter(color: accessory.color)),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.crown) ...[
          Positioned(
            left: 46,
            right: 46,
            top: -8,
            child: _animatedAccessory(
              child: SizedBox(
                height: 86,
                child: CustomPaint(
                  painter: CrownPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.scarf) ...[
          Positioned(
            left: 34,
            right: 34,
            bottom: 12,
            child: _animatedAccessory(
              dramatic: true,
              child: SizedBox(
                height: 74,
                child: CustomPaint(
                  painter: ScarfPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.ribbon) ...[
          Positioned(
            left: 46,
            top: 36,
            child: _animatedAccessory(
              dramatic: true,
              child: SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: RibbonPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.goggles) ...[
          Positioned(
            left: 34,
            right: 34,
            top: 72,
            child: _animatedAccessory(
              child: SizedBox(
                height: 62,
                child: CustomPaint(
                  painter: GogglesPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.monocle) ...[
          Positioned(
            left: 56,
            top: 82,
            child: _animatedAccessory(
              child: SizedBox(
                width: 88,
                height: 90,
                child: CustomPaint(
                  painter: MonoclePainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.halo) ...[
          Positioned(
            left: 60,
            right: 60,
            top: -18,
            child: _animatedAccessory(
              child: SizedBox(
                height: 44,
                child: CustomPaint(
                  painter: HaloPainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ] else if (accessory.visual == AccessoryVisual.necklace) ...[
          Positioned(
            left: 50,
            right: 50,
            bottom: 6,
            child: _animatedAccessory(
              dramatic: true,
              child: SizedBox(
                height: 64,
                child: CustomPaint(
                  painter: NecklacePainter(color: accessory.color),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class StonePainter extends CustomPainter {
  StonePainter({required this.wet, required this.hot, required this.loading});

  final bool wet;
  final bool hot;
  final bool loading;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.25)
      ..cubicTo(
        size.width * 0.08,
        size.height * 0.36,
        size.width * 0.06,
        size.height * 0.68,
        size.width * 0.25,
        size.height * 0.84,
      )
      ..cubicTo(
        size.width * 0.39,
        size.height * 0.97,
        size.width * 0.64,
        size.height * 0.98,
        size.width * 0.8,
        size.height * 0.86,
      )
      ..cubicTo(
        size.width * 0.96,
        size.height * 0.74,
        size.width * 0.96,
        size.height * 0.41,
        size.width * 0.82,
        size.height * 0.26,
      )
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.09,
        size.width * 0.34,
        size.height * 0.08,
        size.width * 0.18,
        size.height * 0.25,
      )
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.55), 24, true);

    final baseColors = hot
        ? [
            const Color(0xFF5F261D),
            const Color(0xFFB34A2E),
            const Color(0xFF3A2A28),
          ]
        : wet
        ? [
            const Color(0xFF252B31),
            const Color(0xFF56626A),
            const Color(0xFF171A1F),
          ]
        : [
            const Color(0xFF49453F),
            const Color(0xFF837A70),
            const Color(0xFF262420),
          ];

    final basePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, -0.2),
        radius: 0.95,
        colors: baseColors,
        stops: const [0.0, 0.58, 1],
      ).createShader(rect);
    canvas.drawPath(path, basePaint);

    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: wet ? 0.24 : 0.14),
          Colors.transparent,
          Colors.black.withValues(alpha: 0.2),
        ],
      ).createShader(rect);
    canvas.drawPath(path, sheenPaint);

    final texturePaint = Paint();
    final spots = [
      (0.24, 0.34, 16.0, 0.14),
      (0.54, 0.28, 12.0, 0.12),
      (0.66, 0.52, 22.0, 0.09),
      (0.36, 0.66, 18.0, 0.1),
      (0.74, 0.74, 14.0, 0.08),
      (0.18, 0.58, 20.0, 0.08),
    ];
    for (final spot in spots) {
      texturePaint.color = Colors.black.withValues(alpha: spot.$4);
      canvas.drawCircle(
        Offset(size.width * spot.$1, size.height * spot.$2),
        spot.$3,
        texturePaint,
      );
    }

    if (loading) {
      final shimmer = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.04),
          ],
          stops: const [0.0, 0.45, 1.0],
          transform: const GradientRotation(-0.7),
        ).createShader(rect);
      canvas.drawPath(path, shimmer);
    }
  }

  @override
  bool shouldRepaint(covariant StonePainter oldDelegate) {
    return wet != oldDelegate.wet ||
        hot != oldDelegate.hot ||
        loading != oldDelegate.loading;
  }
}

class RopePainter extends CustomPainter {
  RopePainter({required this.missingStone, required this.stormy});

  final bool missingStone;
  final bool stormy;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..quadraticBezierTo(
        size.width * (stormy ? 0.15 : 0.35),
        size.height * 0.35,
        size.width / 2,
        size.height,
      );

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, shadow);

    final rope = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD9C6A0), Color(0xFF8C7655), Color(0xFF524533)],
      ).createShader(Offset.zero & size)
      ..strokeWidth = missingStone ? 4.5 : 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, rope);
  }

  @override
  bool shouldRepaint(covariant RopePainter oldDelegate) {
    return missingStone != oldDelegate.missingStone ||
        stormy != oldDelegate.stormy;
  }
}

class SnowCapPainter extends CustomPainter {
  const SnowCapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.3)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.12,
        size.width * 0.5,
        size.height * 0.18,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.08,
        size.width * 0.8,
        size.height * 0.28,
      )
      ..quadraticBezierTo(
        size.width * 0.76,
        size.height * 0.35,
        size.width * 0.64,
        size.height * 0.34,
      )
      ..quadraticBezierTo(
        size.width * 0.52,
        size.height * 0.38,
        size.width * 0.4,
        size.height * 0.33,
      )
      ..quadraticBezierTo(
        size.width * 0.26,
        size.height * 0.38,
        size.width * 0.2,
        size.height * 0.3,
      )
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.18), 10, true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FBFF), Color(0xFFD9E4F3)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HeatWavePainter extends CustomPainter {
  const HeatWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66FFB56B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.2 + (i * 0.18));
      final path = Path()..moveTo(x, size.height * 0.05);
      path.cubicTo(
        x + 8,
        size.height * 0.18,
        x - 10,
        size.height * 0.34,
        x + 6,
        size.height * 0.46,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CrackPainter extends CustomPainter {
  CrackPainter({required this.strength});

  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1.5 + strength
      ..style = PaintingStyle.stroke;

    final main = Path()
      ..moveTo(size.width * 0.58, 0)
      ..lineTo(size.width * 0.56, size.height * 0.18)
      ..lineTo(size.width * 0.62, size.height * 0.32)
      ..lineTo(size.width * 0.48, size.height * 0.54)
      ..lineTo(size.width * 0.52, size.height * 0.8)
      ..lineTo(size.width * 0.44, size.height);
    canvas.drawPath(main, paint);

    final branch1 = Path()
      ..moveTo(size.width * 0.62, size.height * 0.32)
      ..lineTo(size.width * 0.8, size.height * 0.2)
      ..lineTo(size.width * 0.88, size.height * 0.12);
    canvas.drawPath(branch1, paint);

    final branch2 = Path()
      ..moveTo(size.width * 0.48, size.height * 0.54)
      ..lineTo(size.width * 0.28, size.height * 0.44)
      ..lineTo(size.width * 0.16, size.height * 0.34);
    canvas.drawPath(branch2, paint);

    final glow = Paint()
      ..color = const Color(0x44CDE7FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..strokeWidth = 4 + (strength * 2)
      ..style = PaintingStyle.stroke;
    canvas.drawPath(main, glow);
  }

  @override
  bool shouldRepaint(covariant CrackPainter oldDelegate) {
    return strength != oldDelegate.strength;
  }
}

class HeadphonesPainter extends CustomPainter {
  HeadphonesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final cups = Paint()..color = color.withValues(alpha: 0.95);

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.02,
        size.width * 0.88,
        size.height * 0.82,
      );
    canvas.drawPath(path, band);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.48, 26, 34),
        const Radius.circular(14),
      ),
      cups,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 26, size.height * 0.48, 26, 34),
        const Radius.circular(14),
      ),
      cups,
    );
  }

  @override
  bool shouldRepaint(covariant HeadphonesPainter oldDelegate) =>
      color != oldDelegate.color;
}

class BeaniePainter extends CustomPainter {
  BeaniePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final hatRect = Rect.fromLTWH(
      0,
      size.height * 0.18,
      size.width,
      size.height * 0.62,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        hatRect,
        topLeft: const Radius.circular(40),
        topRight: const Radius.circular(40),
        bottomLeft: const Radius.circular(18),
        bottomRight: const Radius.circular(18),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.6)],
        ).createShader(hatRect),
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.12),
      12,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.52, size.width, 20),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xFFF0F3F5).withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(covariant BeaniePainter oldDelegate) =>
      color != oldDelegate.color;
}

class GlassesPainter extends CustomPainter {
  GlassesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final lens = Paint()..color = Colors.black.withValues(alpha: 0.74);

    final left = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 10, size.width * 0.42, size.height - 18),
      const Radius.circular(18),
    );
    final right = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.58, 10, size.width * 0.42, size.height - 18),
      const Radius.circular(18),
    );
    canvas.drawRRect(left, lens);
    canvas.drawRRect(right, lens);
    canvas.drawRRect(left, frame);
    canvas.drawRRect(right, frame);
    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.44),
      Offset(size.width * 0.58, size.height * 0.44),
      frame,
    );
  }

  @override
  bool shouldRepaint(covariant GlassesPainter oldDelegate) =>
      color != oldDelegate.color;
}

class GogglesPainter extends CustomPainter {
  GogglesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strap = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height * 0.45),
      Offset(size.width, size.height * 0.45),
      strap,
    );

    final shell = Paint()..color = color.withValues(alpha: 0.95);
    final lens = Paint()..color = const Color(0xAA8FE8FF);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.08, 8, size.width * 0.84, size.height - 16),
      const Radius.circular(24),
    );
    canvas.drawRRect(rect, shell);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.16,
          16,
          size.width * 0.68,
          size.height - 32,
        ),
        const Radius.circular(18),
      ),
      lens,
    );
  }

  @override
  bool shouldRepaint(covariant GogglesPainter oldDelegate) =>
      color != oldDelegate.color;
}

class PiercingPainter extends CustomPainter {
  PiercingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(
      Rect.fromLTWH(2, 6, size.width - 4, size.height - 12),
      0.7,
      math.pi * 1.3,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant PiercingPainter oldDelegate) =>
      color != oldDelegate.color;
}

class CapPainter extends CustomPainter {
  CapPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final crownRect = Rect.fromLTWH(
      size.width * 0.12,
      0,
      size.width * 0.72,
      size.height * 0.58,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        crownRect,
        topLeft: const Radius.circular(40),
        topRight: const Radius.circular(40),
        bottomLeft: const Radius.circular(18),
        bottomRight: const Radius.circular(14),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.96), color.withValues(alpha: 0.7)],
        ).createShader(crownRect),
    );

    final brim = Path()
      ..moveTo(size.width * 0.38, size.height * 0.48)
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.44,
        size.width,
        size.height * 0.64,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.78,
        size.width * 0.42,
        size.height * 0.66,
      )
      ..close();
    canvas.drawPath(brim, Paint()..color = color.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant CapPainter oldDelegate) =>
      color != oldDelegate.color;
}

class CrownPainter extends CustomPainter {
  CrownPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height * 0.8)
      ..lineTo(size.width * 0.18, size.height * 0.18)
      ..lineTo(size.width * 0.38, size.height * 0.62)
      ..lineTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.62, size.height * 0.62)
      ..lineTo(size.width * 0.82, size.height * 0.18)
      ..lineTo(size.width, size.height * 0.8)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.25), 10, true);
    canvas.drawPath(path, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.72, size.width, 16),
        const Radius.circular(8),
      ),
      Paint()..color = color.withValues(alpha: 0.88),
    );
  }

  @override
  bool shouldRepaint(covariant CrownPainter oldDelegate) =>
      color != oldDelegate.color;
}

class ScarfPainter extends CustomPainter {
  ScarfPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.95);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.04,
          0,
          size.width * 0.92,
          size.height * 0.4,
        ),
        const Radius.circular(22),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.3,
          size.height * 0.24,
          size.width * 0.16,
          size.height * 0.74,
        ),
        const Radius.circular(12),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.56,
          size.height * 0.18,
          size.width * 0.16,
          size.height * 0.64,
        ),
        const Radius.circular(12),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ScarfPainter oldDelegate) =>
      color != oldDelegate.color;
}

class RibbonPainter extends CustomPainter {
  RibbonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.96);
    final left = Path()
      ..moveTo(size.width * 0.48, size.height * 0.48)
      ..lineTo(size.width * 0.12, size.height * 0.18)
      ..lineTo(size.width * 0.16, size.height * 0.66)
      ..close();
    final right = Path()
      ..moveTo(size.width * 0.52, size.height * 0.48)
      ..lineTo(size.width * 0.88, size.height * 0.18)
      ..lineTo(size.width * 0.84, size.height * 0.66)
      ..close();
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.48),
      12,
      Paint()..color = const Color(0xFFFDE7C1),
    );
  }

  @override
  bool shouldRepaint(covariant RibbonPainter oldDelegate) =>
      color != oldDelegate.color;
}

class MonoclePainter extends CustomPainter {
  MonoclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final glass = Paint()..color = const Color(0x66CFF4FF);

    canvas.drawCircle(Offset(size.width * 0.34, size.height * 0.28), 22, glass);
    canvas.drawCircle(Offset(size.width * 0.34, size.height * 0.28), 22, ring);
    canvas.drawLine(
      Offset(size.width * 0.48, size.height * 0.45),
      Offset(size.width * 0.82, size.height * 0.96),
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant MonoclePainter oldDelegate) =>
      color != oldDelegate.color;
}

class HaloPainter extends CustomPainter {
  HaloPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      size.height * 0.15,
      size.width,
      size.height * 0.5,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
  }

  @override
  bool shouldRepaint(covariant HaloPainter oldDelegate) =>
      color != oldDelegate.color;
}

class NecklacePainter extends CustomPainter {
  NecklacePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final chain = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.18)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.84,
        size.width * 0.9,
        size.height * 0.18,
      );
    canvas.drawPath(path, chain);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.64),
      10,
      Paint()..color = const Color(0xFFFCE7B1),
    );
  }

  @override
  bool shouldRepaint(covariant NecklacePainter oldDelegate) =>
      color != oldDelegate.color;
}

class AppStorage {
  AppStorage(this._preferences);

  static const _guideSeenKey = 'guide_seen';
  static const _accessoryKey = 'selected_accessory';
  static const _forceWidgetAnimationKey = 'force_widget_animation';

  final SharedPreferences _preferences;

  bool get hasSeenGuide => _preferences.getBool(_guideSeenKey) ?? false;

  bool get forceWidgetAnimation =>
      _preferences.getBool(_forceWidgetAnimationKey) ?? false;

  Future<void> markGuideSeen() async {
    await _preferences.setBool(_guideSeenKey, true);
  }

  Accessory loadAccessory() {
    final id = _preferences.getString(_accessoryKey);
    return accessories.firstWhere(
      (item) => item.id == id,
      orElse: () => accessories.first,
    );
  }

  Future<void> saveAccessory(String id) async {
    await _preferences.setString(_accessoryKey, id);
  }

  Future<void> setForceWidgetAnimation(bool value) async {
    await _preferences.setBool(_forceWidgetAnimationKey, value);
  }
}

class AdService {
  InterstitialAd? _interstitial;
  bool _loading = false;

  String get _adUnitId =>
      Platform.isIOS ? _iosInterstitialAdUnit : _androidInterstitialAdUnit;

  void preloadInterstitial() {
    if (_loading || _interstitial != null) {
      return;
    }

    _loading = true;
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loading = false;
        },
        onAdFailedToLoad: (_) {
          _loading = false;
          _interstitial = null;
        },
      ),
    );
  }

  Future<void> showAccessoryInterstitial(
    Future<void> Function() onApplied,
  ) async {
    final ad = _interstitial;
    _interstitial = null;

    if (ad == null) {
      await onApplied();
      preloadInterstitial();
      return;
    }

    final completer = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) async {
        ad.dispose();
        await onApplied();
        preloadInterstitial();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, _) async {
        ad.dispose();
        await onApplied();
        preloadInterstitial();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    ad.show();
    await completer.future;
  }

  void dispose() {
    _interstitial?.dispose();
  }
}

class WeatherService {
  Future<WeatherSnapshot> fetchCurrentWeather() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const WeatherException('위치 서비스가 꺼져 있어요. 켠 뒤 다시 시도해 주세요.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const WeatherException('현재 날씨를 적용하려면 위치 권한이 필요해요.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );

    final weatherUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': position.latitude.toString(),
      'longitude': position.longitude.toString(),
      'current':
          'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day',
      'timezone': 'auto',
    });

    final weatherResponse = await http
        .get(weatherUri)
        .timeout(const Duration(seconds: 10));
    if (weatherResponse.statusCode != 200) {
      throw const WeatherException('날씨 서버가 잠시 응답하지 않아요.');
    }

    final weatherJson =
        jsonDecode(weatherResponse.body) as Map<String, dynamic>;
    final current = weatherJson['current'] as Map<String, dynamic>?;
    if (current == null) {
      throw const WeatherException('현재 날씨 데이터가 비어 있어요.');
    }

    String locationLabel = '현재 위치';
    final reverseUri =
        Uri.https('geocoding-api.open-meteo.com', '/v1/reverse', {
          'latitude': position.latitude.toString(),
          'longitude': position.longitude.toString(),
          'language': 'ko',
          'count': '1',
        });

    try {
      final reverseResponse = await http
          .get(reverseUri)
          .timeout(const Duration(seconds: 10));
      if (reverseResponse.statusCode == 200) {
        final reverseJson =
            jsonDecode(reverseResponse.body) as Map<String, dynamic>;
        final results = reverseJson['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map<String, dynamic>;
          final city = first['name']?.toString();
          final admin = first['admin1']?.toString();
          locationLabel = [city, admin]
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .take(2)
              .join(' · ');
          if (locationLabel.isEmpty) {
            locationLabel = '현재 위치';
          }
        }
      }
    } catch (_) {
      locationLabel = '현재 위치';
    }

    return WeatherSnapshot(
      locationLabel: locationLabel,
      temperature: (current['temperature_2m'] as num).toDouble(),
      apparentTemperature: (current['apparent_temperature'] as num).toDouble(),
      humidity: (current['relative_humidity_2m'] as num).toInt(),
      weatherCode: (current['weather_code'] as num).toInt(),
      windSpeed: (current['wind_speed_10m'] as num).toDouble(),
      isDay: (current['is_day'] as num).toInt() == 1,
    );
  }
}

class WeatherSnapshot {
  WeatherSnapshot({
    required this.locationLabel,
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.weatherCode,
    required this.windSpeed,
    required this.isDay,
  });

  final String locationLabel;
  final double temperature;
  final double apparentTemperature;
  final int humidity;
  final int weatherCode;
  final double windSpeed;
  final bool isDay;

  bool get isRainy => {
    51,
    53,
    55,
    56,
    57,
    61,
    63,
    65,
    66,
    67,
    80,
    81,
    82,
    95,
    96,
    99,
  }.contains(weatherCode);

  bool get isSnowy => {71, 73, 75, 77, 85, 86}.contains(weatherCode);

  bool get isFoggy => {45, 48}.contains(weatherCode);

  bool get isSunny =>
      {0, 1}.contains(weatherCode) || (weatherCode == 2 && isDay);

  bool get isWindy => windSpeed >= 10;

  bool get isTyphoon => windSpeed >= 24;

  bool get isSevereTyphoon => windSpeed >= 33;

  bool get isOverheated => apparentTemperature >= 33 && isSunny;

  bool get showHeatShimmer => apparentTemperature >= 31 && isSunny;

  bool get shouldAnimateWidget => isWindy && !isTyphoon;

  String get temperatureLabel => '${temperature.round()}°C';

  String get windLabel => '${windSpeed.toStringAsFixed(1)} m/s';

  String get humidityLabel => '$humidity%';

  String get widgetStatus {
    if (isSevereTyphoon) {
      return '초강풍';
    }
    if (isTyphoon) {
      return '태풍급 바람';
    }
    if (isSnowy) {
      return '눈 쌓임';
    }
    if (isRainy) {
      return '비에 젖음';
    }
    if (isFoggy) {
      return '안개';
    }
    if (isOverheated) {
      return '뜨겁게 익는 중';
    }
    if (isWindy) {
      return '흔들림';
    }
    return '고요함';
  }

  String get statusHeadline {
    if (isSevereTyphoon) {
      return '돌이 날아가고 화면이 깨졌어요';
    }
    if (isTyphoon) {
      return '태풍 때문에 돌이 사라졌어요';
    }
    if (isSnowy) {
      return '돌 위에 눈이 소복이 쌓였어요';
    }
    if (isRainy) {
      return '비에 젖어 반짝이고 있어요';
    }
    if (isFoggy) {
      return '희뿌연 안개 속에 잠겨 있어요';
    }
    if (isOverheated) {
      return '돌이 벌겋게 익고 있어요';
    }
    if (isWindy) {
      return '바람에 매달린 채 흔들리고 있어요';
    }
    return '오늘은 차분하게 매달려 있어요';
  }

  String get longDescription {
    final weatherText = _weatherCodeLabel(weatherCode);
    final dayText = isDay ? '낮' : '밤';
    return '$locationLabel 기준 현재 $dayText 날씨는 $weatherText, 체감온도는 ${apparentTemperature.round()}°C예요. '
        '그래서 돌 상태는 "$statusHeadline" 쪽으로 연출됩니다.';
  }
}

class WeatherException implements Exception {
  const WeatherException(this.message);

  final String message;
}

class Accessory {
  const Accessory({
    required this.id,
    required this.name,
    required this.shortNote,
    required this.visual,
    required this.color,
    required this.icon,
  });

  final String id;
  final String name;
  final String shortNote;
  final AccessoryVisual visual;
  final Color color;
  final IconData icon;
}

enum AccessoryVisual {
  none,
  headphones,
  winterHat,
  sunglasses,
  piercing,
  cap,
  crown,
  scarf,
  ribbon,
  goggles,
  monocle,
  halo,
  necklace,
}

const accessories = <Accessory>[
  Accessory(
    id: 'none',
    name: '맨돌',
    shortNote: '아무것도 걸치지 않음',
    visual: AccessoryVisual.none,
    color: Color(0xFF938B80),
    icon: Icons.circle_outlined,
  ),
  Accessory(
    id: 'studio_headphones',
    name: '스튜디오 헤드폰',
    shortNote: '무광 블랙',
    visual: AccessoryVisual.headphones,
    color: Color(0xFF1E1E22),
    icon: Icons.headphones_rounded,
  ),
  Accessory(
    id: 'retro_headphones',
    name: '레트로 헤드폰',
    shortNote: '웜 브라운',
    visual: AccessoryVisual.headphones,
    color: Color(0xFF8B5E3C),
    icon: Icons.headphones_rounded,
  ),
  Accessory(
    id: 'fluffy_beanie',
    name: '털모자',
    shortNote: '보송한 아이보리',
    visual: AccessoryVisual.winterHat,
    color: Color(0xFFC5B59A),
    icon: Icons.ac_unit_rounded,
  ),
  Accessory(
    id: 'trapper_hat',
    name: '트래퍼 햇',
    shortNote: '한겨울 대비',
    visual: AccessoryVisual.winterHat,
    color: Color(0xFF6D4C41),
    icon: Icons.terrain_rounded,
  ),
  Accessory(
    id: 'aviator_sunglasses',
    name: '에비에이터 선글라스',
    shortNote: '차가운 금속 프레임',
    visual: AccessoryVisual.sunglasses,
    color: Color(0xFFC8B16C),
    icon: Icons.visibility_rounded,
  ),
  Accessory(
    id: 'cat_eye_sunglasses',
    name: '캣아이 선글라스',
    shortNote: '날카로운 실루엣',
    visual: AccessoryVisual.sunglasses,
    color: Color(0xFF292B39),
    icon: Icons.visibility_rounded,
  ),
  Accessory(
    id: 'silver_piercing',
    name: '실버 피어싱',
    shortNote: '차가운 링 하나',
    visual: AccessoryVisual.piercing,
    color: Color(0xFFDCE3E8),
    icon: Icons.adjust_rounded,
  ),
  Accessory(
    id: 'gold_piercing',
    name: '골드 피어싱',
    shortNote: '작지만 반짝임 강함',
    visual: AccessoryVisual.piercing,
    color: Color(0xFFF0C46B),
    icon: Icons.adjust_rounded,
  ),
  Accessory(
    id: 'black_cap',
    name: '블랙 캡',
    shortNote: '도시적인 무드',
    visual: AccessoryVisual.cap,
    color: Color(0xFF20262D),
    icon: Icons.sports_baseball_rounded,
  ),
  Accessory(
    id: 'denim_cap',
    name: '데님 캡',
    shortNote: '빈티지 청색',
    visual: AccessoryVisual.cap,
    color: Color(0xFF3E5F7C),
    icon: Icons.sports_baseball_rounded,
  ),
  Accessory(
    id: 'crystal_crown',
    name: '크리스털 왕관',
    shortNote: '살짝 차가운 광채',
    visual: AccessoryVisual.crown,
    color: Color(0xFFA6D8FF),
    icon: Icons.workspace_premium_rounded,
  ),
  Accessory(
    id: 'thorn_crown',
    name: '가시 왕관',
    shortNote: '거친 분위기',
    visual: AccessoryVisual.crown,
    color: Color(0xFF7B4C3F),
    icon: Icons.workspace_premium_rounded,
  ),
  Accessory(
    id: 'wool_scarf',
    name: '울 머플러',
    shortNote: '포근한 감촉',
    visual: AccessoryVisual.scarf,
    color: Color(0xFFB94D4A),
    icon: Icons.waves_rounded,
  ),
  Accessory(
    id: 'wind_scarf',
    name: '실크 스카프',
    shortNote: '바람에 잘 날림',
    visual: AccessoryVisual.scarf,
    color: Color(0xFF5C7C9B),
    icon: Icons.waves_rounded,
  ),
  Accessory(
    id: 'neon_goggles',
    name: '네온 고글',
    shortNote: '강한 반사광',
    visual: AccessoryVisual.goggles,
    color: Color(0xFF79F5D3),
    icon: Icons.visibility_rounded,
  ),
  Accessory(
    id: 'ski_goggles',
    name: '스키 고글',
    shortNote: '눈 오는 날 찰떡',
    visual: AccessoryVisual.goggles,
    color: Color(0xFF93BCE8),
    icon: Icons.visibility_rounded,
  ),
  Accessory(
    id: 'monocle',
    name: '모노클',
    shortNote: '고풍스러운 한쪽 렌즈',
    visual: AccessoryVisual.monocle,
    color: Color(0xFFD7BE79),
    icon: Icons.search_rounded,
  ),
  Accessory(
    id: 'halo_ring',
    name: '후광 링',
    shortNote: '공중에 뜬 빛',
    visual: AccessoryVisual.halo,
    color: Color(0xFFF8D77E),
    icon: Icons.light_mode_rounded,
  ),
  Accessory(
    id: 'flower_crown',
    name: '플라워 크라운',
    shortNote: '봄기운 추가',
    visual: AccessoryVisual.crown,
    color: Color(0xFFDF7A9A),
    icon: Icons.local_florist_rounded,
  ),
  Accessory(
    id: 'silk_ribbon',
    name: '실크 리본',
    shortNote: '부드러운 매듭',
    visual: AccessoryVisual.ribbon,
    color: Color(0xFFE08EA7),
    icon: Icons.interests_rounded,
  ),
  Accessory(
    id: 'bow_ribbon',
    name: '보우 리본',
    shortNote: '작고 또렷한 포인트',
    visual: AccessoryVisual.ribbon,
    color: Color(0xFF9B5DE5),
    icon: Icons.interests_rounded,
  ),
  Accessory(
    id: 'chain_necklace',
    name: '체인 목걸이',
    shortNote: '은빛 라인',
    visual: AccessoryVisual.necklace,
    color: Color(0xFFCBD6DD),
    icon: Icons.link_rounded,
  ),
  Accessory(
    id: 'pearl_necklace',
    name: '진주 목걸이',
    shortNote: '동그란 진주 포인트',
    visual: AccessoryVisual.necklace,
    color: Color(0xFFF6E6D5),
    icon: Icons.circle_rounded,
  ),
  Accessory(
    id: 'ear_cuff',
    name: '이어 커프',
    shortNote: '귀선에 얹힌 금속',
    visual: AccessoryVisual.piercing,
    color: Color(0xFFB5C2D2),
    icon: Icons.adjust_rounded,
  ),
  Accessory(
    id: 'charm_pin',
    name: '참 핀',
    shortNote: '작은 장식 고리',
    visual: AccessoryVisual.piercing,
    color: Color(0xFFE06C75),
    icon: Icons.push_pin_rounded,
  ),
  Accessory(
    id: 'bucket_hat',
    name: '버킷햇',
    shortNote: '둥글게 눌러쓴 모자',
    visual: AccessoryVisual.cap,
    color: Color(0xFF7D8A66),
    icon: Icons.checkroom_rounded,
  ),
  Accessory(
    id: 'pilot_headset',
    name: '파일럿 헤드셋',
    shortNote: '묵직한 통신 장비',
    visual: AccessoryVisual.headphones,
    color: Color(0xFF52606D),
    icon: Icons.headset_mic_rounded,
  ),
  Accessory(
    id: 'snow_hat',
    name: '스노우 햇',
    shortNote: '차가운 하늘색 모자',
    visual: AccessoryVisual.winterHat,
    color: Color(0xFF86AACF),
    icon: Icons.ac_unit_rounded,
  ),
  Accessory(
    id: 'bandana',
    name: '반다나',
    shortNote: '비비드 포인트',
    visual: AccessoryVisual.cap,
    color: Color(0xFFD44B58),
    icon: Icons.flag_rounded,
  ),
  Accessory(
    id: 'saint_halo',
    name: '세인트 헤일로',
    shortNote: '밝은 황금빛 고리',
    visual: AccessoryVisual.halo,
    color: Color(0xFFFFE08A),
    icon: Icons.auto_awesome_rounded,
  ),
];

String _weatherCodeLabel(int code) {
  if (code == 0) {
    return '맑음';
  }
  if (code == 1 || code == 2 || code == 3) {
    return '구름 조금';
  }
  if (code == 45 || code == 48) {
    return '안개';
  }
  if ({51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82}.contains(code)) {
    return '비';
  }
  if ({71, 73, 75, 77, 85, 86}.contains(code)) {
    return '눈';
  }
  if ({95, 96, 99}.contains(code)) {
    return '뇌우';
  }
  return '변화무쌍한 날씨';
}
