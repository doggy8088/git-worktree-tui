#!/usr/bin/env python3
"""把 PTY 的原始輸出重播成「最後的畫面」，用來檢查選單排版。

為什麼需要它：gwt 的選單是靠 ANSI 跳脫序列就地重繪的，錯誤不會顯示在
stdout 的文字裡，只會表現在終端機的最終畫面上。要驗證「有沒有重複的列」、
「游標往上移幾行」這類問題，只能把序列重播一遍。

只支援 gwt 實際會用到的序列，刻意不寫成完整的終端機模擬器：

    \\r            游標回到行首
    \\n            換行（到最後一列時整頁上捲）
    \\e[<n>A       往上 n 行（到頂為止，與真實終端機一致）
    \\e[<n>B       往下 n 行
    \\e[2K         清除整列
    \\e[K          清除游標到行尾
    \\e[J          清除游標到畫面結尾
    \\e[<n>m       SGR，忽略
    \\e[?25l/h     顯示／隱藏游標，忽略

用法：
    screen.py --rows 24 --cols 80 --raw 原始輸出.bin

輸出前半是重播後的最終畫面，後半是給測試用的結構摘要：

    ITEM_ROWS   畫面上有幾列項目
    INDEXES     出現過的編號（壓成區間，例如 11-20）
    DUPLICATES  重複出現的編號（正確的重繪不該有）
    SELECTED    光棒所在那一列的編號
    WRAPS       寫滿一列之後又寫字、被迫折到下一行的次數（正確的排版不該有）

欄寬：每個字元都算 1 欄（不認得全形字）。所以 WRAPS 只對 ASCII 內容準確——
有全形字時實際更寬，這裡會少算；要用 WRAPS 驗折行的測試，fixture 必須只有 ASCII。
"""

import argparse
import re
import sys

CSI = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")


class Screen:
    def __init__(self, rows: int, cols: int) -> None:
        self.rows = rows
        self.cols = cols
        self.grid = [[" "] * cols for _ in range(rows)]
        self.row = 0
        self.col = 0
        self.wraps = 0

    def _scroll(self) -> None:
        self.grid.pop(0)
        self.grid.append([" "] * self.cols)
        self.row = self.rows - 1

    def newline(self) -> None:
        self.row += 1
        if self.row >= self.rows:
            self._scroll()

    def put(self, ch: str) -> None:
        # 與真實終端機一樣：寫到最後一欄之後不會馬上換行，要等下一個字元才折行
        # （中間若先收到 \r 或 \n 就不會折）。所以這裡數到的就是真的折行。
        if self.col >= self.cols:
            self.col = 0
            self.newline()
            self.wraps += 1
        self.grid[self.row][self.col] = ch
        self.col += 1

    def clear_line(self) -> None:
        self.grid[self.row] = [" "] * self.cols
        self.col = 0

    def clear_to_eol(self) -> None:
        for c in range(self.col, self.cols):
            self.grid[self.row][c] = " "

    def clear_to_eos(self) -> None:
        self.clear_to_eol()
        for r in range(self.row + 1, self.rows):
            self.grid[r] = [" "] * self.cols

    def lines(self) -> list[str]:
        return ["".join(r).rstrip() for r in self.grid]


def replay(data: bytes, rows: int, cols: int) -> Screen:
    screen = Screen(rows, cols)
    text = data.decode("utf-8", "replace")
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\x1b":
            match = CSI.match(text, i)
            if not match:
                i += 1
                continue
            params, final = match.group(1), match.group(2)
            i = match.end()
            if final == "A":
                n = int(params) if params.isdigit() else 1
                screen.row = max(0, screen.row - n)
            elif final == "B":
                n = int(params) if params.isdigit() else 1
                screen.row = min(screen.rows - 1, screen.row + n)
            elif final == "K":
                if params == "2":
                    screen.clear_line()
                else:
                    screen.clear_to_eol()
            elif final == "J":
                screen.clear_to_eos()
            continue
        if ch == "\r":
            screen.col = 0
        elif ch == "\n":
            screen.newline()
        elif ch == "\x07":
            pass
        elif ch >= " ":
            screen.put(ch)
        i += 1
    return screen


def compress(numbers: list[int]) -> str:
    if not numbers:
        return "-"
    parts = []
    start = prev = numbers[0]
    for n in numbers[1:]:
        if n == prev + 1:
            prev = n
            continue
        parts.append(f"{start}" if start == prev else f"{start}-{prev}")
        start = prev = n
    parts.append(f"{start}" if start == prev else f"{start}-{prev}")
    return ",".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description="重播 gwt 的選單輸出")
    parser.add_argument("--rows", type=int, default=24)
    parser.add_argument("--cols", type=int, default=80)
    parser.add_argument("--raw", required=True, help="PTY 原始輸出檔")
    parser.add_argument(
        "--until",
        default="",
        help="遇到這個字串就停止重播。測試在選單之後印出的斷言結果會把畫面"
        "往上推，用這個切點才看得到選單最後的樣子。",
    )
    args = parser.parse_args()

    with open(args.raw, "rb") as handle:
        data = handle.read()
    if args.until:
        marker = args.until.encode()
        cut = data.find(marker)
        if cut >= 0:
            data = data[:cut]
    screen = replay(data, args.rows, args.cols)

    lines = screen.lines()
    item_rows = 0
    indexes = []
    selected = "-"
    for line in lines:
        match = re.search(r"\[(\d+)\]", line)
        if not match:
            continue
        item_rows += 1
        indexes.append(int(match.group(1)))
        if line.lstrip().startswith(">"):
            selected = match.group(1)

    seen = set()
    duplicates = set()
    for n in indexes:
        if n in seen:
            duplicates.add(n)
        seen.add(n)

    print("--- 畫面 ---")
    for line in lines:
        print(line)
    print("--- 結構摘要 ---")
    print(f"ITEM_ROWS={item_rows}")
    print(f"INDEXES={compress(indexes)}")
    print(f"DUPLICATES={'-' if not duplicates else compress(sorted(duplicates))}")
    print(f"SELECTED={selected}")
    print(f"WRAPS={screen.wraps}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
