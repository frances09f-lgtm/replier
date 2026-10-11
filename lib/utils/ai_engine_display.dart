import 'package:flutter/material.dart';

/// Labels and styling for AI engine types used in dashboard and logs.
class AiEngineDisplay {
  AiEngineDisplay._();

  static const List<String> allEngineIds = [
    'groq_api',
    'gemini_api',
    'phi_local',
  ];

  static ({String label, IconData icon, Color color}) forEngine(
      String engineId) {
    return switch (engineId) {
      'groq_api' => (
          label: 'Groq Cloud',
          icon: Icons.speed,
          color: Colors.orange.shade700,
        ),
      'gemini_api' => (
          label: 'Google Gemini',
          icon: Icons.auto_awesome,
          color: Colors.blue.shade700,
        ),
      'phi_local' => (
          label: 'On-Device AI',
          icon: Icons.memory,
          color: Colors.purple,
        ),
      'deepseek_local' => (
          label: 'DeepSeek (On-Device)',
          icon: Icons.memory,
          color: Colors.purple,
        ),
      _ => (
          label: engineId,
          icon: Icons.smart_toy,
          color: Colors.grey,
        ),
    };
  }
}
