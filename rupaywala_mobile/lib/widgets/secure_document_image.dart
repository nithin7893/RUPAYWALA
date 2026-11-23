import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/state/app_scope.dart';
import '../core/theme/app_theme.dart';

class SecureDocumentImage extends StatefulWidget {
  const SecureDocumentImage({
    super.key,
    this.documentPath,
    this.height = 180,
    this.borderRadius = 12,
  });

  final String? documentPath;
  final double height;
  final double borderRadius;

  @override
  State<SecureDocumentImage> createState() => _SecureDocumentImageState();
}

class _SecureDocumentImageState extends State<SecureDocumentImage> {
  late Future<Uint8List> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant SecureDocumentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentPath != widget.documentPath) {
      _future = _load();
    }
  }

  String? _normalizePath(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('/documents/') || value.startsWith('/uploads/')) return value;
    if (value.startsWith('documents/') || value.startsWith('uploads/')) return '/$value';
    // Legacy relative proof path
    return '/uploads/$value';
  }

  Future<Uint8List> _load() async {
    final path = _normalizePath(widget.documentPath);
    if (path == null) {
      throw const ApiException('Document unavailable.');
    }
    return context.api.client.getBytes(path);
  }

  @override
  Widget build(BuildContext context) {
    final path = _normalizePath(widget.documentPath);
    if (path == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: AppColors.neutralSoft,
        child: FutureBuilder<Uint8List>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is ApiException
                  ? error.message
                  : 'Unable to load document.';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, color: AppColors.textHint),
                      const SizedBox(height: AppSpacing.sm),
                      Text(message, style: AppText.caption, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return const Center(child: Text('Document unavailable'));
            }
            return Image.memory(bytes, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }
}
