import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../services/reel_upload_service.dart';
import '../services/worker_backend.dart';
import '../theme.dart';

typedef ReelUpload = Future<Reel> Function(ReelUploadDraft draft);

class ReelUploadDraft {
  const ReelUploadDraft({
    required this.filePath,
    required this.fileName,
    required this.caption,
    required this.sizeBytes,
    required this.sha256,
    required this.idempotencyKey,
    this.onProgress,
  });

  ReelUploadDraft copyWith({
    String? filePath,
    String? fileName,
    String? caption,
    int? sizeBytes,
    String? sha256,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
  }) => ReelUploadDraft(
    filePath: filePath ?? this.filePath,
    fileName: fileName ?? this.fileName,
    caption: caption ?? this.caption,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    onProgress: onProgress ?? this.onProgress,
  );

  final String filePath;
  final String fileName;
  final String caption;
  final int sizeBytes;
  final String sha256;
  final String idempotencyKey;
  final void Function(int sent, int total)? onProgress;
}

class ReelUploadScreen extends StatefulWidget {
  const ReelUploadScreen({
    super.key,
    this.prepareUpload,
    this.submitUpload,
    this.picker,
  });

  final Future<ReelUploadTicket?> Function(ReelUploadDraft draft)?
  prepareUpload;
  final Future<void> Function(ReelUploadDraft draft, ReelUploadTicket ticket)?
  submitUpload;
  final FilePicker? picker;

  @override
  State<ReelUploadScreen> createState() => _ReelUploadScreenState();
}

class _ReelUploadScreenState extends State<ReelUploadScreen> {
  final _caption = TextEditingController();
  ReelUploadDraft? _draft;
  String? _error;
  bool _picking = false;
  bool _uploading = false;
  double? _progress;

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
        type: FileType.video,
      );
      final file = result?.files.singleOrNull;
      if (!mounted || file == null || file.path == null) return;
      final size = file.size;
      if (size < 1 || size > ReelUploadService.maxBytes) {
        setState(() => _error = 'Video must be between 1 byte and 50 MB.');
        return;
      }
      if (!file.name.toLowerCase().endsWith('.mp4')) {
        setState(() => _error = 'Only MP4 videos are allowed.');
        return;
      }
      setState(() => _picking = false);
      final digest = await ReelUploadService.sha256File(file.path!);
      if (!mounted) return;
      setState(() {
        _draft = ReelUploadDraft(
          filePath: file.path!,
          fileName: file.name,
          caption: _caption.text.trim(),
          sizeBytes: size,
          sha256: digest,
          idempotencyKey: Backend.newIdempotencyKey(),
          onProgress: (sent, total) {
            if (mounted) setState(() => _progress = sent / total);
          },
        );
        _picking = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _picking = false;
          _error = 'Could not read that video. Try another file.';
        });
      }
    }
  }

  Future<void> _submit() async {
    final draft = _draft;
    if (draft == null || _uploading) return;
    final prepare = widget.prepareUpload;
    final submit = widget.submitUpload;
    if (prepare == null || submit == null) {
      setState(() => _error = 'Reels uploads are unavailable.');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final ticket = await prepare(
        ReelUploadDraft(
          filePath: draft.filePath,
          fileName: draft.fileName,
          caption: _caption.text.trim(),
          sizeBytes: draft.sizeBytes,
          sha256: draft.sha256,
          idempotencyKey: draft.idempotencyKey,
        ),
      );
      if (ticket == null) {
        throw const ApiException(
          kind: ApiErrorKind.server,
          message: 'Upload unavailable',
          code: 'reels_not_configured',
        );
      }
      await submit(draft.copyWith(caption: _caption.text.trim()), ticket);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Upload failed. Your video is ready to retry.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
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
              hintText: 'Tell viewers about this video',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: _picking || _uploading ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(
              draft == null ? 'Choose MP4 from gallery' : draft.fileName,
            ),
          ),
          if (_picking) const LinearProgressIndicator(),
          if (_progress != null) ...[
            const SizedBox(height: AppSpace.md),
            LinearProgressIndicator(value: _progress),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              _error!,
              style: AppText.caption.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: draft == null || _uploading ? null : _submit,
            child: Text(_uploading ? 'Uploading…' : 'Post reel'),
          ),
          if (_uploading)
            TextButton(
              onPressed: null,
              child: const Text('Keep the app open while uploading.'),
            ),
        ],
      ),
    );
  }
}
