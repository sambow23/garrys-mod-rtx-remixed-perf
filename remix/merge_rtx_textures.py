#!/usr/bin/env python3
"""
Merge texture ID lists from one or more RTX Remix rtx.conf files.

Behavior:
- Scans input files for lines whose keys end with "Texture" or "Textures"
- Extracts only hex texture IDs (tokens like 0xDEADBEEF...)
- Merges and de-duplicates IDs per key while preserving first-seen order
- Outputs lines in proper syntax: "<key> = 0x..., 0x..., ..."

Examples:
  python remix/merge_rtx_textures.py -o merged_textures.conf remix/rtx.conf other/rtx.conf
  python remix/merge_rtx_textures.py remix/rtx.conf other/rtx.conf  # prints to stdout
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import OrderedDict
from typing import Dict, Iterable, List, Tuple


TEXTURE_KEY_REGEX = re.compile(r"^\s*([A-Za-z0-9_.]*[Tt]extures?)\s*=\s*(.*?)\s*$")
HEX_TOKEN_REGEX = re.compile(r"0x[0-9A-Fa-f]+")


def parse_texture_line(line: str) -> Tuple[str, List[str]] | Tuple[None, None]:
    """Parse a single config line.

    Returns:
        (key, tokens) if the line ends with 'Texture'/'Textures' and contains hex tokens
        (None, None) otherwise
    """
    match = TEXTURE_KEY_REGEX.match(line)
    if not match:
        return None, None

    key = match.group(1)
    rhs = match.group(2)

    # Only keep valid hex texture IDs; skip flags like "detectUITextures = False"
    tokens = HEX_TOKEN_REGEX.findall(rhs)
    if not tokens:
        return None, None

    return key, tokens


def merge_texture_lists(input_files: Iterable[str]) -> Dict[str, List[str]]:
    """Merge texture IDs per key across multiple files.

    Preserves the first-seen order of both keys and texture IDs.
    """
    merged: "OrderedDict[str, OrderedDict[str, None]]" = OrderedDict()

    for path in input_files:
        if not os.path.exists(path):
            print(f"Warning: '{path}' not found; skipping.", file=sys.stderr)
            continue

        try:
            with open(path, "r", encoding="utf-8") as f:
                for raw_line in f:
                    key, tokens = parse_texture_line(raw_line)
                    if not key:
                        continue

                    if key not in merged:
                        merged[key] = OrderedDict()

                    dest = merged[key]
                    for token in tokens:
                        if token not in dest:
                            dest[token] = None
        except Exception as exc:
            print(f"Error reading '{path}': {exc}", file=sys.stderr)

    # Convert OrderedDict token sets back to ordered lists
    return {key: list(tokens.keys()) for key, tokens in merged.items()}


def format_texture_lines(merged: Dict[str, List[str]]) -> List[str]:
    """Render merged texture lists back to config lines."""
    lines: List[str] = []
    for key, tokens in merged.items():
        # Use exactly: key = token1, token2, ...
        rhs = ", ".join(tokens)
        lines.append(f"{key} = {rhs}")
    return lines


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge 'Texture(s) =' fields from multiple rtx.conf files, deduplicating IDs.",
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Input rtx.conf files to merge (one or more)",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Optional path to write merged lines. If omitted, prints to stdout.",
    )

    args = parser.parse_args(argv)

    merged = merge_texture_lists(args.inputs)

    lines = format_texture_lines(merged)

    if args.output:
        try:
            with open(args.output, "w", encoding="utf-8") as f:
                for line in lines:
                    f.write(line + "\n")
            print(f"Wrote {len(lines)} merged texture lines to '{args.output}'")
        except Exception as exc:
            print(f"Error writing '{args.output}': {exc}", file=sys.stderr)
            return 1
    else:
        for line in lines:
            print(line)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())


