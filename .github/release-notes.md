## Replier v1.1.5

### Fix: stuck "Sending the reply" card
The dashboard card could stay on "Sending the reply" when no final event arrived. The sending stage now has a 30 second guard after its countdown ends, so the card clears itself instead of staying on screen. (pull request #2)

### Settings restyle
The Settings screen is regrouped into rounded cards with icon headings: Permissions, App Settings, Schedule, AI Auto-Reply, Contact Filtering and Appearance. Appearance has a Light / Dark choice, and the Groq API key field has a Show / Hide button. Settings still opens from the gear at the top right. (new pull request on top of this version, replacing the draft built on the older code)

Same options and the same stored values as before. Reply logic, storage and permissions are not changed.

### Not verified
Nothing was tested on a phone. CI ran analyze, tests, the release APK build and the Android unit tests.
