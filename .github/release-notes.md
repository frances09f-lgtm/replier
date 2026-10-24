## Replier v1.1.8

### Diagnostic: nothing in Logs is now explained
- Pipeline events are now recorded natively, so a reply that fails or is skipped while the app is closed still appears in Logs when you open the app.
- Every silent skip now records its reason: master switch off, app disabled, outside schedule window, self-sent message, repeated message, non-1:1 chat, sender not allowed, no rule matched and AI replies off, notification artifact.
- Failed replies are still logged live when the app is running, unchanged from v1.1.7.

### What this build is for
Install it, send one test message, then open the app: Logs now shows exactly which step stopped the reply. (pull request #7)
