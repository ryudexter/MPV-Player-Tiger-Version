#!/usr/bin/env python3
"""Smoke test for MPV Player: Tiger Version, on macOS, Windows and Linux.

Runs a headless mpv (--vo=null --ao=null) on this config, plays clips mpv makes
for itself, presses keys through the IPC socket and checks what changed. It
needs nothing but Python 3 and mpv: the clips come from mpv's own encoder, so
there is no ffmpeg to install on a fresh Windows runner.

    python3 tests/smoke.py                   # this checkout, mpv from PATH
    python3 tests/smoke.py --config ~/.config/mpv --mpv /opt/homebrew/bin/mpv
    python3 tests/smoke.py --launcher        # also the single-instance launcher
    python3 tests/smoke.py --desktop         # also i and Cmd/Ctrl+Delete, for real

--desktop opens a file manager window and really moves a test clip to the
Trash / Recycle Bin; --launcher talks to the launcher's fixed socket. On a
machine you use, leave both off while mpv is open. The CI passes both.

It checks behaviour that differs per system, and that each script loads
without a Lua error. It does not look at pixels or listen to audio.
"""
import argparse, json, os, shutil, socket, subprocess, sys, tempfile, time

WIN = os.name == "nt"
MAC = sys.platform == "darwin"
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# every script in scripts/, which must all load and never raise
SCRIPTS = sorted(n[:-4] for n in os.listdir(os.path.join(HERE, "scripts")) if n.endswith(".lua"))

results = []


def check(name, ok, detail=""):
    if isinstance(detail, (list, tuple)):
        detail = " | ".join(str(d).strip() for d in detail)
    detail = str(detail)
    results.append((name, bool(ok), detail))
    print(("  ok    " if ok else "  FAIL  ") + name + (("  - " + detail) if detail else ""), flush=True)
    return ok


class IPC:
    """mpv's JSON IPC over a Unix socket, or a named pipe on Windows."""

    def __init__(self, path, timeout=15):
        deadline = time.time() + timeout
        while True:
            try:
                if WIN:
                    self.f = open(path, "r+b", buffering=0)
                else:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.connect(path)
                    self.f = s.makefile("rwb", buffering=0)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.1)
        self.rid = 0

    def _readline(self):
        line = b""
        while not line.endswith(b"\n"):
            c = self.f.read(1)
            if not c:
                raise EOFError("mpv closed the IPC connection")
            line += c
        return line

    def cmd(self, *args):
        self.rid += 1
        self.f.write((json.dumps({"command": list(args), "request_id": self.rid}) + "\n").encode())
        while True:
            m = json.loads(self._readline())
            if m.get("request_id") == self.rid:
                return m.get("data") if m.get("error") == "success" else None

    def get(self, prop, default=None):
        v = self.cmd("get_property", prop)
        return default if v is None else v

    def wait(self, what, test, timeout=10):
        deadline = time.time() + timeout
        while time.time() < deadline:
            v = test()
            if v:
                return v
            time.sleep(0.1)
        return None


def make_clips(mpv, folder, names):
    os.makedirs(folder, exist_ok=True)
    for i, name in enumerate(names):
        subprocess.run([mpv, "--no-config", "--msg-level=all=error",
                        "av://lavfi:testsrc=d=60:s=320x240:r=24",
                        "--audio-file=av://lavfi:sine=f=%d:d=60" % (300 + 100 * i),
                        "--o=" + os.path.join(folder, name), "--of=matroska",
                        "--ovc=mpeg4", "--oac=aac"], check=True, timeout=120)


def start(mpv, config, ipc_path, log, extra=()):
    args = [mpv, "--config-dir=" + config, "--vo=null", "--ao=null", "--idle=yes",
            "--force-window=no", "--input-ipc-server=" + ipc_path,
            "--log-file=" + log, "--msg-level=all=v"] + list(extra)
    return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def osd_log_since(log, mark):
    with open(log, encoding="utf-8", errors="replace") as f:
        return f.read()[mark:]


