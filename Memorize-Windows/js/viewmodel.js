/*
 * Memorize 视图模型 —— Swift 版 GameViewModel 的等价移植 + 打磨阶段的玩法扩展。
 *
 * 职责与原版一致：视图与 Game 模型之间的唯一通道，负责状态发布与交互调度。
 *
 * 交互规则（逐条对应 day8/Memorize/ViewModels/GameViewModel.swift）：
 * - 错配后进入「等待翻回」状态并锁定交互，防止连点造成状态错乱；
 * - 由 ViewModel 调度 mismatchFlipDelay 秒后的翻回任务，视图不持有计时逻辑；
 * - 重开一局或切换主题会立即解除锁定，并让过期计时回调失效。
 *
 * 扩展部分（不改变原有规则，只是在外围增加状态）：
 * - 暂停：一次冻结「倒计时 + 输入 + 错配翻回任务」，恢复后按剩余时间继续；
 * - 难度：经典模式下按难度取 {时长, 对数, 翻回速度}，默认档与原版参数一致；
 * - 闯关：三关递进，共享一条倒计时，每过一关补时，失败即止步；
 * - 计分规则保持 +2 / -1 不变，闯关只把各关得分累加。
 *
 * 与原版的差异仅在于发布机制：Swift 用 @Published + Combine，这里用一个
 * 极简的订阅回调代替，语义等价（状态变化即通知），便于在浏览器与 Node 中共用。
 */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./model.js'), require('./config.js'));
  } else {
    root.MemorizeViewModel = factory(root.MemorizeModel, root.MemorizeConfig);
  }
}(typeof self !== 'undefined' ? self : this, function (Model, Config) {
  'use strict';

  var Card = Model.Card;
  var Game = Model.Game;
  var Theme = Model.Theme;

  /** 倒计时默认参数（对应 Swift 的 CountdownDefaults）。 */
  var CountdownDefaults = {
    duration: 60,        // 每局初始倒计时秒数
    tickInterval: 1000   // 计时器触发间隔（毫秒）= 1 秒
  };

  /** 错配后卡片保持正面的时长（秒），对应 Swift 默认值 0.8。 */
  var DEFAULT_MISMATCH_FLIP_DELAY = 0.8;

  var defaultTimers = {
    setTimeout: function (fn, ms) { return setTimeout(fn, ms); },
    clearTimeout: function (id) { clearTimeout(id); },
    setInterval: function (fn, ms) { return setInterval(fn, ms); },
    clearInterval: function (id) { clearInterval(id); },
    // 暂停需要知道「已经过去了多久」，因此计时器实现需要暴露当前时刻。
    // Node 的假时钟直接给数字，浏览器给函数，两种都支持。
    now: function () { return Date.now(); }
  };

  /**
   * @param {object} [options]
   * @param {Theme}  [options.theme]              初始主题，默认第一个内置主题
   * @param {number} [options.numberOfPairs]      卡片对数，默认取开局配置
   * @param {boolean}[options.shuffle]            是否洗牌，默认 true
   * @param {string} [options.mode]               'classic' | 'campaign'，默认 classic
   * @param {string} [options.difficulty]         难度 id，默认 classic
   * @param {number} [options.mismatchFlipDelay]  覆盖错配保持正面时长（秒），用于测试
   * @param {object} [options.timers]             计时器实现，便于测试注入
   */
  function GameViewModel(options) {
    var opts = options || {};

    this.theme = opts.theme || Theme.builtIn[0];

    this.mode = opts.mode === 'campaign' ? 'campaign' : 'classic';
    this.difficulty = Config.findDifficulty(opts.difficulty).id;
    this.levelIndex = 0;
    this.levelCount = this.mode === 'campaign' ? Config.CAMPAIGN.stageCount : 1;
    this.round = Config.resolveRound(this.mode, this.difficulty, 0);

    // 显式传入 numberOfPairs 时按调用方给的来，否则用配置里的对数
    var pairs = opts.numberOfPairs == null ? this.round.pairs : opts.numberOfPairs;
    this.game = new Game(this.theme, pairs, opts.shuffle);

    // ---- 连击（挑战档专属）----
    this.comboEnabled = Config.isComboMode(this.mode, this.difficulty);
    this.comboStreak = 0;        // 当前连击次数
    this.comboMultiplier = 1;    // 当前生效倍率
    this.comboBonus = 0;         // 连击带来的额外分数（已并入 score）
    this.bestCombo = 0;          // 本局最高连击
    this._comboCarry = 0;        // 倍率取整后的余数，跨次结转

    // ---- 长按偷看 ----
    this.peekLimit = this.round.peek;
    this.peekRemaining = this.peekLimit;
    this.peekingCardId = null;

    // ---- 助记自适应 ----
    this.delayAdjust = 0;                                  // 由外部根据样本算好后注入
    this.baseMismatchFlipDelay = this.round.mismatchFlipDelay;
    this.recentLatencies = [];                              // 最近若干张牌的反应时间（毫秒）
    this._firstSeenAt = {};                                 // cardId → 首次翻看时刻

    this.mismatchFlipDelay = opts.mismatchFlipDelay == null
      ? this._effectiveDelay()
      : opts.mismatchFlipDelay;

    this.timers = opts.timers || defaultTimers;

    // ---- 对外发布的状态（对应 @Published）----
    this.cards = this.game.cards;
    this.score = this.game.score;
    this.isInteractionLocked = false;
    this.isPaused = false;
    this.boardRevision = 0;
    this.scoreRevision = 0;
    this.scoreChangeDelta = 0;

    this.countdownRemaining = 0;
    this.countdownTotal = 0;
    this.countdownState = 'idle'; // idle | running | paused | finished | stopped
    this.didTimeOut = false;
    /** 本局结束原因：'win' | 'timeout' | null，用于结算文案。 */
    this.resultReason = null;

    // ---- 内部状态 ----
    this._countdownDuration = 0;   // 本局倒计时时长，用于重开时恢复
    this._carryScore = 0;          // 闯关模式下前几关累计的得分
    this._pendingTimerToken = null;
    this._flipTimerId = null;
    this._flipDeadline = 0;        // 错配翻回的预计触发时刻（毫秒）
    this._flipRemainingMs = null;  // 暂停时冻结的翻回剩余时间
    this._clockTimerId = null;
    this._listeners = new Set();
  }

  // ---------------- 订阅 ----------------

  /** 订阅状态变化；返回取消订阅函数。 */
  GameViewModel.prototype.subscribe = function (listener) {
    this._listeners.add(listener);
    var self = this;
    return function () { self._listeners.delete(listener); };
  };

  GameViewModel.prototype._notify = function (event) {
    this._listeners.forEach(function (listener) {
      listener(event || {});
    });
  };

  // ---------------- 只读派生属性 ----------------

  Object.defineProperty(GameViewModel.prototype, 'isGameOver', {
    get: function () { return this.game.isGameOver; }
  });

  Object.defineProperty(GameViewModel.prototype, 'matchedPairsCount', {
    get: function () { return this.game.matchedPairsCount; }
  });

  Object.defineProperty(GameViewModel.prototype, 'hasPendingMismatch', {
    get: function () { return this.game.hasPendingMismatch; }
  });

  /** 当前关卡序号（从 1 开始），经典模式恒为 1。 */
  Object.defineProperty(GameViewModel.prototype, 'levelNumber', {
    get: function () { return this.levelIndex + 1; }
  });

  /**
   * 结算弹窗标题：按结束原因给文案，闯关与经典分开。
   */
  Object.defineProperty(GameViewModel.prototype, 'resultTitle', {
    get: function () {
      if (this.resultReason === 'timeout') {
        return this.mode === 'campaign' ? '挑战失败' : '时间到！';
      }
      if (this.resultReason === 'win') {
        return this.mode === 'campaign' ? '闯关成功！' : '全部配对成功！';
      }
      return this.game.isGameOver ? '全部配对成功！' : '时间到！';
    }
  });

  /**
   * 提示行文案（对应 GameView.hintText）。
   */
  Object.defineProperty(GameViewModel.prototype, 'hintText', {
    get: function () {
      if (this.isPaused) {
        return '已暂停 · 计时与翻牌已冻结';
      }
      if (this.countdownState === 'finished') {
        return this.mode === 'campaign' ? '时间到，本次闯关结束' : '时间到，点击「再来一局」重新开始';
      }
      if (this.countdownState === 'stopped') {
        return '全部配对成功！';
      }
      if (this.countdownState === 'paused') {
        return '倒计时已暂停，点击环形继续计时';
      }
      return this.isInteractionLocked
        ? '配对失败，卡片即将翻回…'
        : '点击卡片翻开，找出全部对子';
    }
  });

  // ---------------- 模式与难度 ----------------

  /**
   * 切换游戏模式。只允许在「未开局」时切换（主界面），
   * 游戏中切换会牵扯到关卡、计时与得分三套状态，属于明确的禁止操作。
   * @returns {boolean} 是否切换成功
   */
  GameViewModel.prototype.setMode = function (mode) {
    if (this.countdownState !== 'idle' || this.isPaused) {
      return false;
    }
    if (mode !== 'classic' && mode !== 'campaign') {
      return false;
    }
    this.mode = mode;
    this.levelIndex = 0;
    this.levelCount = mode === 'campaign' ? Config.CAMPAIGN.stageCount : 1;
    this._applyRound(0);
    return true;
  };

  /** 切换难度，同样只允许在未开局时进行。 */
  GameViewModel.prototype.setDifficulty = function (difficultyId) {
    if (this.countdownState !== 'idle' || this.isPaused) {
      return false;
    }
    var id = Config.findDifficulty(difficultyId).id;
    if (id === this.difficulty) {
      return true;
    }
    this.difficulty = id;
    this._applyRound(this.levelIndex);
    return true;
  };

  /**
   * 应用某一关的配置：只改参数与牌组，不动计时与得分。
   * 主界面阶段用 shuffle=false 生成一副占位牌组（不渲染），
   * 真正开局时再传 true 洗牌，避免主界面白白消耗一次洗牌随机性。
   *
   * @param {number}  stageIndex 关卡下标
   * @param {boolean} [shuffle]  是否洗牌，默认 false
   */
  GameViewModel.prototype._applyRound = function (stageIndex, shuffle) {
    this.round = Config.resolveRound(this.mode, this.difficulty, stageIndex);
    this.baseMismatchFlipDelay = this.round.mismatchFlipDelay;
    this.mismatchFlipDelay = this._effectiveDelay();
    this.peekLimit = this.round.peek;
    this.peekRemaining = this.peekLimit;
    this.peekingCardId = null;
    this._firstSeenAt = {};
    // 连击开关随「模式 + 难度」变化，换档同时把余额清零（不能带着挑战档的 ×1.5 回经典档）
    this.comboEnabled = Config.isComboMode(this.mode, this.difficulty);
    this._resetCombo();
    this.game = new Game(this.theme, this.round.pairs, shuffle === true);
    this._syncFromGame();
  };

  /**
   * 本局实际生效的错配翻回时长。
   * 自适应只作用于经典模式下的轻松/经典档，且偏移量已被夹在 ±0.15 秒内，
   * 因此最坏情况也就是 0.65–0.95 秒，不会动摇「错配 0.8 秒」这条主参数。
   */
  GameViewModel.prototype._effectiveDelay = function () {
    if (!Config.isAdaptiveMode(this.mode, this.difficulty)) {
      return this.round.mismatchFlipDelay;
    }
    return Config.effectiveDelay(this.round.mismatchFlipDelay, this.delayAdjust);
  };

  /**
   * 注入自适应偏移量（秒）。只影响下一次建局，不会改动正在进行的这一局。
   * 这是「保守」的关键：一局之内判定节奏恒定，玩家不会打到一半发现难度变了。
   */
  GameViewModel.prototype.setDelayAdjust = function (adjust) {
    var value = Number(adjust);
    if (!isFinite(value)) {
      value = 0;
    }
    var max = Config.ADAPTIVE.maxDelta;
    this.delayAdjust = Math.max(-max, Math.min(max, Math.round(value * 1000) / 1000));
    return this.delayAdjust;
  };

  /** 当前是否允许自适应微调（供界面显示状态）。 */
  Object.defineProperty(GameViewModel.prototype, 'isAdaptiveActive', {
    get: function () {
      return Config.isAdaptiveMode(this.mode, this.difficulty) && this.delayAdjust !== 0;
    }
  });

  /**
   * 重算当前翻回时长。
   * 刻意只在 countdownState === 'idle'（主界面 / 未开局）时生效：
   * 牌局进行中改判定节奏，会让同一局内前后两次错配的等待时间不一样，
   * 玩家会明确感到「手感变了」，这与自适应「微调」的定位相冲突。
   */
  GameViewModel.prototype.refreshDelay = function () {
    if (this.countdownState !== 'idle') {
      return this.mismatchFlipDelay;
    }
    this.baseMismatchFlipDelay = this.round.mismatchFlipDelay;
    this.mismatchFlipDelay = this._effectiveDelay();
    return this.mismatchFlipDelay;
  };

  // ---------------- 连击 ----------------

  /** 连击倍数表直接取自配置，保证界面显示与结算一致。 */
  Object.defineProperty(GameViewModel.prototype, 'comboLabel', {
    get: function () {
      if (!this.comboEnabled || this.comboStreak < Config.COMBO.visibleFrom) {
        return '';
      }
      return '×' + this.comboMultiplier.toFixed(2).replace(/0$/, '');
    }
  });

  /** 配对成功：累加连击、按倍率发放奖励分、记录反应时间。 */
  GameViewModel.prototype._registerMatch = function () {
    var now = this._now();

    /*
     * 反应时间按「对」采样，而不是按「张」：
     * 刚翻开的第二张牌耗时天然是 0，如果两张都记一条，平均值会被系统性拉低一半，
     * 自适应就会误判成「玩家很快」而持续缩短翻回时间。
     * 因此一对只产生一条样本：从这一对里第一张被翻看到配对完成的时长。
     */
    var earliest = null;
    for (var i = 0; i < this.game.cards.length; i += 1) {
      var item = this.game.cards[i];
      if (!item.isMatched) {
        continue;
      }
      var seenAt = this._firstSeenAt[item.id];
      if (seenAt == null) {
        continue;
      }
      if (earliest === null || seenAt < earliest) {
        earliest = seenAt;
      }
      delete this._firstSeenAt[item.id];
    }

    if (earliest !== null) {
      var sample = Math.max(1, Math.round(now - earliest));
      this.recentLatencies = this.recentLatencies.concat([sample]);
      if (this.recentLatencies.length > 40) {
        this.recentLatencies = this.recentLatencies.slice(-40);
      }
      this._notify({ type: 'latency', samples: [sample], average: this.averageLatency() });
    }

    this.comboStreak += 1;
    if (this.comboStreak > this.bestCombo) {
      this.bestCombo = this.comboStreak;
    }

    if (this.comboEnabled) {
      var award = Config.comboAward(this.comboStreak, this._comboCarry);
      this.comboMultiplier = award.multiplier;
      // base 分已由 model 发放，这里只补「多出来的部分」
      this.comboBonus += award.whole - Config.COMBO.base;
      this._comboCarry = award.carry;
    } else {
      this.comboMultiplier = 1;
    }

    this._notify({
      type: 'combo',
      streak: this.comboStreak,
      multiplier: this.comboMultiplier,
      bonus: this.comboBonus,
      enabled: this.comboEnabled
    });
  };

  /**
   * 连击中断：任何一次错配都清零（哪怕这张牌是第一次翻看、没扣分）。
   * 已到手的分不回收，只影响后续倍率。
   */
  GameViewModel.prototype._breakCombo = function () {
    if (this.comboStreak === 0 && this._comboCarry === 0) {
      return;
    }
    var broken = this.comboStreak;
    this.comboStreak = 0;
    this.comboMultiplier = 1;
    this._comboCarry = 0;
    this._notify({ type: 'combo', streak: 0, multiplier: 1, broken: broken, enabled: this.comboEnabled });
  };

  /** 新局 / 新关卡时彻底清空连击与其余额。 */
  GameViewModel.prototype._resetCombo = function () {
    var changed = this.comboStreak > 0 || this.comboBonus !== 0 || this._comboCarry !== 0;
    this.comboStreak = 0;
    this.comboMultiplier = 1;
    this.comboBonus = 0;
    this.bestCombo = 0;
    this._comboCarry = 0;
    if (changed) {
      this._notify({ type: 'combo', streak: 0, multiplier: 1, enabled: this.comboEnabled });
    }
  };

  /** 窗口内平均反应时间（毫秒）；无样本时返回 0。 */
  GameViewModel.prototype.averageLatency = function () {
    if (this.recentLatencies.length === 0) {
      return 0;
    }
    var sum = 0;
    for (var i = 0; i < this.recentLatencies.length; i += 1) {
      sum += this.recentLatencies[i];
    }
    return Math.round(sum / this.recentLatencies.length);
  };

  // ---------------- 长按偷看 ----------------

  /**
   * 长按偷看：只让玩家看见图案 0.4 秒，**不改变任何模型状态**
   * （不置 isFaceUp、不判定配对、不计入 seenCardIDs、不影响扣分条件）。
   *
   * 因此这是一条纯粹的「辅助信息」通道，次数有限、且受暂停/锁定约束。
   */
  GameViewModel.prototype.canPeek = function (card) {
    if (!card) {
      return false;
    }
    if (this.isPaused || this.countdownState !== 'running') {
      return false;
    }
    if (this.isInteractionLocked) {
      return false;
    }
    if (this.peekRemaining <= 0) {
      return false;
    }
    if (card.isMatched || card.isFaceUp) {
      return false;
    }
    return this.peekingCardId === null;
  };

  /** @returns {boolean} 是否真的开始了一次偷看 */
  GameViewModel.prototype.peek = function (card) {
    if (!this.canPeek(card)) {
      return false;
    }
    this.peekRemaining -= 1;
    this.peekingCardId = card.id;
    this._notify({ type: 'peek', cardId: card.id, remaining: this.peekRemaining });
    return true;
  };

  /** 结束偷看（到时、切页、重开都会调用；重复调用无副作用）。 */
  GameViewModel.prototype.endPeek = function () {
    if (this.peekingCardId === null) {
      return false;
    }
    var cardId = this.peekingCardId;
    this.peekingCardId = null;
    this._notify({ type: 'peekend', cardId: cardId, remaining: this.peekRemaining });
    return true;
  };

  /** 偷看次数文案，供界面直接显示。 */
  Object.defineProperty(GameViewModel.prototype, 'peekLabel', {
    get: function () {
      return '偷看 ' + this.peekRemaining + '/' + this.peekLimit;
    }
  });

  // ---------------- 核心交互 ----------------

  /**
   * 处理一次卡片点击；错配时锁定交互并调度延时翻回。
   * 暂停期间直接丢弃输入：视图虽然被遮罩挡住，模型侧仍要守住，
   * 避免键盘快捷键或脚本触发绕过遮罩。
   */
  GameViewModel.prototype.choose = function (card) {
    if (this.isInteractionLocked || this.isPaused) {
      return;
    }

    var previousScore = this.score;
    var before = null;
    for (var i = 0; i < this.game.cards.length; i += 1) {
      if (this.game.cards[i].id === card.id) {
        before = this.game.cards[i];
        break;
      }
    }
    var wasFaceUp = before ? before.isFaceUp : false;
    var matchedBefore = this.game.matchedPairsCount;

    // 记录「这张牌第一次被看到」的时刻，用于统计反应时间（自适应样本）。
    // 只记第一次：反复翻看同一张牌不会把平均时间拉长。
    if (!wasFaceUp && this._firstSeenAt[card.id] == null) {
      this._firstSeenAt[card.id] = this._now();
    }

    this.game.choose(card);

    if (this.game.matchedPairsCount > matchedBefore) {
      // 配对成功：先结算连击与反应时间，再同步分数，这样视图拿到的增量已含倍率奖励
      this._registerMatch();
    } else if (this.game.hasPendingMismatch) {
      // 错配即中断连击（暂停、无效点击都不算）
      this._breakCombo();
    }

    this._syncFromGame();

    // 只有「背面翻到正面」的真实变化才记录翻牌动画，重复点击不会叠加。
    var updated = null;
    for (var j = 0; j < this.game.cards.length; j += 1) {
      if (this.game.cards[j].id === card.id) {
        updated = this.game.cards[j];
        break;
      }
    }
    if (!wasFaceUp && updated && updated.isFaceUp) {
      this._notify({ type: 'flip', cardId: updated.id, matched: updated.isMatched });
    }

    if (previousScore !== this.score) {
      this.scoreRevision += 1;
      this.scoreChangeDelta = this.score - previousScore;
      this._notify({
        type: 'score',
        delta: this.scoreChangeDelta,
        revision: this.scoreRevision
      });
    }

    if (!this.game.hasPendingMismatch) {
      if (this.game.isGameOver) {
        this._handleRoundCleared();
      }
      return;
    }

    this.isInteractionLocked = true;
    this._notify({ type: 'locked' });
    this._scheduleFlipBack();
  };

  /** 翻牌动画播放结束（预留给视图，用于释放动画占用）。 */
  GameViewModel.prototype.endFlip = function () {
    // Web 版由 CSS 自身管理过渡，无需额外的动画占用表；
    // 保留该接口以维持与原版一致的方法面。
  };

  // ---------------- 暂停 / 恢复 ----------------

  /**
   * 暂停游戏：冻结倒计时、输入与错配翻回任务。
   *
   * 为什么连错配翻回也要冻结：
   * 那一张卡片正处于「已翻开但未翻回」的中间态，若暂停时让它照常翻回，
   * 玩家回来会看到牌面莫名其妙变了一次，等于暂停期间游戏逻辑仍在推进。
   *
   * @returns {boolean} 是否真的进入暂停
   */
  GameViewModel.prototype.pause = function () {
    if (this.isPaused) {
      return false;
    }
    // 只有「正在计时」的对局可以暂停；结算后、主界面、已暂停都不接受。
    if (this.countdownState !== 'running') {
      return false;
    }

    this.isPaused = true;

    // 暂停时立刻收回偷看：否则牌面会在遮罩下多亮 0.4 秒，等于暂停期间还能看牌
    this.endPeek();

    if (this._pendingTimerToken !== null) {
      var remaining = this._flipDeadline - this._now();
      this._flipRemainingMs = Math.max(0, remaining);
      this._stopFlipTimer();
      // 作废旧令牌：恢复时会用剩余时间重新排一次任务
      this._pendingTimerToken = null;
    }

    this._stopClock();
    this.countdownState = 'paused';
    this._notify({ type: 'pause' });
    this._notify({ type: 'countdown' });
    return true;
  };

  /**
   * 恢复游戏：倒计时继续走秒，被冻结的翻回任务按剩余时间重新排队。
   * @returns {boolean} 是否真的恢复
   */
  GameViewModel.prototype.resume = function () {
    if (!this.isPaused) {
      return false;
    }

    this.isPaused = false;

    if (this.countdownState === 'paused') {
      this.countdownState = 'running';
      this._scheduleCountdownTicks();
    }

    if (this._flipRemainingMs != null) {
      var remaining = this._flipRemainingMs;
      this._flipRemainingMs = null;
      this._scheduleFlipBack(remaining);
    }

    this._notify({ type: 'resume' });
    this._notify({ type: 'countdown' });
    return true;
  };

  /** 在暂停 / 恢复之间切换。 */
  GameViewModel.prototype.togglePause = function () {
    return this.isPaused ? this.resume() : this.pause();
  };

  // ---------------- 倒计时 ----------------

  /**
   * 开始倒计时；已在计时中会先停止旧计时再重新开始。
   * @param {number} [duration] 总秒数，必须大于 0
   */
  GameViewModel.prototype.startCountdown = function (duration) {
    var total = duration == null ? CountdownDefaults.duration : duration;
    if (!(total > 0)) {
      return;
    }

    this._stopClock();
    this._countdownDuration = total;
    this.countdownTotal = total;
    this.countdownRemaining = total;
    this.didTimeOut = false;
    this.resultReason = null;
    this.countdownState = 'running';
    this._scheduleCountdownTicks();
    this._notify({ type: 'countdown' });
  };

  /** 首次进入界面时启动倒计时；已经启动过则不重复启动。 */
  GameViewModel.prototype.startCountdownIfNeeded = function () {
    if (this.countdownState === 'idle' && this._countdownDuration === 0) {
      this.startCountdown();
    }
  };

  /**
   * 正式开局：按当前模式/难度选牌、重洗牌组并启动倒计时。
   *
   * 主界面阶段不会调用本方法，因此玩家点「开始游戏」之前，
   * 既没有牌面渲染，也没有任何计时任务在跑。
   *
   * @param {number} [duration] 覆盖本局时长（仅测试与特殊演示使用）
   */
  GameViewModel.prototype.startGame = function (duration) {
    this._stopFlipTimer();
    this._pendingTimerToken = null;
    this._flipRemainingMs = null;
    this.isInteractionLocked = false;
    this.isPaused = false;
    this.scoreChangeDelta = 0;
    this.resultReason = null;

    this.levelIndex = 0;
    this.levelCount = this.mode === 'campaign' ? Config.CAMPAIGN.stageCount : 1;
    this._carryScore = 0;
    this._applyRound(0, true);

    this.boardRevision += 1;
    this._notify({ type: 'newgame' });

    this.startCountdown(duration == null ? this.round.duration : duration);
  };

  /**
   * 离开游戏回到主界面：停掉所有计时并清空本局进度。
   *
   * 与 stopCountdown 的区别是同时解除交互锁、作废未触发的翻回任务；
   * 停留主界面期间 countdownState 恒为 idle，剩余秒数归零，
   * 因此不会出现「在主界面继续走秒」的情况。
   */
  GameViewModel.prototype.leaveGame = function () {
    this._stopFlipTimer();
    this._pendingTimerToken = null;
    this._flipRemainingMs = null;
    this.isInteractionLocked = false;
    this.isPaused = false;
    this.scoreChangeDelta = 0;
    this.didTimeOut = false;
    this.resultReason = null;
    this.countdownState = 'idle';
    this.countdownRemaining = 0;
    this.countdownTotal = 0;
    this._countdownDuration = 0;
    this.levelIndex = 0;
    this.levelCount = this.mode === 'campaign' ? Config.CAMPAIGN.stageCount : 1;
    this._carryScore = 0;
    this._applyRound(0);
    this._stopClock();
    this._notify({ type: 'countdown' });
    this._notify({ type: 'idle' });
  };

  /** 每次计时器触发：剩余秒数减一，归零时进入结束状态。 */
  GameViewModel.prototype.tickCountdown = function () {
    if (this.countdownState !== 'running') {
      return;
    }

    if (this.countdownRemaining <= 0) {
      this._finishCountdown();
      return;
    }

    this.countdownRemaining -= 1;
    if (this.countdownRemaining === 0) {
      this._finishCountdown();
    } else {
      this._notify({ type: 'countdown' });
    }
  };

  /** 暂停倒计时，保留剩余秒数。 */
  GameViewModel.prototype.pauseCountdown = function () {
    if (this.countdownState !== 'running') {
      return;
    }
    this._stopClock();
    this.countdownState = 'paused';
    this._notify({ type: 'countdown' });
  };

  /** 恢复到暂停前的剩余秒数继续计时。 */
  GameViewModel.prototype.resumeCountdown = function () {
    if (this.countdownState !== 'paused') {
      return;
    }
    this.countdownState = 'running';
    this._scheduleCountdownTicks();
    this._notify({ type: 'countdown' });
  };

  /**
   * 运行 / 暂停切换。
   * 打磨阶段统一为「整局暂停」：暂停后输入与游戏逻辑一并冻结，
   * 不再保留「只停表还能翻牌」的半暂停状态。
   */
  GameViewModel.prototype.toggleCountdown = function () {
    this.togglePause();
  };

  /** 停止倒计时并恢复到未开始状态。 */
  GameViewModel.prototype.stopCountdown = function () {
    this._stopClock();
    this._countdownDuration = 0;
    this.countdownRemaining = 0;
    this.countdownTotal = 0;
    this.didTimeOut = false;
    this.countdownState = 'idle';
    this._notify({ type: 'countdown' });
  };

  /**
   * 通关一关后补时（闯关模式用）。
   * 同时抬高剩余与总量，环形进度按新总量重新计算，视觉上会「涨一截」。
   */
  GameViewModel.prototype.addCountdownTime = function (seconds) {
    var bonus = Number(seconds);
    if (!(bonus > 0)) {
      return;
    }
    if (this.countdownState !== 'running' && this.countdownState !== 'paused') {
      return;
    }
    this.countdownRemaining += bonus;
    this.countdownTotal += bonus;
  };

  /** 剩余时间对应的进度 0...1（对应 PieGeometry.progress）。 */
  GameViewModel.prototype.countdownProgress = function () {
    var total = this.countdownTotal;
    if (!(total > 0)) {
      return 0;
    }
    if (this.countdownRemaining <= 0) {
      return 0;
    }
    if (this.countdownRemaining >= total) {
      return 1;
    }
    return this.countdownRemaining / total;
  };

  // ---------------- 收尾与重开 ----------------

  /**
   * 错配延时结束：翻回卡片并解除交互锁。手动调用同样有效（供测试与兜底使用）。
   */
  GameViewModel.prototype.completeMismatchFlipBack = function () {
    this._pendingTimerToken = null;

    if (!this.game.hasPendingMismatch) {
      return;
    }

    this.game.flipBackMismatch();
    this._syncFromGame();
    // 时间到后保持锁定，避免翻回任务把超时锁定意外解除。
    this.isInteractionLocked = this.countdownState === 'finished';
    this._notify({ type: 'flipback' });
  };

  /**
   * 使用当前模式 / 难度重新开始（闯关从第 1 关重新挑战）。
   * 解除交互锁、作废未触发的计时回调，得分归零。
   */
  GameViewModel.prototype.newGame = function () {
    var shouldRestartClock = this._countdownDuration > 0;
    var duration = this._countdownDuration > 0
      ? this._countdownDuration
      : this.round.duration;

    this._stopFlipTimer();
    this._pendingTimerToken = null;
    this._flipRemainingMs = null;
    this.isInteractionLocked = false;
    this.isPaused = false;
    this.scoreChangeDelta = 0;
    this.resultReason = null;

    this.levelIndex = 0;
    this.levelCount = this.mode === 'campaign' ? Config.CAMPAIGN.stageCount : 1;
    this._carryScore = 0;
    this._applyRound(0, true);

    this.boardRevision += 1;

    if (shouldRestartClock) {
      // 闯关重开必须回到初始时间预算，不能用累计后的总量
      this.startCountdown(this.mode === 'campaign' ? this.round.duration : duration);
    } else {
      this._notify({ type: 'countdown' });
    }

    this._notify({ type: 'newgame' });
  };

  /**
   * 切换主题并重新开始，解除交互锁并作废未触发的计时回调。
   *
   * 闯关模式下中途换主题等同于重开挑战：牌组与关卡是一一对应的，
   * 只换牌不回到第 1 关会让「第 2 关 7 对」这类进度失去意义。
   */
  GameViewModel.prototype.chooseTheme = function (theme) {
    // 暂停中不换主题：换主题会重建牌组并重启计时，与「冻结」相矛盾
    if (this.isPaused) {
      return;
    }

    this._pendingTimerToken = null;
    this._flipRemainingMs = null;
    this.isInteractionLocked = false;
    this.scoreChangeDelta = 0;

    this.theme = theme;

    if (this.mode === 'campaign' && this._countdownDuration > 0) {
      this.newGame();
      return;
    }

    // 换主题等同于换一副牌：走同一条建局路径，连击、偷看、反应时间样本一并复位
    this._applyRound(this.levelIndex, true);
    this.boardRevision += 1;
    this._restartCountdownIfNeeded();
    this._notify({ type: 'newgame' });
  };

  /** 资源清理：停止所有计时器。 */
  GameViewModel.prototype.dispose = function () {
    this._stopClock();
    this._stopFlipTimer();
    this._listeners.clear();
  };

  // ---------------- 私有实现 ----------------

  /** 当前时刻（毫秒），兼容函数的 now 与数字的 now。 */
  GameViewModel.prototype._now = function () {
    var source = this.timers ? this.timers.now : null;
    if (typeof source === 'function') {
      return source();
    }
    if (typeof source === 'number') {
      return source;
    }
    return Date.now();
  };

  /**
   * 本关全部配对完成后的分流：
   * - 闯关且还有下一关 → 进入下一关（保留得分、补时、换牌）；
   * - 否则 → 通关结算并立即停表。
   */
  GameViewModel.prototype._handleRoundCleared = function () {
    if (this.mode === 'campaign' && this.levelIndex + 1 < this.levelCount) {
      this._advanceLevel();
      return;
    }

    this.resultReason = 'win';
    this._haltCountdownOnWin();
    this._notify({ type: 'gameover' });
  };

  /**
   * 进入下一关：把本关得分收进累计分，换一副更大的牌，补时并通知视图重排。
   * 倒计时不重置，这是闯关模式的核心压力来源。
   */
  GameViewModel.prototype._advanceLevel = function () {
    var clearedStage = this.levelIndex + 1;
    // 本关实际得分含连击奖励，累加时不能只取 game.score
    this._carryScore += this.game.score + this.comboBonus;

    this.levelIndex += 1;
    this.round = Config.resolveRound('campaign', this.difficulty, this.levelIndex);
    this.baseMismatchFlipDelay = this.round.mismatchFlipDelay;
    this.mismatchFlipDelay = this._effectiveDelay();
    this.peekLimit = this.round.peek;
    this.peekRemaining = this.peekLimit;
    this.peekingCardId = null;
    this._firstSeenAt = {};
    this.comboEnabled = Config.isComboMode(this.mode, this.difficulty);
    this._resetCombo();
    this.game = new Game(this.theme, this.round.pairs, true);
    this._syncFromGame();

    var bonus = Config.CAMPAIGN.clearBonus;
    this.addCountdownTime(bonus);

    this.boardRevision += 1;
    this.isInteractionLocked = false;
    this._notify({ type: 'countdown' });
    this._notify({
      type: 'levelclear',
      clearedStage: clearedStage,
      level: this.levelNumber,
      levelCount: this.levelCount,
      bonus: bonus,
      score: this.score
    });
  };

  /** 调度一次延时翻回；已有挂起任务时不再重复调度。 */
  GameViewModel.prototype._scheduleFlipBack = function (delayMs) {
    if (this._pendingTimerToken !== null) {
      return;
    }

    var wait = delayMs == null ? this.mismatchFlipDelay * 1000 : Math.max(0, delayMs);
    var token = 'token-' + (GameViewModel._tokenSeed += 1);
    this._pendingTimerToken = token;
    this._flipDeadline = this._now() + wait;

    var self = this;
    this._flipTimerId = this.timers.setTimeout(function () {
      self._flipTimerId = null;
      // 令牌不匹配的回调视为过期，直接丢弃。
      if (self._pendingTimerToken !== token) {
        return;
      }
      self.completeMismatchFlipBack();
    }, wait);
  };

  GameViewModel.prototype._stopFlipTimer = function () {
    if (this._flipTimerId !== null) {
      this.timers.clearTimeout(this._flipTimerId);
      this._flipTimerId = null;
    }
  };

  GameViewModel.prototype._scheduleCountdownTicks = function () {
    var self = this;
    this._stopClock();
    this._clockTimerId = this.timers.setInterval(function () {
      self.tickCountdown();
    }, CountdownDefaults.tickInterval);
  };

  GameViewModel.prototype._stopClock = function () {
    if (this._clockTimerId !== null) {
      this.timers.clearInterval(this._clockTimerId);
      this._clockTimerId = null;
    }
  };

  GameViewModel.prototype._finishCountdown = function () {
    this._stopClock();
    this.peekRemaining = 0;
    this.endPeek();
    this.countdownRemaining = 0;
    this.didTimeOut = true;
    this.countdownState = 'finished';
    this.isInteractionLocked = true;
    this.resultReason = 'timeout';
    this._notify({ type: 'timeout' });
  };

  /**
   * 通关时停表：只停时钟，保留剩余秒数与总时长，
   * 这样「再来一局」仍能按原时长重新开始。
   *
   * 注：Swift 原版通关后倒计时会继续走到底，这里按需求改为立即停止，
   * 属于明确要求的行为调整，配对的计分与判定逻辑未变。
   */
  GameViewModel.prototype._haltCountdownOnWin = function () {
    if (this.countdownState !== 'running' && this.countdownState !== 'paused') {
      return;
    }
    this._stopClock();
    this.endPeek();
    this.countdownState = 'stopped';
    this._notify({ type: 'countdown' });
  };

  /** 重开一局时如果倒计时曾经启动过，则按原时长重新计时。 */
  GameViewModel.prototype._restartCountdownIfNeeded = function () {
    if (this._countdownDuration > 0) {
      this.startCountdown(this._countdownDuration);
    }
  };

  /** 把模型状态同步到对外发布的属性，触发视图刷新。 */
  GameViewModel.prototype._syncFromGame = function () {
    this.cards = this.game.cards;
    // 连击奖励是「model 之外的附加分」，必须在这里并入总分，
    // 否则闯关累加、结算提交、最高分比较都会漏掉它。
    this.score = this._carryScore + this.game.score + this.comboBonus;
  };

  GameViewModel._tokenSeed = 0;

  return {
    GameViewModel: GameViewModel,
    CountdownDefaults: CountdownDefaults,
    DEFAULT_MISMATCH_FLIP_DELAY: DEFAULT_MISMATCH_FLIP_DELAY
  };
}));
