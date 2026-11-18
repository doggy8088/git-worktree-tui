# -----------------------------------------------------------------------------
# 常用開發指令：make help 看全部
# -----------------------------------------------------------------------------
SHELL := /bin/bash
# 注意：不要用 ZSH 當變數名，oh-my-zsh 會把它設成安裝目錄
ZSHBIN ?= zsh
PYTHON ?= python3

ZSH_FILES := gwt.zsh gwt.plugin.zsh
TEST_FILES := tests/run.sh tests/lib/assert.zsh tests/lib/fixture.zsh \
              tests/cases/*.zsh tests/cases-pty/*.zsh

.DEFAULT_GOAL := help

.PHONY: help test test-pwsh lint install uninstall site demo clean

help:  ## 顯示可用指令
	@echo "可用指令："
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

test:  ## 執行全部測試（單元 + PTY 互動）
	@bash tests/run.sh

test-pwsh:  ## 執行 PowerShell 版測試（需要 pwsh 7；Windows 上含 ConPTY 真主控台測試）
	@pwsh -NoProfile -File tests/pwsh/run.ps1

lint:  ## 語法檢查（zsh -n 與 python 編譯檢查）
	@for f in $(ZSH_FILES) $(TEST_FILES); do $(ZSHBIN) -n "$$f" || exit 1; done
	@$(PYTHON) -m py_compile tests/lib/ptydrive.py
	@rm -rf tests/lib/__pycache__
	@echo "語法檢查通過"

install:  ## 安裝到 ~/.zsh/gwt.zsh 並在 ~/.zshrc 加入 source
	@bash install.sh

uninstall:  ## 移除安裝
	@bash install.sh --uninstall

site:  ## 在本機預覽網站（http://localhost:8765）
	@cd site && python3 -m http.server 8765

demo:  ## 建立一個示範用的多 worktree 儲存庫
	@bash scripts/demo.sh

clean:  ## 清除暫存產物
	@rm -rf tests/lib/__pycache__ .gwt-test-out
	@echo "已清除"
