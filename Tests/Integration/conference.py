#!/usr/bin/env python3
"""Three loopback peers verify bidirectional RTP mixing through TelefonX."""
import pathlib
import tempfile
import time

from loopback import Peer, inspect_audio, tone


def connect(caller, callee):
    caller.ok(f"CALL sip:peer@127.0.0.1:{callee.port}")
    callee.wait(lambda line: line.startswith("EVENT 2 2 "))
    callee.ok("ANSWER")
    caller.wait(lambda line: line.startswith("EVENT 2 5 "))
    time.sleep(0.2)


def wait_routes(peer, expected, timeout=4):
    deadline = time.monotonic() + timeout
    observed = None
    while time.monotonic() < deadline:
        peer.send("CONFERENCEROUTES")
        observed = peer.wait(lambda line: line.startswith("CONFERENCEROUTES "))
        peer.wait(lambda line: line == "RESULT CONFERENCEROUTES 0")
        if observed == expected:
            return
        time.sleep(0.05)
    raise AssertionError(f"Conference routes remained {observed}; expected {expected}")


def exercise(directory):
    peers = []
    try:
        for _ in range(3):
            peers.append(Peer("opus"))
        host, first, second = peers
        connect(host, first)
        connect(host, second)

        first.ok(f"MEDIA {directory / 'first.wav'} {directory / 'first-recording.wav'}")
        second.ok(f"MEDIA {directory / 'second.wav'} {directory / 'second-recording.wav'}")
        host.ok("CONFERENCE 1")
        wait_routes(host, "CONFERENCEROUTES 1 1")
        time.sleep(3)
        first.ok("RECORD -")
        second.ok("RECORD -")

        host.ok("HOLDAT 0 1")
        first.wait(lambda line: line.startswith("EVENT 3 0 0 0 1"))
        host.ok("HOLDAT 0 0")
        first.wait(lambda line: line.startswith("EVENT 3 0 0 0 0"))
        wait_routes(host, "CONFERENCEROUTES 1 1")
        host.ok("CONFERENCE 0")
        wait_routes(host, "CONFERENCEROUTES 0 0")

        second.ok("HANGUP")
        host.wait(lambda line: line.startswith("EVENT 2 6 "))
        host.ok("DTMF 5")
        first.wait(lambda line: line.startswith(f"EVENT 6 0 {ord('5')} "))
        first.ok("HANGUP")
        for peer in peers:
            peer.stop()

        first_result = inspect_audio(directory / "first-recording.wav", 659)
        second_result = inspect_audio(directory / "second-recording.wav", 523)
        print(f"PASS local conference: bidirectional remote mixing {first_result}, {second_result}; participant hold/resume; remaining call survives hangup")
    finally:
        for peer in peers:
            peer.stop()


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="telefonx-conference-") as raw:
        directory = pathlib.Path(raw)
        tone(directory / "first.wav", 523)
        tone(directory / "second.wav", 659)
        exercise(directory)
