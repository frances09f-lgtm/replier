import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../providers/note_provider.dart';
import '../services/note_extraction_service.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allNotes = ref.watch(notesProvider);
    final activeNotes = ref.watch(activeNotesProvider);
    final completedNotes = ref.watch(completedNotesProvider);
    final theme = Theme.of(context);

    // Apply search filter
    final filteredActive = _filterNotes(activeNotes);
    final filteredCompleted = _filterNotes(completedNotes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes & Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_alt_outlined),
            tooltip: 'Test Note Extraction',
            onPressed: () => _showTestExtractionDialog(context),
          ),
          if (allNotes.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'clear_completed') {
                  for (final n in completedNotes) {
                    ref.read(notesProvider.notifier).deleteNote(n.id);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cleared completed notes')),
                  );
                } else if (val == 'clear_all') {
                  _confirmClearAll(context);
                }
              },
              itemBuilder: (ctx) => [
                if (completedNotes.isNotEmpty)
                  const PopupMenuItem(
                    value: 'clear_completed',
                    child: Text('Clear completed notes'),
                  ),
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Text('Clear all notes',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Active'),
                    if (activeNotes.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${activeNotes.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Completed'),
                    if (completedNotes.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${completedNotes.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddNoteDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Note'),
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes by title, sender, or content...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim().toLowerCase());
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNotesList(context, filteredActive, isCompletedTab: false),
                _buildNotesList(context, filteredCompleted,
                    isCompletedTab: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Note> _filterNotes(List<Note> notes) {
    if (_searchQuery.isEmpty) return notes;
    return notes.where((n) {
      return n.title.toLowerCase().contains(_searchQuery) ||
          n.content.toLowerCase().contains(_searchQuery) ||
          n.sender.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  Widget _buildNotesList(BuildContext context, List<Note> notes,
      {required bool isCompletedTab}) {
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCompletedTab
                    ? Icons.check_circle_outline
                    : Icons.event_note_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                isCompletedTab
                    ? 'No completed notes yet'
                    : (_searchQuery.isNotEmpty
                        ? 'No notes matching "$_searchQuery"'
                        : 'No active notes'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                isCompletedTab
                    ? 'Notes marked as done will appear here.'
                    : 'Notes and meetings from incoming messages (e.g. "meeting tomorrow at 9 am") are automatically captured here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              if (!isCompletedTab && _searchQuery.isEmpty) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => _showTestExtractionDialog(context),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Try Example Message'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final note = notes[index];
        return _NoteCard(note: note);
      },
    );
  }

  void _showAddNoteDialog(BuildContext context) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Note'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title / Subject',
                  hintText: 'e.g. Meeting with Sarah',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Details / Message',
                  hintText: 'e.g. Conduct a meeting tomorrow at 9 AM',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              final content = contentController.text.trim();
              if (title.isEmpty && content.isEmpty) return;

              final extractor = NoteExtractionService();
              final effectiveTitle =
                  title.isNotEmpty ? title : extractor.extractTitle(content);
              final eventTime = extractor
                  .parseEventDateTime(content.isNotEmpty ? content : title);

              final newNote = Note(
                id: const Uuid().v4(),
                title: effectiveTitle,
                content: content.isNotEmpty ? content : title,
                sender: 'Self',
                createdAt: DateTime.now(),
                eventTime: eventTime,
                isCompleted: false,
              );

              ref.read(notesProvider.notifier).addNote(newNote);
              Navigator.pop(ctx);
            },
            child: const Text('Save Note'),
          ),
        ],
      ),
    );
  }

  void _showTestExtractionDialog(BuildContext context) {
    final testController = TextEditingController(
      text: 'we will conduct a meeting tommorow at 9 am',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Colors.amber),
            SizedBox(width: 8),
            Text('Test Note Detection'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simulate an incoming message to test how the smart note engine extracts meeting information:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: testController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Incoming Message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ActionChip(
                  label:
                      const Text('Meeting 9am', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    testController.text =
                        'we will conduct a meeting tommorow at 9 am';
                  },
                ),
                ActionChip(
                  label: const Text('Call 3pm', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    testController.text =
                        "Let's have a call today at 3pm to review";
                  },
                ),
                ActionChip(
                  label: const Text('Reminder 5pm',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    testController.text =
                        'Reminder: Submit final report by 5pm tomorrow';
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add_task, size: 18),
            label: const Text('Simulate & Add Note'),
            onPressed: () async {
              final message = testController.text.trim();
              if (message.isNotEmpty) {
                final extractor = NoteExtractionService();
                final note = await extractor.processMessage(
                  'Alex',
                  message,
                  appName: 'WhatsApp',
                );
                if (context.mounted) {
                  Navigator.pop(ctx);
                  if (note != null) {
                    ref.read(notesProvider.notifier).loadNotes();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Note extracted: "${note.title}"'),
                        backgroundColor: Colors.green.shade700,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Message did not contain an actionable meeting or note.'),
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notes?'),
        content: const Text(
            'This will permanently delete all active and completed notes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(notesProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDone = note.isCompleted;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDone
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.5)
              : theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      color: isDone
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
          : theme.colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            ref.read(notesProvider.notifier).toggleNoteCompleted(note.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isDone,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    onChanged: (_) {
                      ref
                          .read(notesProvider.notifier)
                          .toggleNoteCompleted(note.id);
                    },
                  ),
                ),
              ),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      note.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Content text
                    Text(
                      note.content,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDone
                            ? theme.colorScheme.outline
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Badges row: Event Time, Sender, App
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (note.eventTime != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_rounded,
                                    size: 13, color: Colors.purple.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('MMM d, h:mm a')
                                      .format(note.eventTime!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (note.sender.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline,
                                    size: 13,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  note.sender,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (note.appName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              note.appName,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.teal.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: theme.colorScheme.outline,
                onPressed: () {
                  ref.read(notesProvider.notifier).deleteNote(note.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Note deleted'),
                      duration: const Duration(seconds: 3),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () {
                          ref.read(notesProvider.notifier).addNote(note);
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
