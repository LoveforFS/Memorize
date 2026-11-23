/*
 * Memorize 本地存档 —— 最高分与偏好（音量开关、上次选择的模式/难度）。
 *
 * 为什么要包一层：
 * - 直接调用 localStorage 在隐私模式、file:// 受限策略或某些嵌入式浏览器里会抛
 *   SecurityError / QuotaExceededError，一旦抛错整个脚本就会中断，游戏直接打不开；
 * - 因此统一走 try/catch，失败时自动退回内存存储：功能照常可用，只是关掉页面后
 *   记录不保留（界面里会显示「本次会话」提示，不谎称已持久化）。
 *
 * 这个模块不依赖 DOM，可以在 Node 里用假 storage 直接测。
 */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.MemorizeStore = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var KEY_BEST = 'memorize.v1.best';
  var KEY_PREFS = 'memorize.v1.prefs';
  /*
   * v2 新增两个键，与 v1 的键共存，因此老存档不需要迁移、也不会被覆盖：
   * - history：最近若干局的成绩明细（数组，最新在前）；
   * - timing：助记自适应用的反应时间样本（数组，最新在后）。
   */
  var KEY_HISTORY = 'memorize.v2.history';
  var KEY_TIMING = 'memorize.v2.timing';

  /** 历史只保留最近 20 局：既能回看趋势，又不会把存储撑大。 */
  var MAX_HISTORY = 20;
  /** 反应时间样本只保留最近 40 条（每局最多贡献 2 条左右）。 */
  var MAX_TIMING = 40;

  /** 内存兜底：接口与 Storage 一致的最小子集。 */
  function MemoryStorage() {
    this._data = {};
  }

  MemoryStorage.prototype.getItem = function (key) {
    return Object.prototype.hasOwnProperty.call(this._data, key) ? this._data[key] : null;
  };

  MemoryStorage.prototype.setItem = function (key, value) {
    this._data[key] = String(value);
  };

  MemoryStorage.prototype.removeItem = function (key) {
    delete this._data[key];
  };

  /**
   * 探测 localStorage 是否真的可写。
   * 仅判断「对象存在」不够：Safari 隐私模式下对象存在但 setItem 抛异常。
   */
  function probeStorage(candidate) {
    if (!candidate) {
      return null;
    }
    try {
      var probe = '__memorize_probe__';
      candidate.setItem(probe, '1');
      candidate.removeItem(probe);
      return candidate;
    } catch (error) {
      return null;
    }
  }

  function defaultStorage() {
    try {
      if (typeof localStorage !== 'undefined') {
        return probeStorage(localStorage);
      }
    } catch (error) {
      return null;
    }
    return null;
  }

  function safeParse(raw, fallback) {
    if (!raw) {
      return fallback;
    }
    try {
      var parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? parsed : fallback;
    } catch (error) {
      return fallback;
    }
  }

  /**
   * @param {Storage} [storage] 可注入的存储实现；不传则自动探测 localStorage
   */
  function ScoreStore(storage) {
    var resolved = storage === undefined ? defaultStorage() : storage;
    this.persistent = !!probeStorage(resolved);
    this._storage = this.persistent ? resolved : new MemoryStorage();
  }

  ScoreStore.prototype._readAll = function (key) {
    try {
      return safeParse(this._storage.getItem(key), {});
    } catch (error) {
      return {};
    }
  };

  ScoreStore.prototype._writeAll = function (key, value) {
    try {
      this._storage.setItem(key, JSON.stringify(value));
      return true;
    } catch (error) {
      return false;
    }
  };

  /** 读取一个数组型存档；任何异常/脏数据都退回空数组，绝不抛错。 */
  ScoreStore.prototype._readArray = function (key) {
    try {
      var parsed = safeParse(this._storage.getItem(key), []);
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  };

  function bestKey(mode, difficultyId) {
    return String(mode || 'classic') + ':' + String(difficultyId || 'classic');
  }

  /** 读取某个模式 + 难度的最高分；没有记录时返回 null（与 0 分区分开）。 */
  ScoreStore.prototype.getBest = function (mode, difficultyId) {
    var all = this._readAll(KEY_BEST);
    var value = all[bestKey(mode, difficultyId)];
    return typeof value === 'number' && isFinite(value) ? value : null;
  };

  /**
   * 提交一局成绩，只有更高才写入。
   * @returns {{best:number, isNewRecord:boolean, previous:number|null}}
   */
  ScoreStore.prototype.submit = function (mode, difficultyId, score) {
    var current = this.getBest(mode, difficultyId);
    var value = Math.floor(Number(score) || 0);

    if (current === null || value > current) {
      var all = this._readAll(KEY_BEST);
      all[bestKey(mode, difficultyId)] = value;
      this._writeAll(KEY_BEST, all);
      return { best: value, isNewRecord: current !== null, previous: current };
    }

    return { best: current, isNewRecord: false, previous: current };
  };

  /** 读取偏好；缺字段时用传入的默认值补齐，调用方不必自己做兜底。 */
  ScoreStore.prototype.getPrefs = function (defaults) {
    var base = defaults || {};
    var stored = this._readAll(KEY_PREFS);
    return {
      sound: stored.sound === undefined ? base.sound !== false : stored.sound === true,
      haptic: stored.haptic === undefined ? base.haptic !== false : stored.haptic === true,
      adaptive: stored.adaptive === undefined ? base.adaptive !== false : stored.adaptive === true,
      mode: typeof stored.mode === 'string' ? stored.mode : (base.mode || 'classic'),
      difficulty: typeof stored.difficulty === 'string'
        ? stored.difficulty
        : (base.difficulty || 'classic')
    };
  };

  ScoreStore.prototype.setPrefs = function (patch) {
    var current = this.getPrefs({});
    var next = {
      sound: patch && patch.sound !== undefined ? patch.sound === true : current.sound,
      haptic: patch && patch.haptic !== undefined ? patch.haptic === true : current.haptic,
      adaptive: patch && patch.adaptive !== undefined ? patch.adaptive === true : current.adaptive,
      mode: patch && patch.mode ? patch.mode : current.mode,
      difficulty: patch && patch.difficulty ? patch.difficulty : current.difficulty
    };
    this._writeAll(KEY_PREFS, next);
    return next;
  };

  // ---------------- 最近对局 ----------------

  /**
   * 规范化一条历史记录。
   * 存档是用户可编辑的（也可被旧版本写坏），因此读出来一律重建字段，
   * 数字字段强制转数值、字符串字段强制转字符串，缺失就给中性默认值。
   */
  function normalizeRecord(raw) {
    if (!raw || typeof raw !== 'object') {
      return null;
    }
    var score = Number(raw.score);
    if (!isFinite(score)) {
      return null;
    }
    return {
      mode: raw.mode === 'campaign' ? 'campaign' : 'classic',
      difficulty: typeof raw.difficulty === 'string' ? raw.difficulty : 'classic',
      score: Math.round(score),
      reason: raw.reason === 'timeout' ? 'timeout' : 'win',
      stage: Math.max(1, Math.floor(Number(raw.stage) || 1)),
      stageCount: Math.max(1, Math.floor(Number(raw.stageCount) || 1)),
      pairs: Math.max(0, Math.floor(Number(raw.pairs) || 0)),
      matched: Math.max(0, Math.floor(Number(raw.matched) || 0)),
      combo: Math.max(0, Math.floor(Number(raw.combo) || 0)),
      at: Math.max(0, Math.floor(Number(raw.at) || 0))
    };
  }

  /**
   * 追加一局成绩。数组最新在前，超过上限时丢弃最旧的。
   * @param {object} entry 至少包含 score；其余字段缺失会被补成中性值
   * @returns {{records:Array, saved:boolean}}
   */
  ScoreStore.prototype.addRecord = function (entry) {
    var record = normalizeRecord(entry);
    if (!record) {
      return { records: this.getHistory(), saved: false };
    }
    var list = this.getHistory();
    list.unshift(record);
    if (list.length > MAX_HISTORY) {
      list = list.slice(0, MAX_HISTORY);
    }
    var saved = this._writeAll(KEY_HISTORY, list);
    return { records: list, saved: saved };
  };

  /** 读取历史记录（最新在前）；limit 用于只要前 N 条。 */
  ScoreStore.prototype.getHistory = function (limit) {
    var raw = this._readArray(KEY_HISTORY);
    var list = [];
    for (var i = 0; i < raw.length && list.length < MAX_HISTORY; i += 1) {
      var record = normalizeRecord(raw[i]);
      if (record) {
        list.push(record);
      }
    }
    if (limit == null) {
      return list;
    }
    var count = Math.max(0, Math.floor(Number(limit) || 0));
    return list.slice(0, count);
  };

  ScoreStore.prototype.clearHistory = function () {
    try {
      this._storage.removeItem(KEY_HISTORY);
      return true;
    } catch (error) {
      return false;
    }
  };

  // ---------------- 反应时间样本（自适应用） ----------------

  /** 读取样本（旧 → 新），只保留合法正数。 */
  ScoreStore.prototype.getTimings = function () {
    var raw = this._readArray(KEY_TIMING);
    var list = [];
    for (var i = 0; i < raw.length; i += 1) {
      var value = Number(raw[i]);
      if (isFinite(value) && value > 0) {
        list.push(Math.round(value));
      }
    }
    return list;
  };

  /** 追加一条样本，超出窗口时从最旧的开始丢。 */
  ScoreStore.prototype.addTimings = function (samples) {
    var list = this.getTimings();
    var input = Array.isArray(samples) ? samples : [samples];
    for (var i = 0; i < input.length; i += 1) {
      var value = Number(input[i]);
      if (isFinite(value) && value > 0) {
        list.push(Math.round(value));
      }
    }
    if (list.length > MAX_TIMING) {
      list = list.slice(list.length - MAX_TIMING);
    }
    this._writeAll(KEY_TIMING, list);
    return list;
  };

  ScoreStore.prototype.clearTimings = function () {
    try {
      this._storage.removeItem(KEY_TIMING);
      return true;
    } catch (error) {
      return false;
    }
  };

  return {
    ScoreStore: ScoreStore,
    MemoryStorage: MemoryStorage,
    KEY_BEST: KEY_BEST,
    KEY_PREFS: KEY_PREFS,
    KEY_HISTORY: KEY_HISTORY,
    KEY_TIMING: KEY_TIMING,
    MAX_HISTORY: MAX_HISTORY,
    MAX_TIMING: MAX_TIMING
  };
}));
