/* ===========================================================================
   gwt — 頁面行為
   1) 示範選單：真的可以用鍵盤操作，和工具本身的行為一致
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
      say: '↑ ↓ 或 j／k 都能移動，到頭尾會循環；光棒只反白到路徑為止，後面的分支與 commit 保持原色。',
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

  function renderMenu() {
    if (!menu) return;
    menu.innerHTML = WORKTREES.map(function (item, index) {
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

    if (!fromMenu) selected = state.selected;

    renderMenu();

    if (clause) clause.textContent = state.clause;
    if (say) say.textContent = state.say;
    if (hint) hint.hidden = false;

    if (after) {
      if (state.done) {
        after.hidden = false;
        after.innerHTML = '<span class="prompt">&gt;</span> <span class="dim">cd ~/projects/' +
          WORKTREES[state.selected].path.split('/').pop() + '</span>' +
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

  if (menu) {
    renderStage(0);

    menu.addEventListener('keydown', function (event) {
      var key = event.key;
      var moved = null;

      if (key === 'ArrowDown' || key === 'j' || key === 'J') moved = 1;
      else if (key === 'ArrowUp' || key === 'k' || key === 'K') moved = -1;
      else if (/^[1-9]$/.test(key)) {
        var pick = Number(key) - 1;
        if (pick < WORKTREES.length) {
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
        if (selected < 0) selected = WORKTREES.length - 1;
        if (selected >= WORKTREES.length) selected = 0;
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

      function done(ok) {
        if (!status) return;
        status.textContent = ok ? '已複製，貼到終端機就好。' : '請手動選取上方的指令複製。';
        window.setTimeout(function () { status.textContent = ''; }, 4000);
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
