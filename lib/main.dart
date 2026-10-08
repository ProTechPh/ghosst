import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
import 'screens/update_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/ad_service.dart';
import 'services/adblock_detector.dart';
import 'services/backend.dart';
import 'services/security.dart';
import 'sign_in.dart';
import 'sign_up.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  runApp(const MyApp());

  // Initialize MobileAds asynchronously so it never delays or crashes app launch
  MobileAds.instance.initialize().catchError((e) {
    debugPrint('MobileAds initialization failed: $e');
    return InitializationStatus({});
  });
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
  final _ads = AdService();

  /// Forced-update gate — set when the launch check finds a newer build.
  UpdateInfo? _pendingUpdate;

  /// Latest announcement regardless of version. The integrity gate borrows
  /// its download link so both gates point at the same official APK.
  UpdateInfo? _latestUpdate;

  /// Integrity verdict (cracked / re-packed / modded build). Null until the
  /// check answers — each leg is bounded and fails open.
  SecurityReport? _security;

  /// Ad-blocker verdict. Null until the check answers — fails open, and
  /// only positive evidence (ads blocked while the network works) locks.
  AdblockReport? _adblock;

  /// Throttle stamp: launch + resume re-checks run at most once a minute
  /// so returning from a settings screen never hammers the probes.
  DateTime? _lastAdblockCheck;

  int _currentBuild = 0;
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
      _checkUpdate(),
      _checkSecurity(),
      _checkAdblock(),
    ]);
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
    _ads.dispose();
    super.dispose();
  }

  /// Asks the backend for a forced update and compares it to this build.
  /// Any failure (offline, collection missing, signed out) = no gate —
  /// a broken check must never brick the launch.
  Future<void> _checkUpdate() async {
    UpdateInfo? info;
    try {
      info = await Backend.checkForcedUpdate().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      info = null;
    }
    var build = 0;
    try {
      final pkg = await PackageInfo.fromPlatform();
      build = int.tryParse(pkg.buildNumber) ?? 0;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _latestUpdate = info;
      _currentBuild = build;
      if (info != null && info.versionCode > build) _pendingUpdate = info;
    });
  }

  /// Signature/debug verdict from the platform side — the modded-build
  /// detector. Fails open on any error so a broken check can't lock out a
  /// legitimate install.
  Future<void> _checkSecurity() async {
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
    // A modified build outranks a newer build: it must not be handed an APK
    // to install over something Android would refuse anyway. The ad-blocker
    // gate ranks last — it's the only one the user can clear in-place.
    final tampered = _security?.blocked ?? false;
    final adBlocked = _adblock?.blocked ?? false;
    final blocked = tampered || _pendingUpdate != null || adBlocked;
    return Stack(
      children: [
        // The gate replaces the entire router — nothing to pop, no UI to
        // reach while a newer build is waiting.
        SafeArea(
          child: blocked
              ? (tampered
                    ? TamperDetectedScreen(
                        info: _latestUpdate,
                        flags: _security?.flags ?? const <String>[],
                      )
                    : _pendingUpdate != null
                    ? UpdateRequiredScreen(
                        info: _pendingUpdate!,
                        currentBuild: _currentBuild,
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
              // Passive app-open ad right after the intro — profit only,
              // never over a gate and never touches the balance.
              if (!blocked) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  try {
                    _ads.showAppOpen();
                  } catch (e) {
                    debugPrint('showAppOpen error: $e');
                  }
                });
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is available here (not in initState) — load the banner once.
    if (!_bannerWanted) {
      _bannerWanted = true;
      _loadBanner();
    }
  }

  @override
  void dispose() {
    _ads.dispose();
    _banner?.dispose();
    super.dispose();
  }

  /// Adaptive banner sized to the screen width, parked above the nav pill.
  Future<void> _loadBanner() async {
    final width = MediaQuery.sizeOf(context).width.round();
    final size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width) ??
        AdSize.banner;
    if (!mounted) return;
    late final BannerAd ad;
    ad = BannerAd(
      adUnitId: AdUnits.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _banner = ad);
        },
        onAdFailedToLoad: (a, _) => a.dispose(),
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
    // ignore: unawaited_futures
    _ads.showInterstitial();
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
