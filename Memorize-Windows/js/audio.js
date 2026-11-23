/*
 * Memorize 音效 —— 用 WebAudio 现场合成，不引入任何音频文件。
 *
 * 为什么不用 mp3/ogg：
 * - 纯 file:// 打开时，音频文件的加载与解码在部分浏览器上会被 CORS 策略拦住，
 *   出现「本地能响、拷给别人就哑」的问题；
 * - 合成音只有几十行，零体积、零请求，弱网和离线都能用；
 * - 音色可以随时调参，不需要重新找素材。
 *
 * 所有调用都必须是无害的：浏览器不支持、上下文被策略挂起、用户关掉音效，
 * 都只应静默返回，绝不能让异常冒到调用方（音效只是锦上添花，不能拖垮游戏）。
 */
(function (root) {
  'use strict';

  /** 常用音高（Hz），按十二平均律取近似值。 */
  var NOTE = {
    C4: 261.6,
    E4: 329.6,
    G4: 392.0,
    A4: 440.0,
    B4: 493.9,
    C5: 523.3,
    D5: 587.3,
    E5: 659.3,
    G5: 784.0,
    A5: 880.0,
    C6: 1046.5
  };

  function SoundKit(options) {
    var opts = options || {};
    this.enabled = opts.enabled !== false;
    this.volume = typeof opts.volume === 'number' ? opts.volume : 0.075;
    this._ctx = null;
    this._broken = false;
  }

  /** 首次用户手势时调用：创建/唤醒音频上下文（移动端必须由手势触发）。 */
  SoundKit.prototype.unlock = function () {
    if (this._broken) {
      return null;
    }
    try {
      if (!this._ctx) {
        var Ctor = root.AudioContext || root.webkitAudioContext;
        if (!Ctor) {
          this._broken = true;
          return null;
        }
        this._ctx = new Ctor();
      }
      if (this._ctx.state === 'suspended' && typeof this._ctx.resume === 'function') {
        this._ctx.resume();
      }
      return this._ctx;
    } catch (error) {
      this._broken = true;
      return null;
    }
  };

  SoundKit.prototype.setEnabled = function (enabled) {
    this.enabled = enabled === true;
    if (this.enabled) {
      this.unlock();
    }
  };

  /**
   * 播放一个单音。
   * @param {number} freq     频率（Hz）
   * @param {number} offset   相对当前时刻的起始延迟（秒）
   * @param {number} duration 持续时长（秒）
   * @param {string} type     波形
   * @param {number} [gain]   音量倍数（相对总音量）
   */
  SoundKit.prototype._tone = function (freq, offset, duration, type, gain) {
    var ctx = this._ctx;
    if (!ctx) {
      return;
    }

    try {
      var start = ctx.currentTime + offset;
      var peak = this.volume * (gain == null ? 1 : gain);

      var osc = ctx.createOscillator();
      var env = ctx.createGain();

      osc.type = type || 'sine';
      osc.frequency.setValueAtTime(freq, start);

      // 短促的起音 + 指数衰减，听感更像「咔哒」而不是「嘀——」
      env.gain.setValueAtTime(0.0001, start);
      env.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0002), start + 0.012);
      env.gain.exponentialRampToValueAtTime(0.0001, start + duration);

      osc.connect(env);
      env.connect(ctx.destination);
      osc.start(start);
      osc.stop(start + duration + 0.02);
    } catch (error) {
      // 单个音符失败不影响其它音符，也不影响游戏
    }
  };

  /** 依次播放一串音符；notes 为 [频率, 相对延迟, 时长, 波形, 音量] 数组。 */
  SoundKit.prototype._sequence = function (notes) {
    for (var i = 0; i < notes.length; i += 1) {
      var note = notes[i];
      this._tone(note[0], note[1], note[2], note[3] || 'sine', note[4]);
    }
  };

  SoundKit.prototype.play = function (name) {
    if (!this.enabled) {
      return;
    }
    if (this.unlock() === null) {
      return;
    }

    switch (name) {
      case 'flip':
        this._sequence([[NOTE.E5, 0, 0.055, 'triangle', 0.55]]);
        break;

      case 'match':
        this._sequence([
          [NOTE.E5, 0, 0.09, 'sine', 1],
          [NOTE.A5, 0.07, 0.13, 'sine', 0.9]
        ]);
        break;

      case 'mismatch':
        this._sequence([
          [NOTE.G4 / 2, 0, 0.10, 'triangle', 0.85],
          [NOTE.E4 / 2, 0.08, 0.13, 'triangle', 0.7]
        ]);
        break;

      case 'levelclear':
        this._sequence([
          [NOTE.C5, 0, 0.10, 'sine', 0.9],
          [NOTE.E5, 0.09, 0.10, 'sine', 0.9],
          [NOTE.G5, 0.18, 0.16, 'sine', 0.9]
        ]);
        break;

      case 'win':
        this._sequence([
          [NOTE.C5, 0, 0.11, 'sine', 0.95],
          [NOTE.E5, 0.10, 0.11, 'sine', 0.95],
          [NOTE.G5, 0.20, 0.11, 'sine', 0.95],
          [NOTE.C6, 0.30, 0.30, 'sine', 1]
        ]);
        break;

      case 'timeout':
        this._sequence([
          [NOTE.E4, 0, 0.16, 'sine', 0.9],
          [NOTE.C4, 0.14, 0.28, 'sine', 0.85]
        ]);
        break;

      case 'pause':
        this._sequence([
          [NOTE.A4, 0, 0.07, 'sine', 0.7],
          [NOTE.E4, 0.06, 0.10, 'sine', 0.6]
        ]);
        break;

      case 'resume':
        this._sequence([
          [NOTE.E4, 0, 0.07, 'sine', 0.7],
          [NOTE.A4, 0.06, 0.10, 'sine', 0.65]
        ]);
        break;

      case 'click':
        this._sequence([[NOTE.G5, 0, 0.035, 'triangle', 0.4]]);
        break;

      default:
        break;
    }
  };

  root.MemorizeAudio = { SoundKit: SoundKit, NOTE: NOTE };
}(typeof self !== 'undefined' ? self : this));
