import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
import 'services/worker_backend.dart';
import 'services/consent_service.dart';
import 'services/distribution.dart';
import 'services/play_store.dart';
import 'services/security.dart';
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
              // No full-screen ad here: it can land under the user's first tap
              // and cause an accidental advertiser click.
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
        onBack: () => go('home'),
      );
    }
    if (route == 'sign-up') {
      return SignUp(
        onSignedUp: () => go('home'),
        onGoToSignIn: () => go('sign-in'),
        onBack: () => go('home'),
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
    // A dead refresh token drops the UI back to the landing page.
    Backend.onSignedOut = () {
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
          debugPrint(
            '[HomeShell] BannerAd failed to load: code ${error.code}, message: ${error.message}, domain: ${error.domain}',
          );
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
    await _ads.showInterstitial();
  }

  Future<void> _refresh() async {
    var balance = coins;
    var failed = false;
    try {
      balance = await Backend.coins();
    } catch (_) {
      // Keep the last known balance; a blip must not read as "0 coins".
      failed = true;
    }
    final results = await Future.wait<Object>([
      Backend.isAdmin().catchError((_) => false),
      Backend.currentUser()
          .then(
            (u) => (u?.name.isNotEmpty ?? false) ? u!.name : (u?.email ?? ''),
          )
          .catchError((_) => ''),
    ]);
    if (!mounted) return;
    setState(() {
      coins = balance;
      isAdmin = results[0] as bool;
      display = results[1] as String;
      loading = false;
    });
    if (failed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not refresh your balance.'),
          action: SnackBarAction(label: 'Retry', onPressed: _refresh),
        ),
      );
    }
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
      MyKeysScreen(
        active: tab == 2,
        onGoToStore: () => setState(() => tab = 0),
      ),
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
        const _ShellBackdrop(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 60,
            titleSpacing: AppSpace.lg,
            title: const Row(
              children: [
                LogoBadge(size: 30, fontSize: 15),
                SizedBox(width: AppSpace.md - 2),
                GradientText('Ghosst', style: AppText.title),
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
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: CoinPill(coins: coins, onTap: _openWallet),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.lg),
                child: Pressable(
                  onTap: _openProfile,
                  scale: 0.92,
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
                ),
              // Floating glass pill — never an edge-to-edge Material bar.
              _GlassNavBar(
                index: safeIndex,
                items: destinations,
                onSelected: (i) {
                  // Re-tapping the current tab is not a tab switch — it must
                  // not count towards (or fire) the interstitial.
                  if (i == safeIndex) return;
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

/// One light source: the mesh's cyan bloom stays at the top, and everything
/// past the first third falls off to near-black so content owns the frame.
class _ShellBackdrop extends StatelessWidget {
  const _ShellBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MeshBackground(),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.05),
                  radius: 1.15,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.20),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0, -0.2),
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg.withValues(alpha: 0),
                    AppColors.bg.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Floating, backdrop-blurred pill navigation. Active tab widens into a
/// tinted pill with its label; inactive tabs stay icon-only.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.index,
    required this.items,
    required this.onSelected,
  });

  final int index;
  final List<_NavItem> items;
  final ValueChanged<int> onSelected;

  /// Width of an icon-only slot; the active tab takes what is left over.
  static const double _slot = 56;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm - 2),
            decoration: BoxDecoration(
              // True glass: the blurred page shows through, never a flat bar.
              color: AppColors.bgSoft.withValues(alpha: 0.62),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [
                // 1px inner top highlight — the pill is lit from above.
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.12),
                  offset: const Offset(0, 1),
                  blurRadius: 1,
                  blurStyle: BlurStyle.inner,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final activeWidth = math.max(
                  _slot,
                  constraints.maxWidth - _slot * (items.length - 1),
                );
                return Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _GlassNavItem(
                        item: items[i],
                        selected: i == index,
                        width: i == index ? activeWidth : _slot,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelected(i);
                        },
                      ),
                  ],
                );
              },
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
    required this.width,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textDim;

    return AnimatedContainer(
      duration: kMotionStandard,
      curve: kPremiumCurve,
      width: width,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.34)
              : Colors.transparent,
        ),
      ),
      child: Pressable(
        onTap: onTap,
        scale: 0.90,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md + 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 21,
                color: color,
              ),
              if (selected) ...[
                const SizedBox(width: AppSpace.sm - 2),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: AppText.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
