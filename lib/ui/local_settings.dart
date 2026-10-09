import 'package:flutter/material.dart';

import '../state/controller.dart';
import '../services/local/model_catalog.dart';

class LocalModelSettings extends StatefulWidget {
  const LocalModelSettings({super.key, required this.c});
  final ReplierController c;
  @override
  State<LocalModelSettings> createState() => _LocalModelSettingsState();
}

class _LocalModelSettingsState extends State<LocalModelSettings> {
  String selected = LocalModelSpec.llama.id;
  String status = '';
  int done = 0, total = 0;
  bool downloading = false, checking = false;
  @override
  void initState() {
    super.initState();
    selected = widget.c.replySettings!.localModel;
  }

  @override
  void dispose() {
    widget.c.downloads?.cancel();
    super.dispose();
  }

  Future<void> download(LocalModelSpec spec) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download local test model?'),
        content: Text(
          '${spec.label}: ${(spec.bytes / 1000000000).toStringAsFixed(2)} GB. Uses internet for the model download only. Allow enough free storage and RAM. Draft quality and speed on your phone are not measured yet. Interrupted downloads can resume; model is usable only after hash verification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      downloading = true;
      status = 'Checking free storage...';
    });
    try {
      await widget.c.resourceGuard(spec, download: true);
      final d = widget.c.downloads;
      if (d == null)
        throw StateError('Local storage unavailable. Restart the app.');
      await d.download(
        spec,
        progress: (a, b) {
          if (mounted)
            setState(() {
              done = a;
              total = b;
              status = a == b ? 'Verifying SHA-256...' : 'Downloading model...';
            });
        },
      );
      if (mounted)
        setState(() => status = 'Verified. Tap Use local model to select it.');
    } catch (_) {
      if (mounted)
        setState(
          () => status = 'Download paused or failed. Free storage or check internet, then Resume. Partial file retained unless hash failed.',
        );
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = LocalModelSpec.all.firstWhere((m) => m.id == selected);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Local AI · phone test',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Current provider: ${widget.c.replySettings!.mode}. Selected local model: Llama 3.2 1B (808 MB). Download and verify it, then tap Use local model. Existing model files stay on this phone. Meta Llama 3.2 community license applies. Local runs on this phone, uses no API key, and never falls back to cloud. Every reply still needs review.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Local model'),
              items: LocalModelSpec.all
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        m.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: downloading
                  ? null
                  : (v) => setState(() {
                      selected = v!;
                      status = '';
                      done = total = 0;
                    }),
            ),
            Text(
              'Separate ${(spec.bytes / 1000000000).toStringAsFixed(2)} GB download. Only one model runs at a time. Local drafts stop and unload on background; Retry after returning.',
            ),
            if (total > 0) LinearProgressIndicator(value: done / total),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(status),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: downloading || checking
                      ? null
                      : () => download(spec),
                  child: const Text('Download / Resume'),
                ),
                if (downloading)
                  TextButton(
                    onPressed: () => widget.c.downloads?.cancel(),
                    child: const Text('Pause'),
                  ),
                FilledButton(
                  onPressed: downloading || checking
                      ? null
                      : () async {
                          setState(() => checking = true);
                          try {
                            await widget.c.resourceGuard(spec, download: false);
                            await widget.c.configureLocal(spec);
                            if (mounted)
                              setState(
                                () => status = 'Local selected. New drafts use this model.',
                              );
                          } catch (_) {
                            if (mounted)
                              setState(
                                () => status = 'Could not select. Download and verify the model, and free RAM first.',
                              );
                          } finally {
                            if (mounted) setState(() => checking = false);
                          }
                        },
                  child: const Text('Use local model'),
                ),
                TextButton(
                  onPressed: downloading
                      ? null
                      : () async {
                          await widget.c.configureOff();
                          if (mounted)
                            setState(
                              () => status = 'AI off. Replies are manual.',
                            );
                        },
                  child: const Text('AI Off'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
