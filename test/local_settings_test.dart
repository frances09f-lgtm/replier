import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:replier/services/ai/reply_settings.dart';
import 'package:replier/services/bridge.dart';
import 'package:replier/services/event_store.dart';
import 'package:replier/state/controller.dart';
import 'package:replier/ui/local_settings.dart';

void main() {
  test('fresh manual default and v8 consent migration', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final a = ReplySettings();
    await a.load();
    expect(a.mode, 'off');
    FlutterSecureStorage.setMockInitialValues({
      'groq_enabled': 'true',
      'groq_key': 'fixture',
    });
    final b = ReplySettings();
    await b.load();
    expect(b.mode, 'groq');
    await b.saveLocal('qwen3_17b');
    final c = ReplySettings();
    await c.load();
    expect(c.mode, 'local');
    expect(c.localModel, 'qwen3_17b');
    await c.off();
    expect(c.mode, 'off');
  });
  testWidgets('local download options show size and no silent fallback', (
    t,
  ) async {
    final settings = ReplySettings();
    final c = ReplierController(
      store: EventStore(),
      bridge: ReplierBridge(),
      replySettings: settings,
    );
    await t.runAsync(() async {
      for (final item in [
        ('Roboto', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
        (
          'MaterialIcons',
          '/home/sandbox/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ]) {
        final f = File(item.$2);
        final l = FontLoader(item.$1)
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await l.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    final k = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(title: const Text('Replier · local test')),
            body: ListView(children: [LocalModelSettings(c: c)]),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('never falls back'), findsOneWidget);
    await t.runAsync(() async {
      final im =
          await (k.currentContext!.findRenderObject() as RenderRepaintBoundary)
              .toImage();
      final b = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/replier-local-settings.png')
          .writeAsBytes(b!.buffer.asUint8List());
    });
    await t.tap(find.text('Download / Resume'));
    await t.pumpAndSettle();
    expect(find.textContaining('1.40 GB'), findsWidgets);
    expect(find.text('Download local test model?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
  });
}
