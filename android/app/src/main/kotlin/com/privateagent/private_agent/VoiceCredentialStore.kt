package com.privateagent.private_agent

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-bound broker token only. Provider API keys never enter this store. */
class VoiceCredentialStore(context: Context, messenger: BinaryMessenger) {
    private val prefs = context.getSharedPreferences("voice_credentials", Context.MODE_PRIVATE)
    private val alias = "greensoil.voice.broker.v1"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    init {
        MethodChannel(messenger, "greensoil/voice_credentials").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> {
                        val raw = prefs.getString("broker", null)
                        if (raw == null) result.success(null) else {
                            val bytes = Base64.decode(raw, Base64.NO_WRAP)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                            result.success(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
                        }
                    }
                    "write" -> {
                        val token = call.argument<String>("token") ?: ""
                        require(token.length <= 4096 && !token.startsWith("AIza"))
                        if (token.isEmpty()) prefs.edit().remove("broker").commit() else {
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            check(prefs.edit().putString("broker", Base64.encodeToString(cipher.iv + cipher.doFinal(token.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)).commit())
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("CREDENTIAL_STORE", "Secure voice credential storage unavailable; re-pair device", null) }
        }
    }
}
