import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../arcade.dart';
import '../premium.dart';
import '../services/ad_service.dart';
import '../services/worker_backend.dart';
import '../services/consent_service.dart';
import '../services/distribution.dart';
import '../services/play_store.dart';
import '../theme.dart';
import 'my_apps_screen.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onSignOut,
    required this.onAccountDeleted,
    required this.onGoToTab,
  });

  /// Signs out of the session. The shell flips back to the landing page.
  final VoidCallback onSignOut;

  /// Returns the shell to its signed-out state after permanent deletion.
  final VoidCallback onAccountDeleted;

  /// Pops this route and activates a bottom-bar tab (e.g. My Purchases).
  final void Function(int tab) onGoToTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUser? _user;
  int _coins = 0;
  List<Claim> _claims = [];
  bool _loading = true;

  /// Set when the coin balance could not be read; [_coins] keeps the last
  /// known value instead of dropping to 0.
  String _coinsError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var coins = _coins;
    var coinsError = '';
    try {
      coins = await Backend.coins();
    } catch (e) {
      coinsError = '$e';
    }
    final results = await Future.wait<Object?>([
      Backend.currentUser().catchError((_) => null),
      Backend.myClaims().catchError((_) => <Claim>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _user = results[0] as AppUser?;
      _coins = coins;
      _coinsError = coinsError;
      _claims = results[1] as List<Claim>;
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

  /// Distinct apps/files purchased — download claims grouped by product.
  int get _appsOwned =>
      _claims.where((c) => c.isDownload).map((c) => c.productId).toSet().length;

  Future<void> _signOut() async {
    Navigator.of(context).pop();
    widget.onSignOut();
  }

  /// Play shows its own full-screen flow when there is an update; otherwise
  /// say so instead of leaving the tap with no feedback.
  Future<void> _checkForUpdate() async {
    final started = await PlayStore.checkForUpdate();
    if (!mounted || started) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Distribution.isPlay
              ? "You're on the latest version."
              : 'Updates come from the Play Store build.',
        ),
      ),
    );
  }

  Future<void> _privacyChoices() async {
    final required = await ConsentService.privacyOptionsRequired();
    if (!mounted) return;
    if (!required) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No additional ad privacy choices are required in your region.',
          ),
        ),
      );
      return;
    }
    final error = await ConsentService.showPrivacyOptions();
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open privacy choices: ${error.message}'),
          ),
        );
      }
    } else {
      final permitted = await ConsentService.canRequestAds();
      if (permitted && !AdService.adsEnabled) {
        try {
          await AdService.instance.initialize();
          unawaited(AdService.instance.preload());
          unawaited(AdService.instance.preloadInterstitial());
        } catch (e) {
          debugPrint(
            '[Consent] Error initializing ads after consent update: $e',
          );
        }
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    await launchUrl(
      Uri.parse('https://protechph.github.io/ghosst/'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _deleteAccount() async {
    var confirmed = false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.red),
          title: const Text('Delete account permanently?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your account, coin balance, ad-reward history, and purchase records. This cannot be undone.',
                style: TextStyle(color: AppColors.textDim, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Text('Type DELETE to confirm.'),
              const SizedBox(height: 8),
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (value) =>
                    setDialogState(() => confirmed = value.trim() == 'DELETE'),
                decoration: const InputDecoration(hintText: 'DELETE'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: confirmed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await Backend.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pop(); // progress
      Navigator.of(context).pop(); // profile
      widget.onAccountDeleted();
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account could not be deleted: $error')),
      );
    }
  }

  void _openWallet() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WalletScreen()));
  }

  void _openAppOwned() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MyAppsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: AppSpace.lg,
        title: const Text('Profile', style: AppText.title),
      ),
      body: Stack(
        children: [
          const MeshBackground(),
          const Positioned.fill(
            child: IgnorePointer(child: TableSurface()),
          ),
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg + 2,
                AppSpace.md,
                AppSpace.lg + 2,
                AppSpace.huge,
              ),
              children: [
                if (_coinsError.isNotEmpty) ...[
                  _coinsBanner(),
                  const SizedBox(height: AppSpace.lg),
                ],
                ScrollReveal(
                  child: CardFrame(
                    tier: RarityTier.standard,
                    radius: AppRadius.hero,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: _header(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                ScrollReveal(
                  delay: const Duration(milliseconds: 100),
                  child: _stats(),
                ),
                const SizedBox(height: AppSpace.xxl),

                const SectionHeader(title: 'Account'),
                const SizedBox(height: AppSpace.sm),
                _group([
                  _row(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    hint: '${groupDigits(_coins)} coins',
                    onTap: _openWallet,
                  ),
                  _row(
                    icon: Icons.shopping_bag_outlined,
                    label: 'My Purchases',
                    hint: '${groupDigits(_claims.length)} claimed',
                    onTap: () => widget.onGoToTab(2),
                  ),
                  if (Distribution.showsDownloadStore)
                    _row(
                      icon: Icons.phone_iphone_rounded,
                      label: 'App Owned',
                      hint: '${groupDigits(_appsOwned)} claimed',
                      onTap: _openAppOwned,
                    ),
                  _row(
                    icon: Icons.logout_rounded,
                    label: 'Sign out',
                    onTap: _signOut,
                  ),
                ]),
                const SizedBox(height: AppSpace.xl),

                const SectionHeader(title: 'App'),
                const SizedBox(height: AppSpace.sm),
                _group([
                  _row(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy choices',
                    onTap: _privacyChoices,
                  ),
                  _row(
                    icon: Icons.star_outline_rounded,
                    label: 'Rate us on Play Store',
                    onTap: PlayStore.rate,
                  ),
                  _row(
                    icon: Icons.system_update_alt_rounded,
                    label: 'Check for updates',
                    onTap: _checkForUpdate,
                  ),
                ]),
                const SizedBox(height: AppSpace.xl),

                const SectionHeader(title: 'Legal'),
                const SizedBox(height: AppSpace.sm),
                _group([
                  _row(
                    icon: Icons.policy_outlined,
                    label: 'Privacy policy',
                    onTap: _openPrivacyPolicy,
                  ),
                ]),
                const SizedBox(height: AppSpace.xxl),

                // Destructive, kept apart from every other row.
                _deleteBlock(),
                const SizedBox(height: AppSpace.xl),
                Center(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final info = snap.data;
                      return Text(
                        info == null
                            ? 'GHOSST'
                            : 'GHOSST · v${info.version}+${info.buildNumber}',
                        style: AppText.label.copyWith(
                          fontSize: 10,
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

  Widget _coinsBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md - 2,
        AppSpace.sm,
        AppSpace.md - 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Coins may be out of date. $_coinsError',
              style: AppText.caption.copyWith(color: AppColors.red),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: kNeonGradient,
            // Squircle, not a circle — it belongs to the same radius family
            // as the cards around it.
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.30),
                blurRadius: 30,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card - 2),
            ),
            child: Text(
              _initial,
              style: AppText.headline.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.title.copyWith(fontSize: 22),
              ),
              if (_email.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  _email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _stats() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatCell(
              label: 'Coins',
              value: groupDigits(_coins),
              icon: Icons.monetization_on_rounded,
              color: AppColors.gold,
            ),
          ),
          _statDivider(),
          Expanded(
            child: StatCell(
              label: 'Keys',
              value: groupDigits(_claims.length),
              icon: Icons.key_rounded,
              color: AppColors.primary,
            ),
          ),
          _statDivider(),
          Expanded(
            child: StatCell(
              label: 'Spent',
              value: groupDigits(_spent),
              icon: Icons.trending_down_rounded,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      color: AppColors.border,
    );
  }

  /// Grouped settings: one surface, hairline separators between rows.
  Widget _group(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
        );
      }
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    String? hint,
    required VoidCallback onTap,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md + 2,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textDim),
              const SizedBox(width: AppSpace.md + 2),
              Expanded(
                child: Text(
                  label,
                  style: AppText.subtitle.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hint != null) Text(hint, style: AppText.caption),
              const SizedBox(width: AppSpace.sm),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: AppColors.textDim.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deleteBlock() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _deleteAccount,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              children: [
                const Icon(
                  Icons.delete_forever_outlined,
                  size: 20,
                  color: AppColors.red,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delete account',
                        style: AppText.subtitle.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Permanently erases your coins, keys and history.',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: AppColors.red.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
