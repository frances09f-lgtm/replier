import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../repositories/note_repository.dart';

/// Service that analyzes messages and extracts actionable notes, meetings, and reminders.
class NoteExtractionService {
  final NoteRepository _noteRepository;
  final Uuid _uuid = const Uuid();

  // Cache to prevent duplicate notes within a short timeframe
  static final Map<String, DateTime> _recentDeduplicationMap = {};

  NoteExtractionService({NoteRepository? noteRepository})
      : _noteRepository = noteRepository ?? NoteRepository();

  // Regex for dates (supporting common typos like 'tommorow')
  static final RegExp _datePattern = RegExp(
    r'\b(today|tonight|tom+o?r+o?w|next\s+week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
    caseSensitive: false,
  );

  // Regex for 12-hour or 24-hour time expressions
  static final RegExp _timePattern = RegExp(
    r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\bat\s+(\d{1,2})(?::(\d{2}))?\b',
    caseSensitive: false,
  );

  // Regex for meeting / event keywords
  static final RegExp _eventPattern = RegExp(
    r'\b(meeting|meet|conduct\s+a\s+meeting|sync|team\s+sync|call|appointment|interview|discussion|session|class|exam|seminar|webinar|workshop|presentation|conference|hangout|gathering)\b',
    caseSensitive: false,
  );

  // Regex for reminder / task cues
  static final RegExp _reminderPattern = RegExp(
    r"\b(remind\s+me|reminder|remember\s+to|don'?t\s+forget|deadline|due\s+date|schedule|scheduled)\b",
    caseSensitive: false,
  );

  /// Determine whether a message contains an actionable note or meeting
  bool isActionableMessage(String message) {
    final text = message.trim().toLowerCase();
    if (text.length < 5) return false;

    final hasEvent = _eventPattern.hasMatch(text);
    final hasDate = _datePattern.hasMatch(text);
    final hasTime = _timePattern.hasMatch(text);
    final hasReminder = _reminderPattern.hasMatch(text);

    // Event + (Date or Time) -> High confidence meeting/event
    if (hasEvent && (hasDate || hasTime)) return true;

    // Direct reminder cues -> High confidence reminder
    if (hasReminder && (hasDate || hasTime || text.contains('to ')))
      return true;

    // Phrases like "we will conduct a meeting" even without explicit time
    if (text.contains('conduct a meeting') ||
        text.contains('schedule a meeting') ||
        text.contains('have a meeting')) {
      return true;
    }

    // Explicit deadline or schedule cues
    if (text.startsWith('reminder:') ||
        text.startsWith('note:') ||
        text.startsWith('todo:')) {
      return true;
    }

    return false;
  }

