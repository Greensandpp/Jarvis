import io
import json
import unittest
from cancellation_server import CancellationApp


class CancellationServerTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.app = CancellationApp(
            authenticate=lambda token: "owner-a" if token == "good-token" else None,
            authorize=lambda principal, room, response: (
                principal == "owner-a" and room == "roomA" and response == "responseB"
            ),
            cancel_and_confirm=self.confirm,
        )

    def confirm(self, principal, room, response, generation):
        self.calls.append((principal, room, response, generation))
        return True

    def request(self, payload=None, *, token="good-token", scheme="https",
                method="POST", mime="application/json", path="/cancel"):
        if payload is None:
            payload = {"room_id": "roomA", "response_id": "responseB", "generation": 17}
        body = json.dumps(payload).encode("utf-8")
        env = {"PATH_INFO": path, "REQUEST_METHOD": method,
               "wsgi.url_scheme": scheme, "CONTENT_TYPE": mime,
               "HTTP_AUTHORIZATION": "Bearer " + token,
               "CONTENT_LENGTH": str(len(body)), "wsgi.input": io.BytesIO(body)}
        status = []
        output = self.app(env, lambda s, h: status.append((s, h)))
        return status[0][0], json.loads(b"".join(output))

    def test_valid_ack_matches_client_contract(self):
        status, result = self.request()
        self.assertEqual(status, "200 OK")
        self.assertEqual(result, {"cancelled": True, "room_id": "roomA",
                                  "response_id": "responseB", "generation": 17})
        self.assertEqual(len(self.calls), 1)

    def test_invalid_token_blocks_backend(self):
        self.assertEqual(self.request(token="bad")[0], "401 Unauthorized")
        self.assertFalse(self.calls)

    def test_room_membership_checked(self):
        status, _ = self.request({"room_id": "other", "response_id": "responseB", "generation": 17})
        self.assertEqual(status, "403 Forbidden")
        self.assertFalse(self.calls)

    def test_reject_non_https(self):
        self.assertEqual(self.request(scheme="http")[0], "403 Forbidden")

    def test_reject_wrong_verb_mime_path(self):
        self.assertEqual(self.request(method="GET")[0], "405 Method Not Allowed")
        self.assertEqual(self.request(mime="text/plain")[0], "415 Unsupported Media Type")
        self.assertEqual(self.request(path="/admin")[0], "404 Not Found")

    def test_reject_boolean_generation_and_extra_fields(self):
        self.assertEqual(self.request({"room_id": "roomA", "response_id": "responseB",
                                       "generation": True})[0], "400 Bad Request")
        self.assertEqual(self.request({"room_id": "roomA", "response_id": "responseB",
                                       "generation": 17, "admin": True})[0], "400 Bad Request")

    def test_reject_large_payload(self):
        self.assertEqual(self.request({"room_id": "roomA", "response_id": "x"*1100,
                                       "generation": 17})[0], "413 Content Too Large")

    def test_fails_closed_if_agent_refuses_ack(self):
        self.app.cancel_and_confirm = lambda *args: False
        status, data = self.request()
        self.assertEqual(status, "409 Conflict")
        self.assertFalse(data["cancelled"])

    def test_fails_closed_if_agent_throws(self):
        def unavailable(*args):
            raise RuntimeError("offline")
        self.app.cancel_and_confirm = unavailable
        status, data = self.request()
        self.assertEqual(status, "503 Service Unavailable")
        self.assertFalse(data["cancelled"])


if __name__ == "__main__":
    unittest.main()
