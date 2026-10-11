import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:injectable/injectable.dart';
import '../core/hive_config.dart';
import '../models/note.dart';

/// Repository for persisting and managing Notes
@injectable
class NoteRepository {
  /// Get all notes, sorted by creation date (newest first)
  List<Note> getAllNotes() {
    if (!HiveConfig.isNotesBoxOpen()) {
      HiveConfig.ensureNotesBoxOpen();
      return [];
    }
    final box = HiveConfig.getNotesBox();
    final notes = box.values.toList();
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  /// Get active (uncompleted) notes
  List<Note> getActiveNotes() {
    return getAllNotes().where((note) => !note.isCompleted).toList();
  }

  /// Get completed notes
  List<Note> getCompletedNotes() {
    return getAllNotes().where((note) => note.isCompleted).toList();
  }

  /// Get active notes count
  int getActiveNotesCount() {
    return getActiveNotes().length;
  }

  /// Get total notes count
  int getTotalNotesCount() {
    if (!HiveConfig.isNotesBoxOpen()) return 0;
    final box = HiveConfig.getNotesBox();
    return box.length;
  }

  /// Add a note
  Future<void> addNote(Note note) async {
    final box = await HiveConfig.ensureNotesBoxOpen();
    await box.put(note.id, note);
  }

  /// Update an existing note
  Future<void> updateNote(Note note) async {
    final box = await HiveConfig.ensureNotesBoxOpen();
    await box.put(note.id, note);
  }

  /// Toggle note completed status
  Future<void> toggleNoteCompleted(String id) async {
    final box = await HiveConfig.ensureNotesBoxOpen();
    final note = box.get(id);
    if (note != null) {
      note.isCompleted = !note.isCompleted;
      await note.save();
    }
  }

  /// Delete note by ID
  Future<void> deleteNote(String id) async {
    final box = await HiveConfig.ensureNotesBoxOpen();
    await box.delete(id);
  }

  /// Clear all notes
  Future<void> clearAllNotes() async {
    final box = await HiveConfig.ensureNotesBoxOpen();
    await box.clear();
  }

  /// Listen to changes in notes box
  ValueListenable<Box<Note>>? listenable() {
    if (!HiveConfig.isNotesBoxOpen()) return null;
    return HiveConfig.getNotesBox().listenable();
  }
}
