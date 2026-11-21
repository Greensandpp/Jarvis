import unittest
from cancellation_registry import ResponseCancellationRegistry
from cancellation_server import CancellationApp
import io
import json


class ResponseCancellationRegistryTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def stop(owner, room, response, generation):
            self.calls.append((owner, room, response, generation))
            return True
        self.registry = ResponseCancellationRegistry(stop)
        self.assertTrue(self.registry.register(owner="owner", room="room",
                                               response="reply", generation=7))

    def test_cancel_exact_active_response(self):
        self.assertTrue(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertFalse(self.registry.is_active("owner", "room", "reply", 7))
        self.assertEqual(len(self.calls), 1)

    def test_reject_stale_generation(self):
        self.assertFalse(self.registry.cancel_and_confirm("owner", "room", "reply", 6))
        self.assertTrue(self.registry.is_active("owner", "room", "reply", 7))
        self.assertEqual(self.calls, [])

    def test_wrong_owner_and_response_rejected(self):
        self.assertFalse(self.registry.cancel_and_confirm("stranger", "room", "reply", 7))
        self.assertFalse(self.registry.cancel_and_confirm("owner", "room", "wrong", 7))
        self.assertEqual(self.calls, [])

    def test_cannot_replace_active_output(self):
        self.assertFalse(self.registry.register(owner="owner", room="room",
                                                response="new", generation=8))
        self.assertTrue(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertTrue(self.registry.register(owner="owner", room="room",
                                               response="new", generation=8))
        self.assertFalse(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertTrue(self.registry.is_active("owner", "room", "new", 8))

    def test_double_cancel_does_not_emit_double_ack(self):
        self.assertTrue(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertFalse(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertEqual(len(self.calls), 1)

    def test_false_ack_fails_closed(self):
        self.registry._stop_and_confirm = lambda *args: False
        self.assertFalse(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertTrue(self.registry.is_active("owner", "room", "reply", 7))
        self.assertEqual(self.calls, [])

    def test_exception_fails_closed(self):
        def fail(*args):
            raise RuntimeError("cannot drain audio")
        self.registry._stop_and_confirm = fail
        self.assertFalse(self.registry.cancel_and_confirm("owner", "room", "reply", 7))
        self.assertTrue(self.registry.is_active("owner", "room", "reply", 7))

    def test_wsgi_contract_with_registry(self):
        app = CancellationApp(
            authenticate=lambda token: "owner" if token == "test-token" else None,
            authorize=self.registry.authorize,
            cancel_and_confirm=self.registry.cancel_and_confirm,
        )
        payload = json.dumps({"room_id": "room", "response_id": "reply",
                              "generation": 7}).encode()
        env = {"PATH_INFO": "/cancel", "REQUEST_METHOD": "POST",
               "wsgi.url_scheme": "https", "CONTENT_TYPE": "application/json",
               "HTTP_AUTHORIZATION": "Bearer test-token",
               "CONTENT_LENGTH": str(len(payload)), "wsgi.input": io.BytesIO(payload)}
        status = []
        output = app(env, lambda s, h: status.append(s))
        self.assertEqual(status, ["200 OK"])
        self.assertTrue(json.loads(b"".join(output))["cancelled"])


if __name__ == "__main__":
    unittest.main()
