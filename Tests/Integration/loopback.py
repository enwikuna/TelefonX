#!/usr/bin/env python3
"""Real SIP/RTP on loopback, synthetic WAV only; no microphone or PBX access."""
import array
import math
import pathlib
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
PEER = ROOT / ".build" / "sip-peer"

class Peer:
    def __init__(self, codec):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            self.port = reservation.getsockname()[1]
        self.process = subprocess.Popen([str(PEER), str(self.port), codec], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.lines = queue.Queue()
        self.transcript = []
        def read():
            for value in self.process.stdout:
                value = value.strip()
                self.transcript.append(value)
                self.lines.put(value)
        threading.Thread(target=read, daemon=True).start()
        self.wait(lambda line: line == "READY")

    def send(self, command):
        self.process.stdin.write(command + "\n")
        self.process.stdin.flush()

    def wait(self, predicate, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = self.lines.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if predicate(value):
                return value
        raise AssertionError("Peer timeout / failed expectation:\n" + "\n".join(self.transcript[-30:]))

    def ok(self, command):
        self.send(command)
        verb = command.split()[0]
        value = self.wait(lambda line: line.startswith("RESULT " + verb + " "))
        assert value == "RESULT " + verb + " 0", value

    def stop(self):
        if self.process.poll() is None:
            self.send("QUIT")
            try:
                self.process.wait(timeout=12)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=5)
        assert self.process.returncode == 0, self.transcript[-20:]

def tone(path, frequency):
    samples = array.array("h", (int(7000 * math.sin(2 * math.pi * frequency * i / 48000)) for i in range(48000 * 2)))
    with wave.open(str(path), "wb") as wav:
        wav.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
        wav.writeframes(samples.tobytes())

def inspect_audio(path, frequency):
    with wave.open(str(path), "rb") as wav:
        rate = wav.getframerate()
        assert wav.getsampwidth() == 2 and wav.getnchannels() == 1
        samples = array.array("h", wav.readframes(wav.getnframes()))
    assert len(samples) > rate, "Less than one second of decoded audio"
    values = samples[rate // 2 : -rate // 4]
    rms = math.sqrt(sum(x * x for x in values) / len(values))
    assert rms > 800, f"Missing or quiet decoded audio: RMS {rms}"
    crossings = sum(a < 0 <= b for a, b in zip(values, values[1:]))
    observed = crossings * rate / len(values)
    assert abs(observed - frequency) < 15, f"Wrong received tone {observed}, expected {frequency}"
    return round(rms), round(observed)

def exercise(codec, directory):
    a = b = None
    try:
        a, b = Peer(codec), Peer(codec)
        a.ok("AEC")
        a.ok(f"CALL sip:peer@127.0.0.1:{b.port}")
        b.wait(lambda line: line.startswith("EVENT 2 2 "))
        b.ok("DECLINE")
        a.wait(lambda line: line.startswith("EVENT 2 6 603 "))
        assert any(line.startswith("EVENT 2 6 603 ") for line in b.transcript), b.transcript[-20:]
        a.ok(f"CALL sip:peer@127.0.0.1:{b.port}")
        b.wait(lambda line: line.startswith("EVENT 2 2 "))
        b.ok("ANSWER")
        a.wait(lambda line: line.startswith("EVENT 2 5 "))
        # ANSWER may print CONFIRMED before its RESULT; inspect the full transcript.
        if not any(line.startswith("EVENT 2 5 ") for line in b.transcript):
            b.wait(lambda line: line.startswith("EVENT 2 5 "))
        a.ok(f"MEDIA {directory / 'a.wav'} {directory / (codec + '-a.wav')}")
        b.ok(f"MEDIA {directory / 'b.wav'} {directory / (codec + '-b.wav')}")
        time.sleep(3)
        for peer in (a, b):
            peer.send("STATS")
            values = peer.wait(lambda line: line.startswith("STATS ")).split()
            assert values[1].lower() == codec.lower(), values
            assert int(values[2]) > 70 and int(values[3]) > 70, values
            assert int(values[4]) == 0, values
        # Finish the continuous speech-tone sample before RFC 4733 replaces
        # audio packets with the complete twelve-key DTMF sequence.
        a.ok("RECORD -"); b.ok("RECORD -")
        for digit in "123456789*0#":
            a.ok(f"DTMF {digit}")
            b.wait(lambda line, code=ord(digit): line.startswith(f"EVENT 6 0 {code} "))
        a.ok("MUTE 1"); a.ok("MUTE 0")
        a.ok("HOLD 1")
        b.wait(lambda line: line.startswith("EVENT 3 0 0 0 1"))
        time.sleep(0.3)
        a.ok("HOLD 0")
        b.wait(lambda line: line.startswith("EVENT 3 0 0 0 0"))
        a.send("STALE")
        stale = a.wait(lambda line: line.startswith("RESULT STALE "))
        assert not stale.endswith(" 0"), "Stale call handle accepted"
        a.ok("HANGUP")
        b.wait(lambda line: line.startswith("EVENT 2 6 "))
        a.stop(); b.stop()
        result_a = inspect_audio(directory / (codec + "-a.wav"), 660)
        result_b = inspect_audio(directory / (codec + "-b.wav"), 440)
        print(f"PASS {codec}: SIP 603 decline; bidirectional decoded RTP {result_a}, {result_b}; DTMF 0-9*#, hold/resume, mute API, stale handle; AEC3 initialized", flush=True)
    finally:
        for peer in (a, b):
            if peer is not None and peer.process.poll() is None:
                peer.stop()

if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="telefonx-loopback-") as raw:
        directory = pathlib.Path(raw)
        tone(directory / "a.wav", 440); tone(directory / "b.wav", 660)
        for codec in (sys.argv[1:] or ["opus", "G722", "PCMA", "PCMU"]):
            exercise(codec, directory)
    print("All loopback tests passed. AirPods/acoustic quality and real PBX interoperability remain manual gates.")
