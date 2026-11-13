import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'announcement_banner.dart';
import 'api/api_exception.dart';
import 'arcade.dart';
import 'premium.dart';
import 'screens/adblock_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/announcements_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/earn_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/my_keys_screen.dart';
import 'screens/notice_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_screen.dart';
import 'screens/tamper_screen.dart';
import 'screens/tutorials_screen.dart';
import 'screens/update_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/ad_service.dart';
import 'services/adblock_detector.dart';
import 'services/announcement_store.dart';
import 'services/chat_service.dart';
import 'services/worker_backend.dart';
import 'services/consent_service.dart';
import 'services/distribution.dart';
import 'services/notice_store.dart';
import 'services/play_integrity.dart';
import 'services/play_store.dart';
import 'services/push.dart';
import 'services/read_store.dart';
import 'services/security.dart';
import 'sign_in.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One init, two dependents: the second init() below would return at its
  // _initStarted guard and warm() would run before Firebase is up.
  final chatReady = ChatService.init();
  unawaited(chatReady.then((_) => Push.init()));
  unawaited(chatReady.then((_) => ChatService.warm()));
  await Distribution.initialize();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghosst',
      debugShowCheckedModeBanner: false,
      // Dark-only by brand intent (dark-neon OLED); darkTheme pins the same
      // theme so system light mode never flashes a light UI.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      // Fixed, pointer-events-none film grain over the whole app.
      // Clamp text scaling so fixed chrome (nav bar, app bar) can't be
      // pushed past its layout at extreme system text sizes.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const Positioned.fill(child: GrainOverlay()),
            ],
          ),
        );
      },
      home: Scaffold(backgroundColor: AppColors.bg, body: const _AppEntry()),
    );
  }
}

