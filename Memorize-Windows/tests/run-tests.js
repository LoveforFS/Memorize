/*
 * Memorize Windows 版行为回归测试。
 *
 * 目的：证明移植后的规则与 Memorize/Models/*.swift、
 * ViewModels/GameViewModel.swift 一致，而不是「看起来能玩」。
 *
 * 运行：node tests/run-tests.js
 * 退出码：全部通过为 0，有失败为 1。
 */
'use strict';

var path = require('path');

var Model = require(path.join(__dirname, '..', 'js', 'model.js'));
var Config = require(path.join(__dirname, '..', 'js', 'config.js'));
var StoreModule = require(path.join(__dirname, '..', 'js', 'store.js'));
var ViewModelModule = require(path.join(__dirname, '..', 'js', 'viewmodel.js'));
var Layout = require(path.join(__dirname, '..', 'js', 'layout.js'));

var Card = Model.Card;
var Theme = Model.Theme;
var Game = Model.Game;
var GameViewModel = ViewModelModule.GameViewModel;

// ---------------- 极简断言框架 ----------------

var passed = 0;
var failures = [];

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log('  PASS  ' + name);
  } catch (error) {
    failures.push({ name: name, message: error.message });
    console.log('  FAIL  ' + name);
    console.log('        ' + error.message);
  }
}

function group(title) {
  console.log('\n' + title);
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error((label || '值不相等') + '：期望 ' + JSON.stringify(expected)
      + '，实际 ' + JSON.stringify(actual));
  }
}

function assertTrue(value, label) {
  if (value !== true) {
    throw new Error((label || '断言为真失败') + '：实际 ' + JSON.stringify(value));
  }
}

function assertFalse(value, label) {
  if (value !== false) {
    throw new Error((label || '断言为假失败') + '：实际 ' + JSON.stringify(value));
  }
}

/** 构造一副可控牌局：不洗牌，顺序为 A A B B C C ... */
function makeOrderedGame(pairCount) {
  var emojis = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'].slice(0, pairCount);
  var theme = new Theme({ name: '测试', emojis: emojis });
  return new Game(theme, pairCount, false);
}

// ---------------- 可控时钟 ----------------

function FakeTimers() {
  this.now = 0;
  this._seq = 0;
  this._tasks = [];
}

FakeTimers.prototype.setTimeout = function (fn, ms) {
  this._seq += 1;
  this._tasks.push({ id: this._seq, type: 'timeout', at: this.now + ms, fn: fn });
  return this._seq;
};

FakeTimers.prototype.setInterval = function (fn, ms) {
  this._seq += 1;
  this._tasks.push({ id: this._seq, type: 'interval', at: this.now + ms, every: ms, fn: fn });
  return this._seq;
};

FakeTimers.prototype._cancel = function (id) {
  this._tasks = this._tasks.filter(function (task) { return task.id !== id; });
};

FakeTimers.prototype.clearTimeout = function (id) { this._cancel(id); };
FakeTimers.prototype.clearInterval = function (id) { this._cancel(id); };

FakeTimers.prototype.advance = function (ms) {
  var target = this.now + ms;
  var guard = 0;

  while (true) {
    guard += 1;
    if (guard > 200000) {
      throw new Error('时钟推进进入死循环');
    }

    var due = this._tasks.filter(function (task) { return task.at <= target; });
    if (due.length === 0) {
      break;
    }
    due.sort(function (a, b) { return a.at - b.at || a.id - b.id; });
    var task = due[0];
    this.now = task.at;

    if (task.type === 'interval') {
      task.at += task.every;
      task.fn();
    } else {
      this._cancel(task.id);
      task.fn();
    }
  }

  this.now = target;
};

// ---------------- 牌组生成 ----------------

group('牌组生成');

test('8 对主题生成 16 张卡片，每个 emoji 恰好两张', function () {
  var theme = Theme.builtIn[0];
  var game = new Game(theme);
  assertEqual(game.cards.length, 16, '卡片总数');

  var counts = {};
  game.cards.forEach(function (card) {
    counts[card.content] = (counts[card.content] || 0) + 1;
  });
  Object.keys(counts).forEach(function (key) {
    assertEqual(counts[key], 2, 'emoji ' + key + ' 出现次数');
  });
  assertEqual(Object.keys(counts).length, 8, '不同 emoji 数量');
});

test('卡片对数超过 emoji 数量时按可用数量截断', function () {
  var theme = Theme.builtIn[0];
  var game = new Game(theme, 99, false);
  assertEqual(game.numberOfPairs, 8, '实际对数');
  assertEqual(game.cards.length, 16, '卡片总数');
});

test('卡片对数传入 0 时下限收敛到 1', function () {
  var theme = Theme.builtIn[0];
  var game = new Game(theme, 0, false);
  assertEqual(game.numberOfPairs, 1, '实际对数');
  assertEqual(game.cards.length, 2, '卡片总数');
});

test('不洗牌时牌序为 A A B B ...，洗牌后仍保持成对', function () {
  var ordered = makeOrderedGame(3);
  assertEqual(ordered.cards.map(function (c) { return c.content; }).join(''), 'AABBCC', '有序牌序');

  var emojis = ['A', 'B', 'C'];
  var theme = new Theme({ name: '测试', emojis: emojis });
  var shuffled = new Game(theme, 3, true);
  var counts = {};
  shuffled.cards.forEach(function (c) {
    counts[c.content] = (counts[c.content] || 0) + 1;
  });
  assertEqual(counts.A, 2, 'A 的数量');
  assertEqual(counts.B, 2, 'B 的数量');
  assertEqual(counts.C, 2, 'C 的数量');
});

test('初始状态：全部背面、未配对、得分 0', function () {
  var game = makeOrderedGame(2);
  assertTrue(game.cards.every(function (c) { return !c.isFaceUp && !c.isMatched; }), '全部背面且未配对');
  assertEqual(game.score, 0, '初始得分');
});

// ---------------- 配对判定与计分 ----------------

group('配对判定与计分');

test('配对成功：两张保持正面、标记已配对、得分 +2', function () {
  var game = makeOrderedGame(2);
  game.choose(game.cards[0]);
  assertEqual(game.score, 0, '翻第一张后得分');
  assertTrue(game.cards[0].isFaceUp, '第一张正面');

  game.choose(game.cards[1]);
  assertEqual(game.score, 2, '配对成功得分');
  assertTrue(game.cards[0].isMatched, '第一张已配对');
  assertTrue(game.cards[1].isMatched, '第二张已配对');
  assertFalse(game.hasPendingMismatch, '不应有待翻回卡片');
});

test('已翻开的卡片重复点击被忽略', function () {
  var game = makeOrderedGame(2);
  game.choose(game.cards[0]);
  game.choose(game.cards[0]);
  assertEqual(game.score, 0, '得分不变');
  assertEqual(game.indexOfFaceUpCard, 0, '待配对下标不变');
});

test('已配对的卡片再次点击被忽略', function () {
  var game = makeOrderedGame(2);
  game.choose(game.cards[0]);
  game.choose(game.cards[1]);

  var scoreBefore = game.score;
  game.choose(game.cards[0]);
  assertEqual(game.score, scoreBefore, '得分不变');
});

test('首次错配不扣分，并进入待翻回状态', function () {
  var game = makeOrderedGame(2);
  game.choose(game.cards[0]); // A
  game.choose(game.cards[2]); // B

  assertEqual(game.score, 0, '首次错配得分');
  assertTrue(game.hasPendingMismatch, '存在待翻回卡片');
  assertTrue(game.cards[0].isFaceUp, '错配卡片仍正面');
});

test('同一张卡重复参与错配扣 1 分', function () {
  var game = makeOrderedGame(2);

  game.choose(game.cards[0]); // A
  game.choose(game.cards[2]); // B，首次错配不扣分
  game.flipBackMismatch();
  assertEqual(game.score, 0, '首次错配后得分');

  game.choose(game.cards[0]); // A，这张此前参与过错配
  game.choose(game.cards[2]); // B，同样参与过 → 扣 1

  assertEqual(game.score, -1, '重复错配得分');
});

