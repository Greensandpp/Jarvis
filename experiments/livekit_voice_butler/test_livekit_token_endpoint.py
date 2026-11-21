import io
import json
import unittest

from livekit_token_endpoint import TokenService


class TokenServiceTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def issuer(room, identity):
            self.calls.append((room, identity))
            return "fake-unit-test-jwt"
        self.service = TokenService(
            owner_bearer="a" * 48,
            livekit_url="wss://sandbox.livekit.invalid",
            token_issuer=issuer,
            max_issues_per_hour=2,
            enabled=True,
            clock=lambda: 1000,
        )

    def request(self, auth=True, payload=None, method="POST", scheme="https"):
        raw = json.dumps(payload if payload is not None else {
            "room_name": "evil",
            "participant_identity": "pretend-admin",
            "room_config": {"agents": [{"agent_name": "expensive-agent"}]},
        }).encode()
        env = {
            "PATH_INFO": "/api/livekit-token", "REQUEST_METHOD": method,
            "wsgi.url_scheme": scheme,
            "HTTP_AUTHORIZATION": "Bearer " + ("a" * 48 if auth else "wrong"),
            "CONTENT_TYPE": "application/json", "CONTENT_LENGTH": str(len(raw)),
            "wsgi.input": io.BytesIO(raw),
        }
        status = []
        response = self.service.handle(env, lambda s, headers: status.append(s))
        return status[0], json.loads(b"".join(response))

    def test_protocol_returns_201_and_correct_fields(self):
        status, body = self.request()
        self.assertEqual(status, "201 Created")
        self.assertEqual(body["server_url"], "wss://sandbox.livekit.invalid")
        self.assertEqual(body["participant_token"], "fake-unit-test-jwt")
        self.assertNotEqual(self.calls[0][0], "evil")
        self.assertNotEqual(self.calls[0][1], "pretend-admin")

    def test_auth_required(self):
        self.assertEqual(self.request(auth=False)[0], "401 Unauthorized")
        self.assertEqual(self.calls, [])

    def test_disallowed_http(self):
        self.assertEqual(self.request(scheme="http")[0], "403 Forbidden")
        self.assertEqual(self.calls, [])

    def test_rate_limit(self):
        self.assertEqual(self.request()[0], "201 Created")
        self.assertEqual(self.request()[0], "201 Created")
        self.assertEqual(self.request()[0], "429 Too Many Requests")
        self.assertEqual(len(self.calls), 2)

    def test_disabled_by_default_when_explicitly_off(self):
        self.service.enabled = False
        self.assertEqual(self.request()[0], "503 Service Unavailable")
        self.assertEqual(self.calls, [])

    def test_wrong_method(self):
        self.assertEqual(self.request(method="GET")[0], "405 Method Not Allowed")

    def test_invalid_config_rejected(self):
        with self.assertRaises(ValueError):
            TokenService(owner_bearer="short", livekit_url="http://wrong",
                         token_issuer=lambda x,y: "", enabled=True)

    def test_issuer_failure_is_not_a_success(self):
        self.service._issuer = lambda room, identity: None
        self.assertEqual(self.request()[0], "503 Service Unavailable")


if __name__ == "__main__":
    unittest.main()
