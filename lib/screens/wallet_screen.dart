import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

/// One merged timeline entry (ad reward or key claim).
class _Tx {
  _Tx({
    required this.amount,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.earn,
  });

  final int amount;
  final String title;
  final String subtitle;
  final String date;
  final bool earn;
}

/// Coin history / wallet — balance hero, metrics strip, date-grouped ledger.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.onGoToEarn});

  /// Optional CTA that pops back and jumps to the Earn tab.
  final VoidCallback? onGoToEarn;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  int _balance = 0;
  List<Claim> _claims = [];
  List<AdReward> _rewards = [];
  bool _loading = true;

  /// Set when the balance could not be read — the last known value stays up.
  String _balanceError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var balance = _balance;
    var balanceError = '';
    try {
      balance = await Backend.coins();
    } catch (e) {
      // A failed fetch must not read as "0 coins" — that flips the UI to
      // "not enough" everywhere.
      balanceError = '$e';
    }
    final results = await Future.wait<Object>([
      Backend.myClaims().catchError((_) => <Claim>[]),
      Backend.myAdRewards().catchError((_) => <AdReward>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _balanceError = balanceError;
      _claims = results[0] as List<Claim>;
      _rewards = results[1] as List<AdReward>;
      _loading = false;
    });
  }

  int get _spent => _claims.fold(0, (sum, c) => sum + c.cost);

  /// balance + total spent reconstructs lifetime earnings even while the
  /// `ad_rewards` collection stays server-side only.
  int get _earnedEst => _balance + _spent;

  /// Distinct apps/files purchased — download claims grouped by product.
  int get _appsOwned =>
      _claims.where((c) => c.isDownload).map((c) => c.productId).toSet().length;

  List<_Tx> get _timeline {
    final entries = <_Tx>[
      for (final c in _claims)
        _Tx(
          amount: -c.cost,
          title: c.productName.isEmpty ? 'License key' : c.productName,
          subtitle: 'Key claimed',
          date: _date(c.createdAt),
          earn: false,
        ),
      for (final r in _rewards)
        _Tx(
          amount: r.reward,
          title: 'Ad reward',
          subtitle: 'Rewarded ad watched',
          date: _date(r.createdAt),
          earn: true,
        ),
    ];
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 20, title: const Text('Wallet')),
      body: Stack(
        children: [
          const MeshBackground(),
          if (_loading)
            _loadingView()
          else
            SafeArea(
              top: false,
              child: RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.surface,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.md,
                    AppSpace.lg,
                    AppSpace.huge,
                  ),
                  children: [
                    if (_balanceError.isNotEmpty) ...[
                      _errorBanner(),
                      const SizedBox(height: AppSpace.md),
                    ],
                    ScrollReveal(child: _hero()),
                    const SizedBox(height: AppSpace.md),
                    ScrollReveal(
                      delay: const Duration(milliseconds: 120),
                      child: _spentBar(),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    ScrollReveal(
                      delay: const Duration(milliseconds: 200),
                      child: _metrics(),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    const ScrollReveal(
                      delay: Duration(milliseconds: 120),
                      child: SectionHeader(title: 'Activity'),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    if (_timeline.isEmpty)
                      const ScrollReveal(
                        child: EmptyState(
                          icon: Icons.history,
                          title: 'No activity yet',
                          message:
                              'Watch ads to earn coins, then claim your first key.',
                        ),
                      )
                    else
                      ..._activity(),
                    if (widget.onGoToEarn != null) ...[
                      const SizedBox(height: AppSpace.xl),
                      ScrollReveal(
                        delay: const Duration(milliseconds: 200),
                        child: IslandButton(
                          label: 'Watch ads to earn',
                          icon: CupertinoIcons.play_rectangle,
                          outline: true,
                          glow: false,
                          onPressed: widget.onGoToEarn,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _loadingView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.huge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(height: 158, radius: AppRadius.hero),
          const SizedBox(height: AppSpace.lg),
          const Skeleton(height: 54, radius: AppRadius.card),
          const SizedBox(height: AppSpace.xl),
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpace.sm),
              child: Skeleton(height: 62, radius: AppRadius.input),
            ),
        ],
      ),
    );
  }

  /// Inline banner — the balance and the activity below keep their last
  /// known values instead of being replaced by a full-screen error.
  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md + 2,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.red),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Balance may be out of date. $_balanceError',
              style: AppText.caption.copyWith(
                fontSize: 12,
                color: AppColors.red,
                height: 1.4,
              ),
            ),
          ),
          Pressable(
            onTap: _load,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.xs + 2,
              ),
              child: Text(
                'RETRY',
                style: AppText.label.copyWith(color: AppColors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- hero -------------------------------------------------------------

  Widget _hero() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B242C), Color(0xFF051216)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.14),
            blurRadius: 30,
            spreadRadius: -10,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: -60,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18),
                        AppColors.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.xl,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 14,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: AppSpace.xs + 2),
                      Text(
                        'BALANCE',
                        style: AppText.label.copyWith(color: AppColors.textDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AnimatedCounter(
                            value: _balance,
                            style: AppText.figure.copyWith(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: -2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      StatCell(
                        label: 'Spent',
                        value: groupDigits(_spent),
                        color: AppColors.textDim,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs + 2),
                  Text('coins', style: AppText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spentBar() {
    final ratio = _earnedEst == 0 ? 0.0 : _spent / _earnedEst;
    final pct = (ratio * 100).round().clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Stack(
            children: [
              Container(height: 4, color: AppColors.border),
              FractionallySizedBox(
                widthFactor: ratio.clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: const BoxDecoration(gradient: kNeonGradient),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$pct% spent', style: AppText.caption.copyWith(fontSize: 11)),
            Text(
              '${100 - pct}% kept',
              style: AppText.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metrics() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
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
              label: 'Earned est.',
              value: groupDigits(_earnedEst),
              icon: Icons.trending_up_rounded,
              color: AppColors.cyan,
            ),
          ),
          _divider(),
          Expanded(
            child: StatCell(
              label: 'Keys',
              value: '${_claims.length}',
              icon: Icons.key_outlined,
            ),
          ),
          _divider(),
          Expanded(
            child: StatCell(
              label: 'Apps',
              value: '$_appsOwned',
              icon: Icons.phone_iphone_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
    color: AppColors.border,
  );

  // ---- activity ---------------------------------------------------------

  List<Widget> _activity() {
    final rows = <Widget>[];
    final timeline = _timeline;
    String? lastDate;
    for (var i = 0; i < timeline.length && i < 40; i++) {
      final tx = timeline[i];
      if (tx.date != lastDate) {
        lastDate = tx.date;
        rows.add(
          Padding(
            padding: EdgeInsets.only(
              top: rows.isEmpty ? AppSpace.sm : AppSpace.lg,
              bottom: AppSpace.xs,
            ),
            child: Text(
              tx.date,
              style: monoStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: AppColors.textDim,
              ),
            ),
          ),
        );
      }
      rows.add(_txRow(tx));
    }
    return rows;
  }

  Widget _txRow(_Tx tx) {
    final tone = tx.earn ? AppColors.cyan : AppColors.textDim;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.withValues(alpha: 0.10),
                border: Border.all(color: tone.withValues(alpha: 0.26)),
              ),
              child: Icon(
                tx.earn ? Icons.play_arrow_rounded : Icons.key_outlined,
                size: 17,
                color: tone,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(fontSize: 14.5),
                  ),
                  const SizedBox(height: 2),
                  Text(tx.subtitle, style: AppText.caption),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Text(
              '${tx.amount > 0 ? '+' : '−'}${groupDigits(tx.amount.abs())}',
              style: monoStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tx.earn ? AppColors.cyan : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
