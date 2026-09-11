# TelefonX

TelefonX is a native SIP phone for Apple Silicon Macs. It brings calls, contacts,
favorites and callback reminders together in a focused macOS interface.

> [!IMPORTANT]
> **Support continued development:** If TelefonX is useful to you, please consider
> subscribing to TelefonX Pro. Paid subscriptions fund maintenance, compatibility
> work and future updates. Continued development depends on this support.

TelefonX works with compatible SIP providers as well as local and hosted phone
systems. Provider-specific interoperability may vary and should be tested before
TelefonX is used in a production environment.

## Free and Pro

TelefonX includes a useful free foundation. Pro unlocks productivity and
customization features for people who use the app regularly.

| Feature | Free | TelefonX Pro |
| --- | :---: | :---: |
| Incoming and outgoing SIP calls | ✓ | ✓ |
| Hold, mute, DTMF and call waiting | ✓ | ✓ |
| Local contacts and Apple Contacts | ✓ | ✓ |
| Favorites, call history and call blocking | ✓ | ✓ |
| Built-in ringtones | ✓ | ✓ |
| Local backup and diagnostics export | ✓ | ✓ |
| SIP lines | 1 | Multiple |
| Callback reminders | — | ✓ |
| Contact CSV import and export | — | ✓ |
| Outgoing dialing rules | — | ✓ |
| Custom ringtone files | — | ✓ |
| Custom hold music | — | ✓ |
| Public business-name lookup | — | ✓ |

Monthly and annual subscriptions unlock the same Pro features. Prices and any
introductory offer are displayed by the App Store for the user's region.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- A compatible SIP account

TelefonX is not an emergency-calling service. Keep an alternative way to place
emergency calls available.

## Build from source

The project requires Xcode 26 or later, CMake and Git. On a fresh checkout:

```sh
./script/build_dependencies.sh
./script/swift.sh test
./script/build_and_run.sh --verify
```

The dependency build uses pinned upstream source versions. Local development
signing does not produce an App Store or generally distributable build.

## Privacy

TelefonX stores its own contacts, call history, settings and reminders locally.
SIP passwords are kept in the macOS Keychain. Access to Apple Contacts and the
microphone is requested only for the corresponding features.

Apple Contacts are displayed as a read-only source. TelefonX does not modify them.

## Project status

TelefonX is currently a prerelease project. Compatibility with providers, phone
systems, networks and audio hardware can differ. Please do not rely on it as your
only telephone until you have tested your setup thoroughly.

See [`CHANGELOG.md`](CHANGELOG.md) for the complete list of user-facing features
and release changes.

## License

Copyright © 2025–2026 Enwikuna.

TelefonX is free software licensed under the
[GNU General Public License, version 3 or later](LICENSE). Third-party components
remain subject to their respective licenses; the applicable notices are included
in the app bundle.
