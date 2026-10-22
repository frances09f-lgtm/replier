import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/draft_theme.dart';
import '../theme/draft_widgets.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatProvider);
    final isLoading = ref.watch(chatLoadingProvider);
    final error = ref.watch(chatErrorProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: null,
      body: Stack(
        children: [
          Column(
            children: [
              Builder(builder: (context) {
                final c = DraftColors.of(context);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('Chat',
                              style: DraftText.display(30, c.tx))),
                      if (messages.isNotEmpty)
                        IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear conversation',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear conversation?'),
                    content: const Text('All messages will be deleted.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(chatProvider.notifier).clearConversation();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
                    ],
                  ),
                );
              }),
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: DraftWarn(
                    'Test mode: nothing is sent. Try the AI and train preferred replies.'),
              ),
              Expanded(
                child: messages.isEmpty
                    ? Builder(builder: (context) {
                        final c = DraftColors.of(context);
                        return ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.85,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: c.s1,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(22),
                                    topRight: Radius.circular(22),
                                    bottomRight: Radius.circular(22),
                                    bottomLeft: Radius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Hi! Type a sample incoming message and I will answer like Replier would.',
                                  style: DraftText.body(15, c.tx),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: DraftButton.secondary(
                                'Train this reply',
                                icon: Icons.thumb_up_outlined,
                                onPressed: null,
                              ),
                            ),
                          ],
                        );
                      })
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return _ChatBubble(
                            chatMessage: msg,
                            colorScheme: colorScheme,
                          );
                        },
                      ),
              ),
              _ChatInputBar(
                onSend: (text) =>
                    ref.read(chatProvider.notifier).sendMessage(text),
                isLoading: isLoading,
              ),
            ],
          ),
          if (error != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style:
                              TextStyle(color: colorScheme.error, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () =>
                            ref.read(chatErrorProvider.notifier).state = null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatBubble extends ConsumerWidget {
  final ChatMessage chatMessage;
  final ColorScheme colorScheme;

  const _ChatBubble({
    required this.chatMessage,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = chatMessage.role == 'user';
    final model = chatMessage.model;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(isUser ? 22 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!isUser && model != null && model.isNotEmpty)
                        Text(
                          model,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (!isUser && chatMessage.isTrained)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green, width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  size: 10, color: Colors.green),
                              SizedBox(width: 3),
                              Text(
                                'Trained',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (!isUser &&
                      ((model != null && model.isNotEmpty) ||
                          chatMessage.isTrained))
                    const SizedBox(height: 4),
                  Text(
                    chatMessage.content,
                    style: TextStyle(
                      fontSize: 15,
                      color: isUser
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (!isUser) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () =>
                            _showEditReplyDialog(context, ref, chatMessage),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_note,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                chatMessage.isTrained
                                    ? 'Edit Training'
                                    : 'Train AI',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _showEditReplyDialog(
      BuildContext context, WidgetRef ref, ChatMessage msg) {
    final controller = TextEditingController(text: msg.content);
    bool createRule = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.school, color: Colors.blue),
                SizedBox(width: 8),
                Text('Train AI Response', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Correct this reply. The AI will learn your style and respond like this in future chats and auto-replies.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Preferred AI Reply',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Also save as Auto-Reply Keyword Rule',
                      style: TextStyle(fontSize: 13)),
                  value: createRule,
                  onChanged: (val) => setState(() => createRule = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newText = controller.text.trim();
                  if (newText.isNotEmpty) {
                    await ref.read(chatProvider.notifier).correctAiReply(
                          msg.id,
                          newText,
                          createRule: createRule,
                        );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              '✅ AI trained! Future responses will follow this style.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Train AI'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatInputBar extends StatefulWidget {
  final void Function(String) onSend;
  final bool isLoading;

  const _ChatInputBar({
    required this.onSend,
    required this.isLoading,
  });

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  final _controller = TextEditingController();

  void _send() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.isLoading) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (widget.isLoading)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.pri,
                  ),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                enabled: !widget.isLoading,
                onSubmitted: (_) => _send(),
                style: DraftText.body(15, c.tx),
                decoration: InputDecoration(
                  hintText:
                      widget.isLoading ? 'Thinking...' : 'Type a test message',
                  hintStyle: DraftText.body(15, c.mut),
                  filled: true,
                  fillColor: c.bg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: c.out, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: c.pri, width: 1.5),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: c.out, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: c.pri,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.isLoading ? null : _send,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.send_rounded,
                    size: 22,
                    color: widget.isLoading ? c.onpri.withValues(alpha: .5) : c.onpri,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
