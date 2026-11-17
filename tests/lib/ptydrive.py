#!/usr/bin/env python3
"""在虛擬終端機 (PTY) 中執行指令，並在畫面靜止後送出按鍵。

為什麼需要這個工具：gwt 只在互動式終端機執行（會檢查 stdin/stdout 是否為
tty），而 zsh 的 `read -k` 在管線 (pipe) 上會直接失敗（not interactive and
can't open terminal），所以測試選單一定要給一個真正的 pseudo-terminal。

另一個關鍵是送按鍵的時機：如果按鍵比選單更早抵達，會被終端機的行緩衝吃掉。
因此本程式不是「啟動後固定延遲 N 秒」，而是等子行程的輸出靜止 settle 秒
（預設 0.3 秒）才送出按鍵，等於確認選單已經畫完、程式正在等輸入。

用法：
    ptydrive.py --keys '\\e[B\\n' --out 輸出檔 -- zsh -f 測試腳本.zsh

--keys 支援 \\e (ESC)、\\n、\\r、\\xNN 等跳脫序列；未指定時只觀察不送鍵。
結束碼沿用子行程的結束碼，方便直接當成測試結果。
"""

import argparse
import codecs
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

ROWS = 40
COLS = 100


def decode_keys(raw: str) -> bytes:
    """把命令列上的跳脫序列字串轉成實際要送進 PTY 的位元組。"""
    if not raw:
        return b""
    # Python 的 unicode_escape 不認識 \e，先換成等價的 \x1b
    prepared = raw.replace("\\e", "\\x1b")
    return codecs.decode(prepared, "unicode_escape").encode("latin-1")


def main() -> int:
    parser = argparse.ArgumentParser(description="PTY 按鍵驅動器")
    parser.add_argument("--keys", default="", help="要送出的按鍵，支援 \\e \\n \\xNN")
    parser.add_argument("--out", default="", help="把子行程的原始輸出寫到這個檔案")
    parser.add_argument(
        "--settle",
        type=float,
        default=0.3,
        help="輸出靜止幾秒後才送按鍵（預設 0.3）",
    )
    parser.add_argument("--timeout", type=float, default=20.0, help="總執行上限秒數")
    parser.add_argument("--rows", type=int, default=ROWS, help="PTY 高度（預設 40）")
    parser.add_argument("--cols", type=int, default=COLS, help="PTY 寬度（預設 100）")
    parser.add_argument("cmd", nargs=argparse.REMAINDER, help="-- 之後是要執行的指令")
    args = parser.parse_args()

    cmd = args.cmd
    if cmd[:1] == ["--"]:
        cmd = cmd[1:]
    if not cmd:
        parser.error("缺少要執行的指令")

    keys = decode_keys(args.keys)

    pid, fd = pty.fork()
    if pid == 0:  # 子行程：stdin/stdout/stderr 都接到 PTY
        try:
            os.execvp(cmd[0], cmd)
        finally:
            os._exit(127)

    fcntl.ioctl(
        fd, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0)
    )

    out = bytearray()
    sent = False
    last_output_at = None
    deadline = time.time() + args.timeout
    status = None

    while True:
        if time.time() > deadline:
            os.kill(pid, signal.SIGKILL)
            break

        ready, _, _ = select.select([fd], [], [], 0.02)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:  # 子行程關閉 PTY 後讀取會得到 EIO
                break
            if not chunk:
                break
            out += chunk
            last_output_at = time.time()

        if (
            not sent
            and last_output_at is not None
            and time.time() - last_output_at >= args.settle
        ):
            os.write(fd, keys)
            sent = True

        done, raw_status = os.waitpid(pid, os.WNOHANG)
        if done == pid:
            status = raw_status
            # 子行程結束後把 PTY 緩衝區剩下來的輸出讀乾淨
            while True:
                ready, _, _ = select.select([fd], [], [], 0.1)
                if not ready:
                    break
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
            break

    os.close(fd)
    if status is None:
        try:
            _, status = os.waitpid(pid, 0)
        except ChildProcessError:
            status = 1

    if args.out:
        with open(args.out, "wb") as handle:
            handle.write(bytes(out))

    if os.WIFSIGNALED(status):
        return -os.WTERMSIG(status)
    return os.WEXITSTATUS(status)


if __name__ == "__main__":
    sys.exit(main())
