import 'dart:async';
import '../update/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../theme/draft_theme.dart';
import '../providers/settings_provider.dart';

/// Screen for app settings
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Persistent controller + PageStorageKey below keeps scroll offset stable
    // across provider rebuilds (permissions / model status load async after
    // first frame), which previously clamped the offset and looked like a
    // "glitch" when flinging from bottom to top.
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final permissions = ref.watch(permissionStatusProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Evaluate once per build so conditional sections above/below can't
    // appear/disappear mid-scroll and shift the scroll extent (the main
    // "jump when flinging from bottom to top" cause).
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final showBusyCard =
        settings.busyModeEnabled && settings.busyUntilTimestamp > nowMillis;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        key: const PageStorageKey<String>('settings_list'),
        controller: _scrollController,
        // Pre-layout offscreen items so a fast fling from bottom to top
        // doesn't jank while cards are (re)built. Keep-alives stay enabled
        // (default) so model tiles keep their state while scrolling.
        cacheExtent: 1200,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
        children: [
          // Permissions section
_SettingsCard(
            title: 'Permissions',
            icon: Icons.shield_outlined,
            children: [

          _PermissionTile(
            title: 'Notification Access',
            subtitle: 'Required to read notifications',
            isGranted: permissions['notificationListener'] ?? false,
            onGrant: () => ref
                .read(permissionStatusProvider.notifier)
                .openNotificationListenerSettings(),
          ),

          _PermissionTile(
            title: 'Post Notifications',
            subtitle: 'Required to show confirmation alerts',
            isGranted: permissions['postNotification'] ?? false,
            onGrant: () => ref
                .read(permissionStatusProvider.notifier)
                .requestPostNotificationPermission(),
          ),


          _PermissionTile(
            title: 'Battery Optimization',
            subtitle: 'Disable for reliable background operation',
            isGranted: permissions['batteryOptimization'] ?? false,
            onGrant: () => ref
                .read(permissionStatusProvider.notifier)
                .openBatteryOptimizationSettings(),
          ),

          ],
          ),
          const SizedBox(height: 16),

          // App settings section
          _SettingsCard(
            title: 'App Settings',
            icon: Icons.tune,
            children: [

          SwitchListTile(
            title: const Text('WhatsApp'),
            subtitle: const Text('Enable auto-reply for WhatsApp'),
            value: settings.whatsappEnabled,
            onChanged: (_) {
              ref.read(appSettingsProvider.notifier).toggleWhatsappEnabled();
            },
          ),

          SwitchListTile(
            title: const Text('Instagram'),
            subtitle: const Text('Enable auto-reply for Instagram'),
            value: settings.instagramEnabled,
            onChanged: (_) {
              ref.read(appSettingsProvider.notifier).toggleInstagramEnabled();
            },
          ),

          const SizedBox(height: 16),

          // Reply delay range
          ListTile(
            title: const Text('Reply Delay Range'),
            subtitle: Text(
                '${settings.minReplyDelaySeconds}s - ${settings.maxReplyDelaySeconds}s (random)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showReplyDelayDialog(context, ref,
                settings.minReplyDelaySeconds, settings.maxReplyDelaySeconds),
          ),

          SwitchListTile(
            title: const Text('Prevent Duplicate Replies'),
            subtitle: const Text('Avoid sending same reply repeatedly'),
            value: settings.preventDuplicateReplies,
            onChanged: (_) {
              ref
                  .read(appSettingsProvider.notifier)
                  .togglePreventDuplicateReplies();
            },
          ),

          const ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('One-to-one chats only'),
            subtitle: Text(
                'Group chats and chats without clear type or identity are always skipped.'),
          ),

          SwitchListTile(
            title: const Text('Confirm Before Reply'),
            subtitle: const Text('Ask before sending each reply'),
            value: settings.confirmBeforeReply,
            onChanged: (_) {
              ref.read(appSettingsProvider.notifier).toggleConfirmBeforeReply();
            },
          ),

          ],
          ),
          const SizedBox(height: 16),

          // Schedule section
          _SettingsCard(
            title: 'Schedule',
            icon: Icons.schedule,
            children: [
          Text(
            'Set time windows when auto-reply is active',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('Enable Schedule'),
            subtitle: const Text('Auto-reply only during set hours'),
            value: settings.scheduleEnabled,
            onChanged: (_) {
              ref.read(appSettingsProvider.notifier).updateSchedule(
                    enabled: !settings.scheduleEnabled,
                    startHour: settings.scheduleStartHour,
                    startMinute: settings.scheduleStartMinute,
                    endHour: settings.scheduleEndHour,
                    endMinute: settings.scheduleEndMinute,
                  );
            },
          ),

          if (settings.scheduleEnabled) ...[
            ListTile(
              title: const Text('Start Time'),
              subtitle: Text(_formatTime(
                  settings.scheduleStartHour, settings.scheduleStartMinute)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTimePickerDialog(
                context,
                ref,
                settings,
                isStart: true,
              ),
            ),
            ListTile(
              title: const Text('End Time'),
              subtitle: Text(_formatTime(
                  settings.scheduleEndHour, settings.scheduleEndMinute)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTimePickerDialog(
                context,
                ref,
                settings,
                isStart: false,
              ),
            ),
          ],

          // Busy mode indicator
          if (showBusyCard) ...[
            Card(
              color: Colors.blue[50],
              child: ListTile(
                leading: Icon(Icons.timer, color: Colors.blue[700]),
                title: const Text('Busy Mode Active',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(
                    '"${settings.busyReplyText}" until ${_formatBusyUntil(settings.busyUntilTimestamp)}'),
                trailing: IconButton(
                  icon: Icon(Icons.cancel, color: Colors.red[400]),
                  onPressed: () =>
                      ref.read(appSettingsProvider.notifier).clearBusyMode(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'AI Auto-Reply',
            icon: Icons.auto_awesome_outlined,
            children: [
          Text(
            'Choose an AI engine for instant auto-replies when no specific rule matches.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('AI Auto-Reply'),
            subtitle: const Text('Reply with AI when no rule matches'),
            value: settings.aiReplyEnabled,
            onChanged: (_) {
              ref.read(appSettingsProvider.notifier).toggleAiReplyEnabled();
            },
          ),

          if (settings.aiReplyEnabled) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'AI Engine & Provider',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),

            // Engine Option 1: Groq
            _buildEngineOptionCard(
              context: context,
              ref: ref,
              settings: settings,
              engineType: 'groq_api',
              title: 'Groq Cloud API (⚡ Super-Fast)',
              subtitle:
                  'Free limits: 1,000 requests/day and 200,000 tokens/day; actual replies vary.',
              badge: 'High Speed',
              badgeColor: Colors.orange[700]!,
              apiKey: settings.groqApiKey,
              model: settings.groqModel,
              defaultModel: 'openai/gpt-oss-20b',
              availableModels: const [
                'openai/gpt-oss-20b',
                'openai/gpt-oss-120b',
                'qwen/qwen3.6-27b',
              ],
              keyUrl: 'https://console.groq.com',
              onSave: (key, model) {
                ref
                    .read(appSettingsProvider.notifier)
                    .updateGroqConfig(key, model);
              },
            ),

            const SizedBox(height: 8),

            _buildEngineOptionCard(
              context: context,
              ref: ref,
              settings: settings,
              engineType: 'cloudflare_api',
              title: 'Cloudflare Workers AI',
              subtitle:
                  '10,000 free Neurons/day. Reply budget depends on model and message length.',
              badge: 'New',
              badgeColor: Colors.deepOrange,
              apiKey: settings.cloudflareApiKey,
              model: settings.cloudflareModel,
              defaultModel: '@cf/qwen/qwen3-30b-a3b-fp8',
              availableModels: const [
                '@cf/qwen/qwen3-30b-a3b-fp8',
                '@cf/openai/gpt-oss-20b'
              ],
              keyUrl: 'https://dash.cloudflare.com',
              accountId: settings.cloudflareAccountId,
              onSave: (key, model) {},
              onCloudflareSave: (key, account, model) => ref
                  .read(appSettingsProvider.notifier)
                  .updateCloudflareConfig(key, account, model),
            ),
            const SizedBox(height: 8),
            // Engine Option 2: Gemini Flash
            _buildEngineOptionCard(
              context: context,
              ref: ref,
              settings: settings,
              engineType: 'gemini_api',
              title: 'Google Gemini Flash (🌟 Google AI)',
              subtitle:
                  'Free quota depends on project/model. Free inputs may be used to improve Google products.',
              badge: 'Smart',
              badgeColor: Colors.blue[700]!,
              apiKey: settings.geminiApiKey,
              model: settings.geminiModel,
              defaultModel: 'gemini-3.6-flash',
              availableModels: const ['gemini-3.6-flash', 'gemini-2.5-flash'],
              keyUrl: 'https://aistudio.google.com',
              onSave: (key, model) {
                ref
                    .read(appSettingsProvider.notifier)
                    .updateGeminiConfig(key, model);
              },
            ),

            const SizedBox(height: 8),

            // Engine Option 3: On-Device Llama 3.2
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: settings.aiModelType == 'phi_local'
                      ? Theme.of(context).primaryColor
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'phi_local',
                    groupValue: settings.aiModelType,
                    title: const Row(
                      children: [
                        Expanded(
                            child: Text('On-Device Llama 3.2 1B',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        SizedBox(width: 8),
                        Icon(Icons.offline_bolt, size: 18, color: Colors.green),
                      ],
                    ),
                    subtitle: const Text(
                        'Offline local model (run private AI on-device, no internet needed)'),
                    onChanged: (val) {
                      if (val != null) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .updateAiModelType(val);
                      }
                    },
                  ),
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: (settings.aiModelType == 'phi_local' ||
                              settings.fallbackToLocalModel)
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ModelRadioTile(
                                    value: 'llama_3_2_1b',
                                    groupValue: settings.selectedLocalModel,
                                    title: settings.aiModelType == 'phi_local'
                                        ? 'Llama 3.2 1B Instruct'
                                        : 'Llama 3.2 1B Instruct (Fallback)',
                                    subtitle:
                                        '~800MB, blazing fast for basic replies',
                                    onTap: () {
                                      ref
                                          .read(appSettingsProvider.notifier)
                                          .updateSelectedLocalModel(
                                              'llama_3_2_1b');
                                    },
                                    modelId: 'llama_3_2_1b',
                                    selectedModelId:
                                        settings.selectedLocalModel,
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Local Model Fallback Switch ────────────────────────────────
            Card(
              elevation: 0,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceVariant
                  .withOpacity(0.35),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile(
                secondary:
                    const Icon(Icons.shield_outlined, color: Colors.green),
                title: const Text(
                  'Local Model Fallback',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Automatically reply with on-device local model (${_getLocalModelLabel(settings.selectedLocalModel)}) whenever cloud API keys fail, expire, hit limits, or lose connection.',
                  style: const TextStyle(fontSize: 12),
                ),
                value: settings.fallbackToLocalModel,
                onChanged: (val) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .updateFallbackToLocalModel(val);
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── Daily Reply Limits ─────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.speed_rounded, size: 20),
              title: const Text('Daily Reply Limits'),
              subtitle: Text(
                _buildLimitSummary(settings),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDailyLimitsDialog(context, ref, settings),
            ),

            // ── System Prompt ─────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('System Prompt & Persona'),
              subtitle: Text(
                settings.aiSystemPrompt.length > 50
                    ? '${settings.aiSystemPrompt.substring(0, 50)}...'
                    : settings.aiSystemPrompt,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSystemPromptDialog(
                  context, ref, settings.aiSystemPrompt),
            ),

            // ── AI Training Memory ───────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('AI Training Memory'),
              subtitle: Text(
                settings.trainingExamples.isEmpty
                    ? 'No trained examples yet. Train AI in Chat Sandbox.'
                    : '${settings.trainingExamples.length} trained response pattern(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showTrainingMemoryDialog(context, ref, settings),
            ),
          ],

          ],
          ),
          const SizedBox(height: 16),

          // Contact Filtering section
          _SettingsCard(
            title: 'Contact Filtering',
            icon: Icons.people_outline,
            children: [

          _buildContactWhitelistSection(context, ref, settings),
          const SizedBox(height: 8),
          _buildContactBlacklistSection(context, ref, settings),

          ],
          ),
          const SizedBox(height: 16),

          // Appearance section
          _SettingsCard(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            children: [
              Text('Theme', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Choose Light or Dark', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Light')),
                    ButtonSegment<bool>(value: true, label: Text('Dark')),
                  ],
                  selected: {settings.darkMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (choice) {
                    if (choice.first != settings.darkMode) {
                      ref.read(appSettingsProvider.notifier).toggleDarkMode();
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Warning section
          // NOTE: previously used BoxDecoration(border: Border(left: ...)) +
          // borderRadius together, which Flutter can't clip correctly and
          // flickers/repaints while scrolling at the end of the page.
          // Use ClipRRect + accent bar instead for a stable paint.
          RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFFFFFBEB), // Amber-50
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 4, color: const Color(0xFFF59E0B)),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Color(0xFFD97706), size: 22),
                                  SizedBox(width: 8),
                                  Text(
                                    'Important Notice',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Automated replying to WhatsApp or Instagram may violate their Terms of Service. '
                                'This app uses official Android notification APIs where possible. '
                                'Use at your own risk and with caution.',
                                style: TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 12,
                                    height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => checkUpdateManually(context),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Check for updates'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBusyUntil(int timestampMillis) {
    final remaining = Duration(
        milliseconds: timestampMillis - DateTime.now().millisecondsSinceEpoch);
    if (remaining.isNegative) return 'expired';
    if (remaining.inDays > 0)
      return '${remaining.inDays}d ${remaining.inHours % 24}h remaining';
    if (remaining.inHours > 0)
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m remaining';
    return '${remaining.inMinutes}m remaining';
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _buildLimitSummary(AppSettings settings) {
    final parts = <String>[];
    if (settings.groqReplyLimit > 0)
      parts.add('Groq: ${settings.groqReplyLimit}/day');
    if (settings.geminiReplyLimit > 0)
      parts.add('Gemini: ${settings.geminiReplyLimit}/day');
    if (settings.localReplyLimit > 0)
      parts.add('Local: ${settings.localReplyLimit}/day');
    return parts.isEmpty ? 'No limits set (unlimited)' : parts.join(' · ');
  }

  String _getLocalModelLabel(String modelId) {
    switch (modelId) {
      case 'qwen_2_5_1_5b':
        return 'Qwen 2.5 1.5B';
      case 'llama_3_2_1b':
      default:
        return 'Llama 3.2 1B';
    }
  }

  void _showDailyLimitsDialog(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    final groqCtrl = TextEditingController(
      text:
          settings.groqReplyLimit > 0 ? settings.groqReplyLimit.toString() : '',
    );
    final geminiCtrl = TextEditingController(
      text: settings.geminiReplyLimit > 0
          ? settings.geminiReplyLimit.toString()
          : '',
    );
    final localCtrl = TextEditingController(
      text: settings.localReplyLimit > 0
          ? settings.localReplyLimit.toString()
          : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily Reply Limits',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set the maximum number of AI replies per day for each engine. Leave blank or 0 for unlimited.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _LimitField(
                  label: '🔶 Groq Cloud',
                  controller: groqCtrl,
                  hint: 'Free tier: ~1,000/day'),
              const SizedBox(height: 12),
              _LimitField(
                  label: '🔵 Google Gemini',
                  controller: geminiCtrl,
                  hint: 'Free tier: 250–500/day'),
              const SizedBox(height: 12),
              _LimitField(
                  label: '🟣 On-Device (Local)',
                  controller: localCtrl,
                  hint: 'Unlimited (e.g. 200)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              int parseLimit(TextEditingController c) {
                return int.tryParse(c.text.trim()) ?? 0;
              }

              ref.read(appSettingsProvider.notifier).updateAiReplyLimits(
                    groqReplyLimit: parseLimit(groqCtrl),
                    geminiReplyLimit: parseLimit(geminiCtrl),
                    localReplyLimit: parseLimit(localCtrl),
                  );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Daily limits saved')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineOptionCard({
    required BuildContext context,
    required WidgetRef ref,
    required AppSettings settings,
    required String engineType,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required String apiKey,
    required String model,
    required String defaultModel,
    required List<String> availableModels,
    required String keyUrl,
    required Function(String key, String model) onSave,
    String? accountId,
    Future<void> Function(String key, String account, String model)?
        onCloudflareSave,
  }) {
    final isSelected = settings.aiModelType == engineType;
    final hasKey = apiKey.trim().isNotEmpty;
    final effectiveModel = model.isNotEmpty ? model : defaultModel;

    return Card(
      elevation: isSelected ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              isSelected ? Theme.of(context).primaryColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(
            value: engineType,
            groupValue: settings.aiModelType,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor),
                  ),
                ),
              ],
            ),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            onChanged: (val) {
              if (val != null) {
                ref.read(appSettingsProvider.notifier).updateAiModelType(val);
              }
            },
          ),
          // Animated expansion instead of instant insert/remove: an abrupt
          // height change while scrolled at the bottom shifts the scroll
          // extent and looks like a glitch when flinging back to the top.
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: isSelected
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                hasKey
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                size: 16,
                                color: hasKey ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(
                                hasKey
                                    ? 'API Key Configured'
                                    : (settings.fallbackToLocalModel
                                        ? 'API Key Missing (Local Fallback Active)'
                                        : 'API Key Missing'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: hasKey
                                      ? Colors.green[800]
                                      : (settings.fallbackToLocalModel
                                          ? Colors.blue[800]
                                          : Colors.orange[800]),
                                ),
                              )),
                              const Spacer(),
                              Flexible(
                                  child: Text(
                                'Model: $effectiveModel',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              )),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _showApiConfigDialog(
                                  context: context,
                                  title: title,
                                  apiKey: apiKey,
                                  currentModel: effectiveModel,
                                  availableModels: availableModels,
                                  keyUrl: keyUrl,
                                  onSave: onSave,
                                  accountId: accountId,
                                  onCloudflareSave: onCloudflareSave,
                                );
                              },
                              icon: const Icon(Icons.key, size: 16),
                              label: Text(hasKey
                                  ? 'Change API Key / Model'
                                  : 'Set API Key & Model'),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiConfigDialog({
    required BuildContext context,
    required String title,
    required String apiKey,
    required String currentModel,
    required List<String> availableModels,
    required String keyUrl,
    required Function(String key, String model) onSave,
    String? accountId,
    Future<void> Function(String key, String account, String model)?
        onCloudflareSave,
  }) {
    final keyController = TextEditingController(text: apiKey);
    final accountController = TextEditingController(text: accountId ?? '');
    String selectedModel = availableModels.contains(currentModel)
        ? currentModel
        : availableModels.first;
    bool obscureKey = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (accountId != null) ...[
                  TextField(
                      controller: accountController,
                      decoration: const InputDecoration(
                          labelText: 'Cloudflare Account ID',
                          hintText: '32-character ID',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  const Text(
                      'Messages and chat context go to Cloudflare. Token is encrypted on this device. Free budget is model-dependent; no automatic paid upgrade.'),
                  const SizedBox(height: 12),
                ],
                const Text('API Key',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: keyController,
                  obscureText: obscureKey,
                  decoration: InputDecoration(
                    hintText: 'Enter API key',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: TextButton(
                      onPressed: () {
                        setDialogState(() => obscureKey = !obscureKey);
                      },
                      child: Text(obscureKey ? 'Show' : 'Hide'),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Get free API key at $keyUrl',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.blue,
                      decoration: TextDecoration.underline),
                ),
                const SizedBox(height: 16),
                const Text('Model Selection',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  items: availableModels.map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text(m,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedModel = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (onCloudflareSave != null) {
                  if (!RegExp(r'^[a-fA-F0-9]{32}$')
                      .hasMatch(accountController.text.trim())) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Enter the 32-character Cloudflare account ID')));
                    return;
                  }
                  try {
                    await onCloudflareSave(keyController.text.trim(),
                        accountController.text.trim(), selectedModel);
                  } catch (_) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('Could not save Cloudflare configuration')));
                    return;
                  }
                } else {
                  onSave(keyController.text.trim(), selectedModel);
                }
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API Configuration Saved')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimePickerDialog(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings, {
    required bool isStart,
  }) async {
    final initialHour =
        isStart ? settings.scheduleStartHour : settings.scheduleEndHour;
    final initialMinute =
        isStart ? settings.scheduleStartMinute : settings.scheduleEndMinute;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      ref.read(appSettingsProvider.notifier).updateSchedule(
            enabled: settings.scheduleEnabled,
            startHour: isStart ? picked.hour : settings.scheduleStartHour,
            startMinute: isStart ? picked.minute : settings.scheduleStartMinute,
            endHour: isStart ? settings.scheduleEndHour : picked.hour,
            endMinute: isStart ? settings.scheduleEndMinute : picked.minute,
          );
    }
  }

  void _showReplyDelayDialog(
    BuildContext context,
    WidgetRef ref,
    int currentMin,
    int currentMax,
  ) {
    final minController = TextEditingController(text: currentMin.toString());
    final maxController = TextEditingController(text: currentMax.toString());
    int tempMin = currentMin;
    int tempMax = currentMax;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reply Delay Range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Min: $tempMin s  |  Max: $tempMax s'),
              const SizedBox(height: 16),
              TextField(
                controller: minController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minimum delay (seconds)',
                  border: OutlineInputBorder(),
                  suffixText: 's',
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value) ?? 0;
                  setDialogState(() {
                    tempMin = parsed.clamp(0, 300);
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Maximum delay (seconds)',
                  border: OutlineInputBorder(),
                  suffixText: 's',
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value) ?? 0;
                  setDialogState(() {
                    tempMax = parsed.clamp(0, 300);
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsedMin =
                    (int.tryParse(minController.text) ?? tempMin).clamp(0, 300);
                final parsedMax =
                    (int.tryParse(maxController.text) ?? tempMax).clamp(0, 300);
                final min = parsedMin <= parsedMax ? parsedMin : parsedMax;
                final max = parsedMin <= parsedMax ? parsedMax : parsedMin;
                ref
                    .read(appSettingsProvider.notifier)
                    .updateReplyDelayRange(min, max);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactWhitelistSection(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    final contacts = settings.contactWhitelist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Contact Whitelist'),
          subtitle: const Text('Only reply to these contacts when enabled'),
          value: settings.contactWhitelistEnabled,
          onChanged: (_) {
            ref.read(appSettingsProvider.notifier).toggleContactWhitelist();
          },
        ),
        if (settings.contactWhitelistEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    contacts.isEmpty
                        ? 'No contacts added — all messages will be blocked'
                        : '${contacts.length} contact${contacts.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  onPressed: () => _showContactListDialog(
                    context,
                    ref,
                    contacts,
                    'Whitelist',
                    (list) => ref
                        .read(appSettingsProvider.notifier)
                        .updateContactWhitelist(list),
                    (c) => ref
                        .read(appSettingsProvider.notifier)
                        .addToWhitelist(c),
                    (c) => ref
                        .read(appSettingsProvider.notifier)
                        .removeFromWhitelist(c),
                  ),
                ),
              ],
            ),
          ),
          if (contacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: contacts.map((name) {
                  return Chip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      ref
                          .read(appSettingsProvider.notifier)
                          .removeFromWhitelist(name);
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildContactBlacklistSection(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    final contacts = settings.contactBlacklist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Blacklisted Contacts',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => _showContactListDialog(
                  context,
                  ref,
                  contacts,
                  'Blacklist',
                  (list) => ref
                      .read(appSettingsProvider.notifier)
                      .updateContactBlacklist(list),
                  (c) =>
                      ref.read(appSettingsProvider.notifier).addToBlacklist(c),
                  (c) => ref
                      .read(appSettingsProvider.notifier)
                      .removeFromBlacklist(c),
                ),
              ),
            ],
          ),
        ),
        if (contacts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: contacts.map((name) {
                return Chip(
                  label: Text(name, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    ref
                        .read(appSettingsProvider.notifier)
                        .removeFromBlacklist(name);
                  },
                );
              }).toList(),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No blacklisted contacts',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Blacklisted contacts will never receive auto-replies. '
            'Whitelist takes priority when enabled.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  void _showContactListDialog(
    BuildContext context,
    WidgetRef ref,
    List<String> initialList,
    String label,
    void Function(List<String>) onSave,
    void Function(String) onAdd,
    void Function(String) onRemove,
  ) {
    final contacts = List<String>.from(initialList);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$label Contacts'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Add contact names exactly as they appear in notifications.',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person, size: 20),
                        title:
                            Text(contact, style: const TextStyle(fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () {
                            contacts.removeAt(index);
                            setDialogState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Contact name',
                          labelText: 'Add contact',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () {
                        final name = controller.text.trim();
                        if (name.isNotEmpty &&
                            !contacts.any(
                                (c) => c.toLowerCase() == name.toLowerCase())) {
                          contacts.add(name);
                          controller.clear();
                          setDialogState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                onSave(contacts);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSystemPromptDialog(
      BuildContext context, WidgetRef ref, String currentPrompt) {
    final controller = TextEditingController(text: currentPrompt);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI System Prompt'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Instructions for how the AI should reply...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(appSettingsProvider.notifier)
                  .updateAiSystemPrompt(controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showTrainingMemoryDialog(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    showDialog(
      context: context,
      builder: (ctx) {
        final examples = settings.trainingExamples;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.school, color: Colors.blue),
              SizedBox(width: 8),
              Text('AI Training Memory', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: examples.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No training examples saved yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Use "Train AI" on response bubbles in the Chat screen to teach the AI how to reply.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: examples.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = examples[index];
                      final id = item['id'] ?? '';
                      final userMsg = item['userMessage'] ?? '';
                      final reply = item['correctedReply'] ?? '';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'User: "$userMsg"',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Trained Reply: "$reply"',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.green),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: () {
                            ref
                                .read(appSettingsProvider.notifier)
                                .removeTrainingExample(id);
                            Navigator.pop(ctx);
                            _showTrainingMemoryDialog(
                                context, ref, ref.read(appSettingsProvider));
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            if (examples.isNotEmpty)
              TextButton(
                onPressed: () {
                  ref
                      .read(appSettingsProvider.notifier)
                      .clearTrainingExamples();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Cleared all AI training examples.')),
                  );
                },
                child: const Text('Clear All',
                    style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _ModelRadioTile extends StatefulWidget {
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? modelId;
  final String? selectedModelId;

  const _ModelRadioTile({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.modelId,
    this.selectedModelId,
  });

  @override
  State<_ModelRadioTile> createState() => _ModelRadioTileState();
}

class _ModelRadioTileState extends State<_ModelRadioTile>
    with AutomaticKeepAliveClientMixin {
  // Cache availability per model so scrolling (which disposes/recreates
  // offscreen tiles) doesn't re-hit the platform channel and cause a
  // height jump mid-fling — the main "glitch when scrolling to top".
  static final Map<String, bool> _statusCache = {};

  @override
  bool get wantKeepAlive => true;

  bool? _available;
  bool _downloading = false;
  int _progress = 0;
  // Start in checking state so the first frame already reserves the loading
  // layout instead of jumping: content -> spinner -> content.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.modelId != null) {
      final cached = _statusCache[widget.modelId];
      if (cached != null) {
        _available = cached;
      } else {
        _checking = true;
        _checkStatus();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _ModelRadioTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId && widget.modelId != null) {
      final cached = _statusCache[widget.modelId];
      if (cached != null) {
        if (mounted) setState(() => _available = cached);
      } else {
        _checkStatus();
      }
    }
  }

  Future<void> _checkStatus() async {
    if (mounted) setState(() => _checking = true);
    try {
      const channel = MethodChannel('com.replier.replier/native');
      final result = await channel.invokeMethod<Map>('getPhiStatus',
          {'modelId': widget.modelId}).timeout(const Duration(seconds: 10));
      if (result != null && mounted) {
        final available = result['available'] == true;
        if (widget.modelId != null) _statusCache[widget.modelId!] = available;
        setState(() => _available = available);
      }
    } catch (_) {
      // Leave previous/cached value; don't collapse the tile on error.
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      const channel = MethodChannel('com.replier.replier/native');
      channel.setMethodCallHandler((call) async {
        if (call.method == 'onDownloadProgress') {
          final args = call.arguments as Map;
          if (args['modelId'] == widget.modelId && mounted) {
            setState(() => _progress = args['progress'] as int? ?? 0);
          }
        }
      });
      final result = await channel
          .invokeMethod<Map>('downloadPhiModel', {'modelId': widget.modelId});
      if (result?['success'] != true) {
        throw StateError(result?['error']?.toString() ??
            'Download failed. Check network and storage.');
      }
      await _checkStatus();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _delete() async {
    try {
      const channel = MethodChannel('com.replier.replier/native');
      await channel.invokeMethod('deletePhiModel', {'modelId': widget.modelId});
      await _checkStatus();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLocalModel = widget.modelId != null;
    final isAvailable = _available ?? false;
    final isThisSelected = isLocalModel &&
        widget.value == widget.groupValue &&
        widget.modelId == widget.selectedModelId;

    // Fixed-size trailing so async status load (spinner -> icon) can't
    // shift the ListTile layout while scrolled at the bottom.
    final Widget trailing = SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: !isLocalModel
            ? Icon(Icons.phone_android, color: Colors.green[700])
            : _checking && _available == null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : isAvailable
                    ? Icon(Icons.check_circle,
                        color: isThisSelected ? Colors.green : Colors.grey)
                    : const Icon(Icons.download, color: Colors.orange),
      ),
    );

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Radio<String>(
              value: widget.value,
              groupValue: widget.groupValue,
              onChanged:
                  isLocalModel && !isAvailable ? null : (_) => widget.onTap(),
            ),
            title: Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(_downloading
                ? 'Downloading... $_progress%'
                : isLocalModel && !isAvailable
                    ? '${widget.subtitle} (tap download)'
                    : widget.subtitle),
            trailing: isLocalModel && !isAvailable && !_downloading
                ? IconButton(
                    icon: const Icon(Icons.download, color: Colors.orange),
                    onPressed: _download,
                    tooltip: 'Download ${widget.title}')
                : trailing,
            onTap: isLocalModel && !isAvailable
                ? (_downloading ? null : _download)
                : () => widget.onTap(),
          ),
          // Animate bottom-area height changes (download button <->
          // progress <-> status) instead of instant jumps that shift the
          // scroll extent mid-scroll.
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _downloading
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                              value: _progress / 100.0,
                              backgroundColor: Colors.grey[300]),
                          const SizedBox(height: 4),
                          Text(
                              'Downloading... $_progress% — Do not close the app',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : (!isLocalModel || isAvailable)
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  !isLocalModel
                                      ? 'Ready'
                                      : isThisSelected
                                          ? 'Currently active'
                                          : 'Downloaded',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isThisSelected
                                          ? Colors.green[700]
                                          : Colors.grey[600]),
                                ),
                              ),
                              if (isLocalModel &&
                                  isAvailable &&
                                  !isThisSelected)
                                TextButton(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('Delete ${widget.title}?'),
                                        content: const Text(
                                            'You can re-download later.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Delete',
                                                  style: TextStyle(
                                                      color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) _delete();
                                  },
                                  child: const Text('Delete',
                                      style: TextStyle(
                                          color: Colors.red, fontSize: 12)),
                                ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _checking ? null : _download,
                              icon: const Icon(Icons.download, size: 18),
                              label: Text('Download ${widget.title}'),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isGranted;
  final VoidCallback onGrant;

  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.isGranted,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          isGranted ? Icons.check_circle : Icons.error,
          color: isGranted ? Colors.green : Colors.orange,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        // Fixed-width trailing so the async permission check
        // (Grant button <-> Granted label) can't change row layout and
        // shift scroll extent while the user is at the bottom.
        trailing: SizedBox(
          width: 88,
          child: Align(
            alignment: Alignment.centerRight,
            child: isGranted
                ? const Text('Granted', style: TextStyle(color: Colors.green))
                : ElevatedButton(
                    onPressed: onGrant, child: const Text('Grant')),
          ),
        ),
      ),
    );
  }
}

/// Rounded section card with an icon heading used on the Settings screen
class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = DraftColors.of(context);
    return Material(
      color: c.s1,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: c.pri),
                const SizedBox(width: 10),
                Text(title, style: DraftText.display(18, c.tx)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Small labeled numeric input for daily limit dialogs
class _LimitField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;

  const _LimitField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            helperText: 'Leave blank or 0 for unlimited',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixText: 'replies/day',
          ),
        ),
      ],
    );
  }
}
