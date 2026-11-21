import asyncio
import io
import json
import threading
import unittest

from cancellation_runtime import build_cancellation_runtime


class FakeSession:
    def __init__(self):
        self.calls = 0

    def interrupt(self, *, force=False):
        self.calls += 1
        future = asyncio.get_running_loop().create_future()
        future.set_result(None)
        return future


class RuntimeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.loop = asyncio.new_event_loop()
        self.worker = threading.Thread(target=self.loop.run_forever, daemon=True)
        self.worker.start()
        self.session = FakeSession()
        self.runtime = build_cancellation_runtime(
            session=self.session,
            agent_loop=self.loop,
            authenticate=lambda token: "owner" if token == "valid-test-token" else None,
        )

    def tearDown(self):
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.worker.join(timeout=2)
        self.loop.close()

    def request(self, response="response1", generation=1, token="valid-test-token"):
        raw = json.dumps({"room_id": "room1", "response_id": response,
                          "generation": generation}).encode("utf-8")
        env = {"PATH_INFO": "/cancel", "REQUEST_METHOD": "POST",
               "wsgi.url_scheme": "https", "CONTENT_TYPE": "application/json",
               "CONTENT_LENGTH": str(len(raw)),
               "HTTP_AUTHORIZATION": "Bearer " + token,
               "wsgi.input": io.BytesIO(raw)}
        status = []
        result = self.runtime.app(env, lambda s, h: status.append(s))
        return status[0], json.loads(b"".join(result))

    def test_authorized_livekit_method_shape_end_to_end(self):
        self.assertTrue(self.runtime.response_started(
            principal="owner", room="room1",
            response_id="response1", generation=1))
        status, body = self.request()
        self.assertEqual(status, "200 OK")
        self.assertTrue(body["cancelled"])
        self.assertEqual(self.session.calls, 1)

    def test_unauthenticated_request_never_calls_sdk(self):
        self.runtime.response_started(principal="owner", room="room1",
                                      response_id="response1", generation=1)
        status, _ = self.request(token="bad")
        self.assertEqual(status, "401 Unauthorized")
        self.assertEqual(self.session.calls, 0)

    def test_unregistered_response_never_calls_sdk(self):
        status, _ = self.request()
        self.assertEqual(status, "403 Forbidden")
        self.assertEqual(self.session.calls, 0)

    def test_stale_generation_never_calls_sdk(self):
        self.runtime.response_started(principal="owner", room="room1",
                                      response_id="response1", generation=2)
        status, _ = self.request(generation=1)
        self.assertEqual(status, "409 Conflict")
        self.assertEqual(self.session.calls, 0)

    def test_repeated_ack_not_allowed(self):
        self.runtime.response_started(principal="owner", room="room1",
                                      response_id="response1", generation=1)
        self.assertEqual(self.request()[0], "200 OK")
        self.assertEqual(self.request()[0], "409 Conflict")
        self.assertEqual(self.session.calls, 1)


if __name__ == "__main__":
    unittest.main()