/// Boots the app: cinematic splash overlaid on the live [Router] so session
/// checks load while the intro plays. The splash removes itself when done.
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> with WidgetsBindingObserver {
  bool _splash = true;

  /// Launch notice (educational-use disclaimer) — shown once per 24h after a skip.
  bool _notice = false;

  /// Integrity verdict (cracked / re-packed / modded build). Null until the
  /// check answers — each leg is bounded and fails open.
  SecurityReport? _security;

  /// Ad-blocker verdict. Null until the check answers — fails open, and
  /// only positive evidence (ads blocked while the network works) locks.
  AdblockReport? _adblock;

  /// Update gate (server config + installed version). Both must land before
  /// an install can be declared outdated.
  AppConfig? _appConfig;
  int _installedVersion = 0;

  /// Throttle stamp: launch + resume re-checks run at most once a minute
  /// so returning from a settings screen never hammers the probes.
  DateTime? _lastAdblockCheck;

  /// Update checks run on launch and every resume (throttled) — an install
  /// left open for days must still be forced to update.
  DateTime? _lastUpdateCheck;

  /// Set when Play itself reports an update (the store's own full-screen
  /// flow drives the install; this keeps our gate up if the user backs out).
  int? _playUpdateVersion;

  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // All legs run in parallel with the intro so the verdict (gate or
    // all-clear) is ready the moment the splash finishes.
    _boot = _launchChecks();
    _checkNotice();
  }

  /// Fails open (shows the notice) if storage cannot be read.
  Future<void> _checkNotice() async {
    var hidden = false;
    try {
      hidden = await NoticeStore.hidden();
    } catch (_) {}
    if (!hidden && mounted) setState(() => _notice = true);
  }

  void _skipNotice() {
    setState(() => _notice = false);
    NoticeStore.skip().ignore();
  }

  Future<void> _launchChecks() async {
    // Fire-and-forget: never delays the splash and never blocks a launch.
    unawaited(_reportPlayIntegrity());
    await Future.wait<void>([
      _initializeAds(),
      _checkSecurity(),
      _checkAdblock(),
      _checkUpdate(),
    ]);
  }

  /// Observe-only Play Integrity: the API decodes the token and logs the
  /// verdict. No verdict is trusted on the device, and no failure is shown.
  Future<void> _reportPlayIntegrity() async {
    try {
      if (await Backend.currentUser() == null) return;
      if (!await PlayIntegrity.due()) return;
      final proof = await PlayIntegrity.request();
      if (proof == null) return;
      await Backend.reportIntegrity(proof.token, proof.nonce);
      await PlayIntegrity.markReported();
    } catch (_) {
      // Telemetry only.
    }
  }

  Future<void> _initializeAds() async {
    var canRequest = false;
    try {
      canRequest = await ConsentService.gatherConsent();
      if (!canRequest) {
        debugPrint('[Consent] Ads not permitted by consent gate.');
        return;
      }
      await AdService.instance.initialize();
      unawaited(AdService.instance.preload());
      unawaited(AdService.instance.preloadInterstitial());
    } catch (e) {
      debugPrint('MobileAds initialization failed: $e');
    }
  }

  /// Blockers are toggled outside the app (quick-settings tile, Private
  /// DNS screen) — re-check on return so the gate reappears the moment the
  /// device starts filtering ads again (throttled, fails open).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkAdblock();
    // Logged-in users keep the app open for days — re-check on every open.
    final last = _lastUpdateCheck;
    if (last == null ||
        DateTime.now().difference(last) >= const Duration(seconds: 30)) {
      unawaited(_checkUpdate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Signature/debug verdict from the platform side — the modded-build
  /// detector. Fails open on any error so a broken check can't lock out a
  /// legitimate install.
  Future<void> _checkSecurity() async {
    // The Play artifact is protected by Play App Signing. Until its separate
    // certificate is enrolled locally, do not route Play users into the
    // direct-build APK recovery flow.
    if (Distribution.isPlay) {
      if (mounted) setState(() => _security = SecurityReport.clean);
      return;
    }
    final report = await Security.check();
    if (!mounted) return;
    setState(() => _security = report);
  }

  /// Server-driven update gate. Fails open on any error (offline, API down,
  /// package info missing) — an outage must not lock everyone out.
  Future<void> _checkUpdate() async {
    _lastUpdateCheck = DateTime.now();

    // Own version first: both gates compare against it and the gate screen
    // prints it. Skipping this (the old early return) is what showed
    // "Installed 0".
    try {
      final info = await PackageInfo.fromPlatform();
      // On Android buildNumber is the versionCode (pubspec `+N`).
      final installed = int.tryParse(info.buildNumber) ?? 0;
      if (mounted && installed > 0) {
        setState(() => _installedVersion = installed);
      }
    } catch (_) {
      // Fail open: treat as unknown, the server gate still applies.
    }

    // Play Store next, for Play installs: this is the same full-screen update
    // flow the store shows. Only when Play's version is actually newer — a
    // sideloaded or QA build of the same code must not be gated. Direct builds
    // can't be asked at all and fall through to `minVersionCode`.
    if (Distribution.isPlay) {
      final playVersion = await PlayStore.updateVersionCode();
      if (playVersion != null && playVersion > _installedVersion) {
        if (!mounted) return;
        setState(() => _playUpdateVersion = playVersion);
        // Fire-and-forget: Play's full-screen flow must never stall the splash.
        // False (Play refused, e.g. not installed by Play) leaves the gate up
        // and its button falls back to the store listing.
        PlayStore.startImmediateUpdate().ignore();
      }
    }

    try {
      final config = await Backend.appConfig().timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
      if (!mounted) return;
      if (config != null) setState(() => _appConfig = config);
    } catch (_) {
      // Fail open.
    }
  }

  /// Probes ad endpoints against our own backend to spot a DNS/VPN filter.
  /// Throttled so rapid resume cycles share one run (the stamp lands before
  /// the network call). Fails open: offline / timeout / broken probe means
  /// no gate — same policy as [Security.check].
  Future<void> _checkAdblock() async {
    final now = DateTime.now();
    final last = _lastAdblockCheck;
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastAdblockCheck = now;
    final report = await AdblockDetector.check();
    if (!mounted) return;
    setState(() => _adblock = report);
  }

  @override
  Widget build(BuildContext context) {
    // Update outranks everything: an install below the API's minimum (or one
    // Play has flagged) cannot use the app at all.
    final playVersion = _playUpdateVersion ?? 0;
    final playUpdate = playVersion > 0;
    final config = _appConfig;
    final serverUpdate = config != null && config.blocks(_installedVersion);
    final forceUpdate = playUpdate || serverUpdate;
    final tampered = _security?.blocked ?? false;
    final adBlocked = _adblock?.blocked ?? false;
    final blocked = tampered || adBlocked;
    return Stack(
      children: [
        // The gate replaces the entire router — nothing to pop, no UI to
        // reach while a newer build is waiting.
        SafeArea(
          child: forceUpdate
              ? UpdateScreen(
                  installedVersion: _installedVersion,
                  requiredVersion: playUpdate
                      ? playVersion
                      : (config!.latestVersionCode > 0
                            ? config.latestVersionCode
                            : config.minVersionCode),
                  updateUrl: playUpdate
                      ? PlayStore.webUrl
                      : (config?.updateUrl(isPlay: Distribution.isPlay) ?? ''),
                  onUpdate: playUpdate
                      ? PlayStore.startImmediateUpdate
                      : null,
                  onRetry: _checkUpdate,
                )
              : blocked
              ? (tampered
                    ? TamperDetectedScreen(
                        flags: _security?.flags ?? const <String>[],
                      )
                    : AdblockScreen(
                        report: _adblock!,
                        recheck: AdblockDetector.check,
                        onResult: (r) {
                          if (mounted) setState(() => _adblock = r);
                        },
                      ))
              : const Router(),
        ),
        // Only after the intro: the 20s read window must not run behind the
        // splash, and the notice must not cover a gate.
        if (_notice && !_splash && !blocked && !forceUpdate)
          NoticeScreen(onSkip: _skipNotice),
        if (_splash)
          SplashScreen(
            // Held BEFORE the exit starts, so the intro never gets cut and the
            // reveal lands on the finished gate (bounded by both legs).
            onReady: () => _boot,
            onDone: () async {
              if (!mounted) return;
              setState(() => _splash = false);
              // No full-screen ad here: it can land under the user's first tap
              // and cause an accidental advertiser click.

              // From here on the home shell may ask for notifications. A fresh
              // install signs in after this point, so the ask happens there.
              Push.splashDone = true;
              if (await Backend.currentUser() != null) {
                unawaited(Push.requestPermission());
              }
            },
          ),
      ],
    );
  }
}

class Router extends StatefulWidget {
  const Router({super.key});

  @override
  State<Router> createState() => _RouterState();
}

class _RouterState extends State<Router> {
  String route = 'home';

  void go(String next) => setState(() => route = next);

  @override
  Widget build(BuildContext context) {
    if (route == 'sign-in') {
      return SignIn(
        onSignedIn: () => go('home'),
        onBack: () => go('home'),
      );
    }
    return Home(onGoToSignIn: () => go('sign-in'));
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.onGoToSignIn});

  final VoidCallback onGoToSignIn;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool loading = true;
  bool signedIn = false;

  @override
  void initState() {
    super.initState();
    // A dead refresh token drops the UI back to the landing page.
    Backend.onSignedOut = () {
      unawaited(ChatService().signOut());
      if (mounted) setState(() => signedIn = false);
    };
    _load();
    // Play only answers for its own installs; silent everywhere else.
    PlayStore.checkForUpdate();
  }

  Future<void> _load() async {
    try {
      final user = await Backend.currentUser();
      if (mounted) setState(() => signedIn = user != null);
      if (user != null) {
        // Pre-authenticate world chat in the background while splash plays:
        unawaited(
          ChatService.started.then((ready) {
            if (ready) unawaited(ChatService().ensureSignedIn());
          }),
        );
      }
    } catch (_) {
      if (mounted) setState(() => signedIn = false);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await Backend.signOut();
    } catch (_) {}
    await ChatService().signOut();
    if (mounted) setState(() => signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!signedIn) {
      // Landing page for signed-out users. Google sign-in happens dito mismo,
      // kaya `_load()` ang magdadala sa HomeShell pagkatapos.
      return LandingScreen(
        onSignIn: widget.onGoToSignIn,
        onGoogleSignedIn: () => unawaited(_load()),
      );
    }
    return HomeShell(onSignOut: _signOut);
  }
}