def log_size(log):
    try:
        return os.path.getsize(log)
    except OSError:
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=HERE, help="the config folder to test (default: this checkout)")
    ap.add_argument("--mpv", default=shutil.which("mpv") or "mpv")
    ap.add_argument("--launcher", action="store_true", help="also test the single-instance launcher")
    ap.add_argument("--desktop", action="store_true",
                    help="also test i (opens a file manager) and trashing a clip, for real")
    ap.add_argument("--keep", action="store_true", help="keep the temporary folder")
    a = ap.parse_args()
    config = os.path.abspath(os.path.expanduser(a.config))

    work = tempfile.mkdtemp(prefix="tiger-smoke-")
    media = os.path.join(work, "Some Show")          # a space, as real paths have
    print("mpv:    " + subprocess.run([a.mpv, "--no-config", "--version"], capture_output=True,
                                      text=True).stdout.splitlines()[0])
    print("config: " + config)
    print("work:   " + work)
    make_clips(a.mpv, media, ["Episode 1.mkv", "Episode 2.mkv", "Episode 3.mkv"])

    log = os.path.join(work, "mpv.log")
    if WIN:
        ipc_path = r"\\.\pipe\tiger-smoke-%d" % os.getpid()
    else:
        ipc_path = "smoke.sock"                      # relative: macOS caps socket paths at 104 bytes
        os.chdir(work)
    proc = start(a.mpv, config, ipc_path, log)
    try:
        ipc = IPC(ipc_path)
        run_checks(a, ipc, media, log, work)
        ipc.cmd("quit")
        proc.wait(timeout=15)
    finally:
        if proc.poll() is None:
            proc.kill()

    text = open(log, encoding="utf-8", errors="replace").read()
    loaded = [s for s in SCRIPTS if ("[%s]" % s) in text or ("/%s.lua" % s) in text]
    check("every script loaded", len(loaded) == len(SCRIPTS),
          "missing: " + ", ".join(sorted(set(SCRIPTS) - set(loaded))) if len(loaded) != len(SCRIPTS) else "")
    lua_errors = [l for l in text.splitlines() if "Lua error" in l or "stack traceback" in l]
    check("no Lua errors", not lua_errors, " | ".join(lua_errors[:5]))
    conf_errors = [l for l in text.splitlines()
                   if "Error parsing option" in l or "setting option" in l and "failed" in l]
    check("mpv.conf parses cleanly", not conf_errors, " | ".join(conf_errors[:5]))

    if a.launcher:
        test_launcher(a, config, media, work)

    failed = [r for r in results if not r[1]]
    print("\n%d checks, %d failed" % (len(results), len(failed)))
    if failed or a.keep:
        print("log: " + log)
    else:
        shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if failed else 0)


def run_checks(a, ipc, media, log, work):
    platform = ipc.get("platform")
    print("platform: %s\n" % platform)
    first = os.path.join(media, "Episode 1.mkv")

    ipc.cmd("loadfile", first)
    ipc.wait("loaded", lambda: ipc.get("duration"), timeout=20)
    check("a video plays", ipc.get("duration"), "duration %s" % ipc.get("duration"))
    # autocreate-playlist=filter: opening one video queues its folder
    check("the folder becomes the playlist", ipc.get("playlist-count") == 3,
          "playlist-count %s" % ipc.get("playlist-count"))

    # [windows-and-linux] clears the Mac's yt-dlp path; the Mac keeps it
    opts = ipc.get("script-opts", {})
    want = "/opt/homebrew/bin/yt-dlp" if platform == "darwin" else ""
    check("yt-dlp path for this system", opts.get("ytdl_hook-ytdl_path") == want,
          repr(opts.get("ytdl_hook-ytdl_path")))

    # Cmd/Ctrl+RIGHT: 30 s, through the platform's own chord
    chord = "Meta" if platform == "darwin" else "Ctrl"
    ipc.cmd("set_property", "pause", True)
    ipc.cmd("seek", 0, "absolute", "exact")
    time.sleep(0.3)
    ipc.cmd("keypress", chord + "+RIGHT")
    pos = ipc.wait("seek", lambda: (ipc.get("time-pos", 0) or 0) > 25 and ipc.get("time-pos"))
    check(chord + "+RIGHT seeks 30 s", pos, "time-pos %s" % ipc.get("time-pos"))

    # Cmd/Ctrl+z: shuffle forces keep-open=always while it is on
    before = ipc.get("keep-open")
    ipc.cmd("keypress", chord + "+z")
    on = ipc.wait("shuffle", lambda: ipc.get("keep-open") == "always")
    check(chord + "+z turns shuffle on", on, "keep-open %s -> %s" % (before, ipc.get("keep-open")))
    ipc.cmd("keypress", chord + "+z")
    ipc.wait("shuffle off", lambda: ipc.get("keep-open") != "always")

    # y -> "always on": the shader chain must arrive as separate files, which
    # on Windows needs ';' between them (':' is in every path there)
    ipc.cmd("keypress", "y")
    shaders = ipc.wait("shaders", lambda: ipc.get("glsl-shaders"))
    shaders = shaders or []
    check("y loads the Anime4K chain as separate files",
          len(shaders) >= 4 and all(os.path.isfile(s) for s in shaders),
          "%d entries, first %r" % (len(shaders), shaders[:1]))
    ipc.cmd("keypress", "y")                       # -> off
    ipc.cmd("keypress", "y")                       # -> auto

    # power: the log says which source the ladder believes in, and must not
    # complain that it could not tell
    time.sleep(1)
    text = osd_log_since(log, 0)
    check("power source read without error", "could not read the power source" not in text)

    # the volume is remembered in ~~state, whose folder may not exist yet on
    # Linux and Windows - global-sound.lua has to make it
    ipc.cmd("set_property", "volume", 61)
    state = ipc.cmd("expand-path", "~~state/sound-state.json")
    saved = ipc.wait("sound state", lambda: os.path.isfile(state) and "61" in open(state).read(),
                     timeout=5)
    check("the volume is saved to ~~state", saved, state)

    # b with no subliminal installed must say so, not raise
    mark = log_size(log)
    ipc.cmd("keypress", "b")
    time.sleep(2)
    said = osd_log_since(log, mark)
    check("b runs (subliminal or a clear message)",
          "Lua error" not in said and ("subliminal" in said or "Looking for subtitles" in said))
    ipc.cmd("keypress", "b")                       # in case it started: one more is a no-op

    # i: reveal. A headless runner may have no file manager to answer; what
    # matters is that the platform's own route is taken and nothing raises.
    if a.desktop:
        mark = log_size(log)
        ipc.cmd("keypress", "i")
        time.sleep(3)
        said = osd_log_since(log, mark)
        # mpv logs every spawn as "Starting subprocess: [prog, arg, ...]"
        route = {"darwin": "[open, -R,", "windows": "mpv-open.exe, --reveal,",
                 "linux": "[dbus-send,"}.get(platform, "?")
        check("i takes this system's reveal route", route in said and "Lua error" not in said,
              [l for l in said.splitlines() if "Starting subprocess" in l or "reveal" in l][:3])

    # p is a macOS feature; elsewhere it must answer rather than act
    ipc.cmd("keypress", "p")
    time.sleep(0.5)
    check("p leaves native-fs alone off the Mac", platform == "darwin" or ipc.get("native-fs") is True)

    if a.desktop:
        test_trash(a, ipc, platform, work, log)


