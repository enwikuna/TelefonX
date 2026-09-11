#!/usr/bin/env python3
"""Three real local SIP peers exercise local music hold and attended transfer."""
import pathlib
import tempfile
import time
from loopback import Peer, tone

def connect(caller, callee):
    caller.ok(f"CALL sip:peer@127.0.0.1:{callee.port}")
    callee.wait(lambda line: line.startswith("EVENT 2 2 "))
    callee.ok("ANSWER")
    caller.wait(lambda line: line.startswith("EVENT 2 5 "))
    time.sleep(0.2)

def exercise(directory):
    peers = []
    try:
        for _ in range(3): peers.append(Peer("opus"))
        a, b, c = peers
        a.ok(f"MUSIC {directory / 'music.wav'}")
        connect(a, b)
        local_mark = len(a.transcript)
        remote_mark = len(b.transcript)
        a.ok("HOLD 1")
        if not any(line.startswith("EVENT 3 0 0 1 0") for line in a.transcript[local_mark:]):
            a.wait(lambda line: line.startswith("EVENT 3 0 0 1 0"))
        time.sleep(0.3)
        assert not any(line.startswith("EVENT 3 0 0 0 1") for line in b.transcript[remote_mark:]), "Music hold signaled provider hold"
        connect(a, c)
        a.ok("TRANSFER")
        a.wait(lambda line: line.startswith("EVENT 4 0 200 "))
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and sum(line.startswith("EVENT 2 6 ") for line in a.transcript) < 2:
            time.sleep(0.05)
        assert sum(line.startswith("EVENT 2 6 ") for line in a.transcript) == 2, a.transcript
        time.sleep(2)
        for peer in (b, c):
            peer.send("STATS")
            stats = peer.wait(lambda line: line.startswith("STATS ")).split()
            assert int(stats[2]) > 20 and int(stats[3]) > 20, stats
        b.ok("HANGUP")
        print("PASS local music hold + attended transfer: no provider hold signal; REFER/Replaces connects B ↔ C with RTP")
    finally:
        for peer in peers: peer.stop()

if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="telefonx-transfer-") as raw:
        directory = pathlib.Path(raw)
        tone(directory / "music.wav", 523)
        exercise(directory)
