/*
 * Memorize 玩法配置 —— 难度档位与闯关关卡的唯一数据源。
 *
 * 设计约束（重要）：
 * - 「经典」档必须与移植时的冻结参数逐项相同：60 秒 / 8 对 / 错配翻回 0.8 秒。
 *   也就是说，默认配置下的判定、计分、时长与原游戏完全一致，
 *   新增难度只是在外围增加可选档位，不改变原有玩法。
 * - 这里只放纯数据与纯函数，不碰 DOM、不碰计时器，便于 Node 直接跑单测。
 */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.MemorizeConfig = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /**
   * 三档难度。字段含义：
   * - duration：本局倒计时秒数；
   * - pairs：卡片对数（受主题 emoji 数量上限约束，当前每套主题 8 个）；
   * - mismatchFlipDelay：错配后保持正面的秒数，越短越难；
   * - peek：每关允许「长按偷看」的次数；
   * - penalty / reward：保持不变（+2 / -1），难度只调参数不调规则。
   */
  var DIFFICULTIES = [
    {
      id: 'easy',
      name: '轻松',
      tagline: '90 秒 · 6 对 · 错配翻回 1.0 秒',
      duration: 90,
      pairs: 6,
      mismatchFlipDelay: 1.0,
      peek: 4
    },
    {
      id: 'classic',
      name: '经典',
      tagline: '60 秒 · 8 对 · 错配翻回 0.8 秒（原始参数）',
      duration: 60,
      pairs: 8,
      mismatchFlipDelay: 0.8,
      peek: 3
    },
    {
      id: 'hard',
      name: '挑战',
      tagline: '45 秒 · 8 对 · 错配翻回 0.6 秒 · 连击加成',
      duration: 45,
      pairs: 8,
      mismatchFlipDelay: 0.6,
      peek: 2
    }
  ];

  /**
   * 闯关模式：三关递进，共用一条倒计时。
   *
   * 为什么共用一条表而不是每关重置：
   * - 每关重置会让三关退化成「连玩三局」，时间压力不累积，缺少递进感；
   * - 共用一条表时，前面拖沓会直接吃掉最后一关的时间，选择「快还是稳」才有意义；
   * - 每过一关补 8 秒，既奖励推进，又不至于让慢节奏玩家直接卡死。
   */
  var CAMPAIGN = {
    id: 'campaign',
    name: '闯关',
    timeBudget: 150,   // 三关共用的初始秒数
    clearBonus: 8,     // 每过一关补时（秒）
    stageCount: 3,
    stages: [
      { pairs: 6, mismatchFlipDelay: 0.85, peek: 3 },
      { pairs: 7, mismatchFlipDelay: 0.75, peek: 2 },
      { pairs: 8, mismatchFlipDelay: 0.65, peek: 2 }
    ]
  };

  /**
   * 连击加成 —— 挑战档专属。
   *
   * 设计约束：基础分 +2 是冻结参数，不能为了「倍数好看」把基数改大。
   * 因此这里按「倍率 × 2」计算应得分数，再用余数结转（carry）消掉小数：
   *   ×1.25 时单次应得 2.5 分 → 实得 2 分、余 0.5；下一次 2.5 + 0.5 = 3 分、余 0。
   * 连续两次平均正好 2.5 分，长期平均严格等于倍率，分数永远是整数，
   * 也不会因为四舍五入让 ×1.25 和 ×1.5 变成同一个值（2.5 与 3 会被区分开）。
   *
   * 中断与上限：
   * - 任何一次错配（无论是否扣分）立即清零连击与余数；
   * - 暂停、点已配对卡片、无效点击都不算中断；
   * - 倍率上限 ×1.5（连击第 3 次起不再增长），避免滚雪球。
   */
  var COMBO = {
    enabled: true,
    /** 只有「经典模式 + 挑战难度」开启；闯关模式没有难度档，不参与。 */
    difficulties: ['hard'],
    base: 2,
    maxMultiplier: 1.5,
    /** 连击达到该次数才显示 UI（第 2 次才开始有加成）。 */
    visibleFrom: 2,
    tiers: [
      { streak: 1, multiplier: 1 },
      { streak: 2, multiplier: 1.25 },
      { streak: 3, multiplier: 1.5 }
    ]
  };

  /**
   * 助记难度自适应 —— 保守版。
   *
   * 只做一件事：根据「每张牌从首次翻看到被配上」的平均反应时间，
   * 微调错配翻回时长（玩家反应慢 → 拉长一点，给回忆留时间；反应快 → 缩短一点）。
   *
   * 保守体现在四处：
   * 1. 只作用于「经典模式 + 轻松/经典档」，挑战档有连击加成，不再叠加第二套变量；
   * 2. 样本不足 minSamples 条时完全不调整（避免开局几把就乱变）；
   * 3. 单次调整量化到 step，总幅度硬夹在 ±maxDelta（0.15 秒）以内；
   * 4. 只在「新开一局 / 换关」时生效，绝不在一局中途改动判定节奏。
   * 回退：ADAPTIVE.enabled = false 即可整体关闭（也可用 ?adaptive=0 临时关闭）。
   */
  var ADAPTIVE = {
    enabled: true,
    applyTo: ['easy', 'classic'],
    windowSize: 20,
    minSamples: 8,
    step: 0.05,
    maxDelta: 0.15,
    /** 目标平均反应时间（毫秒）：低于它说明玩家偏快，高于它说明偏慢。 */
    targetLatencyMs: 2600,
    /** 平均反应每偏离目标 1 秒，翻回时长同向调整 0.08 秒。 */
    gainPerSecond: 0.08,
    minDelay: 0.35,
    maxDelay: 1.4
  };

  var MODES = [
    { id: 'classic', name: '经典', tagline: '单局挑战，清空一副牌' },
    { id: 'campaign', name: '闯关', tagline: '连续三关，共享一条倒计时' }
  ];

  /** 按 id 取难度档；未知 id 回落到经典档（保证永远有可用配置）。 */
  function findDifficulty(id) {
    for (var i = 0; i < DIFFICULTIES.length; i += 1) {
      if (DIFFICULTIES[i].id === id) {
        return DIFFICULTIES[i];
      }
    }
    return DIFFICULTIES[1];
  }

  function findMode(id) {
    for (var i = 0; i < MODES.length; i += 1) {
      if (MODES[i].id === id) {
        return MODES[i];
      }
    }
    return MODES[0];
  }

  /**
   * 解析某一关的完整参数。
   *
   * @param {string} mode         'classic' | 'campaign'
   * @param {string} difficultyId 难度 id，仅经典模式生效
   * @param {number} [stageIndex] 关卡下标，从 0 开始
   * @returns {{mode:string, pairs:number, duration:number,
   *            mismatchFlipDelay:number, stage:number, stageCount:number}}
   */
  function resolveRound(mode, difficultyId, stageIndex) {
    var difficulty = findDifficulty(difficultyId);

    if (mode === 'campaign') {
      var index = Math.floor(Number(stageIndex) || 0);
      if (index < 0) {
        index = 0;
      }
      if (index > CAMPAIGN.stageCount - 1) {
        index = CAMPAIGN.stageCount - 1;
      }
      var stage = CAMPAIGN.stages[index];
      return {
        mode: 'campaign',
        pairs: stage.pairs,
        // 闯关只在开局用一次时长，后续关卡靠补时推进
        duration: CAMPAIGN.timeBudget,
        mismatchFlipDelay: stage.mismatchFlipDelay,
        peek: stage.peek,
        stage: index + 1,
        stageCount: CAMPAIGN.stageCount
      };
    }

    return {
      mode: 'classic',
      pairs: difficulty.pairs,
      duration: difficulty.duration,
      mismatchFlipDelay: difficulty.mismatchFlipDelay,
      peek: difficulty.peek,
      stage: 1,
      stageCount: 1
    };
  }

  // ---------------- 连击 ----------------

  /** 连击第 streak 次配对成功时适用的倍率；1 次为 ×1，封顶 ×1.5。 */
  function comboMultiplier(streak) {
    var count = Math.floor(Number(streak) || 0);
    if (count <= 1) {
      return 1;
    }
    if (count === 2) {
      return 1.25;
    }
    return COMBO.maxMultiplier;
  }

  /** 该「模式 + 难度」组合是否开启连击加成。 */
  function isComboMode(mode, difficultyId) {
    if (!COMBO.enabled || mode !== 'classic') {
      return false;
    }
    return COMBO.difficulties.indexOf(String(difficultyId)) >= 0;
  }

  /**
   * 一次配对成功应得的「带倍率分数」与结转余数。
   * @returns {{multiplier:number, award:number, whole:number, carry:number}}
   */
  function comboAward(streak, carry) {
    var multiplier = comboMultiplier(streak);
    var award = COMBO.base * multiplier + (Number(carry) || 0);
    var whole = Math.floor(award + 1e-9);
    return {
      multiplier: multiplier,
      award: award,
      whole: whole,
      carry: Math.round((award - whole) * 1000) / 1000
    };
  }

  // ---------------- 自适应翻回时长 ----------------

  /**
   * 根据平均反应时间算出翻回时长的偏移量（秒），可正可负。
   * 样本不足、数据非法或开关关闭时返回 0（完全等同于原始参数）。
   */
  function adaptiveAdjust(averageMs, sampleCount) {
    if (!ADAPTIVE.enabled) {
      return 0;
    }
    var count = Math.floor(Number(sampleCount) || 0);
    if (count < ADAPTIVE.minSamples) {
      return 0;
    }
    var avg = Number(averageMs);
    if (!isFinite(avg) || avg <= 0) {
      return 0;
    }
    var raw = ((avg - ADAPTIVE.targetLatencyMs) / 1000) * ADAPTIVE.gainPerSecond;
    var clamped = Math.max(-ADAPTIVE.maxDelta, Math.min(ADAPTIVE.maxDelta, raw));
    var stepped = Math.round(clamped / ADAPTIVE.step) * ADAPTIVE.step;
    // 归一到 3 位小数，避免 0.30000000000000004 这类浮点噪声写进 diff
    return Math.round(stepped * 1000) / 1000;
  }

  /** 把偏移量叠加到基础翻回时长上，并夹在安全区间内。 */
  function effectiveDelay(base, adjust) {
    // 总开关关闭时必须「完全等同原始参数」，不能残留上一轮的偏移
    if (!ADAPTIVE.enabled) {
      return base;
    }
    var value = Number(base) + (Number(adjust) || 0);
    if (!isFinite(value)) {
      return base;
    }
    var bounded = Math.max(ADAPTIVE.minDelay, Math.min(ADAPTIVE.maxDelay, value));
    return Math.round(bounded * 1000) / 1000;
  }

  /** 该「模式 + 难度」是否允许自适应微调。 */
  function isAdaptiveMode(mode, difficultyId) {
    if (!ADAPTIVE.enabled || mode !== 'classic') {
      return false;
    }
    return ADAPTIVE.applyTo.indexOf(String(difficultyId)) >= 0;
  }

  return {
    DIFFICULTIES: DIFFICULTIES,
    MODES: MODES,
    CAMPAIGN: CAMPAIGN,
    COMBO: COMBO,
    ADAPTIVE: ADAPTIVE,
    findDifficulty: findDifficulty,
    findMode: findMode,
    resolveRound: resolveRound,
    comboMultiplier: comboMultiplier,
    comboAward: comboAward,
    isComboMode: isComboMode,
    adaptiveAdjust: adaptiveAdjust,
    effectiveDelay: effectiveDelay,
    isAdaptiveMode: isAdaptiveMode
  };
}));
