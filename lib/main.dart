import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'premium.dart';
import 'screens/admin_screen.dart';
import 'screens/earn_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/my_keys_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/store_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/backend.dart';
import 'sign_in.dart';
import 'sign_up.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
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
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: const _AppEntry(),
      ),
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

class _AppEntryState extends State<_AppEntry> {
  bool _splash = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SafeArea(child: Router()),
        if (_splash)
          SplashScreen(onDone: () => setState(() => _splash = false)),
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait<Object>([
      Backend.coins().catchError((_) => 0),
      Backend.isAdmin().catchError((_) => false),
      Backend.currentUser()
          .then((u) => (u?.name.isNotEmpty ?? false) ? u!.name : (u?.email ?? ''))
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
      _NavItem(Icons.key_outlined, Icons.key, 'My Keys'),
      if (isAdmin)
        _NavItem(
            Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'Admin'),
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
                child: CoinPill(
                  coins: coins,
                  onTap: _openWallet,
                ),
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
          body: IndexedStack(
            index: safeIndex,
            children: pages,
          ),
          // Floating glass pill — never an edge-to-edge Material bar.
          bottomNavigationBar: _GlassNavBar(
            index: safeIndex,
            items: destinations,
            onSelected: (i) => setState(() => tab = i),
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
