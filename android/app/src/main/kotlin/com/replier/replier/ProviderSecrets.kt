package com.replier.replier
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
/** Only runtime-entered provider keys. Ciphertext is stored; key never leaves Android Keystore. */
object ProviderSecrets {
 private const val ALIAS="replier.provider.keys.v1"
 private fun key():SecretKey {val ks=KeyStore.getInstance("AndroidKeyStore").apply{load(null)};val old=ks.getKey(ALIAS,null) as? SecretKey;if(old!=null)return old;return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply{init(KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())}.generateKey()}
 fun write(c:Context,provider:String,value:String){require(provider in setOf("groq","gemini"));val p=c.getSharedPreferences("encrypted_provider_keys",0);if(value.isEmpty()){p.edit().remove(provider).commit();return};val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key());p.edit().putString(provider,Base64.encodeToString(cipher.iv+cipher.doFinal(value.toByteArray(Charsets.UTF_8)),Base64.NO_WRAP)).commit()}
 fun read(c:Context,provider:String):String {require(provider in setOf("groq","gemini"));val value=c.getSharedPreferences("encrypted_provider_keys",0).getString(provider,null)?:return "";return try{val data=Base64.decode(value,Base64.NO_WRAP);val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,data.copyOfRange(0,12)));String(cipher.doFinal(data.copyOfRange(12,data.size)),Charsets.UTF_8)}catch(_:Exception){""}}
}