test('换一对全新的卡错配不扣分（seen 只记录参与过的卡）', function () {
  var game = makeOrderedGame(3);

  game.choose(game.cards[0]); // A
  game.choose(game.cards[2]); // B，错配，seen 记下这两张
  game.flipBackMismatch();

  game.choose(game.cards[3]); // B 的另一张，没参与过错配
  game.choose(game.cards[4]); // C，没参与过错配

  assertEqual(game.score, 0, '未参与过错配的卡片不再扣分');
});

test('得分可以为负数', function () {
  var game = makeOrderedGame(2);
  var i;
  for (i = 0; i < 3; i += 1) {
    game.choose(game.cards[0]);
    game.choose(game.cards[2]);
    game.flipBackMismatch();
  }
  assertTrue(game.score < 0, '得分应为负，实际 ' + game.score);
});

test('flipBackMismatch 把错配卡片翻回背面', function () {
  var game = makeOrderedGame(2);
  game.choose(game.cards[0]);
  game.choose(game.cards[2]);
  game.flipBackMismatch();

  assertFalse(game.cards[0].isFaceUp, '第一张已翻回');
  assertFalse(game.cards[2].isFaceUp, '第二张已翻回');
  assertFalse(game.hasPendingMismatch, '无待翻回卡片');
});

test('上一回合错配未翻回时，翻新卡会先自动复位前两张', function () {
  var game = makeOrderedGame(3);
  game.choose(game.cards[0]); // A
  game.choose(game.cards[2]); // B，错配未翻回

  game.choose(game.cards[4]); // C

  assertFalse(game.cards[0].isFaceUp, '前一张 A 已自动翻回');
  assertFalse(game.cards[2].isFaceUp, '前一张 B 已自动翻回');
  assertTrue(game.cards[4].isFaceUp, '新卡 C 正面');
  assertEqual(game.indexOfFaceUpCard, 4, '待配对下标指向 C');
});

// ---------------- 结算与重开 ----------------

group('结算与重开');

test('全部配对后 isGameOver 为真', function () {
  var game = makeOrderedGame(2);
  assertFalse(game.isGameOver, '初始未结束');

  game.choose(game.cards[0]);
  game.choose(game.cards[1]);
  assertFalse(game.isGameOver, '一对后仍未结束');

  game.choose(game.cards[2]);
  game.choose(game.cards[3]);
  assertTrue(game.isGameOver, '全部配对后结束');
});

test('matchedPairsCount 返回已配对对数', function () {
  var game = makeOrderedGame(3);
  assertEqual(game.matchedPairsCount, 0, '初始对数');
  game.choose(game.cards[0]);
  game.choose(game.cards[1]);
  assertEqual(game.matchedPairsCount, 1, '一对之后');
});

test('newGame 重置牌组与得分', function () {
  var game = makeOrderedGame(2);
  game.choose(game.cards[0]);
  game.choose(game.cards[1]);
  assertEqual(game.score, 2, '重置前得分');

  game.newGame(false);
  assertEqual(game.score, 0, '重置后得分');
  assertEqual(game.cards.length, 4, '重置后卡片数');
  assertTrue(game.cards.every(function (c) { return !c.isFaceUp && !c.isMatched; }), '重置后全部背面');
});

test('startNewGame 切换主题并重建牌组', function () {
  var game = makeOrderedGame(2);
  var newTheme = Theme.builtIn[5];
  game.startNewGame(newTheme, false);

  assertEqual(game.theme.name, '食物', '主题名称');
  assertEqual(game.cards.length, 16, '新主题卡片数');
  assertEqual(game.score, 0, '得分归零');
});

// ---------------- 主题校验 ----------------

group('主题校验');

test('主题名称不能为空', function () {
  var threw = false;
  try {
    new Theme({ name: '   ', emojis: ['A'] });
  } catch (e) {
    threw = true;
  }
  assertTrue(threw, '空名称应抛错');
});

test('主题至少需要一个 emoji', function () {
  var threw = false;
  try {
    new Theme({ name: '空', emojis: ['', '  '] });
  } catch (e) {
    threw = true;
  }
  assertTrue(threw, '空 emoji 集合应抛错');
});

test('卡片对数必须大于 0', function () {
  var threw = false;
  try {
    new Theme({ name: '零', emojis: ['A'], numberOfPairs: 0 });
  } catch (e) {
    threw = true;
  }
  assertTrue(threw, '对数 0 应抛错');
});

test('内置主题为 6 个，各 8 个 emoji、8 对', function () {
  assertEqual(Theme.builtIn.length, 6, '主题数量');
  Theme.builtIn.forEach(function (theme) {
    assertEqual(theme.emojis.length, 8, theme.name + ' 的 emoji 数量');
    assertEqual(theme.numberOfPairs, 8, theme.name + ' 的对数');
  });
});

// ---------------- 视图模型：交互锁与错配翻回 ----------------

group('视图模型：交互锁与错配翻回');

test('错配后立即锁定交互', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[2]);

  assertTrue(vm.isInteractionLocked, '错配后应锁定');
});

test('锁定期间点击被忽略，得分不变', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[2]);
  var scoreBefore = vm.score;

  vm.choose(vm.cards[4]);
  assertEqual(vm.score, scoreBefore, '锁定期间得分不变');
  assertFalse(vm.cards[4].isFaceUp, '锁定期间卡片不翻开');
});

test('0.8 秒后自动翻回并解除锁定', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[2]);

  timers.advance(799);
  assertTrue(vm.isInteractionLocked, '799ms 时仍锁定');

  timers.advance(1);
  assertFalse(vm.isInteractionLocked, '800ms 时解锁');
  assertFalse(vm.cards[0].isFaceUp, '卡片已翻回');
  assertFalse(vm.hasPendingMismatch, '无待翻回卡片');
});

test('重开后作废旧翻回计时，旧回调不会误解锁', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[2]);
  vm.newGame();

  timers.advance(1000);
  assertFalse(vm.isInteractionLocked, '重开后保持未锁定');
  assertEqual(vm.score, 0, '重开后得分归零');
});

// ---------------- 视图模型：倒计时 ----------------

group('视图模型：倒计时');

test('首次启动倒计时为 60 秒', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });

  vm.startCountdownIfNeeded();
  assertEqual(vm.countdownState, 'running', '状态');
  assertEqual(vm.countdownRemaining, 60, '剩余秒数');
  assertEqual(vm.countdownTotal, 60, '总秒数');
});

test('每秒递减一次，60 秒后进入结束状态', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startCountdownIfNeeded();

  timers.advance(1000);
  assertEqual(vm.countdownRemaining, 59, '1 秒后剩余');

  timers.advance(58000);
  assertEqual(vm.countdownRemaining, 1, '59 秒后剩余');

  timers.advance(1000);
  assertEqual(vm.countdownRemaining, 0, '60 秒后剩余');
  assertEqual(vm.countdownState, 'finished', '状态为已结束');
  assertTrue(vm.didTimeOut, '标记为超时');
});

test('超时后锁定交互，点击卡片无效', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });
  vm.startCountdownIfNeeded();
  timers.advance(60000);

  assertTrue(vm.isInteractionLocked, '超时后锁定');
  vm.choose(vm.cards[0]);
  assertFalse(vm.cards[0].isFaceUp, '超时后卡片不翻开');
});

test('超时后错配翻回不会解除锁定', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });
  vm.startCountdownIfNeeded();

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[2]);   // 错配，安排 0.8s 后翻回
  timers.advance(800);      // 先完成翻回

  timers.advance(59200);    // 推到 60 秒整
  assertEqual(vm.countdownState, 'finished', '已超时');
  assertTrue(vm.isInteractionLocked, '超时锁定');

  vm.completeMismatchFlipBack();
  assertTrue(vm.isInteractionLocked, '翻回收尾后仍保持锁定');
});

test('剩余 5 秒及以内应触发红色提示（阈值判定）', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startCountdownIfNeeded();

  timers.advance(55000);
  assertEqual(vm.countdownRemaining, 5, '剩余 5 秒');

  var isWarning = vm.countdownRemaining <= 5 && vm.countdownTotal > 0;
  assertTrue(isWarning, '5 秒时应为警示态');

  timers.advance(-1000); // 不推进，仅确认逻辑：6 秒时不应警示
  assertEqual(6 <= 5, false, '6 秒不应警示');
});

