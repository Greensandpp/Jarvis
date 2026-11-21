package com.privateagent.private_agent

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Explicit, foreground-only audio I/O for the owner-opted-in Gemini Live
 * session. Nothing here records unless Dart calls startCapture after the
 * owner taps the Live button and RECORD_AUDIO is granted. Audio is never
 * written to disk. Capture stops on release(), focus loss or activity destroy.
 */
class LiveAudioBridge(private val context: Context, messenger: BinaryMessenger) {
    companion object {
        const val METHOD = "greensoil/live_audio"
        const val EVENTS = "greensoil/live_audio/events"
        const val IN_RATE = 16000
        const val CHUNK_BYTES = 1600 // 50 ms of 16 kHz mono PCM16
    }

    private val main = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var sink: EventChannel.EventSink? = null

    private var record: AudioRecord? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var agc: AutomaticGainControl? = null
    private var captureThread: Thread? = null
    private val capturing = AtomicBoolean(false)

    private var track: AudioTrack? = null
    private var trackRate = 0
    private data class Packet(val pcm: ByteArray, val epoch: Long)
    private val playQueue = LinkedBlockingQueue<Packet>(64)
    private val playbackEpoch = AtomicLong(0)
    private val playbackLock = Any()
    private var playThread: Thread? = null
    private val playing = AtomicBoolean(false)

