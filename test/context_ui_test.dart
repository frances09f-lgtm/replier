import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/ui/home.dart';
import 'package:replier/services/event_store.dart';
import 'package:replier/services/bridge.dart';
import 'package:replier/services/ai/reply_settings.dart';
import 'package:replier/services/ai/groq_provider.dart';
import 'package:replier/models/message_event.dart';
import 'package:replier/state/controller.dart';

class DemoStore extends EventStore {
  final m = MessageEvent(
    id: 'test',
    notifKey: 'chat',
    appPackage: 'chat',
    appLabel: 'Chat',
    sender: 'Example chat',
    text: 'Mi station var pochlo, fakt sangaycha hota.',
    at: DateTime(2026, 10, 8, 12, 20),
    generatedReply: 'Kalavlyabaddal dhanyavaad!',
    status: 'generated',
  );
  @override
  List<MessageEvent> newestFirst() => [m];
  @override
  List<MessageEvent> pendingReview() => [m];
}

void main() {
  testWidgets('cloud setup and same-script fixture fit phone', (t) async {
    final settings = ReplySettings();
    final c = ReplierController(
      store: DemoStore(),
      bridge: ReplierBridge(),
      replySettings: settings,
      provider: GroqProvider(key: '', model: settings.model),
    );
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      final l = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
      await l.load();
    });
    await t.binding.setSurfaceSize(const Size(412, 950));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RepaintBoundary(
          key: key,
          child: ReplierHome(controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    Future<void> capture(String name) async {
      await t.runAsync(() async {
        final im =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final d = await im.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/$name.png').writeAsBytes(d!.buffer.asUint8List());
      });
    }

    expect(find.text('Kalavlyabaddal dhanyavaad!'), findsOneWidget);
    await capture('replier-context-draft');
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.text('Groq API settings'), findsOneWidget);
    expect(find.text('Use Groq for drafts'), findsOneWidget);
    expect(t.takeException(), isNull);
    await capture('replier-groq-settings');
    c.dispose();
    await t.binding.setSurfaceSize(null);
  });
}
