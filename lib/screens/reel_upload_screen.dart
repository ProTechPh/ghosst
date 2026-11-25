import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../services/models.dart';
import '../services/reel_upload_service.dart';
import '../theme.dart';

class ReelUploadScreen extends StatefulWidget {
  const ReelUploadScreen({
    super.key,
    this.prepareUpload,
    this.submitUpload,
    this.picker,
  });

  final Future<ReelUploadTicket> Function(ReelUploadDraft draft)? prepareUpload;
  final Future<void> Function(
    ReelUploadDraft draft,
    ReelUploadTicket ticket,
  )?
  submitUpload;
  final FilePicker? picker;

  @override
  State<ReelUploadScreen> createState() => _ReelUploadScreenState();
}

class _ReelUploadScreenState extends State<ReelUploadScreen> {
  final _caption = TextEditingController();
  List<ReelDraftImage> _images = const [];
  String? _error;
  bool _picking = false;
  bool _uploading = false;
  int _done = 0;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking || _uploading) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await (widget.picker ?? FilePicker.platform).pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      final files = result?.files ?? const <PlatformFile>[];
      if (!mounted || files.isEmpty) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      if (files.length > ReelUploadService.maxImages) {
        setState(() {
          _picking = false;
          _error = 'Upload 1 to 5 images.';
          _images = const [];
        });
        return;
      }
      final images = <ReelDraftImage>[];
      for (final file in files) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          setState(() {
            _picking = false;
            _error = 'This file has no readable local path.';
            _images = const [];
          });
          return;
        }
        final name = file.name;
        final ext = name.toLowerCase().split('.').last;
        final mime = switch (ext) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => '',
        };
        final draft = ReelDraftImage(
          path: path,
          fileName: name,
          sizeBytes: file.size,
          sha256: '0' * 64,
          mimeType: mime,
        );
        images.add(draft);
      }
      final preHashError = ReelUploadService.validateImages(
        images
            .map(
              (i) => i.copyWith(
                sha256: 'a' * 64,
              ), // shape validation before hashing
            )
            .toList(),
      );
      if (preHashError != null) {
        setState(() {
          _picking = false;
          _error = preHashError;
          _images = const [];
        });
        return;
      }
      final hashed = <ReelDraftImage>[];
      for (final image in images) {
        final sha = await ReelUploadService.sha256File(image.path);
        hashed.add(image.copyWith(sha256: sha));
      }
      final error = ReelUploadService.validateImages(hashed);
      if (!mounted) return;
      setState(() {
        _picking = false;
        _images = error == null ? hashed : const [];
        _error = error;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _picking = false;
          _error = 'Could not read those images. Try again.';
          _images = const [];
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_uploading || _images.isEmpty) return;
    final prepare = widget.prepareUpload;
    final submit = widget.submitUpload;
    if (prepare == null || submit == null) {
      setState(() => _error = 'Reels uploads are unavailable.');
      return;
    }
    final draft = ReelUploadDraft(
      caption: _caption.text.trim(),
      images: _images,
      idempotencyBase: 'reel-${DateTime.now().microsecondsSinceEpoch}',
      onProgress: (done, total) {
        if (mounted) setState(() => _done = done);
      },
    );
    setState(() {
      _uploading = true;
      _error = null;
      _done = 0;
    });
    try {
      final ticket = await prepare(draft);
      await submit(draft, ticket);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Upload failed. Try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Upload reel')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          TextField(
            controller: _caption,
            maxLength: 300,
            enabled: !_uploading,
            decoration: const InputDecoration(
              labelText: 'Caption',
              hintText: 'Tell viewers about this post',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: _picking || _uploading ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              _images.isEmpty
                  ? 'Choose 1-5 images'
                  : '${_images.length} image(s) selected',
            ),
          ),
          if (_picking) const LinearProgressIndicator(),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Text('Uploading $_done/${_images.length}...'),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              _error!,
              style: AppText.caption.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: _images.isEmpty || _uploading ? null : _submit,
            child: Text(_uploading ? 'Uploading…' : 'Post reel'),
          ),
        ],
      ),
    );
  }
}
