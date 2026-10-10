import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import 'premium.dart';
import 'screens/adblock_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/earn_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/my_keys_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_screen.dart';
import 'screens/tamper_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/ad_service.dart';
import 'services/adblock_detector.dart';
import 'services/backend.dart';
import 'services/consent_service.dart';
import 'services/distribution.dart';
import 'services/security.dart';
import 'services/yandex_ad_service.dart';
import 'sign_in.dart';
import 'sign_up.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: AppTheme.dark,
      // Fixed, pointer-events-none film grain over the whole app.
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          const Positioned.fill(child: GrainOverlay()),
        ],
      ),
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

  /// Integrity verdict (cracked / re-packed / modded build). Null until the
  /// check answers — each leg is bounded and fails open.
  SecurityReport? _security;

  /// Ad-blocker verdict. Null until the check answers — fails open, and
  /// only positive evidence (ads blocked while the network works) locks.
  AdblockReport? _adblock;

  /// Throttle stamp: launch + resume re-checks run at most once a minute
  /// so returning from a settings screen never hammers the probes.
  DateTime? _lastAdblockCheck;

  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // All legs run in parallel with the intro so the verdict (gate or
    // all-clear) is ready the moment the splash finishes.
    _boot = _launchChecks();
  }

  Future<void> _launchChecks() async {
    await Future.wait<void>([
      _initializeAds(),
      _checkSecurity(),
      _checkAdblock(),
    ]);
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
    if (!canRequest) return;
    try {
      await YandexAdService.instance.initialize();
      unawaited(YandexAdService.instance.preload());
    } catch (e, st) {
      // Yandex is supplemental; its failure must never disable Google ads.
      debugPrint('[YandexAds] Initialization failed: $e\n$st');
    }
  }

  /// Blockers are toggled outside the app (quick-settings tile, Private
  /// DNS screen) — re-check on return so the gate reappears the moment the
  /// device starts filtering ads again (throttled, fails open).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAdblock();
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
    // A modified build outranks the ad-blocker gate. App updates are handled
    // exclusively by Google Play and never block launch from inside the app.
    final tampered = _security?.blocked ?? false;
    final adBlocked = _adblock?.blocked ?? false;
    final blocked = tampered || adBlocked;
    return Stack(
      children: [
        // The gate replaces the entire router — nothing to pop, no UI to
        // reach while a newer build is waiting.
        SafeArea(
          child: blocked
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
        if (_splash)
          SplashScreen(
            // Held BEFORE the exit starts, so the intro never gets cut and the
            // reveal lands on the finished gate (bounded by both legs).
            onReady: () => _boot,
            onDone: () async {
              if (!mounted) return;
              setState(() => _splash = false);
              // Do not present an app-open ad after revealing interactive UI.
              // It can land under the user's first tap and cause an accidental
              // advertiser click just as they press a navigation/earn button.
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
        onGoToSignUp: () => go('sign-up'),
      );
    }
    if (route == 'sign-up') {
      return SignUp(
        onSignedUp: () => go('home'),
        onGoToSignIn: () => go('sign-in'),
      );
    }
    return Home(
      onGoToSignIn: () => go('sign-in'),
      onGoToSignUp: () => go('sign-up'),
    );
  }
}

class Home extends StatefulWidget {
  const Home({
    super.key,
    required this.onGoToSignIn,
    required this.onGoToSignUp,
  });

  final VoidCallback onGoToSignIn;
  final VoidCallback onGoToSignUp;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool loading = true;
  bool signedIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await Backend.currentUser();
      if (mounted) setState(() => signedIn = user != null);
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
    if (mounted) setState(() => signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!signedIn) {
      // Landing page for signed-out users.
      return LandingScreen(
        onSignIn: widget.onGoToSignIn,
        onSignUp: widget.onGoToSignUp,
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
  bool loading = true;
  String display = '';

  /// Passive formats (banner + interstitial) — profit only, no coins.
  final _ads = AdService();
  BannerAd? _banner;
  bool _bannerWanted = false;
  int _bannerRetryAttempts = 0;
  Timer? _bannerRetryTimer;
  yandex.BannerAd? _yandexBanner;
  StreamSubscription<yandex.BannerAdLoadState>? _yandexBannerSub;
  int _tabSwitches = 0;
  DateTime? _lastInterstitial;

  /// Interstitial cadence: every other tab switch, at most once per cooldown
  /// (and never right at launch — the app-open ad already ran).
  static const _interCooldown = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    // First interstitial can only appear after the cooldown, not on open.
    _lastInterstitial = DateTime.now();
    _refresh();
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

  @override
  void dispose() {
    _bannerRetryTimer?.cancel();
    AdService.instance.adsEnabledNotifier.removeListener(
      _onAdsEnabledForBanner,
    );
    _banner?.dispose();
    _banner = null;
    unawaited(_disposeYandexBanner());
    super.dispose();
  }

  Future<void> _disposeYandexBanner() async {
    await _yandexBannerSub?.cancel();
    _yandexBannerSub = null;
    final ad = _yandexBanner;
    _yandexBanner = null;
    if (ad != null) await YandexAdService.instance.destroyBanner(ad);
  }

  /// Loads a Yandex banner as a no-fill fallback for the AdMob banner.
  ///
  /// The plugin only issues its request once `AdWidget` is attached, so the
  /// ad is primed first and mounted immediately after.
  Future<void> _loadYandexBanner() async {
    if (!mounted || !AdService.adsEnabled || _yandexBanner != null) return;
    final width = MediaQuery.sizeOf(context).width.round();
    final ad = await YandexAdService.instance.prepareBanner(width: width);
    if (!mounted) {
      if (ad != null) await YandexAdService.instance.destroyBanner(ad);
      return;
    }
    if (ad == null) {
      debugPrint('[HomeShell] Yandex BannerAd unavailable.');
      return;
    }

    await _yandexBannerSub?.cancel();
    _yandexBannerSub = ad.loadStateStream.listen((state) {
      if (!mounted) return;
      if (state is yandex.BannerAdLoadStateLoaded) {
        debugPrint(
          '[HomeShell] Yandex BannerAd loaded ${state.width}x${state.height}',
        );
        setState(() {});
      } else if (state is yandex.BannerAdLoadStateError) {
        debugPrint('[HomeShell] Yandex BannerAd failed: ${state.error}');
        final failed = _yandexBanner;
        setState(() => _yandexBanner = null);
        if (failed != null) {
          unawaited(YandexAdService.instance.destroyBanner(failed));
        }
      }
    });
    setState(() => _yandexBanner = ad);
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
            // AdMob won the race — drop any Yandex fallback so only one
            // banner is ever rendered.
            if (_yandexBanner != null) {
              unawaited(_disposeYandexBanner());
            }
            setState(() => _banner = ad);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (a, error) {
          a.dispose();
          debugPrint(
            '[HomeShell] BannerAd failed to load: code ${error.code}, message: ${error.message}, domain: ${error.domain}',
          );
          if (!mounted) return;
          setState(() => _banner = null);
          if (error.code == 3) {
            debugPrint(
              '[HomeShell] BannerAd no fill; falling back to Yandex banner.',
            );
            unawaited(_loadYandexBanner());
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
            debugPrint(
              '[HomeShell] BannerAd retries exhausted; falling back to Yandex banner.',
            );
            unawaited(_loadYandexBanner());
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
    unawaited(_showInterstitialWithFallback());
  }

  /// AdMob first; when it has no inventory, quietly use the Yandex unit so
  /// the placement still earns instead of rendering nothing. Never awaited,
  /// so a slow fallback cannot stall navigation.
  Future<void> _showInterstitialWithFallback() async {
    if (await _ads.showInterstitial()) return;
    await YandexAdService.instance.showInterstitial(onClosed: () {});
  }

  Future<void> _refresh() async {
    final results = await Future.wait<Object>([
      Backend.coins().catchError((_) => 0),
      Backend.isAdmin().catchError((_) => false),
      Backend.currentUser()
          .then(
            (u) => (u?.name.isNotEmpty ?? false) ? u!.name : (u?.email ?? ''),
          )
          .catchError((_) => ''),
    ]);
    if (!mounted) return;
    setState(() {
      coins = results[0] as int;
      isAdmin = results[1] as bool;
      display = results[2] as String;
      loading = false;
    });
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
      return const Center(child: CircularProgressIndicator());
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
      const MyKeysScreen(),
      if (isAdmin) const AdminScreen(),
    ];

    final destinations = <_NavItem>[
      _NavItem(Icons.storefront_outlined, Icons.storefront, 'Store'),
      _NavItem(Icons.play_circle_outline, Icons.play_circle, 'Earn'),
      _NavItem(Icons.shopping_bag_outlined, Icons.shopping_bag, 'Purchases'),
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
        const MeshBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              children: [
                const LogoBadge(size: 34, fontSize: 17),
                const SizedBox(width: 10),
                const GradientText(
                  'Ghosst',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
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
                      Colors.white.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CoinPill(coins: coins, onTap: _openWallet),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: GestureDetector(
                  onTap: _openProfile,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: kNeonGradient,
                    ),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceHigh,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        display.trim().isEmpty
                            ? 'G'
                            : display.trim()[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // IndexedStack keeps each tab's state (scroll position, loaded data).
          body: IndexedStack(index: safeIndex, children: pages),
          // Banner strip sits above the floating pill (visible on every tab);
          // only mounts once loaded, so a failed ad leaves no empty gap.
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_banner != null)
                SizedBox(
                  width: _banner!.size.width.toDouble(),
                  height: _banner!.size.height.toDouble(),
                  child: ColoredBox(
                    color: AppColors.bg,
                    child: AdWidget(ad: _banner!),
                  ),
                )
              else if (_yandexBanner != null)
                // Yandex's AdWidget sizes itself once the native view reports
                // its measured dimensions, so it is mounted unconstrained.
                ColoredBox(
                  color: AppColors.bg,
                  child: yandex.AdWidget(bannerAd: _yandexBanner!),
                ),
              // Floating glass pill — never an edge-to-edge Material bar.
              _GlassNavBar(
                index: safeIndex,
                items: destinations,
                onSelected: (i) {
                  setState(() => tab = i);
                  _maybeShowInterstitial();
                },
              ),
            ],
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

/// Floating, backdrop-blurred pill navigation with an animated indicator.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.index,
    required this.items,
    required this.onSelected,
  });

  final int index;
  final List<_NavItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _GlassNavItem(
                      item: items[i],
                      selected: i == index,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelected(i);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  const _GlassNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textDim;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: kMotionFast,
        curve: kPremiumCurve,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: kMotionFast,
              switchInCurve: kPremiumCurve,
              switchOutCurve: kPremiumCurve,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                key: ValueKey(selected),
                size: 21,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: kMotionFast,
              curve: kPremiumCurve,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                letterSpacing: 0.1,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
