"""WSGI entrypoint for a dedicated, isolated staging token service.

Never mount into the existing production JARVIS or trading bot.
Requires environment to be configured securely. Default-off issuance.
Only expose behind a trusted HTTPS reverse proxy that sets
wsgi.url_scheme='https' based on the actual TLS connection.
"""
from livekit_token_endpoint import from_environment

application = from_environment().handle
