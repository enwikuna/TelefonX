# Changelog

This file records notable user-facing changes to TelefonX. Entries are grouped
by release and written for users rather than as an internal development log.

## [1.0.0] - Unreleased

Initial public release.

### Calling and lines

- Make and receive calls through compatible SIP accounts.
- Configure one or more SIP lines and choose the line used for outgoing calls.
- See connection status for every configured line in the app and menu bar.
- Reorder, enable, disable and reconnect individual lines.
- Redial the most recent outgoing number for the selected line.
- Put calls on hold, mute the microphone and send DTMF keypad tones.
- Receive a second call using call waiting and switch between active calls.
- Start consultation calls and complete attended transfers.
- Merge two connected calls into a local three-way conference.
- Suppress caller ID permanently for a line or once for the next outgoing call.
- Automatically recover unavailable registrations after network, VPN and wake
  changes.
- Verify that a line is reachable immediately before starting an outgoing call.
- Use UDP, TCP or TLS according to the SIP provider's configuration.
- Require secure media for supported TLS/SRTP configurations.
- Use wideband and compatibility audio modes for different phone systems.

### Dialing and call control

- Enter numbers with the on-screen keypad or the Mac keyboard.
- Type a number directly from the main window without first selecting the dialer.
- Choose whether call buttons start calls immediately or prepare the number for
  confirmation.
- Open `tel:`, `sip:` and `sips:` links with TelefonX.
- Use the macOS service to prepare selected text for dialing in TelefonX.
- Apply configurable outgoing dialing rules.

### Contacts and favorites

- Create and edit local contacts with names, companies, notes and multiple
  labeled phone numbers.
- Assign a preferred number and preferred SIP line to a contact.
- Organize local contacts using groups.
- Add local contacts to favorites and choose the number used by each favorite.
- Access frequently used favorites directly above the call history.
- Add, replace or remove local contact photos.
- Display matching names and photos throughout contacts, history and calls.
- Show contacts from the macOS Contacts app as an optional read-only source.
- Filter the contact list between all, TelefonX and Apple contacts.
- Copy an Apple contact into TelefonX as an independent editable contact.
- Import and export local contacts as CSV files.

### Call history and blocking

- Keep a local history of incoming, outgoing, missed, declined and blocked calls.
- Filter history by call direction or status and search by name or number.
- Call, copy, create a contact, add to a contact, block or delete from a call's
  context menu.
- Select multiple history or contact entries for supported bulk actions.
- Use native trackpad swipe actions for common blocking and deletion tasks.
- Block individual numbers, number prefixes or anonymous callers.
- Manage blocking and dialing rules in Settings.
- Optionally look up public business names for unknown telephone numbers.

### Callback reminders

- Create callback reminders manually or from recent calls.
- Store a due date, telephone number, note and optional preferred line.
- Browse reminders grouped into overdue, today, later and completed sections.
- Receive local notifications with actions to prepare the call or snooze it.
- Mark one or more reminders as completed or delete them.
- Export callback reminders as a CSV file.

### Audio

- Select separate devices for microphone, call output and ringtone playback.
- Retain audio-device selections across app launches.
- Choose a built-in ringtone separately for each SIP line.
- Use custom audio files as line ringtones.
- Preview ringtones before saving a line.
- Play locally selected hold music to a remote participant.
- Warn when a selected audio device or custom audio file is unavailable.
- Optionally pause Apple Music or Spotify when a call begins.

### macOS integration

- Use a native macOS interface with light and dark appearance support.
- Keep line status and common actions available from the menu bar.
- Optionally launch TelefonX when signing in to the Mac.
- Synchronize TelefonX Do Not Disturb with macOS Focus.
- Enable Do Not Disturb for 30 minutes, one hour, two hours or until disabled.
- Receive local incoming-call and callback notifications.
- See a Dock badge for unseen missed calls.
- Use English or German based on the Mac's language settings.

### Data and privacy

- Store TelefonX contacts, call history, settings and reminders locally.
- Keep SIP passwords in the macOS Keychain.
- Export and restore a local JSON backup without SIP passwords.
- Restore TelefonX data from a compatible backup.
- Export technical diagnostics without including SIP credentials.
- Request access to the microphone, Apple Contacts and other system integrations
  only when their respective features are used.

### TelefonX Pro

- Unlock additional SIP lines, callback reminders and outgoing dialing rules.
- Unlock contact CSV import and export, custom ringtones and custom hold music.
- Unlock public business-name lookup.
- Choose between monthly and annual subscriptions with the same feature set.
- Display regional prices and introductory offers supplied by the App Store.
- Restore previous purchases and open Apple's subscription management.

The free version includes one SIP line, core calling, local and Apple contacts,
favorites, call history, blocking, built-in ringtones, local backup and technical
diagnostics.
