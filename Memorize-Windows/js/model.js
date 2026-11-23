/*
 * Memorize 核心模型 —— Swift 版 Card / Theme / Game 的等价移植。
 *
 * 移植原则：只换语言，不换规则。所有判定顺序、扣分条件、边界处理
 * 均与 day8/Memorize/Models/*.swift 保持一致，逐条对照见 README 的
 * 「行为对照表」。
 *
 * 运行环境：浏览器（挂到 window.MemorizeModel）与 Node（module.exports）
 * 共用同一份代码，因此用 UMD 包裹，便于用 Node 直接跑回归测试。
 */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.MemorizeModel = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var idSeed = 0;

  function nextCardId() {
    idSeed += 1;
    return 'card-' + idSeed;
  }

  /** 把卡片对数限制在 1...可用数量 的范围内（对应 Swift 的 Game.clamp）。 */
  function clamp(pairs, emojiCount) {
    return Math.max(1, Math.min(pairs, emojiCount));
  }

  /**
   * 洗牌：Fisher-Yates。Swift 的 Array.shuffle() 采用同一算法，
   * 因此随机均匀性与原版一致。rng 可注入，便于测试复现同一牌序。
   */
  function shuffleInPlace(list, rng) {
    var random = rng || Math.random;
    for (var i = list.length - 1; i > 0; i -= 1) {
      var j = Math.floor(random() * (i + 1));
      var tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }

  /**
   * 卡片：一张卡片只有唯一 id 与固定内容，翻转与配对属于可变状态。
   */
  function Card(content, options) {
    var opts = options || {};
    var trimmed = String(content == null ? '' : content).trim();

    // 对应 Swift 的 precondition(!trimmedContent.isEmpty)
    if (!trimmed) {
      throw new Error('卡片内容不能为空');
    }

    this.id = opts.id || nextCardId();
    this.content = trimmed;
    this.isFaceUp = opts.isFaceUp === true;
    this.isMatched = opts.isMatched === true;
  }

  /** 同一张卡片（id 相同）视为相等，翻转/配对状态不参与比较。 */
  Card.prototype.equals = function (other) {
    return other instanceof Card && other.id === this.id;
  };

  /**
   * 主题：定义一局游戏使用的 emoji 集合与配色。
   *
   * 校验规则（对应 Swift Theme.init 的 throws）：
   * - 名称去除首尾空白后不能为空；
   * - emoji 集合去除空白项后至少保留一个；
   * - 卡片对数必须大于 0，且不超过可用 emoji 数量（超出时截断）。
   */
  function Theme(options) {
    var opts = options || {};

    var trimmedName = String(opts.name == null ? '' : opts.name).trim();
    if (!trimmedName) {
      throw new Error('主题名称不能为空');
    }

    var cleanedEmojis = (opts.emojis || [])
      .map(function (emoji) { return String(emoji).trim(); })
      .filter(function (emoji) { return emoji !== ''; });

    if (cleanedEmojis.length === 0) {
      throw new Error('主题至少需要一个 emoji');
    }

    var requestedPairs = opts.numberOfPairs == null ? cleanedEmojis.length : opts.numberOfPairs;
    if (!(requestedPairs > 0)) {
      throw new Error('卡片对数必须大于 0，当前为 ' + requestedPairs);
    }

    this.id = opts.id || ('theme-' + trimmedName);
    this.name = trimmedName;
    this.emojis = cleanedEmojis;
    this.color = opts.color || '#007AFF';
    this.numberOfPairs = Math.min(requestedPairs, cleanedEmojis.length);
  }

  /**
   * 内置主题，与 Swift 版 Theme.builtIn 完全一致：6 个主题，各 8 个 emoji，
   * 默认 8 对即 16 张卡片。颜色取 iOS 系统色对应的十六进制值。
   */
  Theme.builtIn = [
    new Theme({
      name: '动物',
      emojis: ['🐶', '🐱', '🐭', '🐹', '🐰', '🐻', '🐼', '🐨'],
      color: '#FF9500'
    }),
    new Theme({
      name: '运动',
      emojis: ['⚽️', '🏀', '🏈', '⚾️', '🎾', '🏐', '🏓', '🏸'],
      color: '#34C759'
    }),
    new Theme({
      name: '表情',
      emojis: ['😀', '😅', '🥲', '😍', '🤔', '😴', '🥳', '😎'],
      color: '#FFCC00'
    }),
    new Theme({
      name: '旗帜',
      emojis: ['🇨🇳', '🇯🇵', '🇰🇷', '🇫🇷', '🇩🇪', '🇮🇹', '🇪🇸', '🇬🇧'],
      color: '#FF3B30'
    }),
    new Theme({
      name: '天气',
      emojis: ['☀️', '🌤', '☁️', '🌧', '⛈', '❄️', '🌪', '🌈'],
      color: '#007AFF'
    }),
    new Theme({
      name: '食物',
      emojis: ['🍎', '🍌', '🍇', '🍓', '🍑', '🍍', '🥝', '🍒'],
      color: '#FF2D55'
    })
  ];

  /**
   * 牌局模型：维护卡片数组、当前翻开的卡片与得分，不依赖任何 UI 框架。
   *
   * 规则（与 Swift 版 Game 一致）：
   * - 每对对子的内容相同，牌组由 makeDeck 生成并按需洗牌；
   * - 每次只允许一张卡片处于「待配对」状态，翻开第二张时立即判定；
   * - 配对成功：两张卡片保持正面，得分 +2；
   * - 配对失败：两张卡片先保持正面，延时后由 flipBackMismatch() 翻回；
   *   若其中任一张在本局中已经翻看过，得分 -1；
   * - 已配对或已翻开的卡片再次点击会被忽略。
   */
  function Game(theme, numberOfPairs, shuffle) {
    if (shuffle === undefined) {
      shuffle = true;
    }

    var pairs = clamp(
      numberOfPairs == null ? theme.numberOfPairs : numberOfPairs,
      theme.emojis.length
    );

    this.theme = theme;
    this.numberOfPairs = pairs;
    this.cards = Game.makeDeck(theme.emojis, pairs, shuffle);
    this.score = 0;
    this.indexOfFaceUpCard = null;
    this._seenCardIDs = new Set();
    this._mismatchedCardIDs = [];
  }

  /**
   * 生成牌组：每个 emoji 生成两张卡片，可选洗牌。
   */
  Game.makeDeck = function (emojis, numberOfPairs, shuffle, rng) {
    if (shuffle === undefined) {
      shuffle = true;
    }

    var pairs = clamp(numberOfPairs, emojis.length);
    var selected = emojis.slice(0, pairs);
    var deck = [];

    for (var i = 0; i < selected.length; i += 1) {
      deck.push(new Card(selected[i]));
      deck.push(new Card(selected[i]));
    }

    if (shuffle) {
      shuffleInPlace(deck, rng);
    }
    return deck;
  };

  Object.defineProperty(Game.prototype, 'isGameOver', {
    get: function () {
      return this.cards.length > 0 && this.cards.every(function (card) {
        return card.isMatched;
      });
    }
  });

  Object.defineProperty(Game.prototype, 'hasPendingMismatch', {
    get: function () {
      return this._mismatchedCardIDs.length > 0;
    }
  });

  Object.defineProperty(Game.prototype, 'matchedPairsCount', {
    get: function () {
      var matched = this.cards.filter(function (card) {
        return card.isMatched;
      }).length;
      return Math.floor(matched / 2);
    }
  });

  /**
   * 翻开一张卡片。若这是本回合第二张，则立即判定配对结果。
   *
   * 配对失败时两张卡片保持正面，由调用方在延时结束后调用
   * flipBackMismatch() 翻回，以便视图层展示「错配延时翻回」效果。
   */
  Game.prototype.choose = function (card) {
    var index = -1;
    for (var i = 0; i < this.cards.length; i += 1) {
      if (this.cards[i].id === card.id) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      return;
    }

    // 已配对或已翻开的卡片再次点击会被忽略。
    if (this.cards[index].isMatched || this.cards[index].isFaceUp) {
      return;
    }

    // 上一回合的错配卡片尚未翻回时先复位，保证同一时刻最多两张正面。
    this.flipBackMismatch();
    this.cards[index].isFaceUp = true;

    var firstIndex = this.indexOfFaceUpCard;
    if (firstIndex === null || firstIndex === index) {
      this.indexOfFaceUpCard = index;
      return;
    }

    if (this.cards[firstIndex].content === this.cards[index].content) {
      // 配对成功：两张都标记为已配对并保持正面。
      this.cards[firstIndex].isMatched = true;
      this.cards[index].isMatched = true;
      this.score += 2;
    } else {
      // 配对失败：只要任一张之前翻看过，就扣 1 分；两张保持正面等待翻回。
      var hasSeenBefore = this._seenCardIDs.has(this.cards[firstIndex].id)
        || this._seenCardIDs.has(this.cards[index].id);
      if (hasSeenBefore) {
        this.score -= 1;
      }
      this._mismatchedCardIDs = [this.cards[firstIndex].id, this.cards[index].id];
    }

    this._seenCardIDs.add(this.cards[firstIndex].id);
    this._seenCardIDs.add(this.cards[index].id);
    this.indexOfFaceUpCard = null;
  };

  /** 把错配的卡片翻回背面。无待翻回卡片时调用不会有任何变化。 */
  Game.prototype.flipBackMismatch = function () {
    if (this._mismatchedCardIDs.length === 0) {
      return;
    }

    for (var i = 0; i < this._mismatchedCardIDs.length; i += 1) {
      var id = this._mismatchedCardIDs[i];
      for (var j = 0; j < this.cards.length; j += 1) {
        if (this.cards[j].id === id) {
          this.cards[j].isFaceUp = false;
          break;
        }
      }
    }
    this._mismatchedCardIDs = [];
  };

  /** 使用当前主题重新开始一局。 */
  Game.prototype.newGame = function (shuffle) {
    if (shuffle === undefined) {
      shuffle = true;
    }
    this._reset(this.theme, this.numberOfPairs, shuffle);
  };

  /** 切换主题并重新开始一局。 */
  Game.prototype.startNewGame = function (newTheme, shuffle) {
    if (shuffle === undefined) {
      shuffle = true;
    }
    this._reset(
      newTheme,
      clamp(newTheme.numberOfPairs, newTheme.emojis.length),
      shuffle
    );
  };

  /** 重置牌局状态。 */
  Game.prototype._reset = function (newTheme, pairs, shuffle) {
    this.theme = newTheme;
    this.numberOfPairs = pairs;
    this.cards = Game.makeDeck(newTheme.emojis, pairs, shuffle);
    this.score = 0;
    this.indexOfFaceUpCard = null;
    this._seenCardIDs.clear();
    this._mismatchedCardIDs = [];
  };

  return {
    Card: Card,
    Theme: Theme,
    Game: Game,
    clamp: clamp,
    shuffleInPlace: shuffleInPlace,
    resetCardIdSeed: function () { idSeed = 0; }
  };
}));