    private var focusRequest: AudioFocusRequest? = null
    private var previousMode = AudioManager.MODE_NORMAL
    private var noisyRegistered = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            if (i?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                emit(mapOf("type" to "route", "value" to "noisy"))
            }
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> emit(mapOf("type" to "focus", "value" to "lost"))
            AudioManager.AUDIOFOCUS_GAIN -> emit(mapOf("type" to "focus", "value" to "gained"))
        }
    }

    init {
        MethodChannel(messenger, METHOD).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startCapture" -> result.success(startCapture())
                    "stopCapture" -> { stopCapture(); result.success(true) }
                    "play" -> {
                        val bytes = call.argument<ByteArray>("pcm")
                        val rate = call.argument<Int>("rate") ?: 24000
                        if (bytes != null) enqueue(bytes, rate)
                        result.success(true)
                    }
                    "flush" -> { flushPlayback(); result.success(true) }
                    "release" -> { release(); result.success(true) }
                    "capabilities" -> result.success(mapOf(
                        "aec" to AcousticEchoCanceler.isAvailable(),
                        "ns" to NoiseSuppressor.isAvailable(),
                        "agc" to AutomaticGainControl.isAvailable(),
                        "sdk" to Build.VERSION.SDK_INT,
                    ))
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("PERMISSION", "Microphone permission not granted", null)
            } catch (e: Exception) {
                result.error("AUDIO", "Audio device unavailable", null)
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
    }

    private fun emit(event: Any) {
        main.post { sink?.success(event) }
    }

    private fun requestFocus(): Boolean {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener(focusListener, main)
            .build()
        focusRequest = req
        return audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    /** Prefer a connected Bluetooth / wired headset, otherwise loudspeaker. */
    private fun routeOutput() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val devices = audioManager.availableCommunicationDevices
            val preferred = devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET
            } ?: devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            if (preferred != null) audioManager.setCommunicationDevice(preferred)
            emit(mapOf("type" to "route", "value" to (preferred?.type?.toString() ?: "default")))
        } else {
            legacySpeakerRoute()
        }
    }

    @Suppress("DEPRECATION")
    private fun legacySpeakerRoute() {
        audioManager.isSpeakerphoneOn = !audioManager.isWiredHeadsetOn
    }

    @SuppressLint("MissingPermission") // RECORD_AUDIO is checked explicitly below.
    private fun startCapture(): Boolean {
        if (capturing.get()) return true
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("RECORD_AUDIO")
        }
        if (!requestFocus()) {
            emit(mapOf("type" to "focus", "value" to "denied"))
            return false
        }
        previousMode = audioManager.mode
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        routeOutput()
        if (!noisyRegistered) {
            ContextCompat.registerReceiver(context, noisyReceiver,
                IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                ContextCompat.RECEIVER_NOT_EXPORTED)
            noisyRegistered = true
        }
        val min = AudioRecord.getMinBufferSize(IN_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, IN_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            maxOf(min, CHUNK_BYTES * 4))
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("AudioRecord init failed")
        }
        val sid = rec.audioSessionId
        if (AcousticEchoCanceler.isAvailable()) aec = AcousticEchoCanceler.create(sid)?.apply { enabled = true }
        if (NoiseSuppressor.isAvailable()) ns = NoiseSuppressor.create(sid)?.apply { enabled = true }
        if (AutomaticGainControl.isAvailable()) agc = AutomaticGainControl.create(sid)?.apply { enabled = true }
        record = rec
        capturing.set(true)
        rec.startRecording()
        captureThread = Thread({
            val buf = ByteArray(CHUNK_BYTES)
            while (capturing.get()) {
                var filled = 0
                while (filled < CHUNK_BYTES && capturing.get()) {
                    val n = rec.read(buf, filled, CHUNK_BYTES - filled)
                    if (n <= 0) break
                    filled += n
                }
                if (filled == 0 && capturing.get()) {
                    emit(mapOf("type" to "error", "value" to "capture_failed"))
                    break
                }
                if (filled > 0 && capturing.get()) {
                    val chunk = buf.copyOf(filled)
                    main.post { sink?.success(mapOf("type" to "mic", "pcm" to chunk)) }
                }
            }
        }, "GreenSoilLiveMic").also { it.start() }
        emit(mapOf("type" to "capture", "value" to "started",
            "aec" to (aec != null), "ns" to (ns != null)))
        return true
    }

    private fun stopCapture() {
        if (!capturing.getAndSet(false)) return
        try { record?.stop() } catch (_: Exception) {}
        try { captureThread?.join(500) } catch (_: InterruptedException) {}
        captureThread = null
        record?.release()
        record = null
        aec?.release(); aec = null
        ns?.release(); ns = null
        agc?.release(); agc = null
        emit(mapOf("type" to "capture", "value" to "stopped"))
    }

    private fun ensureTrack(rate: Int) {
        if (track != null && trackRate == rate) return
        stopPlayback()
        val min = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT)
        val t = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(maxOf(min, rate / 5 * 2))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        t.play()
        track = t
        trackRate = rate
        playing.set(true)
        playThread = Thread({
            while (playing.get()) {
                val chunk = try { playQueue.poll(200, TimeUnit.MILLISECONDS) } catch (_: InterruptedException) { null }
                if (chunk != null && playing.get()) {
                    var offset = 0
                    while (offset < chunk.pcm.size && playing.get() && chunk.epoch == playbackEpoch.get()) {
                        val n = synchronized(playbackLock) {
                            if (chunk.epoch != playbackEpoch.get()) -1 else
                                t.write(chunk.pcm, offset, minOf(1920, chunk.pcm.size - offset), AudioTrack.WRITE_NON_BLOCKING)
                        }
                        if (n < 0) break
                        if (n == 0) Thread.sleep(2) else offset += n
                    }
                }
            }
        }, "GreenSoilLivePlayback").also { it.start() }
    }

    private fun enqueue(bytes: ByteArray, rate: Int) {
        ensureTrack(rate)
        require(rate == 24000 || rate == 16000 || rate == 48000)
        require(bytes.size % 2 == 0 && bytes.size <= rate * 2)
        if (!playQueue.offer(Packet(bytes, playbackEpoch.get()))) {
            flushPlayback()
            emit(mapOf("type" to "error", "value" to "playback_overflow"))
        }
    }

    /** Barge-in: drop everything queued and buffered immediately. */
    private fun flushPlayback() {
        synchronized(playbackLock) {
            playbackEpoch.incrementAndGet()
            playQueue.clear()
            track?.let {
                try { it.pause(); it.flush(); it.play() } catch (_: Exception) {}
            }
        }
    }

    private fun stopPlayback() {
        playing.set(false)
        playbackEpoch.incrementAndGet()
        playQueue.clear()
        try { playThread?.join(300) } catch (_: InterruptedException) {}
        playThread = null
        track?.let { try { it.stop() } catch (_: Exception) {}; it.release() }
        track = null
        trackRate = 0
    }

    fun release() {
        stopCapture()
        stopPlayback()
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) audioManager.clearCommunicationDevice()
        audioManager.mode = previousMode
        if (noisyRegistered) {
            try { context.unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
            noisyRegistered = false
        }
    }
}
