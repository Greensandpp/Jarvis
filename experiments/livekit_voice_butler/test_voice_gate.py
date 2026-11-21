"""Run: python -m unittest discover -s experiments/livekit_voice_butler -p 'test_*.py'"""
import unittest

from voice_gate import Phase, VoiceGate


class VoiceGateTest(unittest.TestCase):
    def test_one_voice_owner(self):
        gate = VoiceGate()
        turn = gate.listen()
        self.assertTrue(gate.think(turn))
        self.assertTrue(gate.claim_speaker(turn, "gemini"))
        self.assertFalse(gate.claim_speaker(turn, "android_tts"))
        self.assertTrue(gate.may_play(turn, "gemini"))
        self.assertTrue(gate.finish(turn, "gemini"))
        self.assertEqual(gate.snapshot.phase, Phase.IDLE)

    def test_interrupt_invalidates_old_audio(self):
        gate = VoiceGate()
        old = gate.listen()
        gate.think(old)
        gate.claim_speaker(old, "gemini")
        new = gate.listen()
        self.assertFalse(gate.may_play(old, "gemini"))
        self.assertFalse(gate.claim_speaker(old, "gemini"))
        self.assertTrue(gate.think(new))
        self.assertTrue(gate.claim_speaker(new, "gemini"))

    def test_deny_early_and_stale_responses(self):
        gate = VoiceGate()
        turn = gate.listen()
        self.assertFalse(gate.claim_speaker(turn, "gemini"))
        self.assertTrue(gate.think(turn))
        gate.stop()
        self.assertFalse(gate.claim_speaker(turn, "gemini"))
        self.assertEqual(gate.snapshot.output_owner, None)

    def test_no_double_finish(self):
        gate = VoiceGate()
        turn = gate.listen()
        gate.think(turn)
        gate.claim_speaker(turn, "gemini")
        self.assertTrue(gate.finish(turn, "gemini"))
        self.assertFalse(gate.finish(turn, "gemini"))


if __name__ == "__main__":
    unittest.main()
