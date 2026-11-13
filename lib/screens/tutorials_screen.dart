import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../services/worker_backend.dart';
import '../services/youtube.dart';
import '../theme.dart';

/// 16:9 YouTube poster (or a text-guide fallback) with a play affordance.
class TutorialThumb extends StatelessWidget {
  const TutorialThumb({super.key, required this.videoUrl, this.playSize = 46});

  final String videoUrl;
  final double playSize;

  @override
  Widget build(BuildContext context) {
    final id = youtubeId(videoUrl);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (id != null)
            CachedNetworkImage(
              imageUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
              fit: BoxFit.cover,
              memCacheWidth: 480,
              memCacheHeight: 360,
              errorWidget: (context, url, error) =>
                  const ColoredBox(color: Colors.black),
            )
          else
            ColoredBox(
              color: AppColors.surfaceHigh,
              child: Center(
                child: Icon(
                  Icons.article_outlined,
                  size: 30,
                  color: AppColors.cyan.withValues(alpha: 0.7),
                ),
              ),
            ),
          if (id != null) ...[
            const ColoredBox(color: Color(0x2E000000)),
            Center(
              child: Container(
                width: playSize,
                height: playSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.62),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: playSize * 0.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tutorial tile: poster + category + title + reads.
class TutorialCard extends StatelessWidget {
  const TutorialCard({super.key, required this.tutorial, this.width});

  final Tutorial tutorial;

  /// Fixed width for the horizontal shelf on the home tab.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TutorialDetailScreen(tutorial: tutorial),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TutorialThumb(videoUrl: tutorial.videoUrl),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tutorial.category.toUpperCase(),
                    style: AppText.label.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      color: AppColors.cyan,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tutorial.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${groupDigits(tutorial.views)} reads',
                    style: AppText.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Tutorials ni-publish sa website CMS (`/v1/tutorials`) — isang lugar lang
/// ang ina-update ng admin, automatic na lumalabas dito at sa home shelf.
class TutorialsScreen extends StatefulWidget {
  const TutorialsScreen({
    super.key,
    this.load,
    this.embedded = false,
    this.active = true,
  });

  /// Injectable for tests; defaults to the API.
  final Future<List<Tutorial>> Function()? load;

  /// True when shown as a shell tab (the shell supplies the bar).
  final bool embedded;

  /// False while hidden inside `IndexedStack` — defers the fetch until the
  /// tab is first opened (same gate as the News/Chat tabs).
  final bool active;

  @override
  State<TutorialsScreen> createState() => _TutorialsScreenState();
}

class _TutorialsScreenState extends State<TutorialsScreen> {
  List<Tutorial> items = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant TutorialsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    final loaded = await (widget.load ?? Backend.tutorials)();
    if (!mounted) return;
    setState(() {
      items = loaded;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = loading
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty
        ? const EmptyState(
            icon: Icons.play_circle_outline_rounded,
            title: 'No tutorials yet',
            message: 'Check back later for guides.',
          )
        : ScrollDownCue(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.xxl,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpace.lg),
              itemBuilder: (_, i) => TutorialCard(tutorial: items[i]),
            ),
          );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Tutorials')),
      body: body,
    );
  }
}

/// One tutorial: poster (tap = YouTube), title, meta, and the CMS body text.
class TutorialDetailScreen extends StatelessWidget {
  const TutorialDetailScreen({super.key, required this.tutorial});

  final Tutorial tutorial;

  Future<void> _openVideo() async {
    final raw = tutorial.videoUrl.trim();
    if (raw.isEmpty) return;
    try {
      await launchUrl(Uri.parse(raw), mode: LaunchMode.externalApplication);
    } catch (_) {
      // No handler — the text guide below still works.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = youtubeId(tutorial.videoUrl) != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Tutorial')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.xxl,
        ),
        children: [
          if (hasVideo)
            Pressable(
              semanticLabel: 'Play tutorial on YouTube',
              onTap: _openVideo,
              child: GlowCard(
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.input + 2),
                  child: TutorialThumb(
                    videoUrl: tutorial.videoUrl,
                    playSize: 58,
                  ),
                ),
              ),
            ),
          if (hasVideo) const SizedBox(height: AppSpace.lg),
          Eyebrow(text: tutorial.category.toUpperCase()),
          const SizedBox(height: AppSpace.sm),
          Text(tutorial.title, style: AppText.headline),
          const SizedBox(height: AppSpace.sm),
          Text('${groupDigits(tutorial.views)} reads', style: AppText.caption),
          const SizedBox(height: AppSpace.lg),
          if (hasVideo) ...[
            NeonButton(
              expand: true,
              onPressed: _openVideo,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_circle_fill_rounded,
                    size: 19,
                    color: Color(0xFF04212A),
                  ),
                  SizedBox(width: AppSpace.sm),
                  Text('Watch tutorial'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
          ],
          Text(
            tutorial.content.replaceAll('\r\n', '\n'),
            style: AppText.body.copyWith(height: 1.6, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
