import 'dart:async';

import 'package:flutter/material.dart';

import '../premium.dart';
import '../theme.dart';

/// Launch notice: Ghosst sells keys and files, it is not an injector/cheat.
/// The close button only unlocks after a 20s read window; skipping hides the
/// notice for 24 hours (persisted by the caller).
class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  static const int _readSeconds = 20;

  int _left = _readSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          const MeshBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - AppSpace.xl * 2,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow(text: 'Read this first'),
                        const Spacer(),
                        const LogoBadge(size: 64),
                        const SizedBox(height: AppSpace.xl),
                        GradientText(
                          'Not an injector.\nNot a cheat.',
                          style: AppText.display,
                        ),
                        const SizedBox(height: AppSpace.lg),
                        Text(
                          'Ghosst only sells license keys and hosts app/file '
                          'downloads. We are not a cheat, mod menu, or '
                          'injector, and other apps or pages using a similar '
                          'name are not us.',
                          style: AppText.body.copyWith(
                            color: AppColors.textDim,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text(
                          'Never give your Ghosst password to anyone.',
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        const Spacer(),
                        if (_left > 0) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: LinearProgressIndicator(
                              value: _left / _readSeconds,
                              minHeight: 3,
                              backgroundColor: AppColors.border,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Text(
                            'Close unlocks in ${_left}s',
                            style: AppText.caption,
                          ),
                        ] else
                          IslandButton(
                            label: 'Skip for 24 hours',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: widget.onSkip,
                          ),
                      ],
                    ),
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
