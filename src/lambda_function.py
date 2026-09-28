"""Small Lambda handler used by the book's bounded lab."""

from __future__ import annotations

import json
import logging
import os
from typing import Any


logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _response(status_code: int, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload, separators=(",", ":"), sort_keys=True),
    }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Validate one greeting event and return an API-style response.

    The special action ``fail`` is intentional. It gives the troubleshooting
    chapter a safe way to produce one controlled function error.
    """

    event = event or {}
    request_id = getattr(context, "aws_request_id", "local-request")
    action = event.get("action", "greet")
    environment = os.getenv("APP_ENV", "lab")

    logger.info(
        json.dumps(
            {
                "event": "invocation_started",
                "request_id": request_id,
                "action": action,
                "environment": environment,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )

    if action == "fail":
        raise RuntimeError("intentional lab failure")

    name = event.get("name")
    if not isinstance(name, str) or not name.strip():
        logger.warning(
            json.dumps(
                {
                    "event": "validation_failed",
                    "request_id": request_id,
                    "reason": "name is required",
                },
                separators=(",", ":"),
                sort_keys=True,
            )
        )
        return _response(400, {"error": "name is required"})

    return _response(
        200,
        {
            "message": f"Hello, {name.strip()}!",
            "environment": environment,
        },
    )
