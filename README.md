# SendMyBattery

SendMyBattery is a rootless iOS 16 jailbreak tweak that sends the device battery percentage to a configured UDP destination.

It is designed to be extremely low power:

- no polling
- no heartbeat
- no retry loop
- sends only from `UIDeviceBatteryLevelDidChangeNotification`
- sends one optional initial packet after SpringBoard loads

## Requirements

- Rootless iOS 16 jailbreak
- Theos
- PreferenceLoader

## Build

```sh
make package THEOS=/home/nocone/theos THEOS_PACKAGE_SCHEME=rootless
```

The package will be written to `packages/`.

## Configure

After installing, open Settings -> SendMyBattery.

Set:

- Enabled
- Host, for example `192.168.1.10`
- Port, for example `9999`
- Send Initial Packet

Preferences are stored in the domain:

```text
com.treebarkbr.sendmybattery
```

## Packet Format

Each UDP packet is compact JSON:

```json
{"battery":87}
```

The tweak skips sending if battery level is unknown, the host is empty, the port is invalid, or the tweak is disabled.

## Example Receiver

Run this on the destination device:

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

## Install

Copy the generated `.deb` to the jailbroken device and install it with your preferred package manager or:

```sh
sudo dpkg -i com.treebarkbr.sendmybattery_1.0.0_iphoneos-arm64.deb
sudo sbreload
```

## License

MIT
