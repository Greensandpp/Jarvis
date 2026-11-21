package com.greensoil.experiment.greensoil_livekit_voice_experiment

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var importer: MethodChannel.Result? = null
    private var recognizer: SpeechRecognizer? = null
    private var speech: MethodChannel.Result? = null
    private var permission: MethodChannel.Result? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var utterance: MethodChannel.Result? = null
    private var utteranceId: String? = null
    private var serial = 0L
    private val expectedSize = 639446688L
    private val expectedHash = "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031"
    private val model get() = File(filesDir, "offline-model/Qwen3-0.6B-Q8_0.gguf")

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        tts = TextToSpeech(this) { status -> ttsReady = status == TextToSpeech.SUCCESS }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) { main.post { finishUtterance(id, null) } }
            @Deprecated("Android compatibility")
            override fun onError(id: String?) { main.post { finishUtterance(id, "Offline voice failed") } }
        })
        MethodChannel(engine.dartExecutor.binaryMessenger, "gs.jarvis.offline/bridge").setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(mapOf(
                    "onDeviceRecognizer" to (Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)),
                    "offlineVoices" to (if (ttsReady) tts?.voices?.filter { offlineVoice(it) && it.locale.language in setOf("ta", "en") }?.map { "${it.locale.toLanguageTag()}: ${it.name}" } else emptyList<String>())
                ))
                "stop" -> { stopAll(); result.success(null) }
                "savedModel" -> io.execute {
                    try { verify(model); main.post { result.success(model.absolutePath) } }
                    catch (_: Exception) { main.post { result.error("model_missing", "No verified saved model. Import the downloaded GGUF.", null) } }
                }
                "importModel" -> {
                    if (importer != null) result.error("busy", "Picker already open", null)
                    else { importer = result; startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE) }, 8701) }
                }
                "listen" -> listen(call.argument<String>("language") ?: "ta-IN", result)
                "speak" -> speak(call.argument<String>("text") ?: "", call.argument<String>("language") ?: "ta-IN", result)
                else -> result.notImplemented()
            }
        }
    }
    private fun verify(file: File) {
        require(file.isFile && file.length() == expectedSize)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) { if (Thread.currentThread().isInterrupted) throw InterruptedException(); val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        require(digest.digest().joinToString("") { "%02x".format(it) } == expectedHash)
    }
    @Deprecated("Document picker compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 8701) return
        val result = importer ?: return; importer = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || uri.scheme != "content") { result.error("cancelled", "Import cancelled", null); return }
        io.execute {
            val temp = File(filesDir, "offline-model/import.partial")
            try {
                temp.parentFile!!.mkdirs(); require(filesDir.usableSpace > expectedSize + 64 * 1024 * 1024)
                contentResolver.openInputStream(uri)!!.use { input -> temp.outputStream().buffered().use { output ->
                    val buffer = ByteArray(1024 * 1024); var total = 0L
                    while (true) { if (Thread.currentThread().isInterrupted) throw InterruptedException(); val n = input.read(buffer); if (n < 0) break; total += n; require(total <= expectedSize); output.write(buffer, 0, n) }
                } }
                verify(temp); check(temp.renameTo(model)); main.post { result.success(model.absolutePath) }
            } catch (_: Exception) { temp.delete(); main.post { result.error("invalid_model", "Choose the exact 639 MB Qwen3-0.6B-Q8_0.gguf. Check free storage and SHA-256.", null) } }
        }
    }
    private fun listen(language: String, result: MethodChannel.Result) {
        stopAll()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { permission = result; requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 8702); return }
        if (Build.VERSION.SDK_INT < 33 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) { result.error("offline_stt", "On-device recognition unavailable. Use typed chat.", null); return }
        speech = result
        val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(this); recognizer = r
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(value: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(results: Bundle?) {}
            override fun onEvent(type: Int, params: Bundle?) {}
            override fun onError(error: Int) { if (speech === result) finishSpeech(null, "Offline recognition error $error. No cloud fallback; use typed chat.") }
            override fun onResults(results: Bundle?) { if (speech === result) finishSpeech(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull(), null) }
        })
        r.checkRecognitionSupport(intent, mainExecutor, object : RecognitionSupportCallback {
            override fun onSupportResult(support: RecognitionSupport) {
                if (speech !== result) return
                if (!support.installedOnDeviceLanguages.any { Locale.forLanguageTag(it).language == Locale.forLanguageTag(language).language }) finishSpeech(null, "Offline $language speech pack not installed. Install it in Android Speech Services or use typed chat.")
                else { r.startListening(intent); main.postDelayed({ if (speech === result) finishSpeech(null, "Microphone timed out; tap Listen again") }, 25000) }
            }
            override fun onError(error: Int) { if (speech === result) finishSpeech(null, "Cannot verify installed offline $language recognition ($error). Use typed chat.") }
        })
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 8702) { permission?.error("permission", "Permission updated. Tap Listen again to start intentionally.", null); permission = null }
    }
    private fun finishSpeech(text: String?, error: String?) {
        val result = speech; speech = null
        recognizer?.cancel(); recognizer?.destroy(); recognizer = null
        if (error == null) result?.success(text) else result?.error("offline_stt", error, null)
    }
    private fun offlineVoice(voice: android.speech.tts.Voice): Boolean = !voice.isNetworkConnectionRequired && voice.features?.none { it.contains("notinstalled", true) } != false
    private fun speak(text: String, language: String, result: MethodChannel.Result) {
        stopAll()
        val voice = if (ttsReady) tts?.voices?.filter { offlineVoice(it) && it.locale.language == Locale.forLanguageTag(language).language }?.sortedByDescending { (if (it.locale.toLanguageTag().equals(language, true)) 10000 else 0) + it.quality }?.firstOrNull() else null
        if (voice == null) { result.error("offline_tts", "No installed offline $language voice. Text reply remains available.", null); return }
        if (text.isBlank()) { result.success(null); return }
        if (tts?.setVoice(voice) != TextToSpeech.SUCCESS) { result.error("offline_tts", "Voice selection failed", null); return }
        val id = "offline-${++serial}"; utteranceId = id; utterance = result
        if (tts?.speak(text.take(3500), TextToSpeech.QUEUE_FLUSH, null, id) != TextToSpeech.SUCCESS) finishUtterance(id, "Offline speech failed")
    }
    private fun finishUtterance(id: String?, error: String?) {
        if (id != utteranceId) return
        val result = utterance; utterance = null; utteranceId = null
        if (error == null) result?.success(null) else result?.error("offline_tts", error, null)
    }
    private fun stopAll() { finishSpeech(null, "Cancelled"); val id = utteranceId; tts?.stop(); if (id != null) finishUtterance(id, "Cancelled") }
    override fun onPause() { stopAll(); super.onPause() }
    override fun onDestroy() { stopAll(); tts?.shutdown(); io.shutdownNow(); super.onDestroy() }
}