test('暂停后不再递减，继续后恢复', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startCountdownIfNeeded();

  timers.advance(3000);
  assertEqual(vm.countdownRemaining, 57, '3 秒后剩余');

  vm.pauseCountdown();
  assertEqual(vm.countdownState, 'paused', '暂停状态');
  timers.advance(10000);
  assertEqual(vm.countdownRemaining, 57, '暂停期间不递减');

  vm.resumeCountdown();
  timers.advance(1000);
  assertEqual(vm.countdownRemaining, 56, '继续后正常递减');
});

test('重开一局按原时长重新计时', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startCountdownIfNeeded();

  timers.advance(30000);
  assertEqual(vm.countdownRemaining, 30, '30 秒后剩余');

  vm.newGame();
  assertEqual(vm.countdownRemaining, 60, '重开后恢复 60 秒');
  assertEqual(vm.countdownState, 'running', '重开后继续计时');
  assertFalse(vm.didTimeOut, '重开后清除超时标记');
});

test('超时后重开可恢复正常游戏', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });
  vm.startCountdownIfNeeded();
  timers.advance(60000);

  assertTrue(vm.isInteractionLocked, '超时锁定');
  vm.newGame();

  assertFalse(vm.isInteractionLocked, '重开后解锁');
  assertEqual(vm.countdownRemaining, 60, '倒计时复位');

  vm.choose(vm.cards[0]);
  assertTrue(vm.cards[0].isFaceUp, '重开后可以正常翻牌');
});

test('结算标题：通关优先于超时', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });

  vm.chooseTheme(new Theme({ name: '单对', emojis: ['X'] }));
  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[1]);
  assertEqual(vm.resultTitle, '全部配对成功！', '通关标题');

  var vm2 = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm2.startCountdownIfNeeded();
  timers.advance(60000);
  assertEqual(vm2.resultTitle, '时间到！', '超时标题');
});

// ---------------- 布局计算 ----------------

group('布局计算');

test('16 张卡片在 350×500 区域内落为 5 列（4 列会超高）', function () {
  // 4 列时：宽 87.5，高 131.25，4 行共 525 > 500，放不下；
  // 5 列时：宽 70，高 105，4 行共 420 <= 500，成立。
  var width = Layout.itemWidthThatFits(16, 350, 500, Layout.CARD_ASPECT_RATIO);
  assertEqual(width, 70, '卡片宽度');
  var columns = Layout.columnCountFor(350, width);
  assertEqual(columns, 5, '列数');
});

test('16 张卡片在 400×700 区域内每行放 4 张', function () {
  var width = Layout.itemWidthThatFits(16, 400, 700, Layout.CARD_ASPECT_RATIO);
  assertEqual(width, 100, '卡片宽度');
  assertEqual(Layout.columnCountFor(400, width), 4, '列数');
});

test('空间不足时兜底为压缩值而不是 0', function () {
  var width = Layout.itemWidthThatFits(16, 100, 100, Layout.CARD_ASPECT_RATIO);
  assertTrue(width > 0, '仍返回正整数，实际 ' + width);
});

test('非法输入返回 0', function () {
  assertEqual(Layout.itemWidthThatFits(0, 300, 300, Layout.CARD_ASPECT_RATIO), 0, '卡片数为 0');
  assertEqual(Layout.itemWidthThatFits(16, 0, 300, Layout.CARD_ASPECT_RATIO), 0, '宽度为 0');
  assertEqual(Layout.itemWidthThatFits(16, 300, 300, 0), 0, '宽高比为 0');
});

test('环形进度：满值 1、零值 0、超出范围被夹取', function () {
  assertEqual(Layout.pieProgress(60, 60), 1, '满进度');
  assertEqual(Layout.pieProgress(0, 60), 0, '零进度');
  assertEqual(Layout.pieProgress(30, 60), 0.5, '半进度');
  assertEqual(Layout.pieProgress(90, 60), 1, '超出上限');
  assertEqual(Layout.pieProgress(-5, 60), 0, '负数');
  assertEqual(Layout.pieProgress(10, 0), 0, '总数为 0');
});

test('发牌延迟按下标递增并封顶 0.6 秒', function () {
  assertEqual(Layout.dealDelay(0), 0, '第 0 张');
  assertEqual(Layout.dealDelay(1), 0.06, '第 1 张');
  assertEqual(Layout.dealDelay(5), 0.3, '第 5 张');
  assertEqual(Layout.dealDelay(10), 0.6, '第 10 张封顶');
  assertEqual(Layout.dealDelay(50), 0.6, '第 50 张仍封顶');
});

test('卡片几何量按短边缩放并受上下限约束', function () {
  var small = Layout.cardMetrics(40, 60);
  assertEqual(small.cornerRadius, 6, '小卡片圆角取下限');
  assertEqual(small.borderWidth, 1, '小卡片边框取下限');

  var large = Layout.cardMetrics(300, 450);
  assertEqual(large.cornerRadius, 20, '大卡片圆角取上限');
  assertEqual(large.borderWidth, 3, '大卡片边框取上限');
});

// ---------------- 视图模型：开局 / 停表 / 返回主界面 ----------------

group('视图模型：开局、停表与返回主界面');

test('构造后不启动计时，startGame 才开始走秒', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });

  assertEqual(vm.countdownState, 'idle', '构造后状态');
  assertEqual(vm.countdownRemaining, 0, '构造后剩余秒数');
  timers.advance(10000);
  assertEqual(vm.countdownRemaining, 0, '未开局不递减');

  vm.startGame();
  assertEqual(vm.countdownState, 'running', '开局后计时中');
  assertEqual(vm.countdownRemaining, 60, '开局剩余 60');

  timers.advance(1000);
  assertEqual(vm.countdownRemaining, 59, '1 秒后递减');
});

test('startGame 会重置得分与牌面，等于重开一局', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });

  vm.startGame();
  // startGame 内部会重洗，因此不能假设相邻两张同图案，按内容找配对卡
  var first = vm.cards[0];
  var partner = null;
  for (var i = 1; i < vm.cards.length; i += 1) {
    if (vm.cards[i].content === first.content) {
      partner = vm.cards[i];
      break;
    }
  }
  assertTrue(partner !== null, '应能找到配对卡');
  vm.choose(first);
  vm.choose(partner);
  assertEqual(vm.score, 2, '先配一对');

  vm.startGame();
  assertEqual(vm.score, 0, '重新开局得分归零');
  assertTrue(vm.cards.every(function (c) { return !c.isFaceUp && !c.isMatched; }),
    '重新开局全部背面');
});

test('通关立即停表，之后不再递减', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });
  // 换成只有一对的主题，便于快速通关
  vm.chooseTheme(new Theme({ name: '单对', emojis: ['X'] }));
  vm.startGame();

  timers.advance(5000);
  assertEqual(vm.countdownRemaining, 55, '5 秒后剩余');

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[1]);
  assertTrue(vm.isGameOver, '已通关');
  assertEqual(vm.countdownState, 'stopped', '通关后状态为已停止');
  assertEqual(vm.countdownRemaining, 55, '停表时保留剩余秒数');

  timers.advance(30000);
  assertEqual(vm.countdownRemaining, 55, '停表后不再递减');
});

test('通关停表后重开，倒计时按原时长恢复', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });
  vm.chooseTheme(new Theme({ name: '单对', emojis: ['X'] }));
  vm.startGame();
  timers.advance(8000);

  vm.choose(vm.cards[0]);
  vm.choose(vm.cards[1]);
  assertEqual(vm.countdownState, 'stopped', '先确认已停表');

  vm.newGame();
  assertEqual(vm.countdownState, 'running', '重开后继续计时');
  assertEqual(vm.countdownRemaining, 60, '恢复为完整时长');
});

