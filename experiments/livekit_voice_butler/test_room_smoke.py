"""Offline admission/security checks for the opt-in network smoke test."""
import json
import os
import unittest
from unittest.mock import MagicMock, patch

import smoke_room


class RoomSmokeTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            'GS_VOICE_FREE_TIER_VERIFIED': 'true', 'GS_VOICE_AGENT_ENABLED': 'true',
            'LIVEKIT_URL': 'wss://example.invalid', 'LIVEKIT_API_KEY': 'test-key',
            'LIVEKIT_API_SECRET': 'test-secret', 'GEMINI_API_KEY': 'test-provider',
            'GS_VOICE_GEMINI_MODEL': 'test-model', 'GS_VOICE_LEDGER_PATH': '/tmp/test-ledger',
            'GS_VOICE_RUN_ROOM_SMOKE': 'true', 'GS_VOICE_SMOKE_OWNER': 'x' * 43,
            'GS_VOICE_SMOKE_ENDPOINT': smoke_room.TOKEN_ENDPOINT,
        }

    def test_test_requires_opt_in_free_setup_and_exact_private_destination(self):
        with patch.dict(os.environ, self.env, clear=True):
            self.assertEqual(smoke_room.validate_config(), 'x' * 43)
            for name, bad in [('GS_VOICE_RUN_ROOM_SMOKE', 'false'),
                              ('GS_VOICE_FREE_TIER_VERIFIED', 'false'),
                              ('GS_VOICE_SMOKE_ENDPOINT', smoke_room.TOKEN_ENDPOINT + '?forward=evil'),
                              ('GS_VOICE_SMOKE_OWNER', 'short')]:
                with self.subTest(name=name), patch.dict(os.environ, {name: bad}):
                    with self.assertRaises(ValueError):
                        smoke_room.validate_config()

    def test_redirect_never_forwards_owner_credential(self):
        with self.assertRaises(ValueError):
            smoke_room.NoRedirect().redirect_request(None, None, 307, '', {}, 'https://evil.invalid')

    def test_actual_authenticated_endpoint_contract_and_project_binding(self):
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.status = 201
        grant = {'server_url': self.env['LIVEKIT_URL'], 'participant_token': 'test-jwt'}
        response.read.return_value = json.dumps(grant).encode()
        with patch.dict(os.environ, self.env, clear=True), patch('urllib.request.build_opener', return_value=opener):
            self.assertEqual(smoke_room.fetch_token('x' * 43), grant)
            req = opener.open.call_args.args[0]
            self.assertEqual(req.full_url, smoke_room.TOKEN_ENDPOINT)
            self.assertEqual(req.get_method(), 'POST')
            self.assertEqual(req.get_header('Authorization'), 'Bearer ' + 'x' * 43)
            grant['server_url'] = 'wss://other.invalid'
            response.read.return_value = json.dumps(grant).encode()
            with self.assertRaises(ValueError):
                smoke_room.fetch_token('x' * 43)
            response.status = 200
            with self.assertRaises(ValueError):
                smoke_room.fetch_token('x' * 43)
