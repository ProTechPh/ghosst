import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/backend.dart';
import '../theme.dart';

class MyKeysScreen extends StatefulWidget {
  const MyKeysScreen({super.key});

  @override
  State<MyKeysScreen> createState() => _MyKeysScreenState();
}

class _MyKeysScreenState extends State<MyKeysScreen> {
  List<Claim> claims = [];
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final c = await Backend.myClaims();
      if (!mounted) return;
      setState(() {
        claims = c;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  void _showKey(Claim c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.key_rounded,
              color: AppColors.primary, size: 32),
        ),
        title: Text(c.productName.isEmpty ? 'Your key' : c.productName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_date(c.createdAt)} · ${c.cost} coins',
                style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                c.keyText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: c.keyText));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          NeonButton(
            dense: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error.isNotEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load keys',
        message: error,
        action: NeonButton(
          dense: true,
          onPressed: _load,
          child: const Text('Retry'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionLabel('My keys'),
          const Text(
            'Claimed licenses',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${claims.length} key(s) in your collection',
            style: const TextStyle(color: AppColors.textDim, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          if (claims.isEmpty)
            const EmptyState(
              icon: Icons.key_off_outlined,
              title: 'No keys yet',
              message:
                  'Watch ads to earn coins, then claim your first license key in the Store.',
            ),
          for (final c in claims) ...[
            GlowCard(
              padding: const EdgeInsets.all(14),
              onTap: () => _showKey(c),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: kTealGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.key_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.productName.isEmpty
                              ? 'License key'
                              : c.productName,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_date(c.createdAt)} · ${c.cost} coins',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.copy_rounded,
                        size: 17, color: AppColors.cyan),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  String _date(String iso) {
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }
}
