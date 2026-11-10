#!/usr/bin/env python3
"""Check that the Touch ID wait hides typed input and always restores echo."""
import fcntl
import os
import pty
import select
import signal
import subprocess
import sys
import termios
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
single_sudo = sys.argv[1:] == ['single-sudo']
if single_sudo:
    script = r'''
unset MOLE_TEST_MODE MOLE_TEST_NO_AUTH
source "$TEST_ROOT/lib/core/common.sh"
source "$TEST_ROOT/lib/core/sudo.sh"

tmp_dir="$(mktemp -d)"
calls="$tmp_dir/calls"
authed="$tmp_dir/authed"
trap 'rm -rf -- "$tmp_dir" # SAFE: exact temporary directory created above' EXIT

sudo() {
    case "$1" in
        -n) [[ -e "$authed" ]] ;;
        -k) return 0 ;;
        -v)
            echo v >> "$calls"
            # The user takes longer than the old five-second window.
            sleep 6
            : > "$authed"
            ;;
        *) return 1 ;;
    esac
}
is_clamshell_mode() { return 1; }
check_touchid_support() { return 0; }
safe_clear_lines() { printf "CLEAR:%s\\n" "$1"; }
safe_clear_line() { :; }

rc=0
request_sudo_access "Admin access required" || rc=$?
printf "RC=%s V_CALLS=%s\\n" "$rc" "$(grep -c . "$calls")"
'''
else:
    script = r'''
source "$TEST_ROOT/lib/core/sudo.sh"
probe() { if stty -a < /dev/tty | grep -q -- '-echo '; then echo off; else echo on; fi; }
echo "BEFORE=$(probe)"
_mole_tty_quiet /dev/tty bash -c 'if stty -a < /dev/tty | grep -q -- "-echo "; then echo INSIDE=off; else echo INSIDE=on; fi'
echo "AFTER=$(probe)"
# Like clean, the caller has its own INT trap; it runs after the quiet
# subshell restored the terminal.
trap 'echo "AFTER_INT=$(probe)"; exit 130' INT
echo READY_FOR_INT
_mole_tty_quiet /dev/tty sleep 30
echo UNREACHED
'''


def own_terminal():
    # A runner that started us in the background leaves SIGINT ignored, and
    # bash cannot trap a signal it inherited ignored; a terminal never does.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


master, slave = pty.openpty()
process = subprocess.Popen(['/bin/bash', '--noprofile', '--norc', '-c', script],
                           stdin=slave, stdout=slave, stderr=slave,
                           env=dict(os.environ, TEST_ROOT=str(root)),
                           preexec_fn=own_terminal)
output = b''
interrupted = False
deadline = time.monotonic() + 15
try:
    while process.poll() is None:
        assert time.monotonic() < deadline, output.decode(errors='replace')
        if select.select([master], [], [], .05)[0]:
            output += os.read(master, 4096)
        if b'READY_FOR_INT' in output and not interrupted:
            time.sleep(.3)
            # A terminal Ctrl-C reaches the whole foreground process group.
            os.killpg(process.pid, signal.SIGINT)
            interrupted = True
    while select.select([master], [], [], .1)[0]:
        chunk = os.read(master, 4096)
        if not chunk:
            break
        output += chunk
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
    os.close(master)
    os.close(slave)

text = output.decode(errors='replace').replace('\r', '')
if single_sudo:
    sys.stdout.write(text)
    if process.returncode != 0:
        sys.exit(process.returncode)
    sys.exit(0)
assert 'BEFORE=on' in text, text
assert 'INSIDE=off' in text, text
assert 'AFTER=on' in text, text
assert 'UNREACHED' not in text, text
assert 'AFTER_INT=on' in text, text
print('PASS: typed input hidden during the wait, echo restored on return and after Ctrl-C')
