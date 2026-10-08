import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/services/local/model_catalog.dart';
import 'package:replier/services/local/model_download.dart';

void main() {
  test('content range must match exact resume and total', () {
    expect(ModelDownload.validRange('bytes 3-8/9', 3, 9), true);
    expect(ModelDownload.validRange('bytes 0-8/9', 3, 9), false);
    expect(ModelDownload.validRange('bytes 3-8/10', 3, 9), false);
  });
  for (final honors in [true, false]) {
    test('resume verifies hash, server honors Range=$honors', () async {
      final bytes = utf8.encode('synthetic model content');
      final dir = await Directory.systemTemp.createTemp();
      final manager = ModelDownload(dir);
      final spec = LocalModelSpec(
        'test',
        'test',
        'test',
        'rev',
        'file',
        bytes.length,
        sha256.convert(bytes).toString(),
      );
      await manager.partFile(spec).writeAsBytes(bytes.take(5).toList());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        expect(req.headers.value('range'), 'bytes=5-');
        if (honors) {
          req.response.statusCode = 206;
          req.response.headers.set(
            'Content-Range',
            'bytes 5-${bytes.length - 1}/${bytes.length}',
          );
          req.response.add(bytes.sublist(5));
        } else {
          req.response.add(bytes);
        }
        await req.response.close();
      });
      await manager.download(
        spec,
        testUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      expect(await manager.installed(spec), true);
      expect(await manager.modelFile(spec).readAsBytes(), bytes);
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
  }
  test('bad hash cannot become runnable', () async {
    final dir = await Directory.systemTemp.createTemp();
    final manager = ModelDownload(dir);
    final spec = LocalModelSpec(
      'test',
      'test',
      'test',
      'rev',
      'file',
      3,
      'bad-hash',
    );
    await manager.partFile(spec).writeAsBytes([1, 2, 3]);
    await expectLater(manager.download(spec), throwsA(isA<FormatException>()));
    expect(await manager.installed(spec), false);
    expect(await manager.partFile(spec).exists(), false);
    await dir.delete(recursive: true);
  });
}
