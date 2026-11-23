/*
 * Memorize 布局计算 —— Swift 版 AspectVGrid 与 PieGeometry 的等价移植。
 *
 * 这两个计算在原版里就是纯函数（不依赖渲染环境），原版也专门为它们写了
 * 单元测试。移植时保持同样的可测性：所有函数无副作用，输入输出确定。
 */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.MemorizeLayout = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /** 卡片宽高比（宽 / 高），对应 CardStyle.aspectRatio = 2/3。 */
  var CARD_ASPECT_RATIO = 2 / 3;

  /*
   * 卡片缝隙：按卡片宽度的 3.2% 推导，并夹在 3...10px 之间，最后取整。
   *
   * 为什么不再用「固定 2px 内缩」：
   * - 内缩 2px 是每边各 2px，相邻两张之间实际是 4px，与「2px 缝隙」的说法不符；
   * - 固定值在小卡片（手机 4 列时约 70px）上占 5.7%，在大卡片上又几乎看不见，
   *   同屏看起来疏密不一致；
   * - 现在交给 CSS Grid 的 gap 处理，间距由浏览器统一绘制，不存在相邻元素
   *   投影互相遮盖或子像素累积导致的错位。
   */
  var CARD_GAP_RATIO = 0.032;
  var MIN_CARD_GAP = 3;
  var MAX_CARD_GAP = 10;

  /**
   * 计算卡片缝隙（整数像素）。取整是为了让列宽 × 列数 + 缝隙 × (列数-1)
   * 能精确等于容器宽度，避免 0.5px 累积后右侧出现 1px 溢出或留白。
   */
  function cardGap(cardWidth) {
    if (!(cardWidth > 0)) {
      return MIN_CARD_GAP;
    }
    var raw = cardWidth * CARD_GAP_RATIO;
    return Math.round(Math.min(Math.max(raw, MIN_CARD_GAP), MAX_CARD_GAP));
  }

  /**
   * 计算在给定可用空间内、能完整放下所有卡片的最大卡片宽度。
   *
   * 对应 Swift AspectVGrid.itemWidthThatFits：
   * 列数从 1 开始逐列增加，直到「行数 × 单元高度」不超过可用高度。
   *
   * @param {number} count        卡片数量
   * @param {number} width        可用宽度
   * @param {number} height       可用高度
   * @param {number} aspectRatio  卡片宽高比（宽 / 高），必须大于 0
   * @param {number} [gap]        卡片缝隙（像素），默认 0 表示紧贴
   * @returns {number} 卡片宽度（向下取整）；输入非法或无法放下时返回 0
   */
  function itemWidthThatFits(count, width, height, aspectRatio, gap) {
    if (!(count > 0) || !(width > 0) || !(height > 0) || !(aspectRatio > 0)) {
      return 0;
    }

    var g = gap > 0 ? gap : 0;
    var columnCount = 1;
    while (columnCount < count) {
      // 缝隙也占宽度：n 列共 (n-1) 道缝
      var candidateWidth = (width - (columnCount - 1) * g) / columnCount;
      if (!(candidateWidth > 0)) {
        break;
      }
      var candidateHeight = candidateWidth / aspectRatio;
      var rowCount = Math.ceil(count / columnCount);
      // 纵向同理：(行数-1) 道缝
      if (rowCount * candidateHeight + (rowCount - 1) * g <= height) {
        return Math.floor(candidateWidth);
      }
      columnCount += 1;
    }

    // 循环结束时 columnCount 已等于 count，这里补检一次满列布局。
    // 原版 repeat...while 在此处直接进入兜底；两种写法结果一致，
    // 但先补检一次能避免满列刚好放下时被兜底公式误压小。
    var lastWidth = (width - (count - 1) * g) / count;
    if (!(lastWidth > 0)) {
      return 0;
    }
    var lastHeight = lastWidth / aspectRatio;
    if (1 * lastHeight <= height) {
      return Math.floor(lastWidth);
    }

    // 兜底：单列也放不下时，按宽高两个方向分别压缩后取更小值。
    return Math.floor(Math.min(lastWidth, height * aspectRatio));
  }

  /**
   * 计算实际列数：给定卡片宽度与缝隙后，一行能放下几张。
   * n 张卡占 n×宽 + (n-1)×缝，反解 n = floor((可用宽 + 缝) / (卡宽 + 缝))。
   */
  function columnCountFor(width, itemWidth, gap) {
    if (!(itemWidth > 0) || !(width > 0)) {
      return 1;
    }
    var g = gap > 0 ? gap : 0;
    return Math.max(1, Math.floor((width + g) / (itemWidth + g)));
  }

  /** 环形倒计时的剩余进度，范围 0...1（对应 PieGeometry.progress）。 */
  function pieProgress(remaining, total) {
    if (!(total > 0)) {
      return 0;
    }
    if (remaining <= 0) {
      return 0;
    }
    if (remaining >= total) {
      return 1;
    }
    return remaining / total;
  }

  /** 环形描边宽度：直径的 10%，限制在 3...10（对应 PieGeometry.ringWidth）。 */
  function ringWidth(diameter) {
    if (!(diameter > 0)) {
      return 0;
    }
    return Math.min(Math.max(diameter * 0.1, 3), 10);
  }

  /**
   * 卡片几何量，对应 CardStyle 的一组比例函数：
   * 全部按短边等比缩放并做上下限约束。
   */
  function cardMetrics(width, height) {
    if (!(width > 0) || !(height > 0)) {
      return { cornerRadius: 0, borderWidth: 0, contentPadding: 0, shadowRadius: 0 };
    }
    var shortSide = Math.min(width, height);
    return {
      cornerRadius: Math.min(Math.max(shortSide * 0.12, 6), 20),
      borderWidth: Math.min(Math.max(shortSide * 0.01, 1), 3),
      contentPadding: Math.min(Math.max(shortSide * 0.08, 2), 8),
      shadowRadius: Math.min(Math.max(shortSide * 0.03, 1), 6)
    };
  }

  /**
   * 第 index 张卡片的发牌延迟（秒），对应 AnimationTiming.dealDelay。
   * 按下标线性错峰，并封顶 dealMaxStagger。
   */
  function dealDelay(index) {
    if (!(index > 0)) {
      return 0;
    }
    return Math.min(index * 0.06, 0.6);
  }

  return {
    CARD_ASPECT_RATIO: CARD_ASPECT_RATIO,
    MIN_CARD_GAP: MIN_CARD_GAP,
    MAX_CARD_GAP: MAX_CARD_GAP,
    cardGap: cardGap,
    itemWidthThatFits: itemWidthThatFits,
    columnCountFor: columnCountFor,
    pieProgress: pieProgress,
    ringWidth: ringWidth,
    cardMetrics: cardMetrics,
    dealDelay: dealDelay
  };
}));
