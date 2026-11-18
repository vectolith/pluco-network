#!/usr/bin/env python3
"""Compare deployed Solidity runtime logic with the local Foundry artifact."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    print(f"Runtime bytecode verification failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def strip_cbor_metadata(bytecode: str, label: str) -> str:
    if len(bytecode) < 4:
        fail(f"{label}: bytecode is too short to contain Solidity metadata")
    try:
        metadata_length = int(bytecode[-4:], 16)
    except ValueError:
        fail(f"{label}: trailing metadata length is not valid hexadecimal")
    total_metadata_bytes = metadata_length + 2
    metadata_hex_length = total_metadata_bytes * 2
    if metadata_hex_length > len(bytecode):
        fail(f"{label}: metadata length exceeds runtime bytecode size")
    return bytecode[:-metadata_hex_length]


def apply_immutable_mask(
    bytecode: str, references: dict[str, list[dict[str, Any]]], label: str
) -> str:
    mutable = list(bytecode)
    for entries in references.values():
        for reference in entries:
            start = reference.get("start")
            length = reference.get("length")
            if not isinstance(start, int) or not isinstance(length, int):
                fail(f"{label}: malformed immutable reference")
            if start < 0 or length <= 0:
                fail(f"{label}: invalid immutable reference range")
            left = start * 2
            right = (start + length) * 2
            if right > len(mutable):
                fail(f"{label}: immutable reference exceeds runtime bytecode")
            mutable[left:right] = list("0" * (length * 2))
    return "".join(mutable)


def main() -> None:
    if len(sys.argv) != 4:
        fail(
            "usage: verify-runtime-bytecode.py <foundry-artifact.json> "
            "<deployed-bytecode-hex> <contract-label>"
        )

    artifact_path = Path(sys.argv[1])
    deployed_input = sys.argv[2]
    label = sys.argv[3]

    try:
        artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{label}: cannot read Foundry artifact: {error}")

    deployed_section = artifact.get("deployedBytecode")
    if not isinstance(deployed_section, dict):
        fail(f"{label}: artifact has no deployedBytecode section")

    compiled = deployed_section.get("object")
    if not isinstance(compiled, str) or not compiled:
        fail(f"{label}: artifact has no deployed runtime bytecode")

    link_references = deployed_section.get("linkReferences", {})
    if link_references:
        fail(f"{label}: linked libraries require explicit address verification")

    immutable_references = deployed_section.get("immutableReferences", {})
    if not isinstance(immutable_references, dict):
        fail(f"{label}: immutableReferences has an invalid shape")

    compiled = compiled.removeprefix("0x").lower()
    deployed = deployed_input.removeprefix("0x").lower()

    if not compiled or not deployed:
        fail(f"{label}: compiled or deployed runtime bytecode is empty")
    if len(compiled) % 2 != 0 or len(deployed) % 2 != 0:
        fail(f"{label}: runtime bytecode contains an odd number of hex digits")
    try:
        bytes.fromhex(compiled)
        bytes.fromhex(deployed)
    except ValueError:
        fail(f"{label}: runtime bytecode contains non-hexadecimal characters")

    compiled_logic = strip_cbor_metadata(compiled, f"{label} artifact")
    deployed_logic = strip_cbor_metadata(deployed, f"{label} deployed code")

    compiled_logic = apply_immutable_mask(
        compiled_logic, immutable_references, f"{label} artifact"
    )
    deployed_logic = apply_immutable_mask(
        deployed_logic, immutable_references, f"{label} deployed code"
    )

    if compiled_logic != deployed_logic:
        fail(
            f"{label}: deployed executable runtime does not match the current "
            "Foundry artifact after masking constructor immutables and "
            "compiler metadata"
        )

    print(
        f"Verified {label}: deployed executable runtime matches the current "
        "Foundry artifact (compiler metadata and constructor immutables excluded)"
    )


if __name__ == "__main__":
    main()
