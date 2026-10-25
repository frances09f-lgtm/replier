## Replier v1.2.1

### Fixes
- The send timer is back on the Analysis card: while a reply waits for its delay, the ring shows the seconds left (e.g. "12s"), fills as it counts down, and the status reads "Sending in 12s". With no delay (or when it reaches 0) it shows "Sending now…".
- "AI replies" on the Dashboard now counts only AI replies actually sent today. It was counting every entry in Logs without a rule, including skip/failure/diagnostic entries, so it climbed to the Logs limit of 1000.

## v1.2.0

### Fixes
- AI replies no longer get stuck at "Got new message". WhatsApp's summary notification for the same chat was cancelling the queued reply; it is now ignored (shown in Logs as "Ignored WhatsApp summary notification").
- Groq replies work again with gpt-oss models. The app sent a setting Groq rejects for them, so every reply silently fell back to the on-phone model.
- No more doubled replies like "Ok, cool.Ok, cool." from the on-phone model.
- On-phone model replies are no longer dropped when its output starts with a role header or marker, and a failed on-phone reply (or failed fallback) now always shows its reason in Logs.

### Dashboard
- The Analysis card is smaller and stays the same height in every state. Several analyses at once show as "+N more".

## v1.1.9+35
- Pipeline events now persist to disk, so skip/failure reasons survive the app being force-closed before the Logs tab is opened.
- The listener records an entry event for every supported-app notification, so an empty Logs tab now means the listener saw nothing at all.

## Replier v1.1.8

### Diagnostic: nothing in Logs is now explained
- Pipeline events are now recorded natively, so a reply that fails or is skipped while the app is closed still appears in Logs when you open the app.
- Every silent skip now records its reason: master switch off, app disabled, outside schedule window, self-sent message, repeated message, non-1:1 chat, sender not allowed, no rule matched and AI replies off, notification artifact.
- Failed replies are still logged live when the app is running, unchanged from v1.1.7.

### What this build is for
Install it, send one test message, then open the app: Logs now shows exactly which step stopped the reply. (pull request #7)
