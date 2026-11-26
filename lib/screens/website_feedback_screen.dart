import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/worker_backend.dart';
import '../social_shell.dart';
import '../theme.dart';

/// Public feedback from the website (feedback.php), rendered in-app.
class WebsiteFeedbackScreen extends StatefulWidget {
  const WebsiteFeedbackScreen({super.key, this.load});

  final Future<List<WebsiteFeedback>> Function()? load;

  @override
  State<WebsiteFeedbackScreen> createState() => _WebsiteFeedbackScreenState();
}

class _WebsiteFeedbackScreenState extends State<WebsiteFeedbackScreen> {
  List<WebsiteFeedback> _items = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await (widget.load ?? Backend.publicFeedback)();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: SocialAppBar(title: 'Feedback'),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
        ? EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load feedback',
            action: TextButton(onPressed: _load, child: const Text('Retry')),
          )
        : _items.isEmpty
        ? const EmptyState(
            icon: Icons.feedback_outlined,
            title: 'No feedback yet',
            message: 'Be the first to share feedback on the website.',
          )
        : ListView.separated(
            padding: const EdgeInsets.all(AppSpace.lg),
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
            itemBuilder: (_, i) => _row(_items[i]),
          ),
  );

  Widget _row(WebsiteFeedback item) => GlowCard(
    key: ValueKey('site-feedback-${item.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceHigh,
              child: Text(
                item.username.isEmpty
                    ? '?'
                    : item.username[0].toUpperCase(),
                style: AppText.caption,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                item.username.isEmpty ? 'Member' : item.username,
                style: AppText.subtitle.copyWith(fontSize: 14),
              ),
            ),
            Text('★' * item.rating, style: const TextStyle(color: AppColors.gold)),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(item.comment, style: AppText.body.copyWith(fontSize: 13)),
        if (item.imageUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.input),
              child: CachedNetworkImage(
                imageUrl: item.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (item.createdAt.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            item.createdAt,
            style: AppText.caption.copyWith(color: AppColors.textDim),
          ),
        ],
      ],
    ),
  );
}
