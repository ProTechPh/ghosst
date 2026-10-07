import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../appwrite_client.dart';
import '../services/backend.dart';
import '../theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Product> products = [];
  List<StockEntry> keys = [];
  Product? selected;
  bool loading = true;
  bool busy = false;
  String message = '';

  final keyInput = TextEditingController();
  final productName = TextEditingController();
  final productCost = TextEditingController();
  final productDesc = TextEditingController();
  final productYoutube = TextEditingController();

  // Reused by the Edit product dialog. Created once and disposed with this
  // State — disposing right after `await showDialog` raced the dialog's exit
  // animation (TextField cursor timer read a disposed controller → first
  // exception → "_dependents.isEmpty" assertion during teardown).
  final editName = TextEditingController();
  final editCost = TextEditingController();
  final editDesc = TextEditingController();
  final editYt = TextEditingController();

  /// Local image paths picked for the "New product" form (uploaded on create).
  List<String> pickedPaths = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    keyInput.dispose();
    productName.dispose();
    productCost.dispose();
    productDesc.dispose();
    productYoutube.dispose();
    editName.dispose();
    editCost.dispose();
    editDesc.dispose();
    editYt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = '';
    });
    try {
      final ps = await Backend.allProducts();
      final ks = await Backend.listKeys();
      if (!mounted) return;
      setState(() {
        products = ps;
        keys = ks;
        selected = selected == null
            ? (ps.isNotEmpty ? ps.first : null)
            : ps.where((p) => p.id == selected!.id).firstOrNull ??
                  (ps.isNotEmpty ? ps.first : null);
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

  int availableCount(String productId) => keys
      .where((k) => k.productId == productId && k.status == 'available')
      .length;

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

  Future<void> _addKeys() async {
    if (selected == null) return;
    final lines = keyInput.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await Backend.addKeys(productId: selected!.id, keys: lines);
      keyInput.clear();
      setState(() => message = 'Added ${lines.length} key(s).');
      await _load();
    } catch (e) {
      setState(() => message = 'Add failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addProduct() async {
    final name = productName.text.trim();
    final cost = int.tryParse(productCost.text.trim());
    if (name.isEmpty || cost == null || cost < 0) {
      setState(() => message = 'Enter a product name and a valid cost.');
      return;
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
      await Backend.createProduct(
        name: name,
        cost: cost,
        description: productDesc.text.trim(),
        youtubeUrl: productYoutube.text.trim(),
        imageIds: uploaded,
      );
      productName.clear();
      productCost.clear();
      productDesc.clear();
      productYoutube.clear();
      setState(() {
        pickedPaths = [];
        message = 'Product "$name" created.';
      });
      await _load();
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
                );
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
      setState(() => message = 'Product "${p.name}" updated.');
      await _load();
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

  Future<void> _deleteKey(StockEntry k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.delete_forever_rounded,
            color: AppColors.red,
            size: 34,
          ),
        ),
        title: const Text('Delete key?'),
        content: SelectableText(
          k.keyText,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.text,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Backend.deleteKey(k.keyId);
      await _load();
    } catch (e) {
      setState(() => message = 'Delete failed: $e');
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        const SectionLabel('Admin panel'),
        const Text(
          'Manage stock & products',
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

        // ---- Stock keys ----
        const SectionLabel('Stock keys'),
        GlowCard(
          child: products.isEmpty
              ? const Text(
                  'Create a product first.',
                  style: TextStyle(color: AppColors.textDim),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<Product>(
                      isExpanded: true,
                      value: selected,
                      dropdownColor: AppColors.surfaceHigh,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        for (final p in products)
                          DropdownMenuItem(
                            value: p,
                            child: Text('${p.name} (${p.cost} coins)'),
                          ),
                      ],
                      onChanged: (p) => setState(() => selected = p),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyInput,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Paste keys, one per line',
                      ),
                    ),
                    const SizedBox(height: 12),
                    NeonButton(
                      expand: true,
                      onPressed: busy ? null : _addKeys,
                      child: Text(
                        'Add ${keyInput.text.split('\n').where((s) => s.trim().isNotEmpty).length} key(s)',
                      ),
                    ),
                  ],
                ),
        ),

        const SizedBox(height: 20),

        // ---- Products ----
        const SectionLabel('Products'),
        if (products.isEmpty)
          const Text(
            'No products yet.',
            style: TextStyle(color: AppColors.textDim),
          ),
        for (final p in products) ...[
          GlowCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
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
                      const SizedBox(height: 2),
                      Text(
                        '${p.cost} coins · ${availableCount(p.id)} in stock'
                        '${p.imageIds.isNotEmpty ? ' · ${p.imageIds.length} img' : ''}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  color: AppColors.cyan,
                  icon: const Icon(Icons.edit_outlined, size: 21),
                  onPressed: busy ? null : () => _editProduct(p),
                ),
                NeonButton(
                  dense: true,
                  outline: p.active,
                  glow: !p.active,
                  onPressed: busy ? null : () => _toggleActive(p),
                  child: Text(p.active ? 'Disable' : 'Enable'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 10),

        // ---- New product ----
        const SectionLabel('New product'),
        GlowCard(
          child: Column(
            children: [
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

        const SizedBox(height: 20),

        // ---- Key stock ----
        SectionLabel('Key stock (${keys.length} shown)'),
        if (keys.isEmpty)
          const Text(
            'No keys stocked yet.',
            style: TextStyle(color: AppColors.textDim),
          ),
        for (final k in keys) ...[
          GlowCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  k.status == 'available'
                      ? Icons.key_rounded
                      : Icons.lock_outline,
                  size: 20,
                  color: k.status == 'available'
                      ? AppColors.cyan
                      : AppColors.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.keyText,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_productName(k.productId)} · ${k.status}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (k.status == 'available')
                  IconButton(
                    color: AppColors.red,
                    icon: const Icon(Icons.delete_outline, size: 21),
                    onPressed: () => _deleteKey(k),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _productName(String id) =>
      products.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? id;
}
