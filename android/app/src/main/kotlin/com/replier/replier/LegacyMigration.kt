package com.replier.replier
import android.content.Context
import android.provider.Settings
object LegacyMigration {
 const val OLD = "com.replier.replier"
 fun status(c:Context):Map<String,Boolean>{
  val present=try{c.packageManager.getApplicationInfo(OLD,0);true}catch(_:Exception){false}
  val notifications=(Settings.Secure.getString(c.contentResolver,"enabled_notification_listeners")?:"").split(':').any{it.substringBefore('/')==OLD}
  val accessibility=(Settings.Secure.getString(c.contentResolver,Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)?:"").split(':').any{it.substringBefore('/')==OLD}
  return mapOf("installed" to present,"notification" to notifications,"accessibility" to accessibility)
 }
 fun blocked(c:Context)=status(c).let{it["notification"]==true||it["accessibility"]==true}
}