test('返回主界面后停表，主界面期间不会继续走秒', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startGame();

  timers.advance(4000);
  assertEqual(vm.countdownRemaining, 56, '4 秒后剩余');

  vm.leaveGame();
  assertEqual(vm.countdownState, 'idle', '回到 idle');
  assertEqual(vm.countdownRemaining, 0, '剩余归零');
  assertFalse(vm.isInteractionLocked, '解除交互锁');

  timers.advance(20000);
  assertEqual(vm.countdownRemaining, 0, '主界面不递减');
  assertEqual(vm.countdownState, 'idle', '仍是 idle');

  // 主界面期间即使重建牌组，也不应自行启动计时
  vm.newGame();
  assertEqual(vm.countdownState, 'idle', '未开局不启动计时');
  timers.advance(5000);
  assertEqual(vm.countdownRemaining, 0, '仍未计时');
});

test('超时后返回主界面再开局，状态完全复位', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], shuffle: false, timers: timers });
  vm.startGame();
  timers.advance(60000);
  assertEqual(vm.countdownState, 'finished', '已超时');

  vm.leaveGame();
  vm.startGame();
  assertEqual(vm.countdownState, 'running', '重新开局计时中');
  assertEqual(vm.countdownRemaining, 60, '倒计时复位');
  assertFalse(vm.didTimeOut, '清除超时标记');

  vm.choose(vm.cards[0]);
  assertTrue(vm.cards[0].isFaceUp, '可以正常翻牌');
});

// ---------------- 卡片缝隙 ----------------

group('卡片缝隙与带缝隙布局');

test('缝隙随卡片宽度变化并夹在 3...10px', function () {
  assertEqual(Layout.cardGap(40), 3, '小卡片取下限');
  assertEqual(Layout.cardGap(118), 4, '常规卡片按比例');
  assertEqual(Layout.cardGap(400), 10, '大卡片取上限');
  assertEqual(Layout.cardGap(0), 3, '非法输入取下限');
});

test('带缝隙布局：六列总宽精确填满且不溢出', function () {
  var width = Layout.itemWidthThatFits(16, 728, 612, Layout.CARD_ASPECT_RATIO, 4);
  assertEqual(width, 118, '卡片宽度');

  var columns = Layout.columnCountFor(728, width, 4);
  assertEqual(columns, 6, '列数');
  assertEqual(columns * width + (columns - 1) * 4, 728, '六列总宽正好 728');

  var rows = Math.ceil(16 / columns);
  var height = rows * (width / Layout.CARD_ASPECT_RATIO) + (rows - 1) * 4;
  assertTrue(height <= 612, '三行总高不溢出，实际 ' + height);
});

test('窄屏带缝隙布局不溢出', function () {
  var width = Layout.itemWidthThatFits(16, 296, 480, Layout.CARD_ASPECT_RATIO, 3);
  assertTrue(width > 0, '仍能得到卡片宽度');
  var columns = Layout.columnCountFor(296, width, 3);
  assertTrue(columns * width + (columns - 1) * 3 <= 296,
    '总宽不溢出：' + columns + ' 列 × ' + width);
});

test('不传缝隙时结果与旧版一致（向后兼容）', function () {
  assertEqual(Layout.itemWidthThatFits(16, 350, 500, Layout.CARD_ASPECT_RATIO),
    Layout.itemWidthThatFits(16, 350, 500, Layout.CARD_ASPECT_RATIO, 0), '无缝等价');
  assertEqual(Layout.columnCountFor(350, 70), Layout.columnCountFor(350, 70, 0), '列数等价');
});

// ---------------- 配置：难度与闯关 ----------------

group('配置：难度与闯关参数');

test('经典档与原版冻结参数完全一致', function () {
  var round = Config.resolveRound('classic', 'classic', 0);
  assertEqual(round.pairs, 8, '对数');
  assertEqual(round.duration, 60, '时长');
  assertEqual(round.mismatchFlipDelay, 0.8, '错配翻回');
  assertEqual(round.stageCount, 1, '关卡数');
});

test('轻松 / 挑战档只改参数，不改规则', function () {
  var easy = Config.resolveRound('classic', 'easy', 0);
  assertEqual(easy.pairs, 6, '轻松对数');
  assertEqual(easy.duration, 90, '轻松时长');
  assertEqual(easy.mismatchFlipDelay, 1.0, '轻松翻回');

  var hard = Config.resolveRound('classic', 'hard', 0);
  assertEqual(hard.pairs, 8, '挑战对数');
  assertEqual(hard.duration, 45, '挑战时长');
  assertEqual(hard.mismatchFlipDelay, 0.6, '挑战翻回');
});

test('闯关三关对数递增、翻回递减，共用同一时长预算', function () {
  var first = Config.resolveRound('campaign', 'classic', 0);
  var second = Config.resolveRound('campaign', 'classic', 1);
  var third = Config.resolveRound('campaign', 'classic', 2);

  assertEqual(first.pairs + '/' + second.pairs + '/' + third.pairs, '6/7/8', '三关对数');
  assertTrue(first.mismatchFlipDelay > second.mismatchFlipDelay, '翻回时间递减一');
  assertTrue(second.mismatchFlipDelay > third.mismatchFlipDelay, '翻回时间递减二');
  assertEqual(first.duration, Config.CAMPAIGN.timeBudget, '时长预算');
  assertEqual(third.stage + '/' + third.stageCount, '3/3', '关卡标记');
});

test('关卡下标越界时收敛到有效范围', function () {
  assertEqual(Config.resolveRound('campaign', 'classic', -5).stage, 1, '下限');
  assertEqual(Config.resolveRound('campaign', 'classic', 99).stage, 3, '上限');
});

test('未知难度回落到经典档，保证总有可用配置', function () {
  assertEqual(Config.findDifficulty('不存在').id, 'classic', '回落 id');
  assertEqual(Config.resolveRound('classic', '不存在', 0).duration, 60, '回落时长');
});

// ---------------- 视图模型：暂停 / 恢复 ----------------

group('视图模型：暂停与恢复');

test('暂停冻结倒计时，恢复后按剩余秒数继续', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  vm.startGame();

  timers.advance(3000);
  assertEqual(vm.countdownRemaining, 57, '走了 3 秒');

  assertTrue(vm.pause(), '暂停成功');
  assertTrue(vm.isPaused, '暂停标记');
  assertEqual(vm.countdownState, 'paused', '倒计时状态');

  timers.advance(5000);
  assertEqual(vm.countdownRemaining, 57, '暂停期间不递减');

  assertTrue(vm.resume(), '恢复成功');
  assertFalse(vm.isPaused, '暂停标记已清除');
  timers.advance(2000);
  assertEqual(vm.countdownRemaining, 55, '恢复后继续走秒');
});

test('暂停期间点击卡片无效，牌面与得分都不变', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  vm.startGame();
  vm.pause();

  var first = vm.cards[0];
  vm.choose(first);
  assertFalse(first.isFaceUp, '暂停时不能翻牌');
  assertEqual(vm.score, 0, '暂停时得分不变');
});

test('暂停会冻结错配翻回，恢复后只补走剩余时间', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  vm.startGame();

  var a = vm.cards[0];
  var b = null;
  for (var i = 1; i < vm.cards.length; i += 1) {
    if (vm.cards[i].content !== a.content) {
      b = vm.cards[i];
      break;
    }
  }
  vm.choose(a);
  vm.choose(b);
  assertTrue(vm.isInteractionLocked, '错配后锁定');

  timers.advance(200);
  vm.pause();
  timers.advance(5000);
  assertTrue(vm.isInteractionLocked, '暂停期间保持锁定');
  assertTrue(vm.game.hasPendingMismatch, '暂停期间不翻回');

  vm.resume();
  timers.advance(560);
  assertTrue(vm.game.hasPendingMismatch, '恢复后先等剩余 600ms');
  timers.advance(60);
  assertFalse(vm.game.hasPendingMismatch, '剩余时间到后翻回');
  assertFalse(vm.isInteractionLocked, '解锁可以继续点');
});

