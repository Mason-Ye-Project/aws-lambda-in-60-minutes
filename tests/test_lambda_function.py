from __future__ import annotations

import json
import os
import unittest
from dataclasses import dataclass
from unittest.mock import patch

from src.lambda_function import lambda_handler


@dataclass
class FakeContext:
    aws_request_id: str = "test-request-001"


class LambdaHandlerTests(unittest.TestCase):
    def test_returns_greeting(self) -> None:
        with patch.dict(os.environ, {"APP_ENV": "test"}, clear=False):
            result = lambda_handler({"name": "Mason"}, FakeContext())

        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(
            json.loads(result["body"]),
            {"environment": "test", "message": "Hello, Mason!"},
        )

    def test_rejects_missing_name(self) -> None:
        result = lambda_handler({}, FakeContext())

        self.assertEqual(result["statusCode"], 400)
        self.assertEqual(json.loads(result["body"]), {"error": "name is required"})

    def test_rejects_blank_name(self) -> None:
        result = lambda_handler({"name": "   "}, FakeContext())

        self.assertEqual(result["statusCode"], 400)

    def test_intentional_failure_is_visible(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "intentional lab failure"):
            lambda_handler({"action": "fail", "name": "Mason"}, FakeContext())


if __name__ == "__main__":
    unittest.main()
