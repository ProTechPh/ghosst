import 'package:appwrite/models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../premium.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onSignOut,
    required this.onGoToTab,
  });

  /// Signs out of the session. The shell flips back to the landing page.
  final VoidCallback onSignOut;

  /// Pops this route and activates a bottom-bar tab (e.g. My Keys).
  final void Function(int tab) onGoToTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  int _coins = 0;
  List<Claim> _claims = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      Backend.currentUser().catchError((_) => null),
      Backend.coins().catchError((_) => 0),
      Backend.myClaims().catchError((_) => <Claim>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _user = results[0] as User?;
      _coins = results[1] as int;
      _claims = results[2] as List<Claim>;
      _loading = false;
    });
  }

  int get _spent => _claims.fold(0, (sum, c) => sum + c.cost);

  String get _name {
    final n = _user?.name.trim() ?? '';
    if (n.isNotEmpty) return n;
    final e = _user?.email.trim() ?? '';
    if (e.isNotEmpty) return e.split('@').first;
    return 'Ghosst member';
  }

  String get _email => _user?.email ?? '';

  String get _initial {
    final n = _name.trim();
    return n.isEmpty ? 'G' : n[0].toUpperCase();
  }

  String get _since {
    final created = _user?.$createdAt ?? '';
    return created.length >= 10 ? created.substring(0, 10) : '';
  }

  static const _tiers = [
    (name: 'Newcomer', color: AppColors.textDim, min: 0),
    (name: 'Key Hunter', color: AppColors.cyan, min: 1),
    (name: 'Collector', color: AppColors.primary, min: 3),
    (name: 'Vault Master', color: AppColors.gold, min: 6),
  ];

  int get _tierIndex {
    var idx = 0;
    for (var i = 0; i < _tiers.length; i++) {
      if (_claims.length >= _tiers[i].min) idx = i;
    }
    return idx;
  }

  double get _tierProgress {
    if (_tierIndex >= _tiers.length - 1) return 1;
    final current = _tiers[_tierIndex].min;
    final next = _tiers[_tierIndex + 1].min;
    return ((_claims.length - current) / (next - current)).clamp(0.0, 1.0);
  }

  Future<void> _signOut() async {
    Navigator.of(context).pop();
    widget.onSignOut();
  }

  void _openWallet() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tier = _tiers[_tierIndex];
    final nextTier =
        _tierIndex < _tiers.length - 1 ? _tiers[_tierIndex + 1] : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 20, title: const Text('Profile')),
      body: Stack(
        children: [
          const MeshBackground(),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                // ---- editorial header ------------------------------------
                ScrollReveal(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: kNeonGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 36,
                              spreadRadius: -6,
                            ),
                          ],
                        ),
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surface,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _initial,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Text(
                              _name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                                height: 1.15,
                              ),
                            ),
                            if (_email.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                _email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                            if (_since.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Eyebrow(text: 'Since $_since'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                // ---- asymmetric stats ------------------------------------
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 340;
                    final keysCard = ScrollReveal(
                      delay: const Duration(milliseconds: 120),
                      child: _statCard(
                        label: 'KEYS OWNED',
                        value: '${_claims.length}',
                        color: AppColors.primary,
                        icon: Icons.key_outlined,
                      ),
                    );
                    final column = Column(
                      children: [
                        ScrollReveal(
                          delay: const Duration(milliseconds: 200),
                          child: _statCard(
                            label: 'COINS',
                            value: '$_coins',
                            color: AppColors.gold,
                            icon: Icons.monetization_on_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ScrollReveal(
                          delay: const Duration(milliseconds: 280),
                          child: _statCard(
                            label: 'SPENT',
                            value: '$_spent',
                            color: AppColors.red,
                            icon: Icons.trending_down_outlined,
                          ),
                        ),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          keysCard,
                          const SizedBox(height: 12),
                          column,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 12, child: keysCard),
                        const SizedBox(width: 12),
                        Expanded(flex: 10, child: column),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ---- collection tier -------------------------------------
                ScrollReveal(
                  delay: const Duration(milliseconds: 200),
                  child: DoubleBezel(
                    padding: const EdgeInsets.all(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0E2229), Color(0xFF07161B)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tier.color.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: tier.color.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Icon(
                                Icons.workspace_premium_outlined,
                                size: 20,
                                color: tier.color,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'COLLECTION TIER',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.2,
                                      color: AppColors.textDim,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    tier.name,
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      color: tier.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: _tierProgress),
                          duration: const Duration(milliseconds: 1100),
                          curve: kPremiumCurve,
                          builder: (context, value, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: Stack(
                              children: [
                                Container(
                                  height: 6,
                                  color: Colors.white.withValues(alpha: 0.07),
                                ),
                                FractionallySizedBox(
                                  widthFactor: value,
                                  child: Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                      gradient: kNeonGradient,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          nextTier == null
                              ? 'Top tier reached · ${_claims.length} keys collected'
                              : '${nextTier.min - _claims.length} more '
                                  'key${nextTier.min - _claims.length == 1 ? '' : 's'} '
                                  'to ${nextTier.name}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),

                // ---- menu rows -------------------------------------------
                const ScrollReveal(
                  delay: Duration(milliseconds: 120),
                  child: SectionLabel('ACCOUNT'),
                ),
                const SizedBox(height: 14),
                ScrollReveal(
                  delay: const Duration(milliseconds: 180),
                  child: DoubleBezel(
                    radius: 24,
                    outerPadding: const EdgeInsets.all(5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Column(
                      children: [
                        _menuRow(
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppColors.gold,
                          label: 'Wallet',
                          hint: '$_coins coins',
                          onTap: _openWallet,
                        ),
                        Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        _menuRow(
                          icon: Icons.key_outlined,
                          color: AppColors.primary,
                          label: 'My Keys',
                          hint: '${_claims.length} claimed',
                          onTap: () => widget.onGoToTab(2),
                        ),
                        Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        _menuRow(
                          icon: Icons.logout_rounded,
                          color: AppColors.red,
                          label: 'Sign out',
                          onTap: _signOut,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Center(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final info = snap.data;
                      return Text(
                        info == null
                            ? 'GHOSST'
                            : 'GHOSST · v${info.version}+${info.buildNumber}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4,
                          color: AppColors.textDim,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return DoubleBezel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: AppColors.textDim,
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.10),
                  border: Border.all(color: color.withValues(alpha: 0.30)),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required Color color,
    required String label,
    String? hint,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.10),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 15,
              color: AppColors.textDim.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
