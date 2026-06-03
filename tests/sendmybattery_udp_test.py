#!/usr/bin/env python3
"""UDP receiver/test harness for the SendMyBattery tweak."""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from dataclasses import dataclass


DEFAULT_BIND_HOST = "0.0.0.0"
DEFAULT_PORT = 9999
DEFAULT_TIMEOUT = 60.0


@dataclass(frozen=True)
class PacketResult:
    raw: bytes
    text: str
    address: tuple[str, int]
    battery: int | None
    diagnostics: dict[str, object]
    error: str | None


def guess_lan_ip() -> str | None:
    """Return the likely LAN address to enter in the tweak settings."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return None
    finally:
        sock.close()


def validate_packet(data: bytes, address: tuple[str, int]) -> PacketResult:
    text = data.decode("utf-8", errors="replace")

    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        return PacketResult(data, text, address, None, {}, f"invalid JSON: {exc.msg}")

    if not isinstance(payload, dict):
        return PacketResult(data, text, address, None, {}, "payload is not a JSON object")

    allowed_keys = {
        "battery",
        "state",
        "source",
        "uptimeSeconds",
        "packetsSent",
        "bytesSent",
        "sendFailures",
    }
    extra_keys = set(payload) - allowed_keys
    if extra_keys:
        keys = ", ".join(sorted(str(key) for key in extra_keys))
        return PacketResult(data, text, address, None, {}, f"unexpected keys: {keys}")
    if "battery" not in payload:
        return PacketResult(data, text, address, None, {}, "missing 'battery'")

    battery = payload["battery"]
    if not isinstance(battery, int) or isinstance(battery, bool):
        return PacketResult(data, text, address, None, {}, "'battery' is not an integer")

    if battery < 0 or battery > 100:
        return PacketResult(data, text, address, battery, {}, "'battery' is outside 0-100")

    diagnostics = {key: value for key, value in payload.items() if key != "battery"}
    return PacketResult(data, text, address, battery, diagnostics, None)


def send_sample(host: str, port: int, battery: int) -> None:
    payload = json.dumps({"battery": battery}, separators=(",", ":")).encode("utf-8")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.sendto(payload, (host, port))
    finally:
        sock.close()


def receive_packets(args: argparse.Namespace) -> int:
    lan_ip = guess_lan_ip()
    bind_address = (args.bind, args.port)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.25)
    sock.bind(bind_address)

    deadline = None if args.timeout <= 0 else time.monotonic() + args.timeout
    valid_count = 0
    invalid_count = 0

    print(f"Listening on udp://{args.bind}:{args.port}")
    if lan_ip:
        print(f"Set SendMyBattery Host to {lan_ip} and Port to {args.port}.")
    else:
        print(f"Set SendMyBattery Host to this computer's LAN IP and Port to {args.port}.")
    print("Waiting for packets. Toggle 'Send Initial Packet' or change battery level to trigger one.")

    try:
        while valid_count < args.count:
            if deadline is not None and time.monotonic() >= deadline:
                print(
                    f"Timed out after {args.timeout:g}s "
                    f"({valid_count} valid, {invalid_count} invalid).",
                    file=sys.stderr,
                )
                return 1

            try:
                data, address = sock.recvfrom(args.max_bytes)
            except socket.timeout:
                continue

            result = validate_packet(data, address)
            prefix = f"{address[0]}:{address[1]}"

            if result.error:
                invalid_count += 1
                print(f"INVALID from {prefix}: {result.error}; raw={result.text!r}")
                if args.strict:
                    return 2
                continue

            valid_count += 1
            detail = ""
            if result.diagnostics:
                detail = " diagnostics=" + json.dumps(result.diagnostics, separators=(",", ":"), sort_keys=True)
            print(f"OK from {prefix}: battery={result.battery}%{detail} raw={result.text!r}")

    except KeyboardInterrupt:
        print("\nStopped.")
        return 130
    finally:
        sock.close()

    print(f"Received {valid_count} valid packet(s).")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Listen for and validate UDP packets sent by the SendMyBattery tweak."
    )
    parser.add_argument("--bind", default=DEFAULT_BIND_HOST, help=f"address to bind (default: {DEFAULT_BIND_HOST})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"UDP port to listen on (default: {DEFAULT_PORT})")
    parser.add_argument("--count", type=int, default=1, help="number of valid packets to wait for (default: 1)")
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help=f"seconds before failing; use 0 to wait forever (default: {DEFAULT_TIMEOUT:g})",
    )
    parser.add_argument("--max-bytes", type=int, default=1024, help="maximum datagram size to read (default: 1024)")
    parser.add_argument("--strict", action="store_true", help="fail immediately if an invalid packet is received")
    parser.add_argument(
        "--send-sample",
        metavar="HOST",
        help="send one sample SendMyBattery packet to HOST instead of listening",
    )
    parser.add_argument("--sample-battery", type=int, default=87, help="battery value for --send-sample (default: 87)")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.port < 1 or args.port > 65535:
        parser.error("--port must be between 1 and 65535")
    if args.count < 1:
        parser.error("--count must be at least 1")
    if args.max_bytes < 1:
        parser.error("--max-bytes must be at least 1")
    if args.sample_battery < 0 or args.sample_battery > 100:
        parser.error("--sample-battery must be between 0 and 100")

    if args.send_sample:
        send_sample(args.send_sample, args.port, args.sample_battery)
        print(f"Sent sample packet to udp://{args.send_sample}:{args.port}: {{\"battery\":{args.sample_battery}}}")
        return 0

    return receive_packets(args)


if __name__ == "__main__":
    raise SystemExit(main())
