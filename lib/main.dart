import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'announcement_banner.dart';
import 'api/api_exception.dart';
import 'arcade.dart';
import 'premium.dart';
import 'screens/adblock_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/direct_chat_screen.dart';
import 'screens/earn_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/website_feedback_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/my_keys_screen.dart';
import 'screens/notice_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_hub_screen.dart';
import 'screens/reel_upload_screen.dart';
import 'screens/reels_screen.dart';
import 'screens/shop_hub_screen.dart';
import 'screens/social_list_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_screen.dart';
import 'screens/tamper_screen.dart';
import 'screens/tutorials_screen.dart';
import 'screens/update_screen.dart';
import 'screens/user_profile_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/ad_service.dart';
import 'services/adblock_detector.dart';
import 'services/announcement_store.dart';
import 'services/chat_service.dart';
import 'services/worker_backend.dart';
import 'services/consent_service.dart';
import 'services/distribution.dart';
import 'services/direct_chat_service.dart';
import 'services/notice_store.dart';
import 'services/play_integrity.dart';
import 'services/play_store.dart';
import 'services/push.dart';
import 'services/read_store.dart';
import 'services/reel_upload_service.dart';
import 'services/security.dart';
import 'sign_in.dart';
import 'social_shell.dart';
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
                  onUpdate: playUpdate ? PlayStore.startImmediateUpdate : null,
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
      return SignIn(onSignedIn: () => go('home'), onBack: () => go('home'));
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
      unawaited(DirectChatService().signOut());
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
    await DirectChatService().signOut();
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
  SocialTab tab = SocialTab.home;
  int _reelRefresh = 0;
  int coins = 0;
  bool isAdmin = false;
  bool isModerator = false;
  bool loading = true;
  String display = '';
  String? photoUrl;
  int _chatUnread = 0;
  final Set<String> _openingProfiles = {};
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
    // Second try at the FCM topic subscription, in case Push.init() ran before
    // Firebase (or the network) was ready.
    unawaited(Push.register());
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
          : 'The server did not respond. If this keeps happening, set your '
                'Private DNS to one.one.one.one (Cloudflare) or install the '
                'Warp VPN app.';
      return coins;
    });
    final results = await Future.wait<Object?>([
      Backend.isAdmin().catchError((_) => false),
      Backend.isModerator().catchError((_) => false),
      Backend.currentUser().catchError((_) => null),
    ]);
    balance = await coinsFuture;
    // A failed banner fetch just means no banner; it must not break the shell.
    Announcement? fresh;
    var allAnnouncements = const <Announcement>[];
    try {
      final stored = await AnnouncementStore.dismissedId();
      await ReadStore.sync();
      allAnnouncements = await Backend.announcements();
      fresh = unreadAnnouncement(
        allAnnouncements.isNotEmpty ? allAnnouncements.first : null,
        stored,
      );
    } catch (_) {
      fresh = null;
    }
    if (!mounted) return;
    final currentUser = results[2] as AppUser?;
    final userDisplay = (currentUser?.name.isNotEmpty ?? false)
        ? currentUser!.name
        : (currentUser?.email ?? '');
    final userPhoto = currentUser?.photoUrl;
    setState(() {
      coins = balance;
      isAdmin = results[0] as bool;
      isModerator = results[1] as bool;
      display = userDisplay;
      photoUrl = userPhoto;
      announcement = fresh;
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

  void _openWallet() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalletScreen(
          onGoToEarn: () {
            Navigator.of(context).pop();
            _openEarn();
          },
        ),
      ),
    );
  }

  void _openStore() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoreScreen(
          coins: coins,
          onRefresh: _refresh,
          onOpenWallet: _openWallet,
          onGoToEarn: _openEarn,
        ),
      ),
    );
  }

  void _openEarn() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EarnScreen(coins: coins, onRefresh: _refresh),
      ),
    );
  }

  void _openKeys() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyKeysScreen(onGoToStore: _openStore),
      ),
    );
  }

  void _openTutorials() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TutorialsScreen(embedded: false),
      ),
    );
  }

  void _openWorldChat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          embedded: false,
          isAdmin: isAdmin,
          isModerator: isModerator,
          onOpenProfile: _openUserProfile,
        ),
      ),
    );
  }

  void _openFeedback() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FeedbackScreen()));
  }

  void _openWebsiteFeedback() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const WebsiteFeedbackScreen(),
      ),
    );
  }

  void _openAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(onAnnouncementSent: _refresh),
      ),
    );
  }

  Future<void> _shareApp() async {
    final text = Backend.referralInviteText(
      referralCode: Backend.cachedUser?.referralCode ?? '',
      isPlay: Distribution.isPlay,
    );
    try {
      await Share.share(text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open sharing.')));
    }
  }

  void _openDirectChat({
    required String peerId,
    required String peerName,
    String? peerAvatarUrl,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DirectChatScreen(
          peerId: peerId,
          peerName: peerName,
          peerAvatarUrl: peerAvatarUrl,
          onOpenProfile: _openUserProfile,
        ),
      ),
    );
  }

  Future<void> _openUserProfile(String id) async {
    if (!_openingProfiles.add(id)) return;
    try {
      if (Backend.cachedUser?.id == id) {
        _openProfile();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            userId: id,
            loader: Backend.publicUser,
            loadBlocked: DirectChatService().isBlocked,
            onMessage: (user) => _openDirectChat(
              peerId: user.id,
              peerName: user.displayName,
              peerAvatarUrl: user.avatarUrl,
            ),
            onReport: () => unawaited(_reportUser(id)),
            onBlock: () => _changeBlock(id, true),
            onUnblock: () => _changeBlock(id, false),
            onFollow: Backend.followUser,
            onUnfollow: Backend.unfollowUser,
            onOpenSocialList: (direction) =>
                unawaited(_openSocialList(id, direction)),
            loadReels: (userId, offset) =>
                Backend.userReels(userId, offset: offset),
            onOpenReel: (reel) => unawaited(_openCreatorReel(reel)),
          ),
        ),
      );
      if (mounted) setState(() => _reelRefresh++);
    } finally {
      _openingProfiles.remove(id);
    }
  }

  Future<void> _openCreatorReel(Reel reel, {bool openComments = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: ReelsScreen(
            embedded: false,
            onFollow: Backend.followUser,
            onDeleteReel: (id) async {
              await Backend.deleteReel(id);
              if (context.mounted) setState(() => _reelRefresh++);
            },
            onOpenTutorials: _openTutorials,
            onOpenFeedback: _openWebsiteFeedback,
            initialReelId: reel.id,
            initialCreatorId: reel.creator.id,
            openCommentsOnLoad: openComments,
            load: (feed, offset) async {
              final page = await Backend.reels(feed: feed, offset: offset);
              final index = page.reels.indexWhere((item) => item.id == reel.id);
              final reels = [...page.reels];
              if (index >= 0) {
                final selected = reels.removeAt(index);
                reels.insert(0, selected);
              } else if (page.reels.every(
                (item) => item.creator.id != reel.creator.id,
              )) {
                reels.addAll(
                  await Backend.userReels(reel.creator.id, limit: 10),
                );
              }
              return ReelFeedPage(reels: reels, nextOffset: page.nextOffset);
            },
            onOpenProfile: _openUserProfile,
          ),
        ),
      ),
    );
  }

  Future<void> _openReelFromActivity(
    String reelId, {
    required bool openComments,
  }) async {
    try {
      final reel = await Backend.reel(reelId);
      if (!mounted) return;
      await _openCreatorReel(reel, openComments: openComments);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open reel.')));
      }
    }
  }

  Future<void> _openSocialList(String userId, SocialListDirection direction) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialListScreen(
          userId: userId,
          direction: direction,
          onOpenProfile: _openUserProfile,
        ),
      ),
    );
  }

  Future<void> _reportUser(String id) async {
    try {
      await Backend.reportContent(
        targetType: 'user',
        targetId: id,
        reason: 'other',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit report. Try again.')),
        );
      }
    }
  }

  Future<void> _openReelUpload() async {
    final service = ReelUploadService();
    try {
      final uploaded = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ReelUploadScreen(
            prepareUpload: (draft) => Backend.startReelUpload(
              caption: draft.caption,
              images: [for (final i in draft.images) i.toJson()],
              idempotencyKey: draft.idempotencyBase,
            ),
            submitUpload: (draft, ticket) async {
              final results = await service.uploadImages(
                images: draft.images,
                ticket: ticket,
                onImageProgress: (done, total) =>
                    draft.onProgress?.call(done, total),
              );
              await Backend.completeReelUpload(
                reelId: ticket.reelId,
                images: [for (final r in results) r.toJson()],
                idempotencyKey: draft.idempotencyBase,
              );
            },
          ),
        ),
      );
      if (!mounted || uploaded == null) return;
      setState(() {
        tab = SocialTab.home;
        _reelRefresh++;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } finally {
      service.close();
    }
  }

  Future<bool> _changeBlock(String id, bool blocked) async {
    try {
      final service = DirectChatService();
      if (blocked) {
        await service.block(id);
      } else {
        await service.unblock(id);
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not ${blocked ? 'block' : 'unblock'} user.'),
          ),
        );
      }
      return false;
    }
  }

  void _openProfile() {
    setState(() => tab = SocialTab.profile);
  }

  void _openProfileSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          onSignOut: widget.onSignOut,
          onAccountDeleted: widget.onSignOut,
          onOpenKeys: _openKeys,
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
      ReelsScreen(
        active: tab == SocialTab.home,
        onFollow: Backend.followUser,
        onOpenTutorials: _openTutorials,
        onOpenFeedback: _openWebsiteFeedback,
        refreshToken: _reelRefresh,
        onOpenProfile: _openUserProfile,
        onDeleteReel: Backend.deleteReel,
        coins: coins,
        onOpenWallet: _openWallet,
      ),
      ShopHubScreen(
        coins: coins,
        onRefresh: _refresh,
        onOpenEarn: _openEarn,
        onOpenStore: _openStore,
        onOpenKeys: _openKeys,
        onOpenTutorials: _openTutorials,
        onOpenWallet: _openWallet,
      ),
      InboxScreen(
        embedded: true,
        onOpenWorldChat: _openWorldChat,
        onUnreadChanged: (count) {
          if (_chatUnread != count) setState(() => _chatUnread = count);
        },
        onOpenThread: (thread, peer) => _openDirectChat(
          peerId: peer.id,
          peerName: peer.name,
          peerAvatarUrl: peer.avatarUrl,
        ),
        onOpenReelNotification: (reelId, {required bool openComments}) {
          unawaited(_openReelFromActivity(reelId, openComments: openComments));
        },
      ),
      ProfileHubScreen(
        key: ValueKey('profile-hub-$_reelRefresh'),
        userId: Backend.cachedUser?.id ?? '',
        displayName: display,
        avatarUrl: photoUrl,
        isAdmin: isAdmin,
        onOpenKeys: _openKeys,
        onOpenWallet: _openWallet,
        onOpenFeedback: _openFeedback,
        onOpenAdmin: _openAdmin,
        onOpenSettings: _openProfileSettings,
        onOpenShare: () => unawaited(_shareApp()),
        onOpenReel: (reel) => unawaited(_openCreatorReel(reel)),
      ),
    ];

    final showShellBanners = tab != SocialTab.home;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (showShellBanners && announcement != null)
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
          if (showShellBanners && _banner != null)
            SizedBox(
              width: _banner!.size.width.toDouble(),
              height: _banner!.size.height.toDouble(),
              child: ColoredBox(
                color: AppColors.bg,
                child: AdWidget(ad: _banner!),
              ),
            ),
          Expanded(
            child: IndexedStack(index: tab.pageIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: FiveTabBar(
        selected: tab,
        onSelected: (next) {
          if (next == tab || next == SocialTab.create) return;
          setState(() => tab = next);
          _maybeShowInterstitial();
        },
        onCreate: _openReelUpload,
        unread: {if (_chatUnread > 0) SocialTab.inbox: _chatUnread},
      ),
    );
  }
}
