import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'model_catalog.dart';

/// One download at a time. An interrupted download retains .part, never a
/// runnable model. Immutable revision + final hash prevents mixed revisions.
class ModelDownload {
  ModelDownload(this.directory);
  final Directory directory;
  HttpClient? _client;
  bool _busy = false, _cancelled = false;
  File modelFile(LocalModelSpec model) =>
      File('${directory.path}/${model.id}.gguf');
  File partFile(LocalModelSpec model) =>
      File('${directory.path}/${model.id}.part');
  bool get busy => _busy;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<bool> installed(LocalModelSpec model) async =>
      await modelFile(model).exists() &&
      await modelFile(model).length() == model.bytes;

  Future<void> download(
    LocalModelSpec model, {
    void Function(int, int)? progress,
    Uri? testUrl,
  }) async {
    if (_busy) throw StateError('Another model download is active.');
    _busy = true;
    _cancelled = false;
    final client = _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    IOSink? sink;
    try {
      await directory.create(recursive: true);
      if (await installed(model)) return;
      final part = partFile(model);
      int offset = await part.exists() ? await part.length() : 0;
      if (offset > model.bytes) {
        await part.delete();
        offset = 0;
      }
      if (offset < model.bytes) {
        final request = await client.getUrl(testUrl ?? model.url);
        if (offset > 0)
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        final response = await request.close();
        if (response.statusCode == 200) {
          offset = 0;
        } else if (response.statusCode == 206) {
          final range =
              response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          if (!validRange(range, offset, model.bytes))
            throw const FormatException(
              'Invalid download range. Retry from start.',
            );
        } else {
          await response.drain<void>();
          throw HttpException('Download unavailable (${response.statusCode}).');
        }
        sink = part.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        var received = offset;
        await for (final chunk in response.timeout(
          const Duration(seconds: 90),
        )) {
          if (_cancelled)
            throw const HttpException('Download paused. Tap Resume.');
          received += chunk.length;
          if (received > model.bytes)
            throw const FormatException('Unexpected model length.');
          sink.add(chunk);
          progress?.call(received, model.bytes);
          // Flush periodically so progress survives Android process death.
          if (received ~/ (4 * 1024 * 1024) !=
              (received - chunk.length) ~/ (4 * 1024 * 1024))
            await sink.flush();
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }
      if (_cancelled) throw const HttpException('Download paused. Tap Resume.');
      if (await part.length() != model.bytes)
        throw const HttpException('Download incomplete. Tap Resume.');
      final digest = await sha256.bind(part.openRead()).first;
      if (_cancelled) throw const HttpException('Download paused. Tap Resume.');
      if (digest.toString() != model.sha256) {
        await part.delete();
        throw const FormatException(
          'Model verification failed. Download again.',
        );
      }
      // Only verified bytes become an installed model.
      await part.rename(modelFile(model).path);
    } catch (_) {
      if (_cancelled) throw const HttpException('Download paused. Tap Resume.');
      rethrow;
    } finally {
      await sink?.close();
      client.close(force: true);
      _client = null;
      _busy = false;
    }
  }

  static bool validRange(String value, int offset, int total) {
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
    if (m == null) return false;
    return int.parse(m[1]!) == offset &&
        int.parse(m[2]!) >= offset &&
        int.parse(m[2]!) < total &&
        int.parse(m[3]!) == total;
  }

  Future<void> remove(LocalModelSpec model) async {
    if (_busy) throw StateError('Pause the download before deleting.');
    for (final f in [modelFile(model), partFile(model)]) {
      if (await f.exists()) await f.delete();
    }
  }
}