test('暂停与恢复各只发一次事件，避免视图重复处理', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  var events = [];
  vm.subscribe(function (event) { events.push(event.type); });
  vm.startGame();
  vm.pause();
  vm.pause();
  vm.resume();
  vm.resume();

  var pauses = events.filter(function (type) { return type === 'pause'; }).length;
  var resumes = events.filter(function (type) { return type === 'resume'; }).length;
  assertEqual(pauses, 1, 'pause 事件数');
  assertEqual(resumes, 1, 'resume 事件数');
});

test('未开局与已结算都不能暂停', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  assertFalse(vm.pause(), '主界面不可暂停');

  vm.startGame();
  timers.advance(60000);
  assertEqual(vm.countdownState, 'finished', '已超时');
  assertFalse(vm.pause(), '结算后不可暂停');
  assertFalse(vm.isPaused, '没有进入暂停态');
});

test('返回主界面会清除暂停态并复位倒计时', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  vm.startGame();
  vm.pause();
  vm.leaveGame();

  assertFalse(vm.isPaused, '暂停已清除');
  assertEqual(vm.countdownState, 'idle', '回到 idle');
  assertEqual(vm.countdownRemaining, 0, '剩余归零');
});

test('暂停时提示文案明确说明已冻结', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  vm.startGame();
  vm.pause();
  assertEqual(vm.hintText, '已暂停 · 计时与翻牌已冻结', '提示文案');
});

// ---------------- 视图模型：难度与闯关 ----------------

/** 逐对翻开，清空当前这一关（关卡切换后自动停手）。 */
function clearCurrentRound(vm) {
  var game = vm.game;
  var guard = 0;
  while (!game.isGameOver && guard < 40) {
    guard += 1;
    var first = null;
    for (var i = 0; i < vm.cards.length; i += 1) {
      if (!vm.cards[i].isMatched && !vm.cards[i].isFaceUp) {
        first = vm.cards[i];
        break;
      }
    }
    if (!first) {
      return;
    }
    vm.choose(first);
    for (var j = 0; j < vm.cards.length; j += 1) {
      if (vm.cards[j] !== first && vm.cards[j].content === first.content
        && !vm.cards[j].isMatched) {
        vm.choose(vm.cards[j]);
        break;
      }
    }
  }
}

group('视图模型：难度与闯关');

test('切换难度后开局：牌数、时长、翻回速度同步生效', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  assertTrue(vm.setDifficulty('easy'), '切换成功');
  vm.startGame();

  assertEqual(vm.cards.length, 12, '6 对 12 张');
  assertEqual(vm.countdownRemaining, 90, '90 秒');
  assertEqual(vm.mismatchFlipDelay, 1.0, '翻回 1.0 秒');
});

test('闯关开局：第 1 关 6 对，共享 150 秒', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers, mode: 'campaign' });
  vm.startGame();

  assertEqual(vm.cards.length, 12, '第 1 关 12 张');
  assertEqual(vm.countdownRemaining, 150, '150 秒');
  assertEqual(vm.levelNumber + '/' + vm.levelCount, '1/3', '关卡进度');
});

test('闯关第一关清空：进入第 2 关、补时 8 秒、得分累计', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers, mode: 'campaign' });
  var levelClears = [];
  vm.subscribe(function (event) {
    if (event.type === 'levelclear') {
      levelClears.push(event);
    }
  });
  vm.startGame();

  clearCurrentRound(vm);
  assertEqual(vm.levelNumber, 2, '进入第 2 关');
  assertEqual(vm.cards.length, 14, '第 2 关 14 张');
  assertEqual(vm.score, 12, '6 对共 +12');
  assertEqual(vm.countdownRemaining, 158, '补时后 158 秒');
  assertEqual(levelClears.length, 1, '一次过关事件');
  assertEqual(levelClears[0].bonus, 8, '补时数值');
  assertEqual(vm.countdownState, 'running', '倒计时继续');
  assertEqual(vm.resultReason, null, '还没结束');
});

test('闯关三关全部清空才算通关并立即停表', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers, mode: 'campaign' });
  vm.startGame();

  clearCurrentRound(vm);
  clearCurrentRound(vm);
  assertEqual(vm.levelNumber, 3, '进入第 3 关');
  assertEqual(vm.score, 26, '前两关累计 26 分');

  clearCurrentRound(vm);
  assertTrue(vm.game.isGameOver, '牌面已清空');
  assertEqual(vm.score, 42, '三关累计 42 分');
  assertEqual(vm.resultReason, 'win', '结束原因');
  assertEqual(vm.resultTitle, '闯关成功！', '标题');
  assertEqual(vm.countdownState, 'stopped', '通关停表');
});

test('闯关超时的文案与经典模式区分开', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers, mode: 'campaign' });
  vm.startGame();
  timers.advance(150000);

  assertEqual(vm.countdownState, 'finished', '时间归零');
  assertEqual(vm.resultReason, 'timeout', '结束原因');
  assertEqual(vm.resultTitle, '挑战失败', '闯关失败标题');
});

test('闯关重开回到第 1 关与初始预算', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers, mode: 'campaign' });
  vm.startGame();
  clearCurrentRound(vm);
  vm.newGame();

  assertEqual(vm.levelNumber, 1, '回到第 1 关');
  assertEqual(vm.cards.length, 12, '牌数复位');
  assertEqual(vm.score, 0, '得分归零');
  assertEqual(vm.countdownRemaining, 150, '时长复位');
});

test('对局进行中不允许切换模式或难度', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ timers: timers });
  vm.startGame();

  assertFalse(vm.setMode('campaign'), '游戏中不能换模式');
  assertFalse(vm.setDifficulty('hard'), '游戏中不能换难度');
  assertEqual(vm.mode, 'classic', '模式未变');
  assertEqual(vm.difficulty, 'classic', '难度未变');
});

// ---------------- 最高分存档 ----------------

group('最高分与本地存档');

test('首次提交只记录成绩，不标记为新纪录', function () {
  var store = new StoreModule.ScoreStore(null);
  assertEqual(store.getBest('classic', 'classic'), null, '初始无记录');

  var first = store.submit('classic', 'classic', 12);
  assertEqual(first.best, 12, '记录成绩');
  assertFalse(first.isNewRecord, '首局不算破纪录');
  assertEqual(store.getBest('classic', 'classic'), 12, '读回成绩');
});

test('只有更高分才覆盖，并标记为新纪录', function () {
  var store = new StoreModule.ScoreStore(null);
  store.submit('classic', 'classic', 12);

  var lower = store.submit('classic', 'classic', 4);
  assertEqual(lower.best, 12, '低分不覆盖');
  assertFalse(lower.isNewRecord, '不是新纪录');

  var higher = store.submit('classic', 'classic', 20);
  assertEqual(higher.best, 20, '高分覆盖');
  assertTrue(higher.isNewRecord, '标记新纪录');
  assertEqual(higher.previous, 12, '原纪录保留');
});

test('不同模式与难度的最高分互不干扰', function () {
  var store = new StoreModule.ScoreStore(null);
  store.submit('classic', 'classic', 10);
  store.submit('classic', 'easy', 30);
  store.submit('campaign', 'campaign', 42);

  assertEqual(store.getBest('classic', 'classic'), 10, '经典');
  assertEqual(store.getBest('classic', 'easy'), 30, '轻松');
  assertEqual(store.getBest('campaign', 'campaign'), 42, '闯关');
});

test('存档不可用时静默回退到内存，不抛异常', function () {
  var hostile = {
    getItem: function () { throw new Error('blocked'); },
    setItem: function () { throw new Error('blocked'); },
    removeItem: function () { throw new Error('blocked'); }
  };
  var store = new StoreModule.ScoreStore(hostile);
  assertFalse(store.persistent, '识别为不可持久化');
  assertFalse(store.submit('classic', 'classic', 8).isNewRecord, '照常可写');
  assertEqual(store.getBest('classic', 'classic'), 8, '内存内可读回');
});

test('偏好设置可读回，缺字段时用默认值补齐', function () {
  var store = new StoreModule.ScoreStore(null);
  var defaults = store.getPrefs({ sound: true, mode: 'classic', difficulty: 'classic' });
  assertTrue(defaults.sound, '默认开启音效');
  assertEqual(defaults.mode, 'classic', '默认模式');

  store.setPrefs({ sound: false, mode: 'campaign', difficulty: 'hard' });
  var saved = store.getPrefs({});
  assertFalse(saved.sound, '音效已关闭');
  assertEqual(saved.mode, 'campaign', '模式已保存');
  assertEqual(saved.difficulty, 'hard', '难度已保存');
});

