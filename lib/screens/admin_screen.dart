import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../appwrite_client.dart';
import '../premium.dart';
import '../services/backend.dart';
import '../theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Product> products = [];

  /// Key stock across all products (the `keys` collection is admins-only),
  /// so each key product can show what's available vs already claimed.
  List<StockEntry> keys = [];

  bool loading = true;
  bool busy = false;
  String message = '';

  /// The "New product" form stays collapsed behind its toggle button so the
  /// panel doesn't run into one long wall of fields.
  bool showNewForm = false;

  final productName = TextEditingController();
  final productCost = TextEditingController();
  final productDesc = TextEditingController();
  final productYoutube = TextEditingController();
  final productVersion = TextEditingController();
  final productFileSize = TextEditingController();

  /// Duration options for the "New product" form — one `Label: cost` per
  /// line (key products only; empty = classic flat-price product).
  final productDurations = TextEditingController();

  /// MediaFire link for the "New product" form (saved once the product id
  /// exists — `app_files` documents reference their product).
  final productLink = TextEditingController();

  /// Shelf for the "New product" form: `key` | `apk` | `file`.
  String productType = 'key';

  // Reused by the Edit product dialog. Created once and disposed with this
  // State — disposing right after `await showDialog` raced the dialog's exit
  // animation (TextField cursor timer read a disposed controller → first
  // exception → "_dependents.isEmpty" assertion during teardown).
  final editName = TextEditingController();
  final editCost = TextEditingController();
  final editDesc = TextEditingController();
  final editYt = TextEditingController();
  final editVersion = TextEditingController();
  final editFileSize = TextEditingController();
  final editLink = TextEditingController();
  final editDurations = TextEditingController();

  /// Local image paths picked for the "New product" form (uploaded on create).
  List<String> pickedPaths = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    productName.dispose();
    productCost.dispose();
    productDesc.dispose();
    productYoutube.dispose();
    productVersion.dispose();
    productFileSize.dispose();
    productLink.dispose();
    productDurations.dispose();
    editName.dispose();
    editCost.dispose();
    editDesc.dispose();
    editYt.dispose();
    editVersion.dispose();
    editFileSize.dispose();
    editLink.dispose();
    editDurations.dispose();
    super.dispose();
  }

  /// Segmented "Keys / APK / File" picker shared by the create + edit forms.
  Widget _typePicker(String value, ValueChanged<String> onChanged) {
    Widget chip(String id, String label, IconData icon) {
      final on = value == id;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(id),
          child: AnimatedContainer(
            duration: kMotionBase,
            curve: kPremiumCurve,
            height: 40,
            decoration: BoxDecoration(
              gradient: on ? kNeonGradient : null,
              color: on ? null : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: on
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: on ? Colors.white : AppColors.textDim,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('WHAT IS THIS PRODUCT?'),
        Row(
          children: [
            chip('key', 'Key', Icons.key_rounded),
            const SizedBox(width: 8),
            chip('apk', 'APK', Icons.android_rounded),
            const SizedBox(width: 8),
            chip('file', 'File', Icons.insert_drive_file_outlined),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value == 'key'
              ? 'Buyers claim a license key from your stock.'
              : 'Buyers unlock a MediaFire download with their coins.',
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = '';
    });
    try {
      final results = await Future.wait<Object>([
        Backend.allProducts(),
        // Best-effort: the panel still works if `keys` can't be read.
        Backend.listKeys().catchError((_) => <StockEntry>[]),
      ]);
      if (!mounted) return;
      setState(() {
        products = results[0] as List<Product>;
        keys = results[1] as List<StockEntry>;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        message = 'Load failed: $e';
        loading = false;
      });
    }
  }

  Future<List<String>> _uploadAll(List<String> paths) async {
    final ids = <String>[];
    for (final p in paths) {
      ids.add(await Backend.uploadImage(p));
    }
    return ids;
  }

  Future<void> _cleanup(List<String> ids) async {
    for (final id in ids) {
      try {
        await Backend.deleteImage(id);
      } catch (_) {
        // best-effort orphan cleanup
      }
    }
  }

  Future<List<String>?> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return null;
    return result.paths.whereType<String>().toList();
  }

  Future<void> _addProduct() async {
    final name = productName.text.trim();
    final cost = int.tryParse(productCost.text.trim());
    if (name.isEmpty || cost == null || cost < 0) {
      setState(() => message = 'Enter a product name and a valid cost.');
      return;
    }
    // Duration options (key products only) — validated before any upload so
    // a typo doesn't leave orphaned images behind.
    var durationsJson = '';
    if (productType == 'key') {
      final parsed = _parseDurationInput(productDurations.text);
      if (parsed.error.isNotEmpty) {
        setState(() => message = parsed.error);
        return;
      }
      durationsJson = _encodeDurations(parsed.options);
    }
    setState(() {
      busy = true;
      message = '';
    });
    List<String> uploaded = [];
    try {
      if (pickedPaths.isNotEmpty) {
        uploaded = await _uploadAll(pickedPaths);
      }
      final newId = await Backend.createProduct(
        name: name,
        cost: cost,
        description: productDesc.text.trim(),
        youtubeUrl: productYoutube.text.trim(),
        imageIds: uploaded,
        type: productType,
        version: productVersion.text.trim(),
        fileSize: productFileSize.text.trim(),
        durations: durationsJson,
      );
      // Attach the MediaFire link for app-store products. The link lives in
      // `app_files` (team:admins only) so buyers can't read it before paying.
      final link = productLink.text.trim();
      if (productType != 'key' && link.isNotEmpty) {
        await Backend.upsertAppFile(newId, link);
      }
      productName.clear();
      productCost.clear();
      productDesc.clear();
      productYoutube.clear();
      productVersion.clear();
      productFileSize.clear();
      productLink.clear();
      productDurations.clear();
      setState(() {
        pickedPaths = [];
        productType = 'key';
        showNewForm = false;
      });
      await _load();
      // _load() clears `message` — set the banner after it so it survives.
      if (mounted) setState(() => message = 'Product "$name" created.');
    } catch (e) {
      await _cleanup(uploaded);
      if (mounted) setState(() => message = 'Create failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Edit name / cost / description / YouTube / images of an existing product.
  Future<void> _editProduct(Product p) async {
    // Seed the reusable controllers (they live on this State, not the dialog).
    editName.text = p.name;
    editCost.text = '${p.cost}';
    editDesc.text = p.description;
    editYt.text = p.youtubeUrl;
    editVersion.text = p.version;
    editFileSize.text = p.fileSize;
    editDurations.text = [for (final d in p.durations) '${d.label}: ${d.cost}']
        .join('\n');
    var type = p.type;
    // MediaFire links are admin-only — fetch the current one before the
    // dialog opens so saving doesn't silently wipe it.
    editLink.text = await Backend.appFileFor(p.id);
    if (!mounted) return;
    var remoteIds = <String>[...p.imageIds];
    var toDelete = <String>[];
    var localPaths = <String>[];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var busy = false;
        var err = '';
        return StatefulBuilder(
          builder: (ctx, setD) {
            Future<void> save() async {
              final n = editName.text.trim();
              final c = int.tryParse(editCost.text.trim());
              if (n.isEmpty || c == null || c < 0) {
                setD(() => err = 'Enter a name and a valid cost.');
                return;
              }
              var durationsJson = '';
              if (type == 'key') {
                final parsed = _parseDurationInput(editDurations.text);
                if (parsed.error.isNotEmpty) {
                  setD(() => err = parsed.error);
                  return;
                }
                durationsJson = _encodeDurations(parsed.options);
              }
              setD(() {
                busy = true;
                err = '';
              });
              List<String> newIds = [];
              try {
                newIds = await _uploadAll(localPaths);
                await Backend.updateProduct(
                  productId: p.id,
                  name: n,
                  cost: c,
                  description: editDesc.text.trim(),
                  youtubeUrl: editYt.text.trim(),
                  imageIds: [...remoteIds, ...newIds],
                  type: type,
                  version: editVersion.text.trim(),
                  fileSize: editFileSize.text.trim(),
                  durations: durationsJson,
                );
                // Keep the MediaFire link in sync for app-store products.
                final link = editLink.text.trim();
                if (type != 'key') {
                  if (link.isNotEmpty) {
                    await Backend.upsertAppFile(p.id, link);
                  } else {
                    await Backend.deleteAppFile(p.id);
                  }
                }
                // Only remove storage files AFTER the doc no longer references them.
                await _cleanup(toDelete);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                await _cleanup(newIds);
                if (ctx.mounted) {
                  setD(() {
                    busy = false;
                    err = 'Save failed: $e';
                  });
                }
              }
            }

            Widget thumb(Widget image, VoidCallback onRemove) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 66, height: 66, child: image),
                ),
                Positioned(
                  right: 3,
                  top: 3,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );

            // Back button / barrier can't dismiss while a save is in flight.
            return PopScope(
              canPop: !busy,
              child: AlertDialog(
                title: const Text('Edit product'),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: editName,
                          decoration: const InputDecoration(
                            hintText: 'Product name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: editCost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Cost in coins',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: editDesc,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Description (optional)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: editYt,
                          decoration: const InputDecoration(
                            hintText: 'YouTube link (optional)',
                            prefixIcon: Icon(Icons.ondemand_video_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _typePicker(type, (v) => setD(() => type = v)),
                        if (type == 'key') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: editDurations,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText:
                                  'Duration options, one per line — '
                                  'e.g. 1 Hour: 10 / 1 Day: 25 (optional)',
                              prefixIcon: Icon(Icons.timelapse_rounded),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Each line is "Label: coins". Buyers pick a '
                            'duration on the product page; keys pasted in '
                            'the Keys dialog belong to the selected pool. '
                            'Leave empty for a single flat price.',
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                        if (type != 'key') ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: editVersion,
                            decoration: const InputDecoration(
                              hintText: 'Version, e.g. 1.2.0 (optional)',
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: editFileSize,
                            decoration: const InputDecoration(
                              hintText: 'Size label, e.g. 24 MB (optional)',
                              prefixIcon: Icon(Icons.data_usage_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: editLink,
                            decoration: const InputDecoration(
                              hintText: 'MediaFire link buyers will unlock',
                              prefixIcon: Icon(Icons.cloud_download_outlined),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Paste the mediafire.com/file/… page link (or a direct '
                            'download link). Buyers only get it after paying.',
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const SectionLabel('Images'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final id in [...remoteIds])
                              thumb(
                                Image.network(
                                  Backend.imageUrl(id, width: 200),
                                  headers: const {
                                    'X-Appwrite-Project': appwriteProjectId,
                                  },
                                  fit: BoxFit.cover,
                                  width: 66,
                                  height: 66,
                                  errorBuilder: (c, e, s) => Container(
                                    color: AppColors.surfaceHigh,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: AppColors.textDim,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                () => setD(() {
                                  toDelete.add(id);
                                  remoteIds = remoteIds
                                      .where((x) => x != id)
                                      .toList();
                                }),
                              ),
                            for (final path in [...localPaths])
                              thumb(
                                Image.file(
                                  File(path),
                                  fit: BoxFit.cover,
                                  width: 66,
                                  height: 66,
                                  errorBuilder: (c, e, s) => Container(
                                    color: AppColors.surfaceHigh,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: AppColors.textDim,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                () => setD(
                                  () => localPaths = localPaths
                                      .where((x) => x != path)
                                      .toList(),
                                ),
                              ),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: busy
                                  ? null
                                  : () async {
                                      final picked = await _pickImages();
                                      if (picked != null && picked.isNotEmpty) {
                                        setD(
                                          () => localPaths = [
                                            ...localPaths,
                                            ...picked,
                                          ],
                                        );
                                      }
                                    },
                              child: Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                  color: AppColors.surfaceHigh,
                                ),
                                child: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: AppColors.cyan,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (err.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            err,
                            style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (busy) ...[
                          const SizedBox(height: 14),
                          const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  NeonButton(
                    dense: true,
                    onPressed: busy ? null : save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // NOTE: edit* controllers are NOT disposed here — the dialog route is
    // still animating out and its TextFields are still mounted. They are
    // disposed with this State (see dispose()).
    if (ok == true && mounted) {
      // _load() clears `message` — set the banner after it so it survives.
      await _load();
      if (mounted) setState(() => message = 'Product "${p.name}" updated.');
    }
  }

  Future<void> _toggleActive(Product p) async {
    try {
      await Backend.setProductActive(p.id, !p.active);
      await _load();
    } catch (e) {
      setState(() => message = 'Update failed: $e');
    }
  }

  /// Short uid for the claimed-by line: `69a74b6d…`
  String _shortId(String id) {
    if (id.isEmpty) return '—';
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }

  String _claimDate(String iso) {
    if (iso.isEmpty) return '—';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }

  /// Live label for the paste-and-add button: 'Adding…' / 'Add keys' /
  /// 'Add 12 keys' as the admin types.
  String _addLabel(String text, bool adding) {
    if (adding) return 'Adding…';
    final n = text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .length;
    return n == 0 ? 'Add keys' : 'Add $n key${n == 1 ? '' : 's'}';
  }

  /// Parses the duration textarea — one `Label: cost` per line.
  /// Returns the parsed options plus an error message (empty = valid);
  /// blank input is valid (flat-price product).
  ({List<ProductDuration> options, String error}) _parseDurationInput(
    String raw,
  ) {
    final options = <ProductDuration>[];
    final seen = <String>{};
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final sep = t.lastIndexOf(':');
      if (sep <= 0) {
        return (
          options: const <ProductDuration>[],
          error: 'Use "Label: cost" per line — problem with "$t".',
        );
      }
      final label = t.substring(0, sep).trim();
      final cost = int.tryParse(t.substring(sep + 1).trim());
      if (label.isEmpty || cost == null || cost < 0) {
        return (
          options: const <ProductDuration>[],
          error: 'Use "Label: cost" per line — problem with "$t".',
        );
      }
      if (label.length > 64) {
        return (
          options: const <ProductDuration>[],
          error: 'Duration labels must be 64 characters or fewer.',
        );
      }
      if (!seen.add(label)) {
        return (
          options: const <ProductDuration>[],
          error: 'Duplicate duration label "$label".',
        );
      }
      options.add(ProductDuration(label: label, cost: cost));
    }
    return (options: options, error: '');
  }

  /// Encodes parsed options for the `durations` column (JSON array).
  /// Empty list → `''` so clearing the field clears the column.
  String _encodeDurations(List<ProductDuration> options) => options.isEmpty
      ? ''
      : jsonEncode([
          for (final d in options) {'label': d.label, 'cost': d.cost},
        ]);

  /// Confirms then removes one available key from the stock.
  /// Returns true when the row was actually deleted.
  Future<bool> _deleteKey(StockEntry k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete key?'),
        content: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0x26E5484D),
              child: Icon(Icons.delete_forever, color: AppColors.red, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                k.keyText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await Backend.deleteKey(k.keyId);
      if (mounted) {
        setState(() => keys = keys.where((x) => x.keyId != k.keyId).toList());
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => message = 'Delete failed: $e');
      return false;
    }
  }

  /// Per-product stock: what's still available + what buyers already claimed.
  /// Both lists mutate inside the dialog so it stays in sync after a delete.
  Future<void> _showKeys(Product p) async {
    var avail = keys.where((k) => k.productId == p.id && !k.claimed).toList();
    var claimed = keys.where((k) => k.productId == p.id && k.claimed).toList();
    var adding = false;
    var addErr = '';
    final keyInput = TextEditingController();

    // Pool that newly pasted keys join (duration products only).
    var keyDuration = p.hasDurations ? p.durations.first.label : '';

    // The dialog may be dismissed while the stock refresh is in flight —
    // only poke its StatefulBuilder while it is still on screen.
    var open = true;
    StateSetter? refresh;

    final dialog = showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          refresh = setD;

          Future<void> removeKey(StockEntry k) async {
            if (!await _deleteKey(k)) return;
            setD(() {
              avail = avail.where((x) => x.keyId != k.keyId).toList();
              claimed = claimed.where((x) => x.keyId != k.keyId).toList();
            });
          }

          Future<void> copyKey(String text) async {
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('Key copied'),
                  duration: Duration(milliseconds: 1200),
                ),
              );
            }
          }

          Future<void> addPasted() async {
            final lines = keyInput.text
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (lines.isEmpty) {
              if (ctx.mounted) {
                setD(() => addErr = 'Paste at least one key (one per line).');
              }
              return;
            }
            if (ctx.mounted) {
              setD(() {
                adding = true;
                addErr = '';
              });
            }
            try {
              await Backend.addKeys(
                productId: p.id,
                keys: lines,
                duration: p.hasDurations ? keyDuration : '',
              );
              final fresh = await Backend.keysForProduct(p.id);
              if (mounted) {
                setState(
                  () => keys = [
                    ...keys.where((x) => x.productId != p.id),
                    ...fresh,
                  ],
                );
              }
              if (ctx.mounted) {
                setD(() {
                  avail = fresh.where((k) => !k.claimed).toList();
                  claimed = fresh.where((k) => k.claimed).toList();
                  keyInput.clear();
                });
              }
            } catch (e) {
              if (ctx.mounted) setD(() => addErr = 'Add failed: $e');
            } finally {
              if (ctx.mounted) setD(() => adding = false);
            }
          }

          return AlertDialog(
            title: Text(p.name),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SectionLabel('Add keys'),
                    if (p.hasDurations) ...[
                      // Pool picker — pasted keys are tagged with the
                      // selected duration; counts come from the live list.
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final d in p.durations)
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setD(() => keyDuration = d.label),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: keyDuration == d.label
                                      ? AppColors.cyan.withValues(alpha: 0.12)
                                      : AppColors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: keyDuration == d.label
                                        ? AppColors.cyan
                                        : AppColors.border,
                                  ),
                                ),
                                child: Text(
                                  '${d.label} · '
                                  '${avail.where((k) => k.duration == d.label).length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: keyDuration == d.label
                                        ? AppColors.text
                                        : AppColors.textDim,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pasted keys join the selected pool.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    TextField(
                      controller: keyInput,
                      minLines: 3,
                      maxLines: 5,
                      onChanged: (_) => setD(() {}),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Paste keys — one per line',
                      ),
                    ),
                    if (addErr.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        addErr,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    NeonButton(
                      expand: true,
                      dense: true,
                      onPressed: adding ? null : addPasted,
                      child: Text(_addLabel(keyInput.text, adding)),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0x14FFFFFF)),
                    SectionLabel('Available (${avail.length})'),
                    if (avail.isEmpty)
                      const Text(
                        'No keys in stock.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                        ),
                      ),
                    for (final k in avail)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => copyKey(k.keyText),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    k.keyText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: AppColors.cyan,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (p.hasDurations && k.duration.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.gold.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  k.duration,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ),
                            ],
                            IconButton(
                              tooltip: 'Delete key',
                              visualDensity: VisualDensity.compact,
                              color: AppColors.red,
                              icon: const Icon(Icons.delete_outline, size: 19),
                              onPressed: () => removeKey(k),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    SectionLabel('Claimed (${claimed.length})'),
                    if (claimed.isEmpty)
                      const Text(
                        'Nothing claimed yet.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                        ),
                      ),
                    for (final k in claimed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              k.keyText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: AppColors.textDim,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_claimDate(k.claimedAt)} · '
                              '${_shortId(k.claimedBy)}'
                              '${k.duration.isEmpty ? '' : ' · ${k.duration}'}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              NeonButton(
                dense: true,
                outline: true,
                glow: false,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => open = false);

    // Stock straight from the database — the shared `keys` window only keeps
    // the newest 200 rows across every product.
    try {
      final fresh = await Backend.keysForProduct(p.id);
      if (mounted) {
        setState(
          () => keys = [...keys.where((x) => x.productId != p.id), ...fresh],
        );
        avail = fresh.where((k) => !k.claimed).toList();
        claimed = fresh.where((k) => k.claimed).toList();
        if (open) refresh?.call(() {});
      }
    } catch (_) {
      // Keep the state-derived lists — viewing and copying still work.
    }

    await dialog;
    // The dialog is closing — dispose its controller after the exit frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => keyInput.dispose());

    // Fold any dialog-side deletes back into the card counts.
    if (mounted) setState(() {});
  }

  /// Full product delete with a server-driven cascade (stock keys /
  /// MediaFire link / images). Leftovers are reported, never hidden;
  /// buyers keep the claims they already paid for.
  Future<void> _deleteProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text(
          'The product is removed from the store. Its stock keys, MediaFire '
          'link and images are cleaned up too. Buyers keep the downloads '
          'they already paid for.',
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      busy = true;
      message = '';
    });
    try {
      // Product doc first — if this throws, nothing else was touched.
      await Backend.deleteProduct(p.id);

      // Cascade, tracked so leftovers get reported instead of hidden.
      final issues = <String>[];
      final keyFails = await Backend.deleteKeysForProduct(p.id);
      if (keyFails > 0) issues.add('$keyFails key(s)');
      try {
        await Backend.deleteAppFile(p.id);
      } catch (_) {
        issues.add('the MediaFire link');
      }
      var imageFails = 0;
      for (final id in p.imageIds) {
        try {
          await Backend.deleteImage(id);
        } catch (_) {
          imageFails++;
        }
      }
      if (imageFails > 0) issues.add('$imageFails image(s)');

      // Reload from the database — the list must reflect what's stored.
      await _load();
      if (!mounted) return;
      setState(() {
        message = issues.isEmpty
            ? 'Deleted "${p.name}".'
            : 'Deleted "${p.name}" — but ${issues.join(', ')} '
                  'could not be removed. Retry, or check the console.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _pathThumb(String path, VoidCallback onRemove) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(path), width: 66, height: 66, fit: BoxFit.cover),
      ),
      Positioned(
        right: 3,
        top: 3,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    final failed = message.toLowerCase().contains('fail');
    final messageColor = failed ? AppColors.red : AppColors.green;

    // Stock per product: available vs already claimed.
    final availCount = <String, int>{};
    final claimedCount = <String, int>{};
    for (final k in keys) {
      if (k.claimed) {
        claimedCount[k.productId] = (claimedCount[k.productId] ?? 0) + 1;
      } else {
        availCount[k.productId] = (availCount[k.productId] ?? 0) + 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        const SectionLabel('Admin panel'),
        const Text(
          'Manage products',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),

        if (message.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: messageColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: messageColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 18,
                  color: messageColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: messageColor,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ---- Products ----
        SectionLabel('Products (${products.length})'),
        if (products.isEmpty)
          const Text(
            'No products yet.',
            style: TextStyle(color: AppColors.textDim),
          ),
        for (final p in products) ...[
          GlowCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      p.active ? Icons.check_circle : Icons.cancel,
                      color: p.active ? AppColors.green : AppColors.red,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${p.cost} coins · ${p.type.toUpperCase()}'
                            '${p.isKey ? ' · ${availCount[p.id] ?? 0} in stock' : ''}'
                            '${p.isKey && (claimedCount[p.id] ?? 0) > 0 ? ' · ${claimedCount[p.id]} claimed' : ''}'
                            '${p.imageIds.isNotEmpty ? ' · ${p.imageIds.length} img' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete product',
                      visualDensity: VisualDensity.compact,
                      color: AppColors.red,
                      icon: const Icon(Icons.delete_outline, size: 21),
                      onPressed: busy ? null : () => _deleteProduct(p),
                    ),
                  ],
                ),
                // Actions get their own row — cramming them beside the name
                // squeezed the buttons on narrow phones.
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: NeonButton(
                        dense: true,
                        outline: true,
                        glow: false,
                        onPressed: busy ? null : () => _editProduct(p),
                        child: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NeonButton(
                        dense: true,
                        outline: p.active,
                        glow: !p.active,
                        onPressed: busy ? null : () => _toggleActive(p),
                        child: Text(p.active ? 'Disable' : 'Enable'),
                      ),
                    ),
                    if (p.isKey) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: NeonButton(
                          dense: true,
                          outline: true,
                          glow: false,
                          onPressed: busy ? null : () => _showKeys(p),
                          child: const Text('Keys'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 16),

        // ---- New product — the form stays collapsed behind its toggle ----
        NeonButton(
          expand: true,
          dense: true,
          outline: showNewForm,
          glow: !showNewForm,
          onPressed: busy
              ? null
              : () => setState(() => showNewForm = !showNewForm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                showNewForm ? Icons.close_rounded : Icons.add_rounded,
                size: 17,
                color: showNewForm ? AppColors.cyan : const Color(0xFF04212A),
              ),
              const SizedBox(width: 7),
              Text(showNewForm ? 'Close' : 'New product'),
            ],
          ),
        ),
        if (showNewForm) ...[
          const SizedBox(height: 12),
          GlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _typePicker(
                  productType,
                  (v) => setState(() => productType = v),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: productName,
                  decoration: const InputDecoration(
                    hintText: 'Product name',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: productCost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Cost in coins',
                    prefixIcon: Icon(Icons.monetization_on_rounded),
                  ),
                ),
                if (productType == 'key') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: productDurations,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          'Duration options, one per line — '
                          'e.g. 1 Hour: 10 / 1 Day: 25 (optional)',
                      prefixIcon: Icon(Icons.timelapse_rounded),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Each line is "Label: coins". Buyers pick a duration on '
                    'the product page; keys pasted in the Keys dialog belong '
                    'to the selected pool. Leave empty for one flat price.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: productDesc,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Description (optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: productYoutube,
                  decoration: const InputDecoration(
                    hintText: 'YouTube link (optional)',
                    prefixIcon: Icon(Icons.ondemand_video_outlined),
                  ),
                ),
                if (productType != 'key') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: productVersion,
                    decoration: const InputDecoration(
                      hintText: 'Version, e.g. 1.2.0 (optional)',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: productFileSize,
                    decoration: const InputDecoration(
                      hintText: 'Size label, e.g. 24 MB (optional)',
                      prefixIcon: Icon(Icons.data_usage_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: productLink,
                    decoration: const InputDecoration(
                      hintText: 'MediaFire link buyers will unlock',
                      prefixIcon: Icon(Icons.cloud_download_outlined),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Paste the mediafire.com/file/… page link (or a direct '
                    'download link). Buyers only get it after paying.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
                if (pickedPaths.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final path in [...pickedPaths])
                          _pathThumb(
                            path,
                            () => setState(
                              () => pickedPaths = pickedPaths
                                  .where((x) => x != path)
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                NeonButton(
                  dense: true,
                  outline: true,
                  expand: true,
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await _pickImages();
                          if (picked != null && picked.isNotEmpty) {
                            setState(
                              () => pickedPaths = [...pickedPaths, ...picked],
                            );
                          }
                        },
                  child: Text(
                    pickedPaths.isEmpty
                        ? 'Add product images'
                        : 'Add more images (${pickedPaths.length})',
                  ),
                ),
                const SizedBox(height: 14),
                NeonButton(
                  expand: true,
                  onPressed: busy ? null : _addProduct,
                  child: const Text('Create product'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
