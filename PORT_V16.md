# Replier 16 working-engine port

Ports reviewed old Replier screens, rules, MLKit, GGUF model engine/downloads, runtime cloud providers, chat, notes/reminders and native background pipeline into the existing com.ambi.replier update identity. No private old Git history or device history is copied into this repository. The source repos are unchanged.

Safety differences: master OFF at install, confirmation ON, explicit first-run setup. Confirmation expires without sending. Provider keys are runtime-entered and encrypted with Android Keystore; keys do not enter settings files, Hive or cloud sync. Backup disabled. Old app notification/accessibility permissions block sends. Accessibility sending is disabled until recipient identity can be proven. RemoteInput submission is not a delivery receipt. Prior new-app history remains in the Archive action in Reply Logs; its Hive type ID is reserved and the new rule type is 51.

Cloud providers receive message/conversation text when enabled by the user. No embedded provider keys and no inherited usage telemetry. Models download only at the user's request. v15's canned draft brain is replaced by the old native engine. This does not alter Friday's Qwen engine.

Tests cover Flutter logic, first-install defaults, plaintext persistence prevention, screens and old native unit tests. Real WhatsApp/Instagram notification receipt/reply, background behavior on different Android versions, local GGUF memory limits and on-device Keystore behavior require phone testing. No real contact messages are sent by CI.
