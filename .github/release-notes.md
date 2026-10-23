## Replier v1.1.6

### Fix: dashboard card stuck on "Sending the reply"
- An overdue reply countdown card now clears itself after 30 seconds instead of staying at 0 seconds.
- The dashboard listeners now start when the app launches, so early events are not missed.
- Reply cards no longer wait on the log save before they update.
- A 60 second check restarts the message listener if Android drops it, and the background service restart is guarded against errors.

The Settings screen is not changed. Reply logic, storage and permissions are the same as v1.1.5 apart from the guards above. (pull request #5)

### Not verified
Nothing was tested on a phone. The causes above were found by reading the code, so it is not known which one affects the phone. CI ran analyze, tests, the release APK build and the Android unit tests.
