import 'package:flutter/material.dart';

import '../services/worker_backend.dart';
import '../theme.dart';

class ReelCommentsScreen extends StatefulWidget {
  const ReelCommentsScreen({
    super.key,
    required this.reelId,
    this.load,
    this.submit,
  });

  final String reelId;
  final Future<List<ReelComment>> Function(int offset)? load;
  final Future<void> Function(String)? submit;

  @override
  State<ReelCommentsScreen> createState() => _ReelCommentsScreenState();
}

class _ReelCommentsScreenState extends State<ReelCommentsScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ReelComment> _comments = [];
  int _offset = 0;
  bool _loading = true;
  bool _failed = false;
  bool _hasMore = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _hasMore &&
        _scroll.position.extentAfter < 200 &&
        !_loading &&
        !_failed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final loaded = await (widget.load != null
          ? widget.load!(_offset)
          : Backend.reelComments(widget.reelId, offset: _offset));
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...loaded];
        _offset += loaded.length;
        _hasMore = loaded.length == 20;
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

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (widget.submit != null) {
        await widget.submit!(text);
      }
      if (!mounted) return;
      _input.clear();
      setState(() {
        _comments = [];
        _offset = 0;
        _hasMore = true;
        _failed = false;
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not post comment. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: _loading && _comments.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _failed && _comments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load comments'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _comments.isEmpty
                ? const Center(child: Text('No comments yet'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpace.lg),
                    itemCount: _comments.length,
                    itemBuilder: (_, i) {
                      final comment = _comments[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(child: Text(comment.user.initial)),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    comment.user.displayName,
                                    style: AppText.subtitle,
                                  ),
                                  Text(comment.text, style: AppText.caption),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _submit,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
