import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replier/ui/home.dart';
import 'package:replier/services/event_store.dart';
import 'package:replier/services/bridge.dart';
import 'package:replier/models/message_event.dart';
import 'package:replier/state/controller.dart';

class PreviewStore extends EventStore {
  final m = MessageEvent(
    id: '1',
    notifKey: '1',
    appPackage: 'chat',
    appLabel: 'Chat',
    sender: 'Example',
    text: 'Hello',
    at: DateTime(2026),
    finalReply: 'Hi',
    status: 'opened_unverified',
  );
  @override
  List<MessageEvent> newestFirst() => [m];
  @override
  List<MessageEvent> pendingReview() => [];
}

void main() {
  testWidgets('unverified history fits phone', (t) async {
    final c = ReplierController(store: PreviewStore(), bridge: ReplierBridge());
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      final l = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
      await l.load();
    });
    await t.binding.setSurfaceSize(const Size(412, 850));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: RepaintBoundary(
          key: key,
          child: ReplierHome(controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Logs'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Chat opened (send unconfirmed)'), findsOneWidget);
    await t.runAsync(() async {
      final im =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/replier-status.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
  });
}
