#!/usr/bin/env python3
"""Real hold-music RTP and conference routing, loopback/null audio only."""
import array
import math
import pathlib
import tempfile
import time
import wave
from loopback import Peer, tone, inspect_audio

def event_since(peer, mark, prefix):
    if not any(line.startswith(prefix) for line in peer.transcript[mark:]):
        peer.wait(lambda line: line.startswith(prefix))

def exercise(codec, directory):
    a = b = None
    try:
        a, b = Peer(codec), Peer(codec)
        a.send("MUSIC /nonexistent/telefonx-test.wav")
        assert not a.wait(lambda line: line.startswith("RESULT MUSIC")).endswith(" 0")
        a.ok(f"MUSIC {directory / 'music.wav'}")
        a.ok(f"CALL sip:peer@127.0.0.1:{b.port}")
        b.wait(lambda line: line.startswith("EVENT 2 2 "))
        mark = len(a.transcript)
        b.ok("ANSWER")
        event_since(a, mark, "EVENT 2 5 ")
        time.sleep(0.2)
        a.send("MUSIC -")
        assert not a.wait(lambda line: line.startswith("RESULT MUSIC")).endswith(" 0"), "Music replaced during call"
        for cycle in range(2):
            local_mark = len(a.transcript)
            remote_mark = len(b.transcript)
            a.ok("HOLD 1")
            event_since(a, local_mark, "EVENT 3 0 0 1 0")
            time.sleep(0.3)
            assert not any(line.startswith("EVENT 3 0 0 0 1") for line in b.transcript[remote_mark:]), "Custom music sent SIP hold to remote"
            a.send("HOLDSTATE")
            assert a.wait(lambda line: line.startswith("HOLDSTATE ")) == "HOLDSTATE 1 0"
            a.ok("MUTE 1"); a.ok("MUTE 0")
            time.sleep(0.1)
            a.send("ROUTES")
            assert a.wait(lambda line: line.startswith("ROUTES ")) == "ROUTES 0 1 0", "Music/microphone route leaked"
            recording = directory / f"{codec}-{cycle}-held.wav"
            b.ok(f"RECORD {recording}")
            time.sleep(2)
            b.ok("RECORD -")
            time.sleep(0.1)
            inspect_audio(recording, 523)
            local_mark = len(a.transcript)
            a.ok("HOLD 0")
            event_since(a, local_mark, "EVENT 3 0 0 0 0")
            time.sleep(0.3)
            a.send("ROUTES")
            assert a.wait(lambda line: line.startswith("ROUTES ")) == "ROUTES 1 0 0", "Music continued after resume"
        silence = directory / f"{codec}-resumed.wav"
        b.ok(f"RECORD {silence}"); time.sleep(1.5); b.ok("RECORD -"); time.sleep(0.1)
        with wave.open(str(silence), "rb") as wav:
            samples = array.array("h", wav.readframes(wav.getnframes()))
        assert samples and math.sqrt(sum(x*x for x in samples) / len(samples)) < 100, "Music leaked after resume"
        a.ok("HOLD 1"); time.sleep(0.3)
        remote_hangup_mark = len(a.transcript)
        b.ok("HANGUP")
        event_since(a, remote_hangup_mark, "EVENT 2 6 ")
        a.ok("MUSIC -")
        a.stop(); b.stop()
        print(f"PASS {codec}: held remote receives 523 Hz RTP; no mic/local music route; two hold/resume cycles; silence after resume; remote hangup while playing", flush=True)
    finally:
        for peer in (a, b):
            if peer and peer.process.poll() is None: peer.stop()

if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="telefonx-hold-music-") as raw:
        directory = pathlib.Path(raw)
        tone(directory / "music.wav", 523)
        for codec in ["opus", "G722", "PCMA", "PCMU"]:
            exercise(codec, directory)
