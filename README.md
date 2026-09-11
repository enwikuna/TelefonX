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

TelefonX connects your Mac to compatible SIP providers and brings calling,
contacts and call organisation together in one native app. The free version
includes the following features:

| Feature | Description |
| --- | --- |
| SIP Calling | Connect TelefonX to compatible SIP providers or phone systems and make and receive calls directly on your Mac. |
| Call Controls | Control active calls with mute, hold and DTMF keypad tones. |
| Call Waiting and Concurrent Calls | Answer a second incoming call and switch between active conversations. |
| Transfers and Three-Way Conferences | Start consultations, transfer calls and join two participants in a local three-way conference. |
| Caller ID Suppression | Hide your caller ID permanently for a line or once for the next outgoing call. |
| Separate Audio Devices | Choose separate devices for your microphone, call output and ringtone playback. |
| Ringtones for Each Line | Assign an included ringtone to each SIP line and test its output directly in TelefonX. |
| Local Contacts | Create and manage contacts with multiple numbers, photos, groups, notes and a preferred line. |
| Apple Contacts | Display Apple Contacts as a read-only source or copy them into TelefonX as independent contacts. |
| Favourites | Mark frequently used contacts as favourites and reach the preferred number more quickly. |
| Call History | Search and filter incoming, outgoing, missed, declined and blocked calls. |
| Call Blocking | Block individual phone numbers, SIP addresses or anonymous callers across all configured lines. |
| macOS Services and Phone Links | Use selected numbers from other apps or open `tel:`, `sip:` and `sips:` links directly with TelefonX. |
| Menu Bar and Notifications | Check line status from the menu bar and manage incoming or active calls through local notifications. |
| Do Not Disturb and Focus | Enable Do Not Disturb for a chosen duration or optionally sync it with macOS Focus. |
| Automatic Media Pausing | Optionally pause Apple Music or Spotify automatically when a call begins. |
| Local Backups | Export and replace your local TelefonX data using a backup file. |
| Automatic Reconnection | Restore SIP connections automatically after network, VPN or wake changes. |

TelefonX Pro adds these features:

| Feature | Description |
| --- | --- |
| Multiple SIP Lines | Add more SIP lines, keep them registered in parallel and choose the appropriate line for each call. |
| Callback Reminders | Schedule callbacks with a date, note and optional line and receive a local reminder. |
| Outgoing Dialling Rules | Route numbers automatically through a chosen SIP line using configurable prefixes. |
| Contact Import and Export | Import and export local TelefonX contacts as CSV files. |
| Custom Ringtones and Hold Music | Use your own audio files as ringtones or play custom music while the other party is on hold. |
| Public Business Lookup | Optionally add matching Apple Maps business names to unknown public phone numbers. |

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
