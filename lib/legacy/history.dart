import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'message_event.dart';

class PreviousHistory extends StatelessWidget {
  const PreviousHistory({super.key});
  @override
  Widget build(BuildContext context) {
    final rows = Hive.box<MessageEvent>('events').values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return Scaffold(
        appBar: AppBar(title: const Text('Previous Replier history')),
        body: rows.isEmpty
            ? const Center(child: Text('No previous history'))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final e = rows[i];
                  return ListTile(
                      title: Text('${e.appLabel}: ${e.sender}'),
                      subtitle: Text(
                          '${e.text}\n${e.finalReply.isNotEmpty ? e.finalReply : e.generatedReply}\n${e.statusLabel}'));
                }));
  }
}