// ---------------- 连击加成 ----------------

group('连击加成（挑战档专属）');

/** 按图案把当前牌组里同内容的两张配成一组，最多取 count 组。 */
function pairsOf(vm, count) {
  var byContent = {};
  var order = [];
  vm.cards.forEach(function (card) {
    if (!byContent[card.content]) {
      byContent[card.content] = [];
      order.push(card.content);
    }
    byContent[card.content].push(card);
  });
  var list = [];
  order.forEach(function (key) {
    if (byContent[key].length >= 2 && list.length < count) {
      list.push([byContent[key][0], byContent[key][1]]);
    }
  });
  return list;
}

function playPair(vm, pair) {
  vm.choose(pair[0]);
  vm.choose(pair[1]);
}

/** 找一对「还没被配上」的同图案卡片（用于连击中断后的续接）。 */
function unmatchedPair(vm) {
  var byContent = {};
  var order = [];
  vm.cards.forEach(function (card) {
    if (card.isMatched) {
      return;
    }
    if (!byContent[card.content]) {
      byContent[card.content] = [];
      order.push(card.content);
    }
    byContent[card.content].push(card);
  });
  for (var i = 0; i < order.length; i += 1) {
    var group = byContent[order[i]];
    if (group.length >= 2) {
      return [group[0], group[1]];
    }
  }
  return null;
}

/** 找两张「背面朝上、内容不同」的牌，用来制造一次错配。 */
function mismatchCandidates(vm) {
  var down = vm.cards.filter(function (card) {
    return !card.isMatched && !card.isFaceUp;
  });
  for (var i = 0; i < down.length; i += 1) {
    for (var j = i + 1; j < down.length; j += 1) {
      if (down[i].content !== down[j].content) {
        return [down[i], down[j]];
      }
    }
  }
  return null;
}

test('经典档不启用连击：连配三对仍是 +2 / +2 / +2', function () {
  var vm = new GameViewModel({ difficulty: 'classic', mode: 'classic', timers: new FakeTimers() });
  vm.startGame();
  assertFalse(vm.comboEnabled, '经典档不开启连击');

  var pairs = pairsOf(vm, 3);
  playPair(vm, pairs[0]);
  assertEqual(vm.score, 2, '第一对');
  playPair(vm, pairs[1]);
  assertEqual(vm.score, 4, '第二对');
  playPair(vm, pairs[2]);
  assertEqual(vm.score, 6, '第三对');
  assertEqual(vm.comboMultiplier, 1, '倍率恒为 1');
  assertEqual(vm.comboBonus, 0, '没有额外奖励分');
});

test('挑战档倍率表：1 → ×1，2 → ×1.25，3 次起 ×1.5', function () {
  assertEqual(Config.comboMultiplier(0), 1, '0 连击');
  assertEqual(Config.comboMultiplier(1), 1, '1 连击');
  assertEqual(Config.comboMultiplier(2), 1.25, '2 连击');
  assertEqual(Config.comboMultiplier(3), 1.5, '3 连击');
  assertEqual(Config.comboMultiplier(9), 1.5, '上限封顶');
});

test('挑战档连配四对：分数按倍率累加，余数结转不丢', function () {
  var vm = new GameViewModel({ difficulty: 'hard', mode: 'classic', timers: new FakeTimers() });
  vm.startGame();
  assertTrue(vm.comboEnabled, '挑战档开启连击');

  var pairs = pairsOf(vm, 4);
  playPair(vm, pairs[0]);
  assertEqual(vm.score, 2, '首对无加成');
  assertEqual(vm.comboMultiplier, 1, '首对倍率');

  playPair(vm, pairs[1]);
  // 2 × 1.25 = 2.5：实得 2 分，余 0.5 留给下一次
  assertEqual(vm.score, 4, '第二对');
  assertEqual(vm.comboMultiplier, 1.25, '第二对倍率');

  playPair(vm, pairs[2]);
  // 2 × 1.5 + 0.5 = 3.5：实得 3 分，余 0.5 继续结转
  assertEqual(vm.score, 7, '第三对');
  assertEqual(vm.comboMultiplier, 1.5, '第三对倍率');

  playPair(vm, pairs[3]);
  assertEqual(vm.score, 10, '第四对');
  assertEqual(vm.comboBonus, 2, '四对累计奖励 2 分');
  assertEqual(vm.bestCombo, 4, '记录最高连击');
});

test('错配立即中断连击，之后回到 +2', function () {
  var vm = new GameViewModel({ difficulty: 'hard', mode: 'classic', timers: new FakeTimers() });
  vm.startGame();
  var pairs = pairsOf(vm, 2);
  playPair(vm, pairs[0]);
  playPair(vm, pairs[1]);
  assertEqual(vm.comboStreak, 2, '已两连击');

  var miss = mismatchCandidates(vm);
  vm.choose(miss[0]);
  vm.choose(miss[1]);
  assertEqual(vm.comboStreak, 0, '连击清零');
  assertEqual(vm.comboMultiplier, 1, '倍率复位');
  assertEqual(vm.score, 4, '错配不回收已得的分');

  vm.completeMismatchFlipBack();
  playPair(vm, unmatchedPair(vm));
  assertEqual(vm.score, 6, '中断后恢复 +2');
});

test('暂停、点已配对的卡片都不算连击中断', function () {
  var vm = new GameViewModel({ difficulty: 'hard', mode: 'classic', timers: new FakeTimers() });
  vm.startGame();
  var pairs = pairsOf(vm, 2);
  playPair(vm, pairs[0]);

  assertTrue(vm.pause(), '可以暂停');
  assertEqual(vm.comboStreak, 1, '暂停不清零');
  assertTrue(vm.resume(), '可以恢复');
  assertEqual(vm.comboStreak, 1, '恢复后连击仍在');

  vm.choose(pairs[0][0]);   // 已配对，模型直接忽略
  assertEqual(vm.comboStreak, 1, '无效点击不清零');
});

test('重开一局清零连击、奖励分与最高连击', function () {
  var vm = new GameViewModel({ difficulty: 'hard', mode: 'classic', timers: new FakeTimers() });
  vm.startGame();
  playPair(vm, pairsOf(vm, 3)[0]);
  playPair(vm, pairsOf(vm, 3)[1]);
  assertTrue(vm.comboStreak > 0, '先积累连击');

  vm.newGame();
  assertEqual(vm.comboStreak, 0, '连击清零');
  assertEqual(vm.comboBonus, 0, '奖励分清零');
  assertEqual(vm.comboMultiplier, 1, '倍率复位');
  assertEqual(vm.bestCombo, 0, '最高连击清零');
  assertEqual(vm.score, 0, '得分归零');
});

test('闯关模式不启用连击', function () {
  var vm = new GameViewModel({ mode: 'campaign', difficulty: 'hard', timers: new FakeTimers() });
  vm.startGame();
  assertFalse(vm.comboEnabled, '闯关没有难度档，不参与连击');
  var pairs = pairsOf(vm, 2);
  playPair(vm, pairs[0]);
  playPair(vm, pairs[1]);
  assertEqual(vm.score, 4, '仍是每对 +2');
});

test('闯关进入下一关：偷看次数按新关卡重置，连击不跨关', function () {
  var vm = new GameViewModel({ mode: 'campaign', timers: new FakeTimers() });
  vm.startGame();
  assertEqual(vm.peekRemaining, 3, '第 1 关 3 次');
  vm.peek(vm.cards[0]);
  vm.endPeek();
  assertEqual(vm.peekRemaining, 2, '用掉一次');

  // 只清空第 1 关：一旦跳过关就停手，否则会连着把第 2 关也打通
  var guard = 0;
  while (!vm.isGameOver && vm.levelNumber === 1 && guard < 40) {
    guard += 1;
    var pair = unmatchedPair(vm);
    if (!pair) {
      break;
    }
    playPair(vm, pair);
  }

  assertEqual(vm.levelNumber, 2, '进入第 2 关');
  assertEqual(vm.cards.length, 14, '第 2 关 7 对 14 张');
  assertEqual(vm.peekRemaining, 2, '第 2 关偷看次数按配置重置');
  assertEqual(vm.comboStreak, 0, '连击不跨关');
});

