// health_documents_widget.dart
//
// A self-contained expandable card for the profile screen (or appointment screen)
// that lets patients store documents locally and share with a doctor via Firebase.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/document_service.dart';

class HealthDocumentsWidget extends StatefulWidget {
  const HealthDocumentsWidget({super.key});

  @override
  State<HealthDocumentsWidget> createState() => _HealthDocumentsWidgetState();
}

class _HealthDocumentsWidgetState extends State<HealthDocumentsWidget> {
  List<HealthDocument> _docs = [];
  bool _loading = true;
  final Map<String, double> _uploadProgress = {};

  static const List<_DocType> _docTypes = [
    _DocType('prescription', 'Prescription', Icons.receipt_long_outlined),
    _DocType('lab_report', 'Lab Report', Icons.biotech_outlined),
    _DocType('xray', 'X-Ray / Scan', Icons.document_scanner_outlined),
    _DocType('other', 'Other', Icons.attach_file_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    final docs = await DocumentService.loadLocalDocuments();
    if (mounted) setState(() { _docs = docs; _loading = false; });
  }

  Future<void> _pickDocument(String type, {bool fromCamera = false}) async {
    final doc = await DocumentService.pickAndSaveDocument(
      type: type,
      fromCamera: fromCamera,
    );
    if (doc != null && mounted) {
      setState(() => _docs.insert(0, doc));
    }
  }

  Future<void> _shareToFirebase(HealthDocument doc) async {
    setState(() => _uploadProgress[doc.localId] = 0.0);
    try {
      final url = await DocumentService.uploadToFirebase(
        doc,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress[doc.localId] = p);
        },
      );
      _uploadProgress.remove(doc.localId);
      await _loadDocs();
      if (mounted) {
        // Copy link to clipboard
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Share link copied to clipboard. Send it to your doctor.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _uploadProgress.remove(doc.localId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      }
    }
  }

  Future<void> _deleteDoc(HealthDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Document?'),
        content: Text('Remove "${doc.fileName}" from your local storage?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DocumentService.deleteLocalDocument(doc.localId);
      await _loadDocs();
    }
  }

  void _showAddOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Add Health Document', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Stored locally on your device'),
            ),
            const Divider(height: 1),
            for (final type in _docTypes) ...[
              ListTile(
                leading: Icon(type.icon),
                title: Text(type.label),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSourcePicker(type.key);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSourcePicker(String type) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(ctx); _pickDocument(type); },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () { Navigator.pop(ctx); _pickDocument(type, fromCamera: true); },
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    return _docTypes.firstWhere((t) => t.key == type, orElse: () => _docTypes.last).icon;
  }

  String _typeLabel(String type) {
    return _docTypes.firstWhere((t) => t.key == type, orElse: () => _docTypes.last).label;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_special_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My Health Documents',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text('Stored on your device · Share with doctor on request',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showAddOptions,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined, color: Colors.grey[400], size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No documents yet. Add prescriptions, lab reports, or scans.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),
            for (final doc in _docs) _buildDocTile(doc, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildDocTile(HealthDocument doc, ColorScheme cs) {
    final progress = _uploadProgress[doc.localId];
    final isUploading = progress != null;
    final file = File(doc.localPath);
    final exists = file.existsSync();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Thumbnail preview or icon
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: exists
                    ? Image.file(file,
                        width: 44, height: 44, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(_typeIcon(doc.type), size: 44, color: cs.primary))
                    : Icon(_typeIcon(doc.type), size: 44, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(_typeLabel(doc.type),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    if (doc.sharedUrl != null)
                      Row(
                        children: [
                          Icon(Icons.cloud_done_outlined, size: 12, color: Colors.green[700]),
                          const SizedBox(width: 4),
                          Text('Shared',
                              style: TextStyle(fontSize: 11, color: Colors.green[700],
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                  ],
                ),
              ),
              // Delete
              IconButton(
                onPressed: isUploading ? null : () => _deleteDoc(doc),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red[300],
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          // Upload progress bar
          if (isUploading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: progress, minHeight: 3,
                  borderRadius: BorderRadius.circular(2)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (doc.sharedUrl == null)
                    TextButton.icon(
                      onPressed: exists ? () => _shareToFirebase(doc) : null,
                      icon: const Icon(Icons.share_outlined, size: 14),
                      label: const Text('Share with Doctor', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(text: doc.sharedUrl!));
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined, size: 14),
                      label: const Text('Copy Link', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: Colors.green[700],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DocType {
  final String key;
  final String label;
  final IconData icon;
  const _DocType(this.key, this.label, this.icon);
}
