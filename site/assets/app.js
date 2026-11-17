/* ===========================================================================
   gwt — 頁面行為
   1) 示範選單：真的可以用鍵盤操作（含 / 模糊搜尋），和工具本身的行為一致
   2) 四個階段：滑桿與選單雙向連動
   3) 常見問題：一次只開一張
   4) 複製安裝指令
   5) 進場動態（尊重 prefers-reduced-motion）
   =========================================================================== */

(function () {
  'use strict';

  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* --- 示範選單 ---------------------------------------------------------- */

  var WORKTREES = [
    { path: '…/shop', branch: 'main', sha: '89ae97a', current: true },
    { path: '…/shop-feature-login', branch: 'feature/login', sha: '89ae97a' },
    { path: '…/shop-feature-search-api', branch: 'feature/search-api', sha: '89ae97a' },
    { path: '…/shop-fix-cart-bug', branch: 'fix/cart-bug', sha: '89ae97a' },
    { path: '…/shop-hotfix', branch: 'detached', sha: '89ae97a' }
  ];

  var menu = document.getElementById('live-menu');
  var hint = document.querySelector('[data-hint]');
  var after = document.querySelector('[data-after]');
  var clause = document.querySelector('[data-clause]');
  var say = document.querySelector('[data-say]');
  var slider = document.getElementById('stage');
  var stageButtons = Array.prototype.slice.call(document.querySelectorAll('[data-stage]'));

  var STAGES = [
    {
      clause: '先執行 gwt，看清單',
      say: '在儲存庫或任何一個 worktree 裡執行，它會列出這個儲存庫的所有工作目錄。',
      selected: -1
    },
    {
      clause: '用方向鍵移動光棒',
      say: '↑ ↓ 或 j／k 都能移動，按 / 則直接模糊搜尋分支與目錄名稱；光棒只反白到路徑為止，後面的分支與 commit 保持原色。',
      selected: 0
    },
    {
      clause: '順便讀出分支',
      say: '每一列都寫著分支名稱與 commit 前七碼，目前所在的那一個用黃色標記，不必再回頭查。',
      selected: 2
    },
    {
      clause: '按 Enter 切過去',
      say: '按下 Enter 就直接切換這個終端機的工作目錄，選單擦掉，回到提示字元。',
      selected: 2,
      done: true
    }
  ];

  var stage = 0;
  var selected = -1;
  var view = WORKTREES.slice();
  var searching = false;
  var query = '';

  function basename(path) {
    var parts = path.split('/');
    return parts[parts.length - 1] || path;
  }

  /* 與 gwt.zsh 的 _gwt_fuzzy_term 相同的子序列評分。兩邊要一起改，不然網站
     示範和終端機的排序會不一致。 */
  function fuzzyTerm(haystack, term) {
    haystack = haystack.toLowerCase();
    term = term.toLowerCase();
    if (!term) return 0;

    var hi = 0;
    var score = 0;
    var last = -1;
    var run = 0;

    for (var ti = 0; ti < term.length; ti++) {
      var ch = term.charAt(ti);
      while (hi < haystack.length && haystack.charAt(hi) !== ch) hi++;
      if (hi >= haystack.length) return null;

      score += 10;
      if (last >= 0) {
        if (hi === last + 1) {
          run += 1;
          score += 6 + run * 2;
        } else {
          run = 0;
          score -= Math.min(hi - last - 1, 4);
        }
      }

      if (hi === 0) {
        score += 14;
      } else if ('/-_. '.indexOf(haystack.charAt(hi - 1)) !== -1) {
        score += 10;
      }

      last = hi;
      hi += 1;
    }

    return score - Math.floor(haystack.length / 5);
  }

  /* 查詢以空白切成多個詞，每個詞都要命中分支或目錄名稱（AND）。 */
  function fuzzyMatch(item, text) {
    var terms = text.split(/\s+/).filter(Boolean);
    if (!terms.length) return 0;

    var base = basename(item.path);
    var total = 0;

    for (var i = 0; i < terms.length; i++) {
      var onBranch = fuzzyTerm(item.branch, terms[i]);
      var onBase = fuzzyTerm(base, terms[i]);
      if (onBranch === null && onBase === null) return null;
      if (onBranch === null) total += onBase;
      else if (onBase === null) total += onBranch;
      else total += Math.max(onBranch, onBase);
    }

    return total;
  }

  function refilter() {
    if (!query.trim()) {
      view = WORKTREES.slice();
      return;
    }

    var scored = [];
    WORKTREES.forEach(function (item, index) {
      var score = fuzzyMatch(item, query);
      if (score !== null) scored.push({ item: item, index: index, score: score });
    });
    scored.sort(function (a, b) {
      return b.score - a.score || a.index - b.index;
    });
    view = scored.map(function (entry) { return entry.item; });
  }

  function updateHint() {
    if (!hint) return;
    if (searching) {
      hint.textContent = '搜尋：' + query + '▏  ' + view.length +
        ' 筆符合 (↑/↓ 移動, Enter 確認, Esc 清除搜尋)：';
    } else {
      hint.textContent = '請選擇 Worktree (↑/↓ 移動, Enter 確認, / 搜尋, 按 1-' +
        view.length + ' 直接跳轉, q/Esc 取消)：';
    }
  }

  function renderMenu() {
    if (!menu) return;
    updateHint();

    if (!view.length) {
      menu.innerHTML = '<li class="row row-empty" role="presentation">' +
        '<span class="path">沒有符合搜尋條件的 worktree。</span></li>';
      menu.removeAttribute('aria-activedescendant');
      return;
    }

    menu.innerHTML = view.map(function (item, index) {
      var active = index === selected ? ' is-active' : '';
      return (
        '<li class="row' + active + '" role="option" id="live-row-' + index + '"' +
        ' aria-selected="' + (index === selected) + '">' +
          '<span class="sel"><span class="num">[' + (index + 1) + ']</span> ' +
          '<span class="path">' + item.path + '</span></span>' +
          '<span class="branch">[' + item.branch + ']</span>' +
          '<span class="sha">(' + item.sha + ')</span>' +
          (item.current ? '<span class="mark">(目前位置)</span>' : '') +
        '</li>'
      );
    }).join('');
    menu.setAttribute('aria-activedescendant', selected >= 0 ? 'live-row-' + selected : '');
  }

  function renderStage(next, fromMenu) {
    stage = Math.max(0, Math.min(STAGES.length - 1, next));
    var state = STAGES[stage];

    if (!fromMenu) {
      searching = false;
      query = '';
      view = WORKTREES.slice();
      selected = state.selected;
    }

    renderMenu();

    if (clause) clause.textContent = state.clause;
    if (say) say.textContent = state.say;
    if (hint) hint.hidden = false;

    if (after) {
      if (state.done) {
        var chosen = view[selected] || WORKTREES[2];
        after.hidden = false;
        after.innerHTML = '<span class="prompt">&gt;</span> <span class="dim">cd ~/projects/' +
          chosen.path.split('/').pop() + '</span>' +
          '<span class="caret" aria-hidden="true"></span>';
        if (menu) menu.hidden = true;
        if (hint) hint.hidden = true;
      } else {
        after.hidden = true;
        if (menu) menu.hidden = false;
      }
    }

    if (slider) slider.value = String(stage);
    stageButtons.forEach(function (button) {
      var on = Number(button.getAttribute('data-stage')) === stage;
      if (on) button.setAttribute('aria-current', 'true');
      else button.removeAttribute('aria-current');
    });
  }

  function enterSearch() {
    searching = true;
    query = '';
    view = WORKTREES.slice();
    selected = view.length ? 0 : -1;
    renderStage(1, true);
  }

  function exitSearch() {
    searching = false;
    query = '';
    view = WORKTREES.slice();
    selected = view.length ? 0 : -1;
    renderStage(1, true);
  }

  function applyQuery() {
    refilter();
    selected = view.length ? 0 : -1;
    renderStage(1, true);
  }

  if (menu) {
    renderStage(0);

    menu.addEventListener('keydown', function (event) {
      if (event.isComposing) return;

      var key = event.key;

      if (searching) {
        if (key === 'Escape') {
          exitSearch();
          event.preventDefault();
          return;
        }

        if (key === 'ArrowDown' || key === 'ArrowUp') {
          if (!view.length) {
            event.preventDefault();
            return;
          }
          if (selected < 0) {
            selected = 0;
          } else {
            selected += key === 'ArrowDown' ? 1 : -1;
            if (selected < 0) selected = view.length - 1;
            if (selected >= view.length) selected = 0;
          }
          after && (after.hidden = true);
          renderStage(1, true);
          event.preventDefault();
          return;
        }

        if (key === 'Enter') {
          if (view.length && selected >= 0) renderStage(3, true);
          event.preventDefault();
          return;
        }

        if (key === 'Backspace') {
          if (query) {
            query = query.slice(0, -1);
            applyQuery();
          }
          event.preventDefault();
          return;
        }

        if (event.ctrlKey && (key === 'u' || key === 'U')) {
          if (query) {
            query = '';
            applyQuery();
          }
          event.preventDefault();
          return;
        }

        if (event.ctrlKey && (key === 'w' || key === 'W')) {
          if (query) {
            var trimmed = query.replace(/\s+$/, '');
            var cut = trimmed.lastIndexOf(' ');
            query = cut >= 0 ? trimmed.slice(0, cut) : '';
            applyQuery();
          }
          event.preventDefault();
          return;
        }

        if (key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          query += key;
          applyQuery();
          event.preventDefault();
        }
        return;
      }

      var moved = null;

      if (key === '/') {
        enterSearch();
        event.preventDefault();
        return;
      } else if (key === 'ArrowDown' || key === 'j' || key === 'J') moved = 1;
      else if (key === 'ArrowUp' || key === 'k' || key === 'K') moved = -1;
      else if (/^[1-9]$/.test(key)) {
        var pick = Number(key) - 1;
        if (pick < view.length) {
          selected = pick;
          after && (after.hidden = true);
          renderStage(3, true);
          event.preventDefault();
          return;
        }
      } else if (key === 'Enter') {
        if (selected >= 0) renderStage(3, true);
        event.preventDefault();
        return;
      } else if (key === 'q' || key === 'Q' || key === 'Escape') {
        renderStage(0);
        event.preventDefault();
        return;
      }

      if (moved === null) return;
      event.preventDefault();

      if (selected < 0) selected = 0;
      else {
        selected += moved;
        if (selected < 0) selected = view.length - 1;
        if (selected >= view.length) selected = 0;
      }
      after && (after.hidden = true);
      renderStage(1, true);
    });
  }

  if (slider) {
    slider.addEventListener('input', function () {
      renderStage(Number(slider.value));
    });
  }

  stageButtons.forEach(function (button) {
    button.addEventListener('click', function () {
      renderStage(Number(button.getAttribute('data-stage')));
    });
  });

  /* --- 常見問題 ---------------------------------------------------------- */

  var heads = Array.prototype.slice.call(document.querySelectorAll('.card-head'));

  function openCard(head) {
    heads.forEach(function (other) {
      var body = document.getElementById(other.getAttribute('aria-controls'));
      var isTarget = other === head;
      other.setAttribute('aria-expanded', String(isTarget));
      if (body) body.hidden = !isTarget;
    });
  }

  heads.forEach(function (head) {
    head.addEventListener('click', function () {
      var isOpen = head.getAttribute('aria-expanded') === 'true';
      if (isOpen) return;
      openCard(head);
    });
  });

  /* --- 複製 -------------------------------------------------------------- */

  var states = Array.prototype.slice.call(document.querySelectorAll('[data-copy-state]'));

  document.querySelectorAll('[data-copy]').forEach(function (button, index) {
    button.addEventListener('click', function () {
      var text = button.getAttribute('data-copy').replace(/&amp;/g, '&');
      var status = states[index] || states[0];

      // 沒有剪貼簿權限時（例如 file:// 或使用者拒絕），直接把指令選取起來
      function selectCommand() {
        var scope = button.closest('section') || document;
        var target = scope.querySelector('.install-code code') || scope.querySelector('.install-cmd');
        if (!target) return false;
        var range = document.createRange();
        range.selectNodeContents(target);
        var selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        return true;
      }

      function done(ok) {
        if (!status) return;
        if (ok) {
          status.textContent = '已複製，貼到終端機就好。';
        } else {
          status.textContent = selectCommand()
            ? '已選取指令，按 Command-C 或 Ctrl-C 複製。'
            : '請手動選取上方的指令複製。';
        }
        window.setTimeout(function () { status.textContent = ''; }, 5000);
      }

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
      } else {
        done(false);
      }
    });
  });

  /* --- 進場 -------------------------------------------------------------- */

  if (!reduce && 'IntersectionObserver' in window) {
    var groups = [
      ['.hero h1', '.hero .lead', '.hero .actions', '.hero-stage'],
      ['.statement-text'],
      ['.how-line', '.how-say', '.how-stage', '.how-control'],
      ['.keys-title', '.keys-table'],
      ['.figures-title', '.tile-accent', '.tile-paper', '.tile-ink'],
      ['.faq-title', '.card-faq'],
      ['.tile-main', '.tile-side-a']
    ];

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('in');
        observer.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

    groups.forEach(function (group) {
      group.forEach(function (selector, index) {
        document.querySelectorAll(selector).forEach(function (node) {
          node.classList.add('reveal');
          node.style.transitionDelay = (index * 75) + 'ms';
          observer.observe(node);
        });
      });
    });
  }
})();
