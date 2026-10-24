## Replier v1.1.7

### Diagnostic: failed replies now show their reason in the Logs tab
- Every failed reply attempt is now saved to Logs with a short, sanitized reason (credentials, URLs, emails and phone numbers redacted; no sender or message content is stored).
- Failed entries show as "Reply failed", do not inflate the daily-replies count, and stay visible under any app filter.
- An AI attempt that times out now reports "AI attempt timed out before any reply was ready" instead of failing silently, and expiry can no longer fire twice.
- Logs written by older app versions still read correctly after the upgrade.

### What this build is for
Install it, send one test message, then open Logs: the reason line under "Reply failed" is the actual cause of "stuck, not replying". (pull request #6)

### Not verified
Nothing was tested on a phone. CI ran analyze, tests, the release APK build and the Android unit tests.
