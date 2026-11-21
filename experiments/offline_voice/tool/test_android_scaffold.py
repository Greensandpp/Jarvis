import runpy
from pathlib import Path
import shutil
import tempfile
import unittest

class ScaffoldTest(unittest.TestCase):
    def test_scaffold_keeps_other_apps_and_removes_debug_network_permission(self):
        source = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'tool').mkdir(); (root/'android_src').mkdir()
            shutil.copyfile(source/'tool/prepare_android.py', root/'tool/prepare_android.py')
            shutil.copyfile(source/'android_src/MainActivity.kt', root/'android_src/MainActivity.kt')
            for variant in ['main','debug','profile']:
                p=root/f'android/app/src/{variant}/AndroidManifest.xml'; p.parent.mkdir(parents=True)
                p.write_text('<manifest><application android:label="greensoil_livekit_voice_experiment"/></manifest>' if variant=='main' else '<manifest>android.permission.INTERNET</manifest>')
            gradle=root/'android/app/build.gradle.kts'
            gradle.write_text('minSdk = flutter.minSdkVersion\napplicationId = "com.greensoil.experiment.greensoil_livekit_voice_experiment"')
            runpy.run_path(str(root/'tool/prepare_android.py'))
            self.assertIn('applicationId = "com.greensoil.experiment.greensoil_livekit_voice_experiment.offline"',gradle.read_text())
            self.assertIn('minSdk = 33',gradle.read_text())
            for p in (root/'android/app/src').glob('*/AndroidManifest.xml'):
                self.assertNotIn('android.permission.INTERNET',p.read_text())
            self.assertIn('android.permission.RECORD_AUDIO',(root/'android/app/src/main/AndroidManifest.xml').read_text())

if __name__=='__main__': unittest.main()
