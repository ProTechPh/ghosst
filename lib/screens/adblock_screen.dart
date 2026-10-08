import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/adblock_detector.dart';
import '../theme.dart';

/// Full-screen, un-skippable ad-blocker gate.
///
/// Replaces the entire app tree at launch (and on re-check) when
/// [AdblockReport.blocked] says this device is filtering ads. Same shape as
/// `TamperDetectedScreen`: no route to pop, no close button — the only way
/// out is letting the ads load again. The "Check again" button re-runs the
/// probe; when it comes back clean the parent swaps the router back in.
class AdblockScreen extends StatefulWidget {
  const AdblockScreen({
    super.key,
    required this.report,
    required this.recheck,
    required this.onResult,
  });

  /// Current verdict — refreshed by the parent whenever [onResult] fires.
  final AdblockReport report;

  /// Fresh probe (unthrottled — this is a deliberate user action).
  final Future<AdblockReport> Function() recheck;

  /// Hands every re-check verdict back to the parent, which keeps the gate
  /// up (new reasons) or lifts it (clean report).
  final ValueChanged<AdblockReport> onResult;

  @override
  State<AdblockScreen> createState() => _AdblockScreenState();
}

class _AdblockScreenState extends State<AdblockScreen> {
  bool _busy = false;

  Future<void> _again() async {
    setState(() => _busy = true);
    var result = widget.report;
    try {
      result = await widget.recheck();
    } catch (_) {
      // A broken probe can't unlock — keep the verdict we already have.
    }
    widget.onResult(result);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final reasons = widget.report.flags.isEmpty
        ? <String>['Ads can’t reach their servers from this device']
        : widget.report.flags.map(adblockReason).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const MeshBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Ad blocker'),
                      const Text(
                        'Ad blocker detected',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ghosst is free because of ads — ads pay for the '
                        'keys, coins and hosting. This device is blocking '
                        'them, so the app stays locked until they can load '
                        'again. Nothing is lost: your account, keys and '
                        'coins stay exactly where they are.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- what tripped the check ----
                      DoubleBezel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Why you see this'),
                            const SizedBox(height: 10),
                            for (var i = 0; i < reasons.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.gpp_maybe_outlined,
                                    size: 15,
                                    color: AppColors.gold,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      reasons[i],
                                      style: const TextStyle(
                                        color: AppColors.text,
                                        fontSize: 13.5,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ---- how to get back in ----
                      DoubleBezel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('Get back in'),
                            const SizedBox(height: 10),
                            const _Step(
                              n: 1,
                              text: 'Turn off your ad blocker — disable '
                                  'AdGuard, Blokada, NextDNS or any '
                                  'hosts/VPN filter for Ghosst.',
                            ),
                            const SizedBox(height: 8),
                            const _Step(
                              n: 2,
                              text: 'If Private DNS uses a custom server, '
                                   'set it back to Automatic — Settings › '
                                   'Network & internet › Private DNS.',
                            ),
                            const SizedBox(height: 8),
                            const _Step(
                              n: 3,
                              text: 'Tap Check again — the app unlocks as '
                                   'soon as ads can load.',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),
                      IslandButton(
                        expand: true,
                        label: _busy ? 'Checking…' : 'Check again',
                        icon: Icons.refresh_rounded,
                        busy: _busy,
                        onPressed: _busy ? null : _again,
                      ),
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'ADS KEEP GHOSST FREE · YOUR KEYS AND COINS '
                          'STAY WHILE YOU FIX THIS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            color: AppColors.textDim,
                          ),
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
    );
  }
}

/// Numbered instruction line — mono index, human copy (same shape as the
/// tamper/update gates).
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '0$n',
          style: monoStyle(fontSize: 12, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
