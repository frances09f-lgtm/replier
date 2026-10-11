import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global ProviderContainer for accessing providers outside the widget tree.
/// Used by AutoReplyService to notify the logs provider when new logs arrive.
final globalProviderContainer = ProviderContainer();