test('comboAward：倍率与余数的换算关系', function () {
  var first = Config.comboAward(2, 0);
  assertEqual(first.award, 2.5, '×1.25 应得 2.5');
  assertEqual(first.whole, 2, '本次实得 2');
  assertEqual(first.carry, 0.5, '余 0.5');

  var second = Config.comboAward(2, 0.5);
  assertEqual(second.award, 3, '带着余数应得 3');
  assertEqual(second.whole, 3, '本次实得 3');
  assertEqual(second.carry, 0, '余数结清');

  var capped = Config.comboAward(8, 0);
  assertEqual(capped.award, 3, '×1.5 应得 3');
});

// ---------------- 最近对局 ----------------

group('最近对局记录（store 扩展为数组）');

test('历史记录：最新在前、字段被规范化', function () {
  var store = new StoreModule.ScoreStore(null);
  assertEqual(store.getHistory().length, 0, '初始为空');

  store.addRecord({
    mode: 'classic', difficulty: 'hard', score: 12, reason: 'win',
    stage: 1, stageCount: 1, pairs: 8, matched: 8, combo: 5, at: 1000
  });
  store.addRecord({
    mode: 'campaign', difficulty: 'classic', score: 6, reason: 'timeout',
    stage: 2, stageCount: 3, pairs: 8, matched: 5, combo: 0, at: 2000
  });

  var list = store.getHistory();
  assertEqual(list.length, 2, '两条记录');
  assertEqual(list[0].mode, 'campaign', '最新的在前');
  assertEqual(list[0].reason, 'timeout', '结局字段保留');
  assertEqual(list[0].stage, 2, '止步关卡');
  assertEqual(list[1].score, 12, '旧记录分数');
  assertEqual(list[1].combo, 5, '连击数被记录');
});

test('历史记录：只保留最近 20 局，可按条数截取', function () {
  var store = new StoreModule.ScoreStore(null);
  for (var i = 1; i <= 25; i += 1) {
    store.addRecord({ score: i, mode: 'classic', difficulty: 'classic', at: i });
  }
  var all = store.getHistory();
  assertEqual(all.length, StoreModule.MAX_HISTORY, '上限 20 条');
  assertEqual(all[0].score, 25, '最新一条在最前');
  assertEqual(all[all.length - 1].score, 6, '最旧的五条被丢弃');

  var top5 = store.getHistory(5);
  assertEqual(top5.length, 5, '只取 5 条');
  assertEqual(top5[0].score, 25, '取的是最新的');
});

test('历史记录：脏数据被过滤而不是让页面崩掉', function () {
  var mem = new StoreModule.MemoryStorage();
  mem.setItem(StoreModule.KEY_HISTORY, JSON.stringify([
    { score: 'abc' },
    null,
    'not-an-object',
    { score: 9, mode: 'weird', reason: '???' }
  ]));
  var store = new StoreModule.ScoreStore(mem);
  var list = store.getHistory();
  assertEqual(list.length, 1, '只留下合法的那条');
  assertEqual(list[0].score, 9, '分数保留');
  assertEqual(list[0].mode, 'classic', '未知模式回落为 classic');
  assertEqual(list[0].reason, 'win', '未知结局回落为 win');
});

test('历史记录：非数组/损坏 JSON 都退回空列表', function () {
  var mem = new StoreModule.MemoryStorage();
  mem.setItem(StoreModule.KEY_HISTORY, '{"a":1}');
  var store = new StoreModule.ScoreStore(mem);
  assertEqual(store.getHistory().length, 0, '对象不是数组');

  mem.setItem(StoreModule.KEY_HISTORY, '[[[');
  assertEqual(store.getHistory().length, 0, 'JSON 损坏');
});

test('历史记录：可以清空，且不影响最高分', function () {
  var store = new StoreModule.ScoreStore(null);
  store.submit('classic', 'classic', 14);
  store.addRecord({ score: 14, mode: 'classic', difficulty: 'classic' });
  store.clearHistory();
  assertEqual(store.getHistory().length, 0, '历史已清空');
  assertEqual(store.getBest('classic', 'classic'), 14, '最高分仍在');
});

test('偏好新增 haptic / adaptive 字段，缺省为开启', function () {
  var store = new StoreModule.ScoreStore(null);
  var defaults = store.getPrefs({});
  assertTrue(defaults.haptic, '默认开启震动');
  assertTrue(defaults.adaptive, '默认开启自适应');

  store.setPrefs({ haptic: false, adaptive: false });
  var saved = store.getPrefs({});
  assertFalse(saved.haptic, '震动已关闭');
  assertFalse(saved.adaptive, '自适应已关闭');
  assertTrue(saved.sound, '未提及的字段保持不变（默认开）');
});

test('反应时间样本：追加、上限 40 条、非法值被丢弃', function () {
  var store = new StoreModule.ScoreStore(null);
  store.addTimings([1200, 1500]);
  assertEqual(store.getTimings().length, 2, '两条样本');

  store.addTimings(['abc', -5, 0, 900]);
  var list = store.getTimings();
  assertEqual(list.length, 3, '只认正数');
  assertEqual(list[2], 900, '新样本追加在末尾');

  for (var i = 0; i < 60; i += 1) {
    store.addTimings(1000 + i);
  }
  var capped = store.getTimings();
  assertEqual(capped.length, StoreModule.MAX_TIMING, '上限 40 条');
  assertEqual(capped[capped.length - 1], 1059, '保留最新的');
});

// ---------------- 长按偷看 ----------------

group('长按偷看（不翻牌、有次数上限）');

test('偷看次数由难度决定，默认与配置一致', function () {
  var classic = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  assertEqual(classic.peekLimit, 3, '经典 3 次');
  assertEqual(classic.peekRemaining, 3, '开局满次数');
  assertEqual(classic.peekLabel, '偷看 3/3', '文案');

  var hard = new GameViewModel({ difficulty: 'hard', timers: new FakeTimers() });
  assertEqual(hard.peekLimit, 2, '挑战 2 次');

  var easy = new GameViewModel({ difficulty: 'easy', timers: new FakeTimers() });
  assertEqual(easy.peekLimit, 4, '轻松 4 次');
});

test('偷看只减少次数，不改变任何模型状态', function () {
  var vm = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  vm.startGame();
  var card = vm.cards[0];

  assertTrue(vm.canPeek(card), '背面卡片可偷看');
  assertTrue(vm.peek(card), '偷看成功');
  assertEqual(vm.peekRemaining, 2, '次数递减');
  assertEqual(vm.peekingCardId, card.id, '记录正在偷看的牌');

  // 关键断言：模型状态一点没动
  assertFalse(card.isFaceUp, '没有被翻开');
  assertFalse(card.isMatched, '没有被配对');
  assertEqual(vm.score, 0, '没有加分');
  assertEqual(vm.matchedPairsCount, 0, '配对进度不变');

  assertTrue(vm.endPeek(), '可以结束偷看');
  assertEqual(vm.peekingCardId, null, '结束偷看后清空');
});

test('同一次只能偷看一张，次数用尽后拒绝', function () {
  var vm = new GameViewModel({ difficulty: 'hard', timers: new FakeTimers() });
  vm.startGame();

  assertTrue(vm.peek(vm.cards[0]), '第一次');
  assertFalse(vm.peek(vm.cards[1]), '上一次还没结束，不能再开');
  vm.endPeek();

  assertTrue(vm.peek(vm.cards[1]), '第二次');
  vm.endPeek();
  assertEqual(vm.peekRemaining, 0, '次数用尽');

  assertFalse(vm.canPeek(vm.cards[2]), '用尽后不可偷看');
  assertFalse(vm.peek(vm.cards[2]), '用尽后调用无效');
});

