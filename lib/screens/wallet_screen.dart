import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/backend.dart';
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

/// Coin history / wallet — asymmetric bento + activity timeline.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>([
      Backend.coins().catchError((_) => 0),
      Backend.myClaims().catchError((_) => <Claim>[]),
      Backend.myAdRewards().catchError((_) => <AdReward>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _balance = results[0] as int;
      _claims = results[1] as List<Claim>;
      _rewards = results[2] as List<AdReward>;
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
            const Center(child: CircularProgressIndicator())
          else
            SafeArea(
              top: false,
              child: RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.surface,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    // ---- hero balance ------------------------------------
                    ScrollReveal(
                      child: DoubleBezel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 24,
                        ),
                        glowColor: AppColors.gold,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL BALANCE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.2,
                                      color: AppColors.textDim,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      AnimatedCounter(
                                        value: _balance,
                                        style: const TextStyle(
                                          fontSize: 44,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.gold,
                                          height: 1.05,
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.only(
                                          left: 8,
                                          bottom: 7,
                                        ),
                                        child: Text(
                                          'coins',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textDim,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFDE68A),
                                    Color(0xFFF59E0B),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gold.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 34,
                                    spreadRadius: -6,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.monetization_on_outlined,
                                color: Color(0xFF1F1403),
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---- asymmetric stats bento --------------------------
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 340;
                        final tall = ScrollReveal(
                          delay: const Duration(milliseconds: 120),
                          child: _earnedCard(),
                        );
                        final column = Column(
                          children: [
                            ScrollReveal(
                              delay: const Duration(milliseconds: 200),
                              child: _miniCard(
                                label: 'SPENT',
                                value: '$_spent',
                                color: AppColors.red,
                                icon: Icons.trending_down_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ScrollReveal(
                              delay: const Duration(milliseconds: 280),
                              child: _miniCard(
                                label: 'KEYS CLAIMED',
                                value: '${_claims.length}',
                                color: AppColors.primary,
                                icon: Icons.key_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ScrollReveal(
                              delay: const Duration(milliseconds: 360),
                              child: _miniCard(
                                label: 'APPS OWNED',
                                value: '$_appsOwned',
                                color: AppColors.green,
                                icon: Icons.phone_iphone_rounded,
                              ),
                            ),
                          ],
                        );
                        if (narrow) {
                          return Column(
                            children: [
                              tall,
                              const SizedBox(height: 12),
                              column,
                            ],
                          );
                        }
                        // Stretch both columns to a shared height so the
                        // earned card fills the column instead of leaving a
                        // hole above the third mini stat.
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 13, child: tall),
                              const SizedBox(width: 12),
                              Expanded(flex: 10, child: column),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 30),

                    // ---- activity timeline -------------------------------
                    const ScrollReveal(
                      delay: Duration(milliseconds: 120),
                      child: SectionLabel('ACTIVITY'),
                    ),
                    const SizedBox(height: 14),
                    if (_timeline.isEmpty)
                      const ScrollReveal(
                        child: EmptyState(
                          icon: Icons.history,
                          title: 'No activity yet',
                          message: 'Watch ads to earn coins, then claim your first key.',
                        ),
                      )
                    else
                      for (var i = 0; i < _timeline.length && i < 40; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ScrollReveal(
                            delay: Duration(
                              milliseconds: 60 * i > 400 ? 400 : 60 * i,
                            ),
                            child: _txRow(_timeline[i]),
                          ),
                        ),

                    // ---- earn CTA ----------------------------------------
                    if (widget.onGoToEarn != null) ...[
                      const SizedBox(height: 22),
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

  Widget _earnedCard() {
    final ratio = _earnedEst == 0 ? 0.0 : _spent / _earnedEst;
    return DoubleBezel(
      padding: const EdgeInsets.all(20),
      // Two groups + spaceBetween: identical in loose height, and when the
      // stats row stretches this card the bar drops to the bottom edge.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'EARNED (EST.)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedCounter(
                value: _earnedEst,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cyan,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'balance + everything spent',
                style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 18),
              // spent-vs-kept hairline bar
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Stack(
                  children: [
                    Container(
                      height: 5,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio.clamp(0.0, 1.0),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          gradient: kNeonGradient,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(ratio * 100).round()}% spent',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textDim,
                    ),
                  ),
                  Text(
                    '${100 - (ratio * 100).round()}% kept',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return DoubleBezel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: AppColors.textDim,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.30)),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ],
      ),
    );
  }

  Widget _txRow(_Tx tx) {
    final color = tx.earn ? AppColors.cyan : AppColors.primary;
    return DoubleBezel(
      radius: 24,
      outerPadding: const EdgeInsets.all(5),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Icon(
              tx.earn ? Icons.play_circle_outline : Icons.key_outlined,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${tx.date} · ${tx.subtitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${tx.amount > 0 ? '+' : ''}${tx.amount}',
            style: monoStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tx.amount > 0 ? AppColors.green : AppColors.red,
            ),
          ),
        ],
      ),
    );
  }
}
