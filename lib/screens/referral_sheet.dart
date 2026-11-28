import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../arcade.dart';
import '../services/distribution.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

/// Share your own code, or enter the code of the person who invited you.
/// The API credits the invitee's referrer — never the person claiming here.
class ReferralSheet extends StatefulWidget {
  const ReferralSheet({
    super.key,
    required this.referralCode,
    required this.onClaim,
  });

  final String referralCode;
  final Future<int> Function(String code) onClaim;

  @override
  State<ReferralSheet> createState() => _ReferralSheetState();
}

class _ReferralSheetState extends State<ReferralSheet> {
  final TextEditingController _code = TextEditingController();
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    if (widget.referralCode.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.referralCode));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Referral code copied')));
  }

  Future<void> _share() async {
    if (widget.referralCode.isEmpty) return;
    await Share.share(
      Backend.referralInviteText(
        referralCode: widget.referralCode,
        isPlay: Distribution.isPlay,
      ),
    );
  }

  Future<void> _claim() async {
    final normalized = Backend.normalizeReferralCode(_code.text);
    if (normalized.isEmpty) {
      setState(() => _error = 'Invalid referral code');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final reward = await widget.onClaim(normalized);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You and your friend earned $reward coins each')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: AppSpace.lg,
      right: AppSpace.lg,
      top: AppSpace.lg,
      bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Referral', style: AppText.title),
        const SizedBox(height: AppSpace.md),
        CardFrame(
          tier: RarityTier.standard,
          radius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your code', style: AppText.label),
                const SizedBox(height: AppSpace.xs),
                Text(
                  widget.referralCode.isEmpty ? '—' : widget.referralCode,
                  style: AppText.subtitle,
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('Copy'),
                    ),
                    TextButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Use a code', style: AppText.label),
        const SizedBox(height: AppSpace.sm),
        TextField(
          key: const Key('referral-code-field'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Referral code',
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            _error,
            style: AppText.caption.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        FilledButton(
          key: const Key('referral-claim-button'),
          onPressed: _busy ? null : _claim,
          child: Text(_busy ? 'Claiming…' : 'Claim'),
        ),
      ],
    ),
  );
}
