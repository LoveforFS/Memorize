/*
 * Memorize 视图层 —— Swift 版 GameView / CardView / Pie / ThemeButton 的等价实现，
 * 外加打磨阶段新增的模式选择、难度选择、暂停层与关卡提示。
 *
 * 分工与原版一致：这里只做「渲染 + 事件转发」，所有规则判定都在
 * model.js、config.js 与 viewmodel.js 中，视图不持有时序逻辑。
 *
 * 界面分两屏：
 *   主界面（#home）—— 标题、模式/难度、玩法说明、开始按钮，屏幕上没有任何计时来源；
 *   游戏界面（#game）—— 只在点「开始游戏」后显示，倒计时从此刻才开始跑。
 * 计时唯一入口是 viewModel.startGame()，离开游戏走 viewModel.leaveGame()。
 */
(function () {
  'use strict';

  var Model = window.MemorizeModel;
  var Config = window.MemorizeConfig;
  var StoreModule = window.MemorizeStore;
  var AudioModule = window.MemorizeAudio;
  var ViewModelModule = window.MemorizeViewModel;
  var Layout = window.MemorizeLayout;

  var Theme = Model.Theme;
  var GameViewModel = ViewModelModule.GameViewModel;

  // ---------------- DOM 引用 ----------------

  var homeEl = document.getElementById('home');
  var gameEl = document.getElementById('game');
  var startButtonEl = document.getElementById('startButton');
  var homeButtonEl = document.getElementById('homeButton');
  var pauseButtonEl = document.getElementById('pauseButton');
  var homeEmojiEl = document.getElementById('homeEmoji');
  var homeTaglineEl = document.getElementById('homeTagline');
  var homeRulesEl = document.getElementById('homeRules');
  var modeSwitchEl = document.getElementById('modeSwitch');
  var difficultyRowEl = document.getElementById('difficultyRow');
  var bestBadgeEl = document.getElementById('bestBadge');
  var soundToggleEl = document.getElementById('soundToggle');
  var hapticToggleEl = document.getElementById('hapticToggle');
  var historyStripEl = document.getElementById('historyStrip');
  var historyClearEl = document.getElementById('historyClear');
  var adaptiveNoteEl = document.getElementById('adaptiveNote');
  var scoreCaptionEl = document.getElementById('scoreCaption');
  var peekHudEl = document.getElementById('peekHud');
  var peekCountEl = document.getElementById('peekCount');
  var boardEl = document.getElementById('board');
  var boardAreaEl = document.getElementById('boardArea');
  var themeBarEl = document.getElementById('themeBar');
  var hintEl = document.getElementById('hint');
  var restartEl = document.getElementById('restart');
  var pieEl = document.getElementById('pie');
  var pieProgressEl = document.getElementById('pieProgress');
  var pieTextEl = document.getElementById('pieText');
  var scoreEl = document.getElementById('scoreValue');
  var scoreDeltaEl = document.getElementById('scoreDelta');
  var themeLabelEl = document.getElementById('themeLabel');
  var progressLabelEl = document.getElementById('progressLabel');
  var levelLabelEl = document.getElementById('levelLabel');
  var levelSepEl = document.querySelector('.sub-sep-level');
  var pauseLayerEl = document.getElementById('pauseLayer');
  var pauseResumeButtonEl = document.getElementById('pauseResume');
  var pauseHomeButtonEl = document.getElementById('pauseHome');
  var toastEl = document.getElementById('toast');
  var modalEl = document.getElementById('modal');
  var modalTitleEl = document.getElementById('modalTitle');
  var modalBodyEl = document.getElementById('modalBody');
  var modalRecordEl = document.getElementById('modalRecord');
  var modalButtonEl = document.getElementById('modalButton');
  var modalHomeEl = document.getElementById('modalHome');

  /** 圆的周长：2πr，r 与 index.html 中的 19.8 保持一致。 */
  var PIE_CIRCUMFERENCE = 2 * Math.PI * 19.8;

  // ---------------- 实例化 ----------------

  var store = new StoreModule.ScoreStore();
  var prefs = store.getPrefs({
    sound: true, haptic: true, adaptive: true, mode: 'classic', difficulty: 'classic'
  });
  var sound = new AudioModule.SoundKit({ enabled: prefs.sound });

  var viewModel = new GameViewModel({
    mode: prefs.mode,
    difficulty: prefs.difficulty
  });

  /** 震动反馈是否可用：接口存在 + 用户开关开着 + 系统没要求「减弱动态」。 */
  var hapticsSupported = typeof navigator !== 'undefined'
    && typeof navigator.vibrate === 'function';
  var hapticsEnabled = prefs.haptic && hapticsSupported;
  /** 助记自适应总开关（可被 ?adaptive=0 临时关闭）。 */
  var adaptiveEnabled = prefs.adaptive;

  /**
   * 手动配色覆盖：URL 带 ?theme=dark / ?theme=light 时给 <html> 打上 data-theme。
   * 用途有两个：
   * 1. 深色模式验收时可以把任意一屏强制成深色截图，不必改系统设置；
   * 2. 系统配色与玩家偏好不一致时，提供一个明确的逃生口。
   * 不带参数时完全不干预，仍按系统 prefers-color-scheme 走。
   */
  function applyThemeOverride() {
    var match = /[?&]theme=(dark|light)/.exec(window.location.search);
    if (match) {
      document.documentElement.setAttribute('data-theme', match[1]);
    }
  }

  applyThemeOverride();

  // ?adaptive=0：临时关闭助记自适应（回退用，不写入偏好）
  if (/[?&]adaptive=0/.test(window.location.search)) {
    adaptiveEnabled = false;
  }

  /** 当前所在界面：home（主界面）| playing（游戏中）。 */
  var screen = 'home';
  var modalOpen = false;
  /** 本轮结算是否已被玩家主动关闭；关闭后不再被后续超时事件重新弹出。 */
  var resultDismissed = false;
  /** 结算被关闭后，提示行变成可点击的重开入口。 */
  var replayPromptActive = false;
  /** 本局成绩是否已经写入存档，避免重复提交把「新纪录」刷出来。 */
  var resultRecorded = false;
  var scorePopTimer = null;
  var scoreDeltaTimer = null;
  var toastTimer = null;
  var rejectTimers = new WeakMap();
  /** 已配对卡片 id，用于识别「刚刚配对成功」并播放一次弹跳。 */
  var matchedIds = {};

  // ---- 长按偷看 ----
  /** 长按判定阈值（毫秒）。低于它的按压仍是普通点击。 */
  var PEEK_HOLD_MS = 320;
  /** 偷看保持时长（毫秒），需求固定为 0.4 秒。 */
  var PEEK_SHOW_MS = 400;
  var peekHoldTimer = null;
  var peekHideTimer = null;
  var peekHoldCardId = null;
  var peekHoldOrigin = null;
  /** 刚刚偷看过的卡片：紧随其后的 click 要被吞掉，否则偷看会顺手把牌翻开。 */
  var peekCardId = null;
  var peekSwallowUntil = 0;

  /** 待落盘的反应时间样本（结算时一次写入）。 */
  var pendingLatencySamples = [];

  // ---------------- 工具 ----------------

  function hexToRgba(hex, alpha) {
    var value = String(hex).replace('#', '');
    if (value.length === 3) {
      value = value[0] + value[0] + value[1] + value[1] + value[2] + value[2];
    }
    var num = parseInt(value, 16);
    var r = (num >> 16) & 255;
    var g = (num >> 8) & 255;
    var b = num & 255;
    return 'rgba(' + r + ', ' + g + ', ' + b + ', ' + alpha + ')';
  }

  function totalPairs() {
    return Math.floor(viewModel.cards.length / 2);
  }

  function isCampaign() {
    return viewModel.mode === 'campaign';
  }

  function currentDifficulty() {
    return Config.findDifficulty(viewModel.difficulty);
  }

  /** 最高分按「模式 + 难度」分桶；闯关模式没有难度概念，固定用 campaign 桶。 */
  function scoreBucket() {
    return {
      mode: viewModel.mode,
      difficulty: isCampaign() ? 'campaign' : viewModel.difficulty
    };
  }

  function cardAriaText(card) {
    if (card.isMatched) {
      return '已配对的卡片 ' + card.content;
    }
    if (card.isFaceUp) {
      return '已翻开的卡片 ' + card.content;
    }
    return '未翻开的卡片';
  }

  /**
   * 轻震反馈。
   * 只在「接口存在 + 用户开启」时调用；桌面浏览器多数没有振动马达，
   * navigator.vibrate 会静默返回 false，因此这里不把它当作可感知的反馈，
   * 只是「有就震一下」的增强项。
   */
  function vibrate(pattern) {
    if (!hapticsEnabled || !hapticsSupported) {
      return false;
    }
    try {
      return navigator.vibrate(pattern) === true;
    } catch (error) {
      return false;
    }
  }

  // ---------------- 助记自适应 ----------------

  /** 依据已存样本算出「当前配置下应有的翻回时长偏移量」。 */
  function computeAdaptiveAdjust() {
    if (!adaptiveEnabled) {
      return 0;
    }
    if (!Config.isAdaptiveMode(viewModel.mode, viewModel.difficulty)) {
      return 0;
    }
    var samples = store.getTimings().slice(-Config.ADAPTIVE.windowSize);
    if (samples.length === 0) {
      return 0;
    }
    var sum = 0;
    for (var i = 0; i < samples.length; i += 1) {
      sum += samples[i];
    }
    return Config.adaptiveAdjust(Math.round(sum / samples.length), samples.length);
  }

  /**
   * 把算好的偏移量交给 ViewModel，并让「当前这张占位牌组」同步刷新。
   * 注意：refreshDelay 内部只在未开局时改写 mismatchFlipDelay，
   * 因此绝不会在牌局进行到一半时改变判定节奏。
   */
  function syncAdaptiveDelay() {
    var adjust = computeAdaptiveAdjust();
    viewModel.setDelayAdjust(adjust);
    viewModel.refreshDelay();
    return adjust;
  }

  /**
   * 把本局累积的反应时间样本落盘。
   * 一局里每配上一对就会产生两条样本，若每次都写 localStorage，
   * 一局要写十几次；因此攒到「结算 / 离开牌局」时一次写入。
   */
  function flushLatency() {
    if (pendingLatencySamples.length === 0) {
      return 0;
    }
    var count = pendingLatencySamples.length;
    store.addTimings(pendingLatencySamples);
    pendingLatencySamples = [];
    return count;
  }

  function renderAdaptiveNote() {
    if (!adaptiveNoteEl) {
      return;
    }
    var samples = store.getTimings();
    var active = adaptiveEnabled
      && Config.isAdaptiveMode(viewModel.mode, viewModel.difficulty)
      && samples.length >= Config.ADAPTIVE.minSamples;

    adaptiveNoteEl.hidden = !active;
    if (!active) {
      return;
    }

    var delay = viewModel.mismatchFlipDelay.toFixed(2);
    adaptiveNoteEl.textContent = '助记自适应：错配翻回 ' + delay + ' 秒 · 样本 '
      + samples.length + ' 条 ';

    var reset = document.createElement('button');
    reset.type = 'button';
    reset.className = 'adaptive-reset';
    reset.id = 'adaptiveReset';
    reset.textContent = '重置';
    reset.title = '清空反应时间样本，回到原始翻回时长';
    adaptiveNoteEl.appendChild(reset);
  }

  // ---------------- 主界面：模式 / 难度 / 说明 ----------------

  function modeTabs() {
    return Array.prototype.slice.call(modeSwitchEl.querySelectorAll('.mode-tab'));
  }

  function difficultyChips() {
    return Array.prototype.slice.call(difficultyRowEl.querySelectorAll('.chip'));
  }

  function buildModeSwitch() {
    modeSwitchEl.innerHTML = '';
    Config.MODES.forEach(function (mode) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'mode-tab';
      button.dataset.mode = mode.id;
      button.setAttribute('role', 'tab');
      button.setAttribute('aria-label', '模式：' + mode.name);
      button.textContent = mode.name;
      modeSwitchEl.appendChild(button);
    });
  }

  function buildDifficultyChips() {
    difficultyRowEl.innerHTML = '';
    Config.DIFFICULTIES.forEach(function (difficulty) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'chip';
      button.dataset.difficulty = difficulty.id;
      button.setAttribute('aria-label', '难度：' + difficulty.name);
      button.textContent = difficulty.name;
      difficultyRowEl.appendChild(button);
    });
  }

  /** 写入一条规则文案：支持「普通文字 + 加粗强调」交替，避免拼 innerHTML。 */
  function writeRule(element, parts) {
    element.textContent = '';
    parts.forEach(function (part) {
      if (typeof part === 'string') {
        element.appendChild(document.createTextNode(part));
        return;
      }
      var strong = document.createElement('b');
      strong.textContent = String(part.bold);
      element.appendChild(strong);
    });
  }

  function renderHomeRules() {
    var rules = homeRulesEl.querySelectorAll('.rule-text');
    if (rules.length < 3) {
      return;
    }

    if (isCampaign()) {
      var campaign = Config.CAMPAIGN;
      writeRule(rules[0], [
        '连续挑战 ', { bold: campaign.stageCount }, ' 关，三关依次是 ',
        { bold: campaign.stages.map(function (s) { return s.pairs + ' 对'; }).join(' / ') },
        '。'
      ]);
      writeRule(rules[1], [
        '三关共用一条 ', { bold: campaign.timeBudget + ' 秒' }, ' 倒计时，每过一关补 ',
        { bold: campaign.clearBonus + ' 秒' }, '，时间归零即失败。'
      ]);
      writeRule(rules[2], [
        '配对得 ', { bold: '+2' }, ' 分，重复出错扣 ', { bold: '1' }, ' 分，三关得分累加；',
        '长按卡片可偷看（每关有限次）。'
      ]);
      return;
    }

    var difficulty = currentDifficulty();
    var pairs = difficulty.pairs;
    writeRule(rules[0], [
      '每次翻开两张卡片，图案相同即配对成功，得 ', { bold: '+2' }, ' 分。'
    ]);
    writeRule(rules[1], [
      '图案不同会锁定 ', { bold: difficulty.mismatchFlipDelay.toFixed(1) + ' 秒' },
      '后自动翻回，重复出错扣 ', { bold: '1' }, ' 分。'
    ]);

    var rule3 = [
      { bold: difficulty.duration + ' 秒' }, '内配完全部 ', { bold: pairs },
      ' 对即通关，倒计时归零则本局结束。'
    ];
    if (viewModel.comboEnabled) {
      rule3.push('连续配对最高可叠到 ', { bold: '×' + Config.COMBO.maxMultiplier }, ' 倍分。');
    }
    rule3.push('长按卡片可偷看（共 ', { bold: difficulty.peek }, ' 次）。');
    writeRule(rules[2], rule3);
  }

  function renderHomeTagline() {
    if (isCampaign()) {
      var campaign = Config.CAMPAIGN;
      homeTaglineEl.textContent = '连续三关 · 共享 ' + campaign.timeBudget
        + ' 秒 · 每过一关补 ' + campaign.clearBonus + ' 秒';
      return;
    }
    homeTaglineEl.textContent = currentDifficulty().tagline;
  }

  function renderHomeSelection() {
    modeTabs().forEach(function (tab) {
      var selected = tab.dataset.mode === viewModel.mode;
      tab.classList.toggle('is-selected', selected);
      tab.setAttribute('aria-selected', selected ? 'true' : 'false');
    });

    // 闯关的关卡是固定的，难度档位对它不生效，直接隐藏避免误解
    difficultyRowEl.hidden = isCampaign();

    difficultyChips().forEach(function (chip) {
      var selected = chip.dataset.difficulty === viewModel.difficulty;
      chip.classList.toggle('is-selected', selected);
      chip.setAttribute('aria-selected', selected ? 'true' : 'false');
    });
  }

  function renderBestBadge() {
    var bucket = scoreBucket();
    var best = store.getBest(bucket.mode, bucket.difficulty);
    var prefix = isCampaign() ? '闯关最高分 ' : currentDifficulty().name + '最高分 ';
    bestBadgeEl.textContent = best === null ? prefix + '暂无记录' : prefix + best;
    bestBadgeEl.classList.toggle('is-empty', best === null);
  }

  function renderSoundToggle() {
    var on = sound.enabled;
    soundToggleEl.classList.toggle('is-off', !on);
    soundToggleEl.setAttribute('aria-pressed', on ? 'true' : 'false');
    soundToggleEl.setAttribute('aria-label', on ? '关闭音效' : '开启音效');
    soundToggleEl.title = on ? '音效：开（点击关闭）' : '音效：关（点击开启）';
  }

  function renderHapticToggle() {
    if (!hapticToggleEl) {
      return;
    }
    // 设备不支持振动时按钮照常显示但置为禁用态，避免「点了没反应」的疑惑
    var on = hapticsEnabled;
    hapticToggleEl.classList.toggle('is-off', !on);
    hapticToggleEl.classList.toggle('is-unsupported', !hapticsSupported);
    hapticToggleEl.setAttribute('aria-pressed', on ? 'true' : 'false');
    hapticToggleEl.setAttribute('aria-disabled', hapticsSupported ? 'false' : 'true');
    hapticToggleEl.setAttribute('aria-label', on ? '关闭震动反馈' : '开启震动反馈');
    hapticToggleEl.title = !hapticsSupported
      ? '当前设备不支持震动'
      : (on ? '震动：开（点击关闭）' : '震动：关（点击开启）');
  }

  /**
   * 连击指示：直接改写得分区的「得分」小标题。
   * 这样不新增布局位、窄屏也不会多挤一行，同时把「当前倍率」放在
   * 玩家本来就会盯着看的位置。
   */
  function renderCombo() {
    if (!scoreCaptionEl) {
      return;
    }
    var active = viewModel.comboEnabled
      && viewModel.comboStreak >= Config.COMBO.visibleFrom;
    var text = active ? '连击 ×' + String(viewModel.comboMultiplier) : '得分';
    if (scoreCaptionEl.textContent !== text) {
      scoreCaptionEl.textContent = text;
      if (active) {
        scoreCaptionEl.classList.remove('is-popping');
        void scoreCaptionEl.offsetWidth;
        scoreCaptionEl.classList.add('is-popping');
      }
    }
    scoreCaptionEl.classList.toggle('is-combo', active);
  }

  /** 偷看剩余次数：0 时压暗并标出「已用完」，长按时给一次轻震提示。 */
  function renderPeekHud() {
    if (!peekCountEl || !peekHudEl) {
      return;
    }
    var left = viewModel.peekRemaining;
    peekCountEl.textContent = String(left);
    peekHudEl.classList.toggle('is-empty', left <= 0);
    peekHudEl.title = left > 0
      ? '长按一张未翻开的卡片可偷看 0.4 秒，剩余 ' + left + ' 次'
      : '偷看次数已用完';
  }

  /** 最近 5 局：紧凑横排，每格一局的分数与结局。 */
  function renderHistory() {
    if (!historyStripEl) {
      return;
    }
    var list = store.getHistory(5);
    historyStripEl.innerHTML = '';

    if (historyClearEl) {
      historyClearEl.hidden = list.length === 0;
    }

    if (list.length === 0) {
      var empty = document.createElement('li');
      empty.className = 'history-empty';
      empty.textContent = '还没有对局记录，先开一局试试';
      historyStripEl.appendChild(empty);
      return;
    }

    list.forEach(function (record) {
      var chip = document.createElement('li');
      chip.className = 'history-chip';
      if (record.reason === 'win') {
        chip.classList.add('is-win');
      }

      var score = document.createElement('span');
      score.className = 'history-score';
      score.textContent = String(record.score);

      var meta = document.createElement('span');
      meta.className = 'history-meta';
      var label = record.mode === 'campaign'
        ? '闯关'
        : Config.findDifficulty(record.difficulty).name;
      var result = record.reason === 'win'
        ? '通关'
        : (record.mode === 'campaign' ? '止步' + record.stage + '关' : '超时');
      meta.textContent = label + '·' + result;

      chip.appendChild(score);
      chip.appendChild(meta);
      chip.title = record.mode === 'campaign'
        ? '闯关 · 第 ' + record.stage + '/' + record.stageCount + ' 关 · '
          + record.score + ' 分 · ' + (record.reason === 'win' ? '通关' : '超时失败')
        : Config.findDifficulty(record.difficulty).name + ' · ' + record.score + ' 分 · '
          + record.matched + '/' + record.pairs + ' 对 · '
          + (record.reason === 'win' ? '通关' : '超时');
      historyStripEl.appendChild(chip);
    });
  }

  /** 主界面的装饰牌面取当前主题的第一个图案，与游戏内保持一致。 */
  function renderHome() {
    var emojis = viewModel.theme.emojis;
    homeEmojiEl.textContent = emojis.length > 0 ? emojis[0] : '?';
    renderHomeTagline();
    renderHomeRules();
    renderHomeSelection();
    renderBestBadge();
    renderSoundToggle();
    renderHapticToggle();
    renderHistory();
    renderAdaptiveNote();
  }

  // ---------------- 界面切换 ----------------

  /**
   * 开始游戏：切到游戏界面，按当前模式/难度重洗牌组并启动倒计时。
   * 这是整个页面唯一启动计时的地方。
   */
  function enterGame() {
    if (screen === 'playing') {
      return;
    }
    screen = 'playing';

    hideResult();
    resultDismissed = false;
    replayPromptActive = false;
    resultRecorded = false;
    pendingLatencySamples = [];
    stopPeek();

    sound.unlock();
    sound.play('click');
    vibrate(6);

    homeEl.hidden = true;
    gameEl.hidden = false;

    // 开局前最后一次校准自适应时长：主界面阶段才允许改写，牌局内不会变
    syncAdaptiveDelay();

    // startGame 内部会重洗牌组并 startCountdown，主界面期间没有任何计时任务
    viewModel.startGame();

    layoutBoard();
    requestAnimationFrame(layoutBoard);
    updateLevelBadge();
    renderPeekHud();
    renderCombo();

    var firstCard = boardEl.querySelector('.card');
    if (firstCard) {
      firstCard.focus({ preventScroll: true });
    }
  }

  /** 返回主界面：停表、清空本局进度，游戏界面隐藏。 */
  function goHome() {
    if (screen === 'home') {
      return;
    }
    screen = 'home';

    stopPeek();
    flushLatency();

    hideResult();
    hideToast();
    resultDismissed = false;
    replayPromptActive = false;
    resultRecorded = false;

    // leaveGame 会停掉时钟并复位为 idle，主界面上不会继续走秒
    viewModel.leaveGame();
    updatePauseUI();
    syncAdaptiveDelay();

    gameEl.hidden = true;
    homeEl.hidden = false;
    renderHome();

    startButtonEl.focus({ preventScroll: true });
  }

  // ---------------- 主题栏 ----------------

  function renderThemeBar() {
    themeBarEl.innerHTML = '';

    Theme.builtIn.forEach(function (theme) {
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'theme-button';
      button.dataset.themeId = theme.id;
      button.setAttribute('role', 'tab');
      button.setAttribute('aria-label', '主题：' + theme.name);

      var emoji = document.createElement('span');
      emoji.className = 'theme-emoji';
      // 原版取 theme.emojis.prefix(2).joined()，即前两个 emoji 连写。
      emoji.textContent = theme.emojis.slice(0, 2).join('');

      var name = document.createElement('span');
      name.className = 'theme-name';
      name.textContent = theme.name;

      button.appendChild(emoji);
      button.appendChild(name);
      themeBarEl.appendChild(button);
    });

    updateThemeSelection();
  }

  function updateThemeSelection() {
    var buttons = themeBarEl.querySelectorAll('.theme-button');

    Array.prototype.forEach.call(buttons, function (button) {
      var theme = null;
      for (var i = 0; i < Theme.builtIn.length; i += 1) {
        if (Theme.builtIn[i].id === button.dataset.themeId) {
          theme = Theme.builtIn[i];
          break;
        }
      }
      if (!theme) {
        return;
      }

      var selected = theme.id === viewModel.theme.id;
      button.classList.toggle('is-selected', selected);
      button.setAttribute('aria-selected', selected ? 'true' : 'false');

      if (selected) {
        button.style.borderColor = theme.color;
        button.style.background = hexToRgba(theme.color, 0.25);
      } else {
        button.style.borderColor = '';
        button.style.background = '';
      }
    });
  }

  /*
   * 副信息行：主题名、关卡与配对进度分开渲染。
   * 关卡只在闯关模式出现，经典模式下这个位置留给主题名。
   */
  function updateThemeLabel() {
    themeLabelEl.textContent = viewModel.theme.name;
  }

  function updateProgress() {
    progressLabelEl.textContent =
      '已配对 ' + viewModel.matchedPairsCount + '/' + totalPairs();
  }

  function updateLevelBadge() {
    if (!isCampaign()) {
      levelLabelEl.hidden = true;
      levelLabelEl.textContent = '';
      if (levelSepEl) {
        levelSepEl.hidden = true;
      }
      return;
    }
    levelLabelEl.hidden = false;
    levelLabelEl.textContent = '第 ' + viewModel.levelNumber + '/' + viewModel.levelCount + ' 关';
    if (levelSepEl) {
      levelSepEl.hidden = false;
    }
  }

  // ---------------- 卡片区 ----------------

  function buildCardElement(card, index) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'card';
    button.dataset.id = card.id;
    // 发牌错峰：第 index 张延迟 index × 0.06s，封顶 0.6s（对应 AnimationTiming.dealDelay）
    button.style.animationDelay = Layout.dealDelay(index) + 's';

    var inner = document.createElement('div');
    inner.className = 'card-inner';

    var front = document.createElement('div');
    front.className = 'card-face card-front';
    var emoji = document.createElement('span');
    emoji.className = 'card-emoji';
    emoji.textContent = card.content;
    front.appendChild(emoji);

    var back = document.createElement('div');
    back.className = 'card-face card-back';
    back.textContent = '?';

    inner.appendChild(front);
    inner.appendChild(back);
    button.appendChild(inner);

    return button;
  }

  function rebuildBoard() {
    boardEl.innerHTML = '';
    matchedIds = {};

    var fragment = document.createDocumentFragment();
    viewModel.cards.forEach(function (card, index) {
      fragment.appendChild(buildCardElement(card, index));
    });
    boardEl.appendChild(fragment);

    layoutBoard();
    updateCardStates();
  }

  function updateCardStates() {
    var byId = {};
    viewModel.cards.forEach(function (card) {
      byId[card.id] = card;
    });

    var elements = boardEl.querySelectorAll('.card');
    Array.prototype.forEach.call(elements, function (element) {
      var card = byId[element.dataset.id];
      if (!card) {
        return;
      }

      // 原版 CardView.isFaceUp = card.isFaceUp || card.isMatched，已配对卡片始终正面。
      var faceUp = card.isFaceUp || card.isMatched;
      element.classList.toggle('is-face-up', faceUp);
      element.classList.toggle('is-matched', card.isMatched);
      element.setAttribute('aria-label', cardAriaText(card));

      // 刚刚配对成功的卡片弹一下，给「配上了」一个即时的手感反馈
      if (card.isMatched && !matchedIds[card.id]) {
        element.classList.remove('is-just-matched');
        // 清掉发牌时写入的 animation-delay，否则弹跳要等到第 index×0.06 秒才播
        element.style.animationDelay = '0s';
        void element.offsetWidth;
        element.classList.add('is-just-matched');
      }

      matchedIds[card.id] = card.isMatched;
    });
  }

  /**
   * 给卡片加/去「偷看中」样式。
   * 只动 DOM 类，不碰 isFaceUp / isMatched —— 偷看在模型层面完全不存在，
   * 因此不会触发配对判定、不会计分、也不会进入 seenCardIDs。
   */
  function markPeekCard(cardId, on) {
    var element = boardEl.querySelector('.card[data-id="' + cardId + '"]');
    if (!element) {
      return;
    }
    element.classList.toggle('is-peeking', on === true);
  }

  /** 取消「还没到阈值」的长按（松手、移动、切页、重开都会走这里）。 */
  function cancelPeekHold() {
    if (peekHoldTimer !== null) {
      window.clearTimeout(peekHoldTimer);
      peekHoldTimer = null;
    }
    peekHoldCardId = null;
    peekHoldOrigin = null;
  }

  /** 结束偷看：收回样式、清掉计时器，并让 ViewModel 同步清空 peekingCardId。 */
  function stopPeek() {
    cancelPeekHold();
    if (peekHideTimer !== null) {
      window.clearTimeout(peekHideTimer);
      peekHideTimer = null;
    }
    viewModel.endPeek();
  }

  /** 长按开始：到阈值才真正「偷看」，松手早于阈值则视为普通点击。 */
  function startPeekHold(cardElement, card, point) {
    cancelPeekHold();
    peekHoldCardId = card.id;
    peekHoldOrigin = point;
    peekHoldTimer = window.setTimeout(function () {
      peekHoldTimer = null;
      if (peekHoldCardId !== card.id) {
        return;
      }
      peekHoldCardId = null;
      // 次数用完 / 暂停 / 锁定 / 已翻开：静默不响应，只用 HUD 与轻震提示
      if (!viewModel.peek(card)) {
        var left = viewModel.peekRemaining;
        var eligible = !card.isMatched && !card.isFaceUp
          && !viewModel.isPaused && !viewModel.isInteractionLocked;
        if (eligible && left <= 0) {
          renderPeekHud();
          peekHudEl.classList.remove('is-denied');
          void peekHudEl.offsetWidth;
          peekHudEl.classList.add('is-denied');
          vibrate(24);
        }
      }
    }, PEEK_HOLD_MS);
  }

  /**
   * 按可用空间计算卡片尺寸、列数与缝隙，对应 AspectVGrid 的排布逻辑。
   * 卡片保持 2:3 宽高比，圆角/描边/内边距/阴影按短边比例推导。
   *
   * 缝隙是两段式计算的：先用「无缝」结果估算卡片大小，据此得到缝隙，
   * 再带着缝隙重算一次宽度。这样缝隙始终与卡片尺寸成比例，
   * 不会在小屏上吃掉过多宽度，也不会在大屏上细到看不见。
   */
  function layoutBoard() {
    var count = viewModel.cards.length;
    if (count === 0) {
      return;
    }

    var width = boardEl.clientWidth;
    var height = boardEl.clientHeight;
    if (!(width > 0) || !(height > 0)) {
      return;
    }

    var baseWidth = Layout.itemWidthThatFits(count, width, height, Layout.CARD_ASPECT_RATIO);
    if (!(baseWidth > 0)) {
      return;
    }

    var gap = Layout.cardGap(baseWidth);
    var itemWidth = Layout.itemWidthThatFits(
      count, width, height, Layout.CARD_ASPECT_RATIO, gap
    );
    if (!(itemWidth > 0)) {
      itemWidth = baseWidth;
      gap = 0;
    }

    var columns = Layout.columnCountFor(width, itemWidth, gap);
    var metrics = Layout.cardMetrics(itemWidth, itemWidth * 1.5);

    boardEl.style.gridTemplateColumns = 'repeat(' + columns + ', ' + itemWidth + 'px)';
    boardEl.style.setProperty('--card-gap', gap + 'px');
    boardEl.style.setProperty('--card-w', itemWidth + 'px');
    boardEl.style.setProperty('--card-radius', metrics.cornerRadius + 'px');
    boardEl.style.setProperty('--card-border', metrics.borderWidth + 'px');
    boardEl.style.setProperty('--card-pad', metrics.contentPadding + 'px');
    boardEl.style.setProperty('--card-shadow', metrics.shadowRadius + 'px');
  }

  // ---------------- 顶部信息 ----------------

  function updateScore() {
    scoreEl.textContent = String(viewModel.score);
    scoreEl.classList.toggle('is-negative', viewModel.score < 0);
  }

  function playScoreFeedback(delta) {
    if (delta === 0) {
      return;
    }

    // 重启动画：先移除类并强制回流，否则连续加分时动画不会重播。
    scoreEl.classList.remove('is-popping');
    void scoreEl.offsetWidth;
    scoreEl.classList.add('is-popping');

    clearTimeout(scorePopTimer);
    scorePopTimer = setTimeout(function () {
      scoreEl.classList.remove('is-popping');
    }, 320);

    scoreDeltaEl.textContent = delta > 0 ? '+' + delta : String(delta);
    scoreDeltaEl.classList.toggle('is-positive', delta > 0);
    scoreDeltaEl.classList.toggle('is-negative', delta < 0);
    scoreDeltaEl.classList.add('is-visible');

    clearTimeout(scoreDeltaTimer);
    scoreDeltaTimer = setTimeout(function () {
      scoreDeltaEl.classList.remove('is-visible');
    }, 700);
  }

  function updatePie() {
    var progress = viewModel.countdownProgress();

    pieProgressEl.style.strokeDashoffset = String(PIE_CIRCUMFERENCE * (1 - progress));
    pieTextEl.textContent = String(viewModel.countdownRemaining);

    var isWarning = viewModel.countdownTotal > 0 && viewModel.countdownRemaining <= 5
      && viewModel.countdownState === 'running';
    pieEl.classList.toggle('is-warning', isWarning);
    pieEl.classList.toggle('is-idle', viewModel.countdownState === 'idle');
    pieEl.classList.toggle('is-paused', viewModel.countdownState === 'paused');
    pieEl.setAttribute('aria-label', '倒计时 ' + viewModel.countdownRemaining + ' 秒');

    // 悬停气泡随状态换文案：环形现在等同于「暂停 / 继续整局」
    var state = viewModel.countdownState;
    var tip = state === 'paused' ? '继续游戏（P）'
      : state === 'finished' ? '本局已结束'
        : state === 'stopped' ? '本局已完成'
          : '暂停游戏（P）';
    if (pieEl.dataset.tip !== tip) {
      pieEl.dataset.tip = tip;
    }
  }

  function updateHint() {
    var finished = viewModel.countdownState === 'finished';
    var stopped = viewModel.countdownState === 'stopped';
    var paused = viewModel.isPaused;
    var isWin = viewModel.resultReason === 'win';
    var showReplay = replayPromptActive && (finished || stopped || isWin);

    if (showReplay) {
      hintEl.textContent = isWin ? '已通关 · 点击此处再来一局' : '时间到 · 点击此处再来一局';
    } else if (paused) {
      hintEl.textContent = viewModel.hintText;
    } else if (viewModel.peekingCardId !== null) {
      // 偷看是唯一「牌面亮着但不能点」的状态，必须说明它只亮 0.4 秒
      hintEl.textContent = '偷看中 · 仅显示 0.4 秒（剩 ' + viewModel.peekRemaining + ' 次）';
    } else if (isWin) {
      // 通关后计时已停止，不再误导玩家去翻牌
      hintEl.textContent = '全部配对成功！';
    } else {
      hintEl.textContent = viewModel.hintText;
    }

    hintEl.classList.toggle('is-actionable', showReplay);
    hintEl.classList.toggle('is-finished', finished && !showReplay);
    hintEl.classList.toggle('is-paused', !finished && paused && !showReplay);
    hintEl.classList.toggle('is-locked',
      !finished && !paused && !showReplay && viewModel.isInteractionLocked);

    if (showReplay) {
      hintEl.setAttribute('role', 'button');
      hintEl.setAttribute('tabindex', '0');
    } else {
      hintEl.removeAttribute('role');
      hintEl.removeAttribute('tabindex');
    }
  }

  function updateThemeBarLock() {
    themeBarEl.classList.toggle('is-locked',
      viewModel.isInteractionLocked || viewModel.isPaused);
  }

  /**
   * 锁定 / 超时状态下的点击反馈。
   * 模型层会直接忽略这类点击，若界面也毫无反应，玩家会误判为卡死。
   */
  function playRejectFeedback(element) {
    var pending = rejectTimers.get(element);
    if (pending) {
      window.clearTimeout(pending);
    }
    element.classList.remove('is-rejected');
    // 强制回流，保证连续点击时抖动动画可以重播
    void element.offsetWidth;
    element.classList.add('is-rejected');
    rejectTimers.set(element, window.setTimeout(function () {
      element.classList.remove('is-rejected');
      rejectTimers.delete(element);
    }, 320));
  }

  // ---------------- 暂停 ----------------

  /**
   * 暂停层的显隐与按钮状态。
   * 只在「游戏界面 + 已暂停」时出现，主界面与结算状态一律收起，
   * 避免出现「回主界面还盖着一层暂停」这类状态残留。
   */
  function updatePauseUI() {
    var paused = screen === 'playing' && viewModel.isPaused && !modalOpen;

    pauseLayerEl.hidden = !paused;
    gameEl.classList.toggle('is-paused', paused);

    // 暂停时把棋盘与主题栏移出焦点序列：Tab 不会跑到遮罩底下，
    // 屏幕阅读器也不会念到被冻结的牌面（不支持 inert 的浏览器会静默跳过）。
    if ('inert' in boardEl) {
      boardEl.inert = paused;
      themeBarEl.inert = paused;
    }

    pauseButtonEl.classList.toggle('is-paused', paused);
    pauseButtonEl.setAttribute('aria-pressed', paused ? 'true' : 'false');
    pauseButtonEl.setAttribute('aria-label', paused ? '继续游戏（P）' : '暂停游戏（P）');
    pauseButtonEl.title = paused ? '继续游戏（P）' : '暂停游戏（P）';

    if (paused) {
      pauseResumeButtonEl.focus();
    } else if (document.activeElement === pauseResumeButtonEl) {
      pauseButtonEl.focus();
    }
  }

  function togglePause() {
    if (screen !== 'playing' || modalOpen) {
      return;
    }
    viewModel.togglePause();
  }

  // ---------------- 关卡提示 ----------------

  function showToast(text) {
    clearTimeout(toastTimer);
    toastEl.textContent = text;
    toastEl.hidden = false;
    // 强制回流后再加类，连续过关时动画才会重播
    void toastEl.offsetWidth;
    toastEl.classList.add('is-visible');
    toastTimer = setTimeout(function () {
      toastEl.classList.remove('is-visible');
      toastTimer = setTimeout(function () { toastEl.hidden = true; }, 240);
    }, 1500);
  }

  function hideToast() {
    clearTimeout(toastTimer);
    toastEl.classList.remove('is-visible');
    toastEl.hidden = true;
  }

  // ---------------- 结算弹窗 ----------------

  /** 把本局成绩写入存档；同一局只写一次（最高分与「最近 5 局」共用一个入口）。 */
  function recordScore() {
    if (resultRecorded) {
      return null;
    }
    resultRecorded = true;
    var bucket = scoreBucket();

    // 历史明细：结算时一次性落盘，保证「最高分」与「最近 5 局」不会出现两份不一致的记录
    store.addRecord({
      mode: viewModel.mode,
      difficulty: bucket.difficulty,
      score: viewModel.score,
      reason: viewModel.resultReason === 'timeout' ? 'timeout' : 'win',
      stage: viewModel.levelNumber,
      stageCount: viewModel.levelCount,
      pairs: totalPairs(),
      matched: viewModel.matchedPairsCount,
      combo: viewModel.bestCombo,
      at: Date.now()
    });

    return store.submit(bucket.mode, bucket.difficulty, viewModel.score);
  }

  function showResult() {
    if (screen !== 'playing') {
      return;
    }
    // resultDismissed 为真表示玩家已经用 Esc 关掉过本次结算，
    // 不再被后续的超时事件重新弹出，避免反复打断。
    if (modalOpen || resultDismissed) {
      return;
    }
    modalOpen = true;

    var isWin = viewModel.resultReason === 'win';
    var record = recordScore();

    modalTitleEl.textContent = viewModel.resultTitle;

    if (isCampaign()) {
      modalBodyEl.textContent = isWin
        ? '三关全部完成 · 总分 ' + viewModel.score
        : '止步第 ' + viewModel.levelNumber + ' 关 · 本局得分 ' + viewModel.score;
    } else {
      var body = '本局得分：' + viewModel.score
        + ' · 配对 ' + viewModel.matchedPairsCount + '/' + totalPairs();
      if (viewModel.comboEnabled && viewModel.bestCombo >= Config.COMBO.visibleFrom) {
        body += ' · 最高 ' + viewModel.bestCombo + ' 连击';
      }
      modalBodyEl.textContent = body;
    }

    if (record && record.isNewRecord) {
      modalRecordEl.hidden = false;
      modalRecordEl.textContent = record.previous === null
        ? '新纪录 · ' + record.best + ' 分'
        : '新纪录 · 比原纪录高 ' + (record.best - record.previous) + ' 分';
    } else if (record && record.best !== null) {
      modalRecordEl.hidden = false;
      modalRecordEl.textContent = '最高分 ' + record.best;
    } else {
      modalRecordEl.hidden = true;
    }

    modalButtonEl.textContent = isCampaign() ? '重新挑战' : '再来一局';

    modalEl.hidden = false;
    updatePauseUI();
    modalButtonEl.focus();
  }

  function hideResult() {
    modalOpen = false;
    modalEl.hidden = true;
  }

  /** Esc 关闭结算：把提示行变成重开入口，避免关掉后无路可走。 */
  function dismissResult() {
    if (!modalOpen) {
      return;
    }
    hideResult();
    resultDismissed = true;
    replayPromptActive = true;
    updateHint();
  }

  /** 重开一局：弹窗、提示行、结算标记一并复位。 */
  function restartGame() {
    if (screen !== 'playing') {
      return;
    }
    stopPeek();
    flushLatency();
    hideResult();
    hideToast();
    resultDismissed = false;
    replayPromptActive = false;
    resultRecorded = false;
    sound.play('click');
    // 先按最新样本校准，再建局，这样新一局用的就是刚学到的时长
    syncAdaptiveDelay();
    viewModel.newGame();
    updatePauseUI();
    updateLevelBadge();
    renderPeekHud();
    renderCombo();
    renderAdaptiveNote();
  }

  // ---------------- 状态订阅 ----------------

  viewModel.subscribe(function (event) {
    switch (event.type) {
      case 'flip':
        updateCardStates();
        updateProgress();
        sound.play('flip');
        break;

      case 'score':
        updateScore();
        playScoreFeedback(event.delta);
        if (event.delta > 0) {
          sound.play('match');
          // 配对成功的轻震：倍数越高震得越长一点，手上能感觉到「热起来了」
          vibrate(viewModel.comboStreak >= Config.COMBO.visibleFrom
            ? [12, 30, 12]
            : 10);
        }
        break;

      case 'combo':
        renderCombo();
        break;

      case 'peek':
        peekCardId = event.cardId;
        peekSwallowUntil = Date.now() + 700;
        markPeekCard(event.cardId, true);
        renderPeekHud();
        updateHint();
        vibrate(8);
        clearTimeout(peekHideTimer);
        // 只亮 0.4 秒：时间到就交给 ViewModel 收回，视图不自己改状态
        peekHideTimer = window.setTimeout(function () {
          viewModel.endPeek();
        }, PEEK_SHOW_MS);
        break;

      case 'peekend':
        if (peekHideTimer !== null) {
          window.clearTimeout(peekHideTimer);
          peekHideTimer = null;
        }
        markPeekCard(event.cardId, false);
        renderPeekHud();
        updateHint();
        break;

      case 'latency':
        // 反应时间样本只在结算时统一落盘，避免每配一对就写一次 localStorage
        pendingLatencySamples = pendingLatencySamples.concat(event.samples);
        break;

      case 'locked':
        updateCardStates();
        updateHint();
        updateThemeBarLock();
        sound.play('mismatch');
        vibrate([18, 40, 18]);
        break;

      case 'flipback':
        updateCardStates();
        updateHint();
        updateThemeBarLock();
        break;

      case 'pause':
        cancelPeekHold();
        updatePauseUI();
        updateHint();
        updatePie();
        updateThemeBarLock();
        sound.play('pause');
        break;

      case 'resume':
        updatePauseUI();
        updateHint();
        updatePie();
        updateThemeBarLock();
        sound.play('resume');
        break;

      case 'levelclear':
        rebuildBoard();
        updateScore();
        updateProgress();
        updatePie();
        updateHint();
        updateLevelBadge();
        updateThemeBarLock();
        renderPeekHud();
        renderCombo();
        sound.play('levelclear');
        vibrate([10, 40, 24]);
        showToast('第 ' + event.level + ' 关 · 时间 +' + event.bonus + ' 秒');
        break;

      case 'gameover':
        updateScore();
        updateProgress();
        updatePie();
        updateHint();
        updateLevelBadge();
        renderCombo();
        flushLatency();
        sound.play('win');
        vibrate([16, 60, 16, 60, 24]);
        showResult();
        break;

      case 'timeout':
        updatePie();
        updateHint();
        updateCardStates();
        updateThemeBarLock();
        renderCombo();
        flushLatency();
        sound.play('timeout');
        vibrate([30, 60, 30]);
        showResult();
        break;

      case 'countdown':
        updatePie();
        updateHint();
        break;

      case 'idle':
        // 回到主界面：倒计时已复位，界面上不应残留暂停/结算样式
        updatePie();
        updateHint();
        updateThemeBarLock();
        updatePauseUI();
        hideResult();
        break;

      case 'newgame':
        rebuildBoard();
        updateScore();
        updateProgress();
        updatePie();
        updateHint();
        updateThemeBarLock();
        updateThemeLabel();
        updateLevelBadge();
        updateThemeSelection();
        renderPeekHud();
        renderCombo();
        hideResult();
        hideToast();
        updatePauseUI();
        break;

      default:
        break;
    }
  });

  // ---------------- 事件绑定 ----------------

  startButtonEl.addEventListener('click', enterGame);
  homeButtonEl.addEventListener('click', goHome);
  pauseButtonEl.addEventListener('click', togglePause);
  pauseResumeButtonEl.addEventListener('click', togglePause);
  pauseHomeButtonEl.addEventListener('click', goHome);

  modeSwitchEl.addEventListener('click', function (event) {
    var target = event.target;
    while (target && target !== modeSwitchEl && !target.classList.contains('mode-tab')) {
      target = target.parentElement;
    }
    if (!target || target === modeSwitchEl) {
      return;
    }
    if (screen !== 'home') {
      return;
    }
    if (viewModel.setMode(target.dataset.mode)) {
      store.setPrefs({ mode: viewModel.mode });
      // 模式切换后自适应是否生效会变（闯关不参与），需要重算
      syncAdaptiveDelay();
      sound.play('click');
      renderHome();
    }
  });

  difficultyRowEl.addEventListener('click', function (event) {
    var target = event.target;
    while (target && target !== difficultyRowEl && !target.classList.contains('chip')) {
      target = target.parentElement;
    }
    if (!target || target === difficultyRowEl) {
      return;
    }
    if (screen !== 'home') {
      return;
    }
    if (viewModel.setDifficulty(target.dataset.difficulty)) {
      store.setPrefs({ difficulty: viewModel.difficulty });
      // 难度换档 → 基础时长与是否自适应都变了，重新校准
      syncAdaptiveDelay();
      sound.play('click');
      renderHome();
    }
  });

  soundToggleEl.addEventListener('click', function () {
    sound.setEnabled(!sound.enabled);
    store.setPrefs({ sound: sound.enabled });
    renderSoundToggle();
    sound.play('click');
  });

  if (hapticToggleEl) {
    hapticToggleEl.addEventListener('click', function () {
      if (!hapticsSupported) {
        return;
      }
      hapticsEnabled = !hapticsEnabled;
      store.setPrefs({ haptic: hapticsEnabled });
      renderHapticToggle();
      sound.play('click');
      // 开启时立刻震一下，明确告知「现在生效了」
      if (hapticsEnabled) {
        vibrate(12);
      }
    });
  }

  if (historyClearEl) {
    historyClearEl.addEventListener('click', function () {
      store.clearHistory();
      renderHistory();
      sound.play('click');
    });
  }

  // 自适应提示里的「重置」是动态生成的按钮，用事件委托接住
  if (adaptiveNoteEl) {
    adaptiveNoteEl.addEventListener('click', function (event) {
      var target = event.target;
      if (!target || !target.classList || !target.classList.contains('adaptive-reset')) {
        return;
      }
      store.clearTimings();
      pendingLatencySamples = [];
      syncAdaptiveDelay();
      renderAdaptiveNote();
      sound.play('click');
    });
  }

  /** 从事件目标向上找到卡片元素（点击卡片内的 emoji/牌面也能命中）。 */
  function closestCard(node) {
    var target = node;
    while (target && target !== boardEl && !target.classList.contains('card')) {
      target = target.parentElement;
    }
    return target && target !== boardEl ? target : null;
  }

  /** 按 id 取当前模型里的卡片对象。 */
  function findCardById(cardId) {
    for (var i = 0; i < viewModel.cards.length; i += 1) {
      if (viewModel.cards[i].id === cardId) {
        return viewModel.cards[i];
      }
    }
    return null;
  }

  boardEl.addEventListener('click', function (event) {
    var target = closestCard(event.target);
    if (!target) {
      return;
    }

    // 偷看后的那一次 click 必须吞掉：触摸松手会补发 click，
    // 不拦就会变成「偷看顺手把牌翻开」，与「只看不翻」的承诺相违背。
    if (peekCardId !== null && target.dataset.id === peekCardId
      && Date.now() < peekSwallowUntil) {
      peekSwallowUntil = 0;
      event.preventDefault();
      return;
    }

    var card = findCardById(target.dataset.id);
    if (!card) {
      return;
    }

    // 已配对的卡片点不动，静默忽略即可，给抖动反而像出错。
    if (card.isMatched) {
      return;
    }

    if (viewModel.isPaused) {
      return;
    }

    if (viewModel.isInteractionLocked) {
      playRejectFeedback(target);
      return;
    }

    // 已翻开、等待配对的那一张，重复点击由模型忽略。
    if (card.isFaceUp) {
      return;
    }

    viewModel.choose(card);
  });

  // ---------------- 长按偷看（触屏 / 鼠标通用）----------------

  boardEl.addEventListener('pointerdown', function (event) {
    if (screen !== 'playing' || modalOpen) {
      return;
    }
    // 只认主键：右键菜单/中键不进入长按判定
    if (event.button !== undefined && event.button !== 0) {
      return;
    }
    var element = closestCard(event.target);
    if (!element) {
      return;
    }
    var card = findCardById(element.dataset.id);
    if (!card || card.isMatched || card.isFaceUp) {
      return;
    }
    startPeekHold(element, card, { x: event.clientX, y: event.clientY });
  });

  boardEl.addEventListener('pointerup', cancelPeekHold);
  boardEl.addEventListener('pointercancel', cancelPeekHold);
  boardEl.addEventListener('pointerleave', cancelPeekHold);

  boardEl.addEventListener('pointermove', function (event) {
    if (!peekHoldOrigin) {
      return;
    }
    var dx = event.clientX - peekHoldOrigin.x;
    var dy = event.clientY - peekHoldOrigin.y;
    // 移动超过 10px 视为滑动/拖拽，不再是长按
    if (dx * dx + dy * dy > 100) {
      cancelPeekHold();
    }
  });

  // 触屏长按会弹系统菜单，会打断偷看；在棋盘内直接禁掉
  boardEl.addEventListener('contextmenu', function (event) {
    if (screen === 'playing') {
      event.preventDefault();
    }
  });

  themeBarEl.addEventListener('click', function (event) {
    var target = event.target;
    while (target && target !== themeBarEl && !target.classList.contains('theme-button')) {
      target = target.parentElement;
    }
    if (!target || target === themeBarEl) {
      return;
    }
    if (viewModel.isPaused || modalOpen) {
      return;
    }

    var themeId = target.dataset.themeId;
    for (var i = 0; i < Theme.builtIn.length; i += 1) {
      if (Theme.builtIn[i].id === themeId) {
        viewModel.chooseTheme(Theme.builtIn[i]);
        return;
      }
    }
  });

  pieEl.addEventListener('click', function () {
    if (screen !== 'playing' || modalOpen || viewModel.countdownState === 'idle') {
      return;
    }
    togglePause();
  });

  restartEl.addEventListener('click', restartGame);
  modalButtonEl.addEventListener('click', restartGame);
  modalHomeEl.addEventListener('click', goHome);

  // 结算被关闭后，提示行本身是可点击的重开入口
  hintEl.addEventListener('click', function () {
    if (replayPromptActive) {
      restartGame();
    }
  });

  hintEl.addEventListener('keydown', function (event) {
    if (!replayPromptActive) {
      return;
    }
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      restartGame();
    }
  });

  // 页面切到后台时自动暂停：否则玩家切走再回来，时间已经在背后走掉了
  document.addEventListener('visibilitychange', function () {
    if (document.hidden && screen === 'playing' && !modalOpen) {
      viewModel.pause();
    }
  });

  window.addEventListener('keydown', function (event) {
    // 主界面：只认「开始」，不响应任何游戏内快捷键
    if (screen === 'home') {
      if (event.key === 'Enter' || event.key === ' ') {
        // 焦点在开始按钮上时浏览器会自动触发 click，这里只兜住其他焦点位置
        if (document.activeElement === startButtonEl) {
          return;
        }
        event.preventDefault();
        enterGame();
      }
      return;
    }

    if (modalOpen) {
      if (event.key === 'Escape') {
        event.preventDefault();
        dismissResult();
        return;
      }
      // 弹窗内只有两个可聚焦按钮，Tab 在两者之间切换，不跑回背后的棋盘
      if (event.key === 'Tab') {
        event.preventDefault();
        if (document.activeElement === modalButtonEl) {
          modalHomeEl.focus();
        } else {
          modalButtonEl.focus();
        }
        return;
      }
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        restartGame();
        return;
      }
      return;
    }

    // P 暂停 / 继续：这是游戏内唯一的暂停快捷键
    if ((event.key === 'p' || event.key === 'P')
      && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault();
      togglePause();
      return;
    }

    // 游戏中按 R 重开：想换一副牌不必先切主题
    if ((event.key === 'r' || event.key === 'R')
      && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault();
      restartGame();
      return;
    }

    // Esc 返回主界面；返回时 leaveGame 会停表并解除暂停
    if (event.key === 'Escape') {
      event.preventDefault();
      goHome();
    }
  });

  // 窗口尺寸变化时重新排布卡片（对应 SwiftUI GeometryReader 的响应式重算）。
  if (typeof ResizeObserver === 'function') {
    var observer = new ResizeObserver(function () {
      layoutBoard();
    });
    observer.observe(boardEl);
    observer.observe(boardAreaEl);
  } else {
    window.addEventListener('resize', layoutBoard);
  }

  window.addEventListener('orientationchange', function () {
    window.setTimeout(layoutBoard, 120);
  });

  // ---------------- 启动 ----------------

  buildModeSwitch();
  buildDifficultyChips();

  /* 启动时只渲染主界面与静态信息：
     不建棋盘、不建主题栏以外的游戏元素、更不启动倒计时。 */
  syncAdaptiveDelay();
  renderHome();
  renderThemeBar();
  updateScore();
  updateProgress();
  updatePie();
  updateHint();
  updateThemeLabel();
  updateLevelBadge();
  updateThemeBarLock();
  updatePauseUI();
  renderPeekHud();
  renderCombo();

  // 便于调试与后续扩展：在控制台可访问当前实例。
  window.memorizeGame = viewModel;
  window.memorizeDebug = {
    screen: function () { return screen; },
    enterGame: enterGame,
    goHome: goHome,
    togglePause: togglePause,
    store: store,
    sound: sound
  };

  /*
   * 调试探针：URL 带 ?probe=1 时把关键状态写入页面标题，
   * 便于在无截图环境下核对布局与状态变化。正常访问不会触发。
   */
  function refreshProbeTitle() {
    if (!/[?&]probe=1/.test(window.location.search)) {
      return;
    }
    var gridStyle = window.getComputedStyle(boardEl);
    var columns = gridStyle.gridTemplateColumns
      .trim().split(/\s+/).filter(Boolean).length;
    var faceUp = viewModel.cards.filter(function (card) {
      return card.isFaceUp || card.isMatched;
    }).length;
    var firstCard = boardEl.querySelector('.card');
    var firstFace = boardEl.querySelector('.card-front');
    var cardBox = firstCard ? firstCard.getBoundingClientRect() : { width: 0, height: 0 };
    var radius = firstFace
      ? window.getComputedStyle(firstFace).borderTopLeftRadius
      : 'none';
    var bucket = scoreBucket();
    document.title = [
      'screen=' + screen,
      'mode=' + viewModel.mode,
      'diff=' + viewModel.difficulty,
      'level=' + viewModel.levelNumber + '/' + viewModel.levelCount,
      'cards=' + viewModel.cards.length,
      'boardCards=' + boardEl.children.length,
      'cols=' + columns,
      'w=' + gridStyle.getPropertyValue('--card-w').trim(),
      'gap=' + gridStyle.getPropertyValue('--card-gap').trim(),
      'boardWH=' + boardEl.clientWidth + 'x' + boardEl.clientHeight,
      'appH=' + document.querySelector('.app').clientHeight,
      'bodyH=' + document.body.clientHeight,
      'score=' + viewModel.score,
      'left=' + viewModel.countdownRemaining,
      'up=' + faceUp,
      'lock=' + (viewModel.isInteractionLocked ? 1 : 0),
      'paused=' + (viewModel.isPaused ? 1 : 0),
      'state=' + viewModel.countdownState,
      'pairs=' + viewModel.matchedPairsCount + '/' + totalPairs(),
      'combo=' + viewModel.comboStreak,
      'mult=' + viewModel.comboMultiplier,
      'bonus=' + viewModel.comboBonus,
      'peek=' + viewModel.peekRemaining + '/' + viewModel.peekLimit,
      'delay=' + viewModel.mismatchFlipDelay,
      'hist=' + store.getHistory(5).length,
      'best=' + (store.getBest(bucket.mode, bucket.difficulty) === null
        ? 'none'
        : store.getBest(bucket.mode, bucket.difficulty)),
      'cardRect=' + Math.round(cardBox.width) + 'x' + Math.round(cardBox.height),
      'radius=' + radius
    ].join('|');
  }

  viewModel.subscribe(refreshProbeTitle);
  window.addEventListener('resize', refreshProbeTitle);
  refreshProbeTitle();
  requestAnimationFrame(refreshProbeTitle);
}());
