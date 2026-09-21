# SlimBlade Bootleg Driver

A small native macOS menu-bar bridge for the **wired Kensington SlimBlade**
(USB vendor `0x047D`, product `0x2041`). It turns the two upper physical-button
bits into ordinary extra mouse buttons and leaves all remapping to your
preferred mouse-remapping software.

I built this because I use a wired Kensington SlimBlade, but I do not want
KensingtonWorks on my Mac. I also prefer to keep button mapping in the mouse
remapping software I already use, instead of running multiple mouse utilities
that can collide while handling the same events.

This app intentionally does one small job: it exposes the SlimBlade's two upper
buttons as ordinary extra mouse buttons. It does not assign actions; your
preferred remapping app remains in charge.

## How it works

The app observes the matching USB HID device with public `IOHIDManager` APIs.
It never opens the device exclusively, seizes it, installs a CGEvent tap, or
maps buttons to actions. For input reports of at least five bytes it reads:

- byte 4, bit 0 → `otherMouseDown` / `otherMouseUp`, button-number field 3
- byte 4, bit 1 → `otherMouseDown` / `otherMouseUp`, button-number field 4

Edges are tracked independently per device and coalesced globally, so detach,
disable, sleep, and multiple connected units cannot leave a synthetic button
held. At attachment the app inspects the HID descriptor. If it finds standard
HID Button usages 3 or 4, that device is shown as **native buttons** and raw
bridging is suppressed to prevent duplicate events.

`SlimBladeCore` contains the report parser and state machine; the AppKit target
contains only HID, event-posting, lifecycle, and menu integration.

## Requirements

- macOS 13 Ventura or newer
- A wired Kensington SlimBlade with VID/PID `047D:2041`
- Your preferred mouse-remapping software for the actual actions

No kernel extension or DriverKit extension is installed.

## Build and test

Command Line Tools or Xcode with Swift 5.9 or newer is sufficient:

```sh
./scripts/test.sh
./scripts/build-app.sh
```

The tests use a dependency-free executable harness so they also run with
minimal Apple Command Line Tools installations that omit XCTest.

The distributable local build is written to
`dist/SlimBlade Bootleg Driver.app`. The script produces a release binary and
ad-hoc-signs the bundle deterministically. For distribution to other Macs,
replace the ad-hoc signature with Developer ID signing and notarize the app.

## Install and set up

1. Copy `SlimBlade Bootleg Driver.app` to `/Applications` and launch it.
2. From the menu-bar mouse icon, choose **Open Accessibility Settings…** and
   enable the app. macOS requires this permission to post mouse events.
3. If macOS requests Input Monitoring access for passive HID input, grant it
   and relaunch the app.
4. Open your preferred mouse-remapping software's event-listening or button-
   capture function. Press each upper SlimBlade button in turn, then assign the
   action you want to each event it detects.
5. Optionally enable **Launch at Login** in the menu. This uses
   `SMAppService.mainApp`; it is most reliable after the app has been copied to
   `/Applications` and normally signed.

The **Enabled** choice is persisted. Turning it off immediately releases any
held synthetic upper buttons. The connection row reports no device, raw bridge
mode, native-button mode, or the most recent HID/event error.

## Caveat

The five-byte report layout is specific to the tested wired `0x2041` protocol.
A firmware revision that uses different report IDs or byte positions may need a
parser adjustment. When the HID descriptor already exposes usages 3/4, this app
intentionally emits nothing; your mouse-remapping software should consume the
device's native button events directly.

## License

This project is available under the MIT License; see [LICENSE](LICENSE).
Portions of the wired SlimBlade HID handling and event synthesis were adapted
from LinearMouse. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for
provenance, copyright notices, and the upstream license.

SlimBlade Bootleg Driver is an unofficial, independent project. It is not
affiliated with, endorsed by, or sponsored by Kensington, the LinearMouse
project, or its contributors. Those names are used only to identify compatible
hardware and upstream provenance.
