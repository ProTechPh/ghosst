import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Swipeable image strip with page dots, shared by the premium game and
/// product pages. Empty list renders the shared fallback tile.
class PremiumCarousel extends StatefulWidget {
  const PremiumCarousel({super.key, required this.images, this.height = 210});

  final List<String> images;
  final double height;

  @override
  State<PremiumCarousel> createState() => _PremiumCarouselState();
}

class _PremiumCarouselState extends State<PremiumCarousel> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: SizedBox(
            height: widget.height,
            child: const PremiumImageFallback(),
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  fit: BoxFit.cover,
                  memCacheWidth: 900,
                  placeholder: (context, url) =>
                      const PremiumImageFallback(),
                  errorWidget: (context, url, e) =>
                      const PremiumImageFallback(),
                ),
              ),
            ),
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.images.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shared empty/error tile for premium images.
class PremiumImageFallback extends StatelessWidget {
  const PremiumImageFallback({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surfaceHigh,
    child: Center(
      child: Icon(
        Icons.sports_esports_outlined,
        color: AppColors.textDim.withValues(alpha: .7),
      ),
    ),
  );
}