def test_trash(a, ipc, platform, work, log):
    folder = os.path.join(work, "Trash me")
    make_clips(a.mpv, folder, ["Doomed.mkv", "Spare.mkv"])
    doomed = os.path.join(folder, "Doomed.mkv")
    ipc.cmd("loadfile", doomed)
    ipc.wait("loaded", lambda: ipc.get("path", "").endswith("Doomed.mkv") and ipc.get("duration"))
    key = "Meta+BS" if platform == "darwin" else "Ctrl+DEL"
    mark = log_size(log)
    ipc.cmd("keypress", key)
    gone = ipc.wait("trashed", lambda: not os.path.exists(doomed), timeout=15)
    said = osd_log_since(log, mark)
    check(key + " moves the playing file to the bin", gone,
          [l for l in said.splitlines() if "trash" in l.lower()][:3])
    check("...and playback carries on", ipc.get("path", "").endswith("Doomed.mkv") and not ipc.get("idle-active"))
    if platform == "linux":
        home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        check("...into the freedesktop Trash", os.path.exists(os.path.join(home, "Trash", "files", "Doomed.mkv")))


def test_launcher(a, config, media, work):
    """Open one file, then another, through the launcher: one player, two opens."""
    print("\nlauncher")
    env = dict(os.environ, MPV_TIGER_FLAGS="--vo=null --ao=null")
    if WIN:
        launcher = [os.path.join(config, "mpv-open.exe")]
        sock = r"\\.\pipe\mpv-single"
    else:
        launcher = [sys.executable, os.path.join(config, "mpv-open")]
        run = os.environ.get("XDG_RUNTIME_DIR")
        if MAC:
            sock = "/tmp/mpv-single.sock"
        elif run and os.path.isdir(run):
            sock = os.path.join(run, "mpv-single.sock")
        else:
            sock = "/tmp/mpv-single-%d.sock" % os.getuid()
    one = os.path.join(media, "Episode 1.mkv")
    two = os.path.join(media, "Episode 2.mkv")
    subprocess.run(launcher + [one], env=env, timeout=60)
    ipc = IPC(sock, timeout=20)
    ipc.wait("loaded", lambda: ipc.get("duration"), timeout=20)
    pid = ipc.get("pid")
    check("the launcher starts a player", (ipc.get("path") or "").endswith("Episode 1.mkv"), ipc.get("path"))
    ipc.cmd("set_property", "pause", True)
    ipc.cmd("set_property", "speed", 3.0)
    subprocess.run(launcher + [two], env=env, timeout=60)
    ok = ipc.wait("switched", lambda: (ipc.get("path") or "").endswith("Episode 2.mkv"), timeout=10)
    check("a second open goes to the SAME player", ok and ipc.get("pid") == pid,
          "path %s, pid %s -> %s" % (ipc.get("path"), pid, ipc.get("pid")))
    check("...without duplicating the playlist", ipc.get("playlist-count") == 3,
          "playlist-count %s" % ipc.get("playlist-count"))
    check("...unpaused, at 1x", ipc.get("pause") is False and ipc.get("speed") == 1.0,
          "pause %s speed %s" % (ipc.get("pause"), ipc.get("speed")))
    try:
        ipc.cmd("quit")
    except (EOFError, OSError):
        pass


if __name__ == "__main__":
    main()
