package com.replier.replier.reminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Schedules and cancels note-reminder alarms on the native side.
 *
 * Reminders are fired BEFORE the note's event time (Flutter computes the
 * `notifyAt` timestamp). Alarms use AlarmManager so they survive the Flutter
 * engine being closed. Pending reminders are persisted so they can be
 * re-armed after a device reboot.
 */
class NoteReminderScheduler private constructor(private val context: Context) {

    companion object {
        private const val TAG = "NoteReminderScheduler"
        private const val PREFS_NAME = "note_reminder_prefs"
        private const val KEY_REMINDERS = "reminders_json"

        @Volatile
        private var instance: NoteReminderScheduler? = null

        fun getInstance(context: Context): NoteReminderScheduler =
            instance ?: synchronized(this) {
                instance ?: NoteReminderScheduler(context.applicationContext).also { instance = it }
            }
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /**
     * Reconcile the native alarm set so it exactly matches `reminders`.
     *
     * Each reminder map has keys: id (String), title (String), body (String),
     * notifyAt (Long millis). Reminders whose notifyAt is already in the past
     * are skipped. Alarms for ids no longer present (deleted/completed/past)
     * are cancelled.
     */
    fun syncReminders(reminders: List<Map<String, Any>>) {
        val now = System.currentTimeMillis()

        // Persist only the reminders that will actually fire
        val toSchedule = reminders.filter {
            (it["notifyAt"] as? Number)?.toLong()?.let { ts -> ts > now } == true
        }
        val freshIds = toSchedule.map { it["id"].toString() }.toSet()

        // Cancel alarms that are no longer wanted
        val previousIds = loadPersistedIds()
        (previousIds - freshIds).forEach { id ->
            cancelAlarmForId(id)
        }

        // (Re)arm wanted alarms — AlarmManager replaces an existing alarm with
        // the same request code, so this doubles as an update.
        toSchedule.forEach { reminder ->
            val id = reminder["id"].toString()
            val notifyAt = (reminder["notifyAt"] as Number).toLong()
            val title = reminder["title"]?.toString().orEmpty()
            val body = reminder["body"]?.toString().orEmpty()
            armAlarm(id, title, body, notifyAt)
        }

        persist(toSchedule)
        Log.d(TAG, "syncReminders: scheduled=${toSchedule.size}, cancelled=${(previousIds - freshIds).size}")
    }

    /** Cancel the reminder alarm for a single note id. */
    fun cancelReminder(id: String) {
        cancelAlarmForId(id)
        val remaining = loadPersisted()
            .filter { it.optString("id") != id }
        persist(remaining.map { persistedAsMap(it) })
        Log.d(TAG, "cancelReminder: cancelled alarm for '$id'")
    }

    /** Re-arm every persisted reminder whose time is still in the future. */
    fun rescheduleDueToBoot() {
        val now = System.currentTimeMillis()
        val persisted = loadPersisted()
        val future = persisted.filter { it.optLong("notifyAt", 0L) > now }
        future.forEach { obj ->
            armAlarm(
                id = obj.optString("id"),
                title = obj.optString("title"),
                body = obj.optString("body"),
                notifyAt = obj.optLong("notifyAt", 0L),
            )
        }
        persist(future.map { persistedAsMap(it) })
        Log.d(TAG, "rescheduleDueToBoot: re-armed ${future.size} future reminders, dropped ${persisted.size - future.size} expired")
    }

    private fun armAlarm(id: String, title: String, body: String, notifyAt: Long) {
        val intent = Intent(context, NoteReminderReceiver::class.java).apply {
            putExtra(NoteReminderReceiver.EXTRA_NOTE_ID, id)
            putExtra(NoteReminderReceiver.EXTRA_TITLE, title)
            putExtra(NoteReminderReceiver.EXTRA_BODY, body)
        }
        val pending = PendingIntent.getBroadcast(
            context,
            requestCodeFor(id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, notifyAt, pending)
            } else {
                @Suppress("DEPRECATION")
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, notifyAt, pending)
            }
            Log.d(TAG, "Armed exact reminder for '$id' at $notifyAt")
        } catch (e: SecurityException) {
            // SCHEDULE_EXACT_ALARM may be denied on Android 12+ — fall back to an
            // inexact alarm instead of failing silently.
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, notifyAt, pending)
            Log.w(TAG, "Exact alarm denied for '$id'; using inexact alarm", e)
        }
    }

    private fun cancelAlarmForId(id: String) {
        val intent = Intent(context, NoteReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            requestCodeFor(id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.cancel(pending)
        Log.d(TAG, "Cancelled alarm for '$id'")
    }

    private fun requestCodeFor(id: String): Int = id.hashCode()

    // ── Persistence (used to re-arm after reboot) ──────────────────────────

    private fun loadPersisted(): List<JSONObject> {
        val raw = prefs.getString(KEY_REMINDERS, "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse persisted reminders: $e")
            emptyList()
        }
    }

    private fun loadPersistedIds(): Set<String> = loadPersisted().map { it.optString("id") }.toSet()

    private fun persistedAsMap(obj: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = obj.get(key)
        }
        return map
    }

    private fun persist(reminders: List<Map<String, Any>>) {
        val arr = JSONArray()
        reminders.forEach { reminder ->
            arr.put(JSONObject(reminder))
        }
        prefs.edit().putString(KEY_REMINDERS, arr.toString()).commit()
    }
}