/// Tab shell shown after sign-in.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  int coins = 0;
  bool isAdmin = false;
  bool isModerator = false;
  bool loading = true;
  String display = '';
  int _chatUnread = 0;
  int _announcementUnread = 0;
  List<Announcement> _announcements = const [];
  Announcement? announcement;

  /// Passive formats (banner + interstitial) — profit only, no coins.
  final _ads = AdService();
  BannerAd? _banner;
  bool _bannerWanted = false;
  int _bannerRetryAttempts = 0;
  Timer? _bannerRetryTimer;
  int _tabSwitches = 0;
  DateTime? _lastInterstitial;

  /// Interstitial cadence: every other tab switch, at most once per cooldown
  /// (and never right at launch).
  static const _interCooldown = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    // First interstitial can only appear after the cooldown, not on open.
    _lastInterstitial = DateTime.now();
    _refresh();
    // A push that lands while the app is in front has no tray notification on
    // Android; reload the shell so an announcement shows as the banner.
    Push.foreground.addListener(_onForegroundPush);
    // The shell only exists when signed in and past the launch gates; the
    // request itself waits for the splash to finish.
    unawaited(Push.requestPermission());
    unawaited(
      ChatService.started.then((ready) {
        if (ready) unawaited(ChatService().ensureSignedIn());
      }),
    );
  }

  void _onAdsEnabledForBanner() {
    if (AdService.adsEnabled && mounted && _banner == null) {
      _loadBanner();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is available here (not in initState) — load the banner once.
    if (!_bannerWanted) {
      _bannerWanted = true;
      AdService.instance.adsEnabledNotifier.addListener(_onAdsEnabledForBanner);
      if (AdService.adsEnabled) {
        _loadBanner();
      }
    }
  }

  void _onForegroundPush() {
    if (mounted) unawaited(_refresh());
  }

  @override
  void dispose() {
    Push.foreground.removeListener(_onForegroundPush);
    _bannerRetryTimer?.cancel();
    AdService.instance.adsEnabledNotifier.removeListener(
      _onAdsEnabledForBanner,
    );
    _banner?.dispose();
    _banner = null;
    super.dispose();
  }

  /// Adaptive banner sized to the screen width, parked above the nav pill.
  Future<void> _loadBanner() async {
    if (!AdService.adsEnabled || !mounted) return;
    final width = MediaQuery.sizeOf(context).width.round();
    final size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width) ??
        AdSize.banner;
    if (!mounted) return;
    _bannerRetryTimer?.cancel();
    late final BannerAd ad;
    ad = BannerAd(
      adUnitId: AdUnits.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            _bannerRetryAttempts = 0;
            setState(() => _banner = ad);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (a, error) {
          a.dispose();
          AdService.logAdError('Banner', AdUnits.banner, error, action: 'load');
          if (!mounted) return;
          setState(() => _banner = null);
          if (error.code == 3) {
            debugPrint('[HomeShell] BannerAd no fill.');
            return;
          }
          if (_bannerRetryAttempts < 3) {
            final delaySeconds = 4 * (1 << _bannerRetryAttempts);
            _bannerRetryAttempts++;
            debugPrint(
              '[HomeShell] Retrying banner in ${delaySeconds}s (attempt $_bannerRetryAttempts/3)',
            );
            _bannerRetryTimer = Timer(Duration(seconds: delaySeconds), () {
              if (mounted) _loadBanner();
            });
          } else {
            debugPrint('[HomeShell] BannerAd retries exhausted.');
          }
        },
        onAdImpression: (_) => debugPrint('[HomeShell] BannerAd impression'),
        onAdClicked: (_) => debugPrint('[HomeShell] BannerAd clicked'),
      ),
    );
    await ad.load();
  }

  /// Fire-and-forget interstitial on tab changes (passive — no coins).
  void _maybeShowInterstitial() {
    _tabSwitches++;
    final now = DateTime.now();
    final cooled =
        _lastInterstitial == null ||
        now.difference(_lastInterstitial!) >= _interCooldown;
    if (_tabSwitches % 2 != 0 || !cooled) return;
    _lastInterstitial = now;
    unawaited(_showInterstitial());
  }

  /// Fire-and-forget so ad loading never stalls navigation.
  Future<void> _showInterstitial() async {
    // Same accidental-click guard as the rewarded path — the tab tap that
    // triggered this must be over before a full-screen ad takes the screen.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await _ads.showInterstitial();
  }

  Future<void> _refresh() async {
    var balance = coins;
    var reason = '';
    // Run the balance fetch alongside the other three instead of serially
    // before them — one round-trip shorter on every shell open.
    final coinsFuture = Backend.coins().then<int>((v) => v).catchError((
      Object e,
    ) {
      // Keep the last known balance; a blip must not read as "0 coins".
      reason = e is ApiException
          ? e.userMessage
          : 'The server did not respond.';
      return coins;
    });
    final results = await Future.wait<Object>([
      Backend.isAdmin().catchError((_) => false),
      Backend.isModerator().catchError((_) => false),
      Backend.currentUser()
          .then(
            (u) => (u?.name.isNotEmpty ?? false) ? u!.name : (u?.email ?? ''),
          )
          .catchError((_) => ''),
    ]);
    balance = await coinsFuture;
    // A failed banner fetch just means no banner; it must not break the shell.
    Announcement? fresh;
    var unreadAnnouncements = 0;
    var allAnnouncements = const <Announcement>[];
    try {
      final stored = await AnnouncementStore.dismissedId();
      final seenAt = await ReadStore.sync();
      allAnnouncements = await Backend.announcements();
      unreadAnnouncements = allAnnouncements
          .where((a) => a.createdAt.compareTo(seenAt) > 0)
          .length;
      fresh = unreadAnnouncement(
        allAnnouncements.isNotEmpty ? allAnnouncements.first : null,
        stored,
      );
    } catch (_) {
      fresh = null;
    }
    if (!mounted) return;
    setState(() {
      coins = balance;
      isAdmin = results[0] as bool;
      isModerator = results[1] as bool;
      display = results[2] as String;
      announcement = fresh;
      _announcements = allAnnouncements;
      _announcementUnread = unreadAnnouncements;
      loading = false;
    });
    if (reason.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // The server's own reason, not a generic "something failed".
          content: Text('Could not refresh the balance. $reason'),
          action: SnackBarAction(label: 'Retry', onPressed: _refresh),
        ),
      );
    }
  }

  /// Closes the banner for good on this device.
  Future<void> _dismissAnnouncement() async {
    final id = announcement?.id ?? '';
    setState(() => announcement = null);
    if (id.isNotEmpty) await AnnouncementStore.dismiss(id);
  }

  /// Opening the News tab clears its badge up to the newest item.
  void _markAnnouncementsSeen() {
    if (_announcements.isEmpty) return;
    unawaited(ReadStore.markAnnouncementsSeen(_announcements.first.createdAt));
    if (_announcementUnread != 0) setState(() => _announcementUnread = 0);
  }

  /// News page (header button): own scaffold + back button, badge cleared on
  /// open.
  void _openNews() {
    _markAnnouncementsSeen();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen()),
    );
  }

  void _openWallet() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalletScreen(
          onGoToEarn: () {
            Navigator.of(context).pop();
            setState(() => tab = 1);
          },
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          onSignOut: widget.onSignOut,
          onAccountDeleted: widget.onSignOut,
          onGoToTab: (t) {
            Navigator.of(context).pop();
            setState(() => tab = t);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Stack(
        children: [
          const ArcadeBackdrop(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoinMedallion(size: 64),
                const SizedBox(height: AppSpace.lg),
                Text(
                  'SETTING THE TABLE',
                  style: AppText.label.copyWith(
                    fontSize: 10,
                    letterSpacing: 2.6,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final pages = <Widget>[
      StoreScreen(
        coins: coins,
        onRefresh: _refresh,
        active: tab == 0,
        onOpenWallet: _openWallet,
        onGoToEarn: () => setState(() => tab = 1),
      ),
      EarnScreen(coins: coins, onRefresh: _refresh),
      MyKeysScreen(
        active: tab == 2,
        onGoToStore: () => setState(() => tab = 0),
      ),
      TutorialsScreen(embedded: true, active: tab == 3),
      ChatScreen(
        embedded: true,
        active: tab == 4,
        isAdmin: isAdmin,
        isModerator: isModerator,
        onUnreadChanged: (count) {
          if (_chatUnread != count) setState(() => _chatUnread = count);
        },
      ),
      if (isAdmin) AdminScreen(onAnnouncementSent: _refresh, active: tab == 5),
    ];

    final destinations = <_NavItem>[
      _NavItem(Icons.storefront_outlined, Icons.storefront, 'Store'),
      _NavItem(Icons.play_circle_outline, Icons.play_circle, 'Earn'),
      _NavItem(Icons.shopping_bag_outlined, Icons.shopping_bag, 'Purchases'),
      _NavItem(Icons.menu_book_outlined, Icons.menu_book, 'Tutorials'),
      _NavItem(Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
      if (isAdmin)
        _NavItem(
          Icons.admin_panel_settings_outlined,
          Icons.admin_panel_settings,
          'Admin',
        ),
    ];

    final safeIndex = tab.clamp(0, pages.length - 1);

    return Stack(
      children: [
        const ArcadeBackdrop(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 74,
            titleSpacing: AppSpace.lg,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    LogoBadge(size: 28, fontSize: 14),
                    SizedBox(width: AppSpace.sm + 2),
                    GradientText('Ghosst', style: AppText.title),
                  ],
                ),
                // Which table you are at — the shell's own breadcrumb.
                Padding(
                  padding: const EdgeInsets.only(
                    left: 28 + AppSpace.sm + 2,
                    top: 1,
                  ),
                  child: Text(
                    destinations[safeIndex].label.toUpperCase(),
                    style: AppText.label.copyWith(
                      fontSize: 10,
                      letterSpacing: 2.2,
                      color: AppColors.textDim.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            // Fading hairline — separation without a hard 1px rule.
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.primary.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              // News lives in the header now: reachable from any tab, and the
              // bottom bar is back to five real destinations.
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.xs),
                child: _NewsButton(
                  unread: _announcementUnread,
                  onTap: _openNews,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: CoinPill(coins: coins, onTap: _openWallet),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.lg),
                child: Pressable(
                  onTap: _openProfile,
                  scale: 0.92,
                  semanticLabel: 'Profile',
                  child: SizedBox(
                    // 48dp hit area, 36dp visual.
                    width: kTouchMin,
                    height: kTouchMin,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: kNeonGradient,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.22),
                            blurRadius: 16,
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: Container(
                        width: 33,
                        height: 33,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(
                            AppRadius.input - 2,
                          ),
                        ),
                        child: Text(
                          display.trim().isEmpty
                              ? 'G'
                              : display.trim()[0].toUpperCase(),
                          style: AppText.subtitle.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // IndexedStack keeps each tab's state (scroll position, loaded data).
          body: Column(
            children: [
              if (announcement != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.sm,
                    AppSpace.lg,
                    0,
                  ),
                  child: AnnouncementBanner(
                    announcement: announcement!,
                    onDismiss: _dismissAnnouncement,
                  ),
                ),
              // Banner sits under the app bar, not against the bottom nav:
              // AdMob forbids ads adjacent to navigational controls.
              if (_banner != null)
                SizedBox(
                  width: _banner!.size.width.toDouble(),
                  height: _banner!.size.height.toDouble(),
                  child: ColoredBox(
                    color: AppColors.bg,
                    child: AdWidget(ad: _banner!),
                  ),
                ),
              Expanded(
                child: IndexedStack(index: safeIndex, children: pages),
              ),
            ],
          ),
          // Floating glass pill — never an edge-to-edge Material bar.
          bottomNavigationBar: _GlassNavBar(
            index: safeIndex,
            items: destinations,
            unread: {
              if (_chatUnread > 0) 4: _chatUnread,
            },
            onSelected: (i) {
              // Re-tapping the current tab is not a tab switch — it must
              // not count towards (or fire) the interstitial.
              if (i == safeIndex) return;
              setState(() => tab = i);
              if (i == 3) _markAnnouncementsSeen();
              _maybeShowInterstitial();
            },
          ),
        ),
      ],
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating, backdrop-blurred pill navigation. Active tab widens into a
/// tinted pill with its label; inactive tabs stay icon-only.

/// Header entry point for News: megaphone with a red unread count, the same
/// badge language the bottom bar used.
class _NewsButton extends StatelessWidget {
  const _NewsButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: unread > 0 ? 'News, $unread unread' : 'News',
      child: SizedBox(
        width: kTouchMin,
        height: kTouchMin,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(color: AppColors.border),
                ),
                child: const ExcludeSemantics(
                  child: Icon(
                    Icons.campaign_outlined,
                    size: AppIcon.md,
                    color: AppColors.textDim,
                  ),
                ),
              ),
              if (unread > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.bg, width: 1.5),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: AppText.caption.copyWith(
                          fontSize: 9.5,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassNavBar extends StatefulWidget {
  const _GlassNavBar({
    required this.index,
    required this.items,
    required this.onSelected,
    this.unread = const {},
  });

  final int index;
  final List<_NavItem> items;
  final ValueChanged<int> onSelected;

  /// tab index → unread count. Zero/absent tabs show no badge.
  final Map<int, int> unread;

  @override
  State<_GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<_GlassNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _fromIndex = 0;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.index;
    _toIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didUpdateWidget(covariant _GlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _fromIndex = widget.index;
        _toIndex = widget.index;
        _controller.value = 1;
      } else {
        _fromIndex = oldWidget.index;
        _toIndex = widget.index;
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.xs),
        decoration: BoxDecoration(
          color: AppColors.bgSoft.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.30),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / widget.items.length;
                return SizedBox(
                  height: 64,
                  child: Stack(
                    children: [
                      // Morphing pill indicator.
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final t = Curves.easeInOutCubic.transform(
                            _controller.value,
                          );
                          final fromLeft = _fromIndex * tabWidth;
                          final toLeft = _toIndex * tabWidth;
                          final left = fromLeft + (toLeft - fromLeft) * t;
                          final distance = (_toIndex - _fromIndex).abs();
                          final stretch =
                              distance * tabWidth * (math.sin(math.pi * t));
                          final width = tabWidth + stretch;
                          return Positioned(
                            left: left,
                            top: 8,
                            width: width,
                            height: 48,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF67E8F9),
                                    Color(0xFF22D3EE),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.5,
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < widget.items.length; i++)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: i == widget.index,
                                label:
                                    '${widget.items[i].label}'
                                    '${(widget.unread[i] ?? 0) > 0 ? ', ${widget.unread[i]} unread' : ''}',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.onSelected(i);
                                  },
                                  child: SizedBox(
                                    height: 64,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            ExcludeSemantics(
                                              child: Icon(
                                                i == widget.index
                                                    ? widget.items[i].selectedIcon
                                                    : widget.items[i].icon,
                                                size: AppIcon.md,
                                                color: i == widget.index
                                                    ? const Color(0xFF04212A)
                                                    : AppColors.textDim,
                                              ),
                                            ),
                                            if ((widget.unread[i] ?? 0) > 0)
                                              Positioned(
                                                top: -6,
                                                right: -12,
                                                child: ExcludeSemantics(
                                                  child: Container(
                                                    constraints: const BoxConstraints(
                                                      minWidth: 16,
                                                    ),
                                                    height: 16,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                        ),
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: AppColors.red,
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: AppColors.bg,
                                                        width: 1.5,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      widget.unread[i]! > 9
                                                          ? '9+'
                                                          : '${widget.unread[i]}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w800,
                                                        height: 1,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.items[i].label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.caption.copyWith(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: i == widget.index
                                                ? const Color(0xFF04212A)
                                                : AppColors.textDim,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
