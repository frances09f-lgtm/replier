# Replier

Android reply assistant for WhatsApp and Instagram notifications, with keyword rules, optional AI, reply confirmation, logs and notes. Current build: **v19 / 1.0.19+19**. Cloudflare Workers AI is optional in this release; live Cloudflare inference still needs a configured user token and a phone test.

## Install and first setup

1. Download `Replier.apk` from this repository's **Releases** section. Use the latest published release, not an arbitrary Actions artifact.
2. Install on an ARM64 Android phone running Android 8.0 or newer. Allow installation from the browser/Files app if Android asks.
3. Open Replier. Continue through **Set up Replier** with replies off.
4. Disable the previous Replier app's notification/accessibility access if it is still installed. This avoids two reply apps watching the same messages; the new app also blocks conflicting legacy services.
5. Open **Settings** and grant **Notification Access** to Replier in Android settings. This lets it receive the supported apps' notifications, including their message contents.
6. Allow Replier notifications so confirmation prompts and service status can appear. Review battery-optimization settings if Android stops its service.
7. Start with **Confirm Before Reply** on, **Ignore Group Chats** on, and a narrow contact whitelist. Enable only the messaging apps you intend to use.
8. Add one test rule, then turn on the master reply switch in Dashboard. Have a consenting test contact send a new message while its notification is visible.

Replier reads notifications, not a complete WhatsApp/Instagram inbox. A muted chat, missing notification or notification without an inline-reply action can prevent replies. Never assume a reply was sent because AI generated text. Check the log and the actual conversation.

## Rules do not need an API key

Open **Manage Rules → Add Rule**. Enter trigger text and the reply you want, choose **Exact Match** or **Contains Match**, check case sensitivity and optional contact filters, then enable/save the rule. Set reply-delay range, duplicate prevention, schedule and daily limits in Settings.

A rule can send your words to another person. Review its text and recipients carefully before enabling it. Turning off confirmation allows automatic replies under your configured rules; do not enable that accidentally.

## Confirmation and sending limits

**Confirm Before Reply** prompts you before each send. A confirmation left unanswered for 15 seconds is cancelled, not auto-sent. Old versions behaved differently; use the current release.

The only supported sending path is the messaging app's Android notification inline reply. **This version contains no Accessibility service** and does not request Accessibility access. If inline reply is unavailable, reply manually in the messaging app. Disable Accessibility access for previous Replier installations as described above; legacy-install conflict checks are retained.

## Optional AI setup

1. Open **Settings → AI Auto-Reply** and enable it if you want AI when no rule matches.
2. Under **AI Engine & Provider**, choose the provider you want.
3. Open that provider's configuration, enter your own key/token and selected model, then save.
4. Set **System Prompt & Persona**, review training memory and any configured conversation context, and keep confirmation on during testing.

| Engine | What you need | Where to put it |
| --- | --- | --- |
| Groq Cloud API | Your Groq API key from `https://console.groq.com/keys` | Groq provider configuration in Settings |
| Google Gemini | Your Gemini API key from `https://aistudio.google.com/apikey` | Gemini provider configuration in Settings |
| Cloudflare Workers AI | Your 32-character Cloudflare Account ID and a token permitted to use Workers AI for that account | Cloudflare provider configuration: Account ID, API token, model |
| On-device | One supported local model download | On-device model card in Settings; no cloud key |

Provider keys are secrets. They are stored encrypted on Android and excluded from settings backups, not bundled in the APK. Account IDs and model names identify configuration; they are not passwords. No shared provider key/token is included here.

Cloud AI sends message text and the configured context to the selected provider. Review this before enabling it for private conversations. Provider availability, quotas and pricing can change; verify them in your provider account. Do not interpret a model dropdown or displayed budget as unlimited free replies.

### v19 safety update

Automatic replies now require confirmed one-to-one notification metadata and the original stable conversation/app identity. Groups and uncertain chats are skipped, including at delayed-send revalidation; incomplete app metadata can also cause genuine direct chats to be skipped. Analysis has a 100-second overall deadline with an animated countdown; expired results cannot schedule a reply. The unused Accessibility service is removed. Current models/providers and the existing dashboard layout are preserved. Real-phone notification and inference behavior still needs testing.

### Cloudflare in v18

Open `https://dash.cloudflare.com`, select your account and copy its Account ID. Create a token through your Cloudflare account's API-token settings with **Account → Workers AI → Read**, scoped to that account. Do not use a Global API Key. Enter the Account ID, token and chosen Workers AI model in Replier's Cloudflare card. The default model is `@cf/qwen/qwen3-30b-a3b-fp8`; another offered option is `@cf/openai/gpt-oss-20b`.

No Cloudflare Worker deployment, server URL or separate Firebase key is needed for this direct Workers AI request. Do not paste a token into GitHub or send it in chat. v18 adds this provider without replacing existing provider choice, stored keys or local-model setup. The app does not automatically upgrade a provider account to paid usage.

### On-device models

Choose **On-Device Llama 3.2 1B**, then the local model card. The current choices include **Llama 3.2 1B Instruct** (about 800 MB) and **Qwen 2.5 1.5B Instruct** (about 980 MB). Use the app's download control and wait until the model is ready; leave enough free storage and keep the app open during setup. Local fallback is a separate setting for cloud failures.

Model download completion is not proof of good reply quality. Test generation with confirmation on. Performance and language quality depend on the model and phone. Replier's local models are different from Friday's Qwen .task model; do not interchange their files.

## Other screens

- **Chat:** test AI and train preferred replies without sending a real notification reply.
- **View Logs:** inspect attempted/sent/failed reply history.
- **Notes & Reminders:** review extracted notes; check dates and details before relying on a reminder.
- **Settings:** schedule, contact whitelist, group exclusion, app selection, confirmation, AI/provider/model, daily limits, persona, memory and theme.

## Troubleshooting

- **No incoming message seen:** check Android Notification Access and that WhatsApp/Instagram notifications are enabled for that chat.
- **Reply not sent:** check master switch, app enablement, schedule, contact whitelist, group exclusion, delay/limits and unanswered confirmation. Inline reply must exist on the notification.
- **AI fails:** verify the selected provider, saved key, model and account quota. For Cloudflare, confirm the token's account scope and Workers AI permission.
- **Repeated replies:** leave duplicate prevention enabled and check that an older reply assistant is not still active.
- **Service stops:** review battery restrictions. Android force-stop and vendor restrictions can stop work; no always-on guarantee is made.
- **Local model fails:** check free storage, completed model download and device performance. Try a rule-only test to separate AI from notification sending.
- **Confirmation never appears:** allow Replier notifications and check Android notification-channel settings. No response means cancel.

## Build from source

CI pins Flutter 3.47.6 and Java 17:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release --target-platform android-arm64
cd android && ./gradlew app:testDebugUnitTest
```

Package: `com.ambi.replier`. CI uses the private permanent release signer. A locally debug-signed APK cannot replace that installed release in place. Use your own keystore for your own distribution; never commit it or its passwords.

Never commit provider tokens, passwords, device backups containing private messages, or private conversation screenshots. Do not place runtime API keys in Dart source, assets, Gradle properties or Actions logs.
