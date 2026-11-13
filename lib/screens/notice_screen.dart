import 'dart:async';

import 'package:flutter/material.dart';

import '../premium.dart';
import '../theme.dart';

/// Launch notice: the app and the injector/loader are separate products, and
/// Play ratings must reflect this app only. The close button only unlocks
/// after a 20s read window; skipping hides the notice for 24 hours (persisted
/// by the caller).
///
/// Bilingual on purpose: Tagalog ang default (audience), English ang toggle.
class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

enum _Lang { tl, en }

/// One language's copy. Kept as data so both versions stay in step.
class _Copy {
  const _Copy({
    required this.title,
    required this.paragraphs,
    required this.contactLead,
    required this.contact,
    required this.thanks,
  });

  final String title;
  final List<String> paragraphs;
  final String contactLead;
  final String contact;
  final String thanks;
}

const _tl = _Copy(
  title: 'Paalala bago\nmagpatuloy.',
  paragraphs: [
    'Ang app na ito at ang injector ay magkaibang application at magkahiwalay '
        'silang gumagana.',
    'Ang pangunahing purpose ng app na ito ay para makapag-generate kayo ng '
        'keys. Hindi ito ang mismong injector at wala itong kontrol sa kung '
        'paano gumagana ang loader o injector.',
    'Kung makaranas kayo ng anumang problema, tulad ng bug, error, crash, o '
        'ibang issue habang ginagamit ang loader o injector, tandaan na '
        'hiwalay ang mga ito sa app na ito.',
    'Kung magbibigay kayo ng rating o review sa Play Store, sana ay ibase '
        'ninyo ito sa mismong experience ninyo sa paggamit ng GHOSST app, '
        'tulad ng key generation, login, at iba pang features nito. Huwag '
        'sanang ibase ang rating sa mga problema ng separate loader o injector '
        'dahil magkaiba ang kanilang functions.',
  ],
  contactLead: 'Kung may makita kayong bug o error sa mismong GHOSST app, '
      'maaari kayong direktang makipag-ugnayan sa developer sa Telegram:',
  contact: '@SylvieOfficeal',
  thanks: 'Salamat sa paggamit ng GHOSST at sa patuloy ninyong suporta!',
);

const _en = _Copy(
  title: 'Please read\nbefore continuing.',
  paragraphs: [
    'This app and the injector are two different applications and they work '
        'separately.',
    'The main purpose of this app is to let you generate keys. It is not the '
        'injector itself and it has no control over how the loader or injector '
        'works.',
    'If you run into any problem - a bug, an error, a crash, or any other '
        'issue - while using the loader or injector, remember that those are '
        'separate from this app.',
    'If you leave a rating or review on the Play Store, please base it on your '
        'own experience with the GHOSST app itself: key generation, login, and '
        "its other features. Please don't base your rating on problems from "
        'the separate loader or injector, because their functions are '
        'different.',
  ],
  contactLead: 'If you find a bug or error in the GHOSST app itself, you can '
      'contact the developer directly on Telegram:',
  contact: '@SylvieOfficeal',
  thanks: 'Thank you for using GHOSST and for your continued support!',
);

class _NoticeScreenState extends State<NoticeScreen> {
  static const int _readSeconds = 20;

  int _left = _readSeconds;
  Timer? _timer;
  _Lang _lang = _Lang.tl;

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
    final copy = _lang == _Lang.tl ? _tl : _en;
    final body = AppText.body.copyWith(
      color: AppColors.textDim,
      height: 1.6,
    );

    return PopScope(
      canPop: false,
      // Material ancestor: without it Text merges into the engine's debug
      // fallback style (yellow underline).
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const MeshBackground(),
            SafeArea(
              child: Column(
                children: [
                  // Pinned with the logo: the switch must stay reachable no
                  // matter how far the copy is scrolled.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xl,
                      AppSpace.md,
                      AppSpace.xl,
                      0,
                    ),
                    child: Row(
                      children: [
                        const LogoBadge(size: 32),
                        const Spacer(),
                        _LangToggle(
                          lang: _lang,
                          onChanged: (l) => setState(() => _lang = l),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        AppSpace.lg,
                        AppSpace.xl,
                        AppSpace.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GradientText(
                            copy.title,
                            style: AppText.display.copyWith(
                              fontSize: 30,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                          for (final p in copy.paragraphs) ...[
                            Text(p, style: body),
                            const SizedBox(height: AppSpace.md),
                          ],
                          const SizedBox(height: AppSpace.xs),
                          Text(copy.contactLead, style: body),
                          const SizedBox(height: AppSpace.md),
                          // Handle stands alone so it is easy to copy by eye.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.md,
                                vertical: AppSpace.sm + 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHigh.withValues(
                                  alpha: 0.6,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.input,
                                ),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.send_rounded,
                                    size: AppIcon.sm,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: AppSpace.sm),
                                  Text(
                                    copy.contact,
                                    style: AppText.figure.copyWith(
                                      fontSize: 14,
                                      color: AppColors.cyan,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                          Text(
                            copy.thanks,
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Pinned: the copy is long enough to scroll, and the
                  // countdown must stay visible while it counts down.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xl,
                      AppSpace.sm,
                      AppSpace.xl,
                      AppSpace.xl,
                    ),
                    child: _left > 0
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
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
                            ],
                          )
                        : IslandButton(
                            label: 'Skip for 24 hours',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: widget.onSkip,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tagalog / English switch. Both notices must stay readable, so the reader
/// picks the one they understand.
class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.lang, required this.onChanged});

  final _Lang lang;
  final ValueChanged<_Lang> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'TL',
            selected: lang == _Lang.tl,
            onTap: () => onChanged(_Lang.tl),
          ),
          _Segment(
            label: 'EN',
            selected: lang == _Lang.en,
            onTap: () => onChanged(_Lang.en),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label == 'TL' ? 'Tagalog' : 'English',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: kMotionStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: selected ? AppColors.cyan : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
