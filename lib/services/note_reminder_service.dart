import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../models/note.dart';

/// Syncs note reminders to the native side.
///
/// For every upcoming note (has an event time, not completed), the native
/// AlarmManager is armed to fire a notification [reminderLeadMinutes] before
/// the event — even when the Flutter UI is closed. This is invoked whenever
/// the notes list changes so alarms always reflect the current set of notes.
class NoteReminderService {
  static const MethodChannel _nativeChannel =
      MethodChannel(AppConstants.nativeChannel);

  /// How long before the event the reminder notification is shown.
  static const int reminderLeadMinutes = 5;

  /// Push the current notes to native so alarms match exactly.
  ///
  /// Notes that no longer qualify (completed, deleted, no event time, or an
  /// event that can no longer be reminded) are unarmed by the native side.
  static Future<void> syncReminders(List<Note> notes) async {
    final now = DateTime.now();

    final reminders = <Map<String, dynamic>>[];
    for (final note in notes) {
      final eventTime = note.eventTime;
      if (note.isCompleted || eventTime == null) continue;

      final notifyAt =
          eventTime.subtract(const Duration(minutes: reminderLeadMinutes));
      // Only arm reminders whose alert time is still in the future.
      if (!notifyAt.isAfter(now)) continue;

      reminders.add({
        'id': note.id,
        'title': 'Reminder: ${note.title}',
        'body': note.content,
        'notifyAt': notifyAt.millisecondsSinceEpoch,
      });
    }

    try {
      await _nativeChannel.invokeMethod('syncNoteReminders', {
        'reminders': reminders,
      });
    } catch (e) {
      // Native side not available (e.g. non-Android or during startup) —
      // reminders are best-effort and will be re-synced on next change.
      // ignore: avoid_print
      print('NoteReminderService: failed to sync reminders: $e');
    }
  }

  /// Unarm the reminder for a single note.
  static Future<void> cancelReminder(String id) async {
    try {
      await _nativeChannel.invokeMethod('cancelNoteReminder', {'id': id});
    } catch (e) {
      // ignore: avoid_print
      print('NoteReminderService: failed to cancel reminder: $e');
    }
  }
}
