import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_exception.dart';

import '../premium.dart';
import '../services/worker_backend.dart';
import '../social_shell.dart';
import '../theme.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.submit, this.loadMine});

  final Future<String> Function(
    String comment,
    int rating,
    String idempotencyKey,
  )?
  submit;
  final Future<List<AppFeedback>> Function()? loadMine;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  bool _submitted = false;
  String _submitError = '';
  String? _idempotencyKey;
  List<AppFeedback> _history = const [];
  bool _historyLoading = true;
  bool _historyFailed = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyFailed = false;
    });
    try {
      final rows = await (widget.loadMine ?? Backend.myFeedback)();
      if (mounted) {
        setState(() {
          _history = rows;
          _historyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyLoading = false;
          _historyFailed = true;
        });
      }
    }
  }

  bool get _canSubmit =>
      !_submitting && validateAppFeedback(_comment.text, _rating) == null;

  String _newIdempotencyKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final key = _idempotencyKey ??= _newIdempotencyKey();
    setState(() {
      _submitting = true;
      _submitted = false;
      _submitError = '';
    });
    try {
      if (widget.submit != null) {
        await widget.submit!(_comment.text.trim(), _rating, key);
      } else {
        await Backend.submitFeedback(
          comment: _comment.text.trim(),
          rating: _rating,
          idempotencyKey: key,
        );
      }
      if (!mounted) return;
      _comment.clear();
      setState(() {
        _rating = 0;
        _idempotencyKey = null;
        _submitting = false;
        _submitted = true;
      });
      await _loadHistory();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = e.code == 'rate_limited' ? e.message : e.userMessage;
        });
      }
    } catch (e) {
      debugPrint('[Feedback] submit failed: $e');
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = kDebugMode
              ? 'Could not send feedback: $e'
              : 'Could not send feedback. Your message is still here.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const SocialAppBar(title: 'Send feedback'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.xxl,
        ),
        children: [
          GlowCard(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feedback is private to the Ghosst team.',
                  style: AppText.subtitle,
                ),
                SizedBox(height: AppSpace.xs),
                Text(
                  'Tell us what worked, what broke, or what you want next.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('Rating', style: AppText.subtitle),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: 'Rate $star star${star == 1 ? '' : 's'}',
                  onPressed: _submitting
                      ? null
                      : () {
                          setState(() {
                            _rating = star;
                            if (_submitError.isNotEmpty) _idempotencyKey = null;
                          });
                        },
                  icon: Semantics(
                    selected: star <= _rating,
                    label: 'Rating $star of 5',
                    child: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: star <= _rating
                          ? AppColors.gold
                          : AppColors.textDim,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _comment,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            enabled: !_submitting,
            onChanged: (_) => setState(() {
              if (_submitError.isNotEmpty) _idempotencyKey = null;
            }),
            decoration: const InputDecoration(
              labelText: 'Comment',
              hintText: 'At least 10 characters',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit feedback'),
          ),
          if (_submitError.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Semantics(
              liveRegion: true,
              child: Text(
                _submitError,
                style: const TextStyle(color: AppColors.red),
              ),
            ),
            TextButton(onPressed: _submit, child: const Text('Retry')),
          ],
          if (_submitted) ...[
            const SizedBox(height: AppSpace.md),
            Semantics(
              liveRegion: true,
              child: const Text(
                'Thank you for your feedback.',
                style: TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xxl),
          const SectionHeader(title: 'Your feedback'),
          const SizedBox(height: AppSpace.sm),
          if (_historyLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Center(child: Text('Loading feedback…')),
            )
          else if (_historyFailed)
            EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load feedback history',
              action: TextButton(
                onPressed: _loadHistory,
                child: const Text('Retry'),
              ),
            )
          else if (_history.isEmpty)
            const EmptyState(
              icon: Icons.feedback_outlined,
              title: 'No feedback submitted yet',
            )
          else
            for (final item in _history)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: GlowCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${item.rating}/5', style: AppText.subtitle),
                          const Spacer(),
                          Text(item.createdAt, style: AppText.caption),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(item.comment, style: AppText.caption),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