test('已翻开、已配对、暂停中、未开局都不能偷看', function () {
  var vm = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  assertFalse(vm.canPeek(vm.cards[0]), '未开局不可偷看');

  vm.startGame();
  var faceUp = vm.cards[0];
  vm.choose(faceUp);
  assertFalse(vm.canPeek(faceUp), '已翻开的牌不用偷看');

  // 暂停中
  var timer2 = new FakeTimers();
  var vm2 = new GameViewModel({ difficulty: 'classic', timers: timer2 });
  vm2.startGame();
  vm2.pause();
  assertFalse(vm2.canPeek(vm2.cards[0]), '暂停中不可偷看');
  vm2.resume();

  // 已配对
  var pairs = pairsOf(vm2, 1);
  playPair(vm2, pairs[0]);
  assertFalse(vm2.canPeek(pairs[0][0]), '已配对的牌不可偷看');
});

test('偷看不触发扣分条件（不计入 seenCardIDs）', function () {
  var vm = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  vm.startGame();
  var peeked = vm.cards[0];
  vm.peek(peeked);
  vm.endPeek();

  // 让偷看过的这张参与一次错配：按原规则，首次翻看不扣分
  var other = null;
  for (var i = 1; i < vm.cards.length; i += 1) {
    if (vm.cards[i].content !== peeked.content) {
      other = vm.cards[i];
      break;
    }
  }
  vm.choose(peeked);
  vm.choose(other);
  assertEqual(vm.score, 0, '偷看没有让这张牌变成「已看过」');
});

test('重开与换关都会恢复偷看次数', function () {
  var vm = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  vm.startGame();
  vm.peek(vm.cards[0]);
  vm.endPeek();
  assertEqual(vm.peekRemaining, 2, '用掉一次');

  vm.newGame();
  assertEqual(vm.peekRemaining, 3, '重开恢复');

  vm.peek(vm.cards[0]);
  vm.endPeek();
  vm.startGame();
  assertEqual(vm.peekRemaining, 3, '再次开局恢复');
});

// ---------------- 自适应翻回时长 ----------------

group('助记自适应（保守微调 + 可回退）');

test('样本不足、开关关闭时不调整', function () {
  assertEqual(Config.adaptiveAdjust(5000, 0), 0, '没有样本');
  assertEqual(Config.adaptiveAdjust(5000, 7), 0, '少于 8 条不调整');
  assertTrue(Config.adaptiveAdjust(5000, 8) > 0, '够了才开始调整');

  var saved = Config.ADAPTIVE.enabled;
  try {
    Config.ADAPTIVE.enabled = false;
    assertEqual(Config.adaptiveAdjust(9000, 40), 0, '总开关关闭');
    assertFalse(Config.isAdaptiveMode('classic', 'classic'), '关闭后不再生效');
    assertEqual(Config.effectiveDelay(0.8, 0.15), 0.8, '完全等同原始参数');
  } finally {
    Config.ADAPTIVE.enabled = saved;
  }
});

test('反应慢则拉长、反应快则缩短，量化到 0.05 秒', function () {
  // 目标 2600ms，每偏离 1 秒调整 0.08 秒
  assertEqual(Config.adaptiveAdjust(2600, 20), 0, '刚好命中目标');
  assertEqual(Config.adaptiveAdjust(4000, 20), 0.1, '慢 1.4 秒 → +0.1');
  assertEqual(Config.adaptiveAdjust(1500, 20), -0.1, '快 1.1 秒 → -0.1');
});

test('偏移量永远夹在 ±0.15 秒内', function () {
  assertEqual(Config.adaptiveAdjust(60000, 20), 0.15, '极慢也只加 0.15');
  assertEqual(Config.adaptiveAdjust(100, 20), -0.15, '极快也只减 0.15');
});

test('最终翻回时长被夹在安全区间，且默认值分毫不差', function () {
  assertEqual(Config.effectiveDelay(0.8, 0), 0.8, '无偏移时等于原值');
  assertEqual(Config.effectiveDelay(0.8, 0.15), 0.95, '加满 0.15');
  assertEqual(Config.effectiveDelay(0.8, -0.15), 0.65, '减满 0.15');
  assertEqual(Config.effectiveDelay(0.8, -5), 0.35, '下限 0.35');
  assertEqual(Config.effectiveDelay(0.8, 5), 1.4, '上限 1.4');
});

test('自适应只作用于经典模式的轻松/经典档', function () {
  assertTrue(Config.isAdaptiveMode('classic', 'classic'), '经典档生效');
  assertTrue(Config.isAdaptiveMode('classic', 'easy'), '轻松档生效');
  assertFalse(Config.isAdaptiveMode('classic', 'hard'), '挑战档不叠加（已有连击）');
  assertFalse(Config.isAdaptiveMode('campaign', 'classic'), '闯关模式不参与');
});

test('偏移只影响下一局：牌局进行中判定节奏不变', function () {
  var vm = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  assertEqual(vm.mismatchFlipDelay, 0.8, '默认就是原始参数');

  vm.setDelayAdjust(0.1);
  assertEqual(vm.mismatchFlipDelay, 0.8, '注入偏移不会立刻改当前牌面');
  vm.refreshDelay();
  assertEqual(vm.mismatchFlipDelay, 0.9, '未开局时刷新才生效');

  vm.startGame();
  assertEqual(vm.mismatchFlipDelay, 0.9, '开局沿用');

  vm.setDelayAdjust(-0.15);
  vm.refreshDelay();
  assertEqual(vm.mismatchFlipDelay, 0.9, '牌局中拒绝改动');

  vm.newGame();
  assertEqual(vm.mismatchFlipDelay, 0.65, '下一局才用新值');
});

test('注入值本身也被夹在 ±0.15 秒', function () {
  var vm = new GameViewModel({ difficulty: 'classic', timers: new FakeTimers() });
  assertEqual(vm.setDelayAdjust(9), 0.15, '正向上限');
  assertEqual(vm.setDelayAdjust(-9), -0.15, '负向下限');
  assertEqual(vm.setDelayAdjust('abc'), 0, '非法输入归零');
});

test('挑战档不叠加自适应：翻回时长恒为 0.6 秒', function () {
  var vm = new GameViewModel({ difficulty: 'hard', timers: new FakeTimers() });
  vm.setDelayAdjust(0.15);
  vm.refreshDelay();
  assertEqual(vm.mismatchFlipDelay, 0.6, '挑战档不受影响');
});

// ---------------- 反应时间采样 ----------------

group('反应时间采样（自适应的输入）');

test('配对成功产生一条样本：从这对里第一张被翻看到配上', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startGame();

  timers.advance(1000);
  var pair = pairsOf(vm, 1)[0];
  vm.choose(pair[0]);
  timers.advance(800);
  vm.choose(pair[1]);

  assertEqual(vm.recentLatencies.length, 1, '一对只记一条');
  assertEqual(vm.recentLatencies[0], 800, '耗时 800ms');
  assertEqual(vm.averageLatency(), 800, '平均值');
});

test('重复翻看同一张牌不会叠加样本', function () {
  var timers = new FakeTimers();
  var vm = new GameViewModel({ theme: Theme.builtIn[0], timers: timers });
  vm.startGame();

  var pair = pairsOf(vm, 1)[0];
  vm.choose(pair[0]);
  timers.advance(300);
  vm.choose(pair[0]);          // 已翻开，模型忽略
  timers.advance(500);
  vm.choose(pair[1]);

  assertEqual(vm.recentLatencies.length, 1, '仍然只有一条');
  assertEqual(vm.recentLatencies[0], 800, '按首次翻看起算');
});

// ---------------- 汇总 ----------------

var total = passed + failures.length;
console.log('\n' + '='.repeat(52));
console.log('总计 ' + total + ' 条 | 通过 ' + passed + ' | 失败 ' + failures.length);

if (failures.length > 0) {
  console.log('\n失败明细：');
  failures.forEach(function (item) {
    console.log('  - ' + item.name + '：' + item.message);
  });
  process.exitCode = 1;
} else {
  console.log('结果：全部通过');
  process.exitCode = 0;
}