  /// Extracts a clean, concise title from the message
  String extractTitle(String message) {
    final text = message.trim();
    final lower = text.toLowerCase();

    // Try to find the event type
    final eventMatch = _eventPattern.firstMatch(lower);
    String eventType = 'Meeting';
    if (lower.startsWith('remind') ||
        lower.contains('reminder') ||
        lower.contains("don't forget") ||
        lower.contains("remember to")) {
      eventType = 'Reminder';
    } else if (eventMatch != null) {
      final raw = eventMatch.group(1)!;
      if (raw.contains('meeting') || raw.contains('meet')) {
        eventType = 'Meeting';
      } else if (raw.contains('call')) {
        eventType = 'Call';
      } else if (raw.contains('sync')) {
        eventType = 'Sync';
      } else if (raw.contains('interview')) {
        eventType = 'Interview';
      } else if (raw.contains('appointment')) {
        eventType = 'Appointment';
      } else if (raw.contains('class') || raw.contains('exam')) {
        eventType = raw[0].toUpperCase() + raw.substring(1);
      } else {
        eventType = 'Event';
      }
    } else if (_reminderPattern.hasMatch(lower)) {
      eventType = 'Reminder';
    }

    // Try to find the date & time phrase
    final dateMatch = _datePattern.firstMatch(lower);
    final timeMatch = _timePattern.firstMatch(lower);

    String dateStr = '';
    if (dateMatch != null) {
      final rawDate = dateMatch.group(1)!.toLowerCase();
      if (rawDate.startsWith('tom')) {
        dateStr = 'tomorrow';
      } else if (rawDate.startsWith('tod')) {
        dateStr = 'today';
      } else {
        dateStr = rawDate[0].toUpperCase() + rawDate.substring(1);
      }
    }

    String timeStr = '';
    if (timeMatch != null) {
      final rawTime = timeMatch.group(0)!.trim();
      if (rawTime.toLowerCase().startsWith('at ')) {
        timeStr = rawTime;
      } else {
        timeStr = 'at $rawTime';
      }
    }

    // Build synthesized title if we have date or time
    if (dateStr.isNotEmpty || timeStr.isNotEmpty) {
      final parts = [eventType];
      if (dateStr.isNotEmpty) parts.add(dateStr);
      if (timeStr.isNotEmpty) parts.add(timeStr);
      return parts.join(' ');
    }

    // Fallback: clean first 60 chars of the message
    var cleaned = text;
    if (cleaned.length > 50) {
      cleaned = '${cleaned.substring(0, 47)}...';
    }
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  /// Attempts to parse a DateTime from relative date and time strings
  DateTime? parseEventDateTime(String message) {
    final lower = message.toLowerCase();
    final now = DateTime.now();

    int addDays = 0;
    final dateMatch = _datePattern.firstMatch(lower);
    if (dateMatch != null) {
      final d = dateMatch.group(1)!.toLowerCase();
      if (d.startsWith('tom')) {
        addDays = 1;
      } else if (d == 'today' || d == 'tonight') {
        addDays = 0;
      } else {
        final days = [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday'
        ];
        final targetIndex = days.indexWhere((day) => d.contains(day));
        if (targetIndex != -1) {
          final currentWeekday = now.weekday - 1; // Monday = 0
          addDays = (targetIndex - currentWeekday + 7) % 7;
          if (addDays == 0) addDays = 7; // Next occurrence
        }
      }
    }

    // Parse time
    int hour = 9;
    int minute = 0;
    bool timeFound = false;

    final timeMatch = _timePattern.firstMatch(lower);
    if (timeMatch != null) {
      final hourStr = timeMatch.group(1) ?? timeMatch.group(4);
      final minStr = timeMatch.group(2) ?? timeMatch.group(5);
      final amPm = timeMatch.group(3)?.toLowerCase();

      if (hourStr != null) {
        hour = int.tryParse(hourStr) ?? 9;
        minute = minStr != null ? (int.tryParse(minStr) ?? 0) : 0;
        if (amPm == 'pm' && hour < 12) hour += 12;
        if (amPm == 'am' && hour == 12) hour = 0;
        timeFound = true;
      }
    }

    if (dateMatch != null || timeFound) {
      final targetDate = now.add(Duration(days: addDays));
      return DateTime(
          targetDate.year, targetDate.month, targetDate.day, hour, minute);
    }

    return null;
  }

  /// Processes an incoming message and creates a Note if actionable
  Future<Note?> processMessage(
    String sender,
    String message, {
    String appName = '',
  }) async {
    if (!isActionableMessage(message)) {
      return null;
    }

    // Deduplication key: same sender and message within 2 minutes
    final dedupKey = '$sender:${message.trim().toLowerCase()}';
    final now = DateTime.now();
    final lastSeen = _recentDeduplicationMap[dedupKey];
    if (lastSeen != null && now.difference(lastSeen).inMinutes < 2) {
      return null;
    }
    _recentDeduplicationMap[dedupKey] = now;

    // Prune deduplication cache if too large
    if (_recentDeduplicationMap.length > 200) {
      _recentDeduplicationMap
          .removeWhere((_, time) => now.difference(time).inMinutes >= 10);
    }

    final title = extractTitle(message);
    final eventTime = parseEventDateTime(message);

    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: message.trim(),
      sender: sender.trim(),
      appName: appName,
      createdAt: now,
      eventTime: eventTime,
      isCompleted: false,
    );

    await _noteRepository.addNote(note);
    return note;
  }
}
