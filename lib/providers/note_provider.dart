import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/hive_config.dart';
import '../models/note.dart';
import '../repositories/note_repository.dart';
import '../services/note_reminder_service.dart';

/// Provider for NoteRepository
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepository();
});

/// State notifier provider for all notes
final notesProvider = StateNotifierProvider<NotesNotifier, List<Note>>((ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return NotesNotifier(repository);
});

/// Provider for active notes (not completed)
final activeNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider);
  return notes.where((note) => !note.isCompleted).toList();
});

/// Provider for completed notes
final completedNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider);
  return notes.where((note) => note.isCompleted).toList();
});

/// Provider for active notes count
final activeNotesCountProvider = Provider<int>((ref) {
  final activeNotes = ref.watch(activeNotesProvider);
  return activeNotes.length;
});

/// Notifier for managing notes state
class NotesNotifier extends StateNotifier<List<Note>> {
  final NoteRepository _repository;

  NotesNotifier(this._repository) : super([]) {
    loadNotes();
  }

  Future<void> loadNotes() async {
    await HiveConfig.ensureNotesBoxOpen();
    state = _repository.getAllNotes();
    await _syncReminders();
  }

  Future<void> addNote(Note note) async {
    await _repository.addNote(note);
    state = _repository.getAllNotes();
    await _syncReminders();
  }

  Future<void> updateNote(Note note) async {
    await _repository.updateNote(note);
    state = _repository.getAllNotes();
    await _syncReminders();
  }

  Future<void> toggleNoteCompleted(String id) async {
    await _repository.toggleNoteCompleted(id);
    state = _repository.getAllNotes();
    await _syncReminders();
  }

  Future<void> deleteNote(String id) async {
    await _repository.deleteNote(id);
    state = _repository.getAllNotes();
    await _syncReminders();
  }

  Future<void> clearAll() async {
    await _repository.clearAllNotes();
    state = [];
    await _syncReminders();
  }

  /// Keep native reminder alarms in sync with the current notes.
  Future<void> _syncReminders() {
    return NoteReminderService.syncReminders(state);
  }
}
