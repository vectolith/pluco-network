from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("verify-runtime-bytecode.py")
SPEC = importlib.util.spec_from_file_location("verify_runtime_bytecode", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RuntimeBytecodeVerifierTests(unittest.TestCase):
    def test_strips_solidity_cbor_metadata(self) -> None:
        # 10-byte CBOR payload followed by Solidity's two-byte payload length.
        runtime = "6000a164736f6c634300081a000a"
        self.assertEqual(MODULE.strip_cbor_metadata(runtime, "test"), "6000")

    def test_rejects_metadata_length_larger_than_runtime(self) -> None:
        with self.assertRaises(SystemExit):
            MODULE.strip_cbor_metadata("600000ff", "test")

    def test_masks_constructor_immutable_ranges(self) -> None:
        runtime = "6000" + ("11" * 20)
        masked = MODULE.apply_immutable_mask(
            runtime,
            {"42": [{"start": 1, "length": 2}]},
            "test",
        )
        self.assertEqual(masked, "60000000" + ("11" * 18))

    def test_rejects_immutable_range_outside_runtime(self) -> None:
        with self.assertRaises(SystemExit):
            MODULE.apply_immutable_mask(
                "6000",
                {"42": [{"start": 1, "length": 2}]},
                "test",
            )

    def test_rejects_malformed_immutable_reference(self) -> None:
        with self.assertRaises(SystemExit):
            MODULE.apply_immutable_mask(
                "6000",
                {"42": [{"start": "1", "length": 2}]},
                "test",
            )


if __name__ == "__main__":
    unittest.main()
