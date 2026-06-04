# SendMyBattery

SendMyBattery is a low-power jailbreak tweak that sends your iPhone battery percentage to another device over UDP.

It is built for rootless jailbreaks and currently packages for iOS 16, but the core battery notification it uses, `UIDeviceBatteryLevelDidChangeNotification`, is available far earlier than that. Apple's iOS 16.5 SDK marks it as available since iOS 3.0, so the iOS 16 requirement is a packaging/support target, not a notification API limit.

## What It Does

- Sends battery percentage changes to a configured UDP host and port.
- Sends one optional initial packet when SpringBoard loads.
- Uses `UIDeviceBatteryLevelDidChangeNotification` instead of polling.
- Uses UDP, so there is no connection to maintain.
- Can optionally include diagnostic fields for troubleshooting.
- Shows a read-only diagnostics snapshot in Settings while keeping the diagnostics plist on disk.

## Low-Power Design

SendMyBattery avoids the usual battery-draining patterns:

- no polling loop
- no heartbeat
- no retry timer
- no background scan
- no persistent TCP connection

The tweak waits for iOS to report a battery percentage change, builds one small JSON payload, sends it with `sendto`, and closes the socket.

## Requirements

- Rootless iOS jailbreak
- Currently packaged/tested for iOS 16
- Theos for building
- PreferenceLoader for the Settings pane

Rootful and older-iOS support may be possible later, but this repo currently targets rootless packaging.

## Build

```sh
make package THEOS=/home/nocone/theos THEOS_PACKAGE_SCHEME=rootless
```

The generated `.deb` is written to `packages/`.

## Install

Copy the generated package to the jailbroken device and install it with your package manager, or over SSH:

```sh
sudo dpkg -i com.treebarkbr.sendmybattery_1.0.0-5_iphoneos-arm64.deb
sudo sbreload
```

## Configure

Open Settings -> SendMyBattery.

Set:

- Enabled
- Host, for example `192.168.1.10`
- Port, for example `9999`
- Send Initial Packet
- Detailed Diagnostics, optional

Preferences are stored under:

```text
com.treebarkbr.sendmybattery
```

## Packet Format

Default packet:

```json
{"battery":87}
```

When Detailed Diagnostics is enabled:

```json
{"battery":87,"state":"unplugged","source":"SendMyBattery","uptimeSeconds":3600,"packetsSent":4,"bytesSent":56,"sendFailures":0}
```

The tweak skips sending if battery level is unknown, the host is empty, the port is invalid, or the tweak is disabled.

## Diagnostics

Detailed Diagnostics adds lightweight tweak activity counters. It does not claim exact mAh drain, because iOS does not expose true per-tweak battery usage from inside SpringBoard.

Tracked counters include:

- notifications observed
- duplicate percentage skips
- invalid configuration skips
- unknown battery skips
- packets sent
- bytes sent
- send failures
- active UDP send time in milliseconds

Diagnostics are written to:

```text
/var/mobile/Library/Preferences/com.treebarkbr.sendmybattery.diagnostics.plist
```

Settings -> SendMyBattery also shows a read-only diagnostics snapshot from that file. Use Refresh Diagnostics to reload the displayed values.

## Test Receiver

This repo includes a helper:

```sh
python3 tests/sendmybattery_udp_test.py --port 9999
```

It prints the LAN IP to enter in Settings and validates incoming packets.

You can also run a tiny receiver manually:

```sh
python3 - <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 9999))

print("listening on udp://0.0.0.0:9999")
while True:
    data, addr = sock.recvfrom(1024)
    print(addr, data.decode("utf-8", errors="replace"))
PY
```

## Compatibility Notes

`UIDeviceBatteryLevelDidChangeNotification` is not new to iOS 16. In the local iPhoneOS 16.5 SDK header, it is declared as available since iOS 3.0.

The current package still declares iOS 16+ because the project was built and tested for rootless iOS 16 jailbreaks. Lowering the package target for older rootless jailbreaks should be treated as a separate compatibility pass.
