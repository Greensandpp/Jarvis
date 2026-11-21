"""Patch only the disposable Flutter-generated offline Android scaffold."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
manifest = root / 'android/app/src/main/AndroidManifest.xml'
s = manifest.read_text().replace('<application', '''<uses-permission android:name="android.permission.RECORD_AUDIO" />
    <queries>
        <intent><action android:name="android.speech.RecognitionService" /></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
    </queries>
    <application''', 1)
s = s.replace('android:label="greensoil_livekit_voice_experiment"', 'android:label="GreenSoil Offline Lab"')
s = s.replace('<application', '<application android:allowBackup="false"', 1)
manifest.write_text(s)
for variant in ['debug', 'profile']:
    p = root / f'android/app/src/{variant}/AndroidManifest.xml'
    if p.exists(): p.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"/>')
kt = root / 'android/app/src/main/kotlin/com/greensoil/experiment/greensoil_livekit_voice_experiment/MainActivity.kt'
kt.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'android_src/MainActivity.kt', kt)
p = root / 'android/app/build.gradle.kts'
p.write_text(p.read_text().replace('minSdk = flutter.minSdkVersion', 'minSdk = 33').replace('applicationId = \"com.greensoil.experiment.greensoil_livekit_voice_experiment\"', 'applicationId = \"com.greensoil.experiment.greensoil_livekit_voice_experiment.offline\"'))
