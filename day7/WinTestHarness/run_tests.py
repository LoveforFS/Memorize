# -*- coding: utf-8 -*-
"""
D7 模块 Windows 行为等价测试执行器。

设计目标：
1. 不修改 day7/MemorizeTests 与 day7/MemorizeUITests 中的任何 Swift 测试文件；
2. 在 Windows + Python 3 上以 unittest 真实执行 132 条用例（D6 基线 98 条 + D7 新增 34 条）；
3. 每条用例与 Swift 测试方法一一对应，断言内容保持一致；
4. 输出结构化结果（名、状态、耗时、失败信息与堆栈），并校验映射完整性。

说明：本执行器是对 Swift 模型、视图模型、布局算法、动画策略、卡片几何与倒计时状态机的
行为等价镜像，不是 XCTest 原生执行；UI 用例以状态投影方式验证与 Swift 版相同的可见结论。
"""

import json
import math
import os
import re
import sys
import time
import traceback
import unittest
import uuid
from dataclasses import dataclass, field
from typing import List, Optional, Set


# ---------------------------------------------------------------------------
# 领域模型（镜像 day5/Memorize/Models）
# ---------------------------------------------------------------------------

class ValidationError(Exception):
    """镜像 Theme.ValidationError。"""

    def __init__(self, code: str, value: Optional[int] = None):
        self.code = code
        self.value = value
        super().__init__(code if value is None else "%s(%d)" % (code, value))


@dataclass
class Theme:
    name: str
    emojis: List[str]
    color: str
    number_of_pairs: int


def make_theme(name: str = "测试主题", emojis: Optional[List[str]] = None,
               color: str = "blue", number_of_pairs: Optional[int] = None) -> Theme:
    trimmed_name = name.strip()
    if not trimmed_name:
        raise ValidationError("emptyName")

    cleaned = [e.strip() for e in (emojis if emojis is not None else []) if e.strip()]
    if not cleaned:
        raise ValidationError("emptyEmojiSet")

    pairs = len(cleaned) if number_of_pairs is None else number_of_pairs
    if pairs <= 0:
        raise ValidationError("invalidNumberOfPairs", pairs)

    return Theme(trimmed_name, cleaned, color, min(pairs, len(cleaned)))


def built_in_themes() -> List[Theme]:
    """镜像 Theme.builtIn，顺序与内容保持一致。"""
    return [
        Theme("动物", ["🐶", "🐱", "🐭", "🐹", "🐰", "🐻", "🐼", "🐨"], "orange", 8),
        Theme("运动", ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏓", "🏸"], "green", 8),
        Theme("表情", ["😀", "😅", "🥲", "😍", "🤔", "😴", "🥳", "😎"], "yellow", 8),
        Theme("旗帜", ["🇨🇳", "🇯🇵", "🇰🇷", "🇫🇷", "🇩🇪", "🇮🇹", "🇪🇸", "🇬🇧"], "red", 8),
        Theme("天气", ["☀️", "🌤", "☁️", "🌧", "⛈", "❄️", "🌪", "🌈"], "blue", 8),
        Theme("食物", ["🍎", "🍌", "🍇", "🍓", "🍑", "🍍", "🥝", "🍒"], "pink", 8),
    ]


@dataclass(eq=False)
class Card:
    """镜像 Card：按 id 相等，内容创建时去空白。"""
    content: str
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    is_face_up: bool = False
    is_matched: bool = False

    def __post_init__(self):
        self.content = self.content.strip()
        if not self.content:
            raise ValueError("卡片内容不能为空")

    def __eq__(self, other):
        return isinstance(other, Card) and self.id == other.id

    def __hash__(self):
        return hash(self.id)


class Game:
    """镜像 Game：单一牌局状态源。"""

    def __init__(self, theme: Theme, number_of_pairs: Optional[int] = None,
                 shuffle: bool = True):
        pairs = Game.clamp(number_of_pairs if number_of_pairs is not None
                           else theme.number_of_pairs, len(theme.emojis))
        self.theme = theme
        self.number_of_pairs = pairs
        self.cards = Game.make_deck(theme.emojis, pairs, shuffle)
        self.score = 0
        self.index_of_face_up_card: Optional[int] = None
        self.seen_card_ids: Set[str] = set()
        self.mismatched_card_ids: List[str] = []

    @staticmethod
    def clamp(pairs: int, emoji_count: int) -> int:
        return max(1, min(pairs, emoji_count))

    @staticmethod
    def make_deck(emojis: List[str], number_of_pairs: int, shuffle: bool = True) -> List[Card]:
        pairs = Game.clamp(number_of_pairs, len(emojis))
        selected = emojis[:pairs]
        deck: List[Card] = []
        for emoji in selected:
            deck.append(Card(content=emoji))
            deck.append(Card(content=emoji))
        if shuffle:
            import random
            random.shuffle(deck)
        return deck

    @property
    def is_game_over(self) -> bool:
        return bool(self.cards) and all(c.is_matched for c in self.cards)

    @property
    def has_pending_mismatch(self) -> bool:
        return bool(self.mismatched_card_ids)

    @property
    def matched_pairs_count(self) -> int:
        return len([c for c in self.cards if c.is_matched]) // 2

    def choose(self, card: Card) -> None:
        index = next((i for i, c in enumerate(self.cards) if c.id == card.id), None)
        if index is None:
            return
        if self.cards[index].is_matched or self.cards[index].is_face_up:
            return

        self.flip_back_mismatch()
        self.cards[index].is_face_up = True

        if self.index_of_face_up_card is None or self.index_of_face_up_card == index:
            self.index_of_face_up_card = index
            return

        first_index = self.index_of_face_up_card
        if self.cards[first_index].content == self.cards[index].content:
            self.cards[first_index].is_matched = True
            self.cards[index].is_matched = True
            self.score += 2
        else:
            has_seen = (self.cards[first_index].id in self.seen_card_ids
                        or self.cards[index].id in self.seen_card_ids)
            if has_seen:
                self.score -= 1
            self.mismatched_card_ids = [self.cards[first_index].id, self.cards[index].id]

        self.seen_card_ids.add(self.cards[first_index].id)
        self.seen_card_ids.add(self.cards[index].id)
        self.index_of_face_up_card = None

    def flip_back_mismatch(self) -> None:
        if not self.mismatched_card_ids:
            return
        for card_id in self.mismatched_card_ids:
            for card in self.cards:
                if card.id == card_id:
                    card.is_face_up = False
        self.mismatched_card_ids = []

    def new_game(self, shuffle: bool = True) -> None:
        self._reset(self.theme, self.number_of_pairs, shuffle)

    def start_new_game(self, theme: Theme, shuffle: bool = True) -> None:
        self._reset(theme, Game.clamp(theme.number_of_pairs, len(theme.emojis)), shuffle)

    def _reset(self, theme: Theme, number_of_pairs: int, shuffle: bool) -> None:
        self.theme = theme
        self.number_of_pairs = number_of_pairs
        self.cards = Game.make_deck(theme.emojis, number_of_pairs, shuffle)
        self.score = 0
        self.index_of_face_up_card = None
        self.seen_card_ids = set()
        self.mismatched_card_ids = []


# ---------------------------------------------------------------------------
# 计时调度与视图模型（镜像 day4/Memorize/ViewModels）
# ---------------------------------------------------------------------------

class FakeMismatchTimer:
    """镜像测试目标中的 FakeMismatchTimer：记录延迟值，手动触发。"""

    def __init__(self):
        self.scheduled_delays: List[float] = []
        self.pending_actions = []

    @property
    def pending_count(self) -> int:
        return len(self.pending_actions)

    def schedule(self, delay: float, action) -> None:
        self.scheduled_delays.append(delay)
        self.pending_actions.append(action)

    def fire_all(self) -> None:
        actions = list(self.pending_actions)
        self.pending_actions.clear()
        for action in actions:
            action()

    def fire_next(self) -> None:
        if not self.pending_actions:
            return
        action = self.pending_actions.pop(0)
        action()


class GameViewModel:
    """镜像 GameViewModel：@Published cards/score + 计时调度。"""

    def __init__(self, theme: Optional[Theme] = None,
                 number_of_pairs: Optional[int] = None, shuffle: bool = True,
                 mismatch_flip_delay: float = 0.8, timer=None, countdown_clock=None):
        theme = theme if theme is not None else built_in_themes()[0]
        timer = timer if timer is not None else FakeMismatchTimer()
        self.game = Game(theme, number_of_pairs, shuffle)
        self.cards = list(self.game.cards)
        self.score = self.game.score
        self.is_interaction_locked = False
        self.mismatch_flip_delay = mismatch_flip_delay
        self.timer = timer
        self.pending_timer_token: Optional[str] = None
        self.animations = GameAnimationCoordinator()
        self.board_revision = 0
        self.score_revision = 0
        self.score_change_delta = 0
        self.countdown_clock = countdown_clock if countdown_clock is not None else FakeCountdownClock()
        self.countdown_remaining = 0
        self.countdown_total = 0
        self.countdown_state = CountdownState.IDLE
        self.did_time_out = False
        self._countdown_duration = 0

    @property
    def theme(self) -> Theme:
        return self.game.theme

    @property
    def is_game_over(self) -> bool:
        return self.game.is_game_over

    @property
    def matched_pairs_count(self) -> int:
        return self.game.matched_pairs_count

    @property
    def has_pending_mismatch(self) -> bool:
        return self.game.has_pending_mismatch

    def choose(self, card: Card) -> None:
        if self.is_interaction_locked:
            return

        previous_score = self.game.score
        was_face_up = any(c.id == card.id and c.is_face_up for c in self.game.cards)

        self.game.choose(card)
        self._sync_from_game()

        updated = next((c for c in self.game.cards if c.id == card.id), None)
        if not was_face_up and updated is not None and updated.is_face_up:
            self.animations.begin_flip(updated.id)

        revision = self.animations.score_did_change(previous_score, self.game.score)
        if revision is not None:
            self.score_revision = revision
            self.score_change_delta = AnimationTiming.score_delta(previous_score, self.game.score)

        if self.game.has_pending_mismatch:
            self.is_interaction_locked = True
            self._schedule_flip_back()

    def end_flip(self, card_id: str) -> None:
        self.animations.end_flip(card_id)

    # MARK: - 倒计时（M8）

    def start_countdown(self, duration: Optional[int] = None) -> None:
        duration = CountdownDefaults.duration if duration is None else duration
        if duration <= 0:
            return

        self.countdown_clock.stop()
        self._countdown_duration = duration
        self.countdown_total = duration
        self.countdown_remaining = duration
        self.did_time_out = False
        self.countdown_state = CountdownState.RUNNING
        self._schedule_countdown_ticks()

    def start_countdown_if_needed(self) -> None:
        if self.countdown_state != CountdownState.IDLE or self._countdown_duration != 0:
            return
        self.start_countdown()

    def tick_countdown(self) -> None:
        if self.countdown_state != CountdownState.RUNNING:
            return

        if self.countdown_remaining <= 0:
            self._finish_countdown()
            return

        self.countdown_remaining -= 1
        if self.countdown_remaining == 0:
            self._finish_countdown()

    def pause_countdown(self) -> None:
        if self.countdown_state != CountdownState.RUNNING:
            return
        self.countdown_clock.stop()
        self.countdown_state = CountdownState.PAUSED

    def resume_countdown(self) -> None:
        if self.countdown_state != CountdownState.PAUSED:
            return
        self.countdown_state = CountdownState.RUNNING
        self._schedule_countdown_ticks()

    def toggle_countdown(self) -> None:
        if self.countdown_state == CountdownState.RUNNING:
            self.pause_countdown()
        elif self.countdown_state == CountdownState.PAUSED:
            self.resume_countdown()
        elif self.countdown_state == CountdownState.IDLE:
            self.start_countdown()

    def stop_countdown(self) -> None:
        self.countdown_clock.stop()
        self._countdown_duration = 0
        self.countdown_remaining = 0
        self.countdown_total = 0
        self.did_time_out = False
        self.countdown_state = CountdownState.IDLE

    def _schedule_countdown_ticks(self) -> None:
        self.countdown_clock.start(CountdownDefaults.tick_interval, self.tick_countdown)

    def _finish_countdown(self) -> None:
        self.countdown_clock.stop()
        self.countdown_remaining = 0
        self.did_time_out = True
        self.countdown_state = CountdownState.FINISHED
        self.is_interaction_locked = True

    def _restart_countdown_if_needed(self) -> None:
        if self._countdown_duration <= 0:
            return
        self.start_countdown(self._countdown_duration)

    def complete_mismatch_flip_back(self) -> None:
        self.pending_timer_token = None
        if not self.game.has_pending_mismatch:
            return
        self.animations.end_all_flips()
        self.game.flip_back_mismatch()
        self._sync_from_game()
        # 时间到后保持锁定，避免翻回任务把超时锁定意外解除。
        self.is_interaction_locked = self.countdown_state == CountdownState.FINISHED

    def new_game(self) -> None:
        self.pending_timer_token = None
        self.is_interaction_locked = False
        self.score_change_delta = 0
        self.game.new_game()
        self._sync_from_game()
        self.board_revision = self.animations.begin_new_board()
        self._restart_countdown_if_needed()

    def choose_theme(self, theme: Theme) -> None:
        self.pending_timer_token = None
        self.is_interaction_locked = False
        self.score_change_delta = 0
        self.game.start_new_game(theme)
        self._sync_from_game()
        self.board_revision = self.animations.begin_new_board()
        self._restart_countdown_if_needed()

    def _schedule_flip_back(self) -> None:
        if self.pending_timer_token is not None:
            return
        token = str(uuid.uuid4())
        self.pending_timer_token = token

        def action():
            if self.pending_timer_token == token:
                self.complete_mismatch_flip_back()

        self.timer.schedule(self.mismatch_flip_delay, action)

    def _sync_from_game(self) -> None:
        self.cards = self.game.cards
        self.score = self.game.score


# ---------------------------------------------------------------------------
# UI 状态投影（镜像 SwiftUI 视图的可访问性输出，用于 UI 用例的等价断言）
# ---------------------------------------------------------------------------

def card_label(card: Card) -> str:
    if card.is_matched:
        return "已配对的卡片 %s" % card.content
    if card.is_face_up:
        return "已翻开的卡片 %s" % card.content
    return "未翻开的卡片"


def hint_label(view_model: GameViewModel) -> str:
    return ("配对失败，卡片即将翻回…" if view_model.is_interaction_locked
            else "点击卡片翻开，找出全部对子")


def theme_label(view_model: GameViewModel) -> str:
    return "主题：%s" % view_model.theme.name


def score_label(view_model: GameViewModel) -> str:
    return str(view_model.score)


# ---------------------------------------------------------------------------
# 布局算法（镜像 day5/Memorize/Views/AspectVGrid.swift）
# ---------------------------------------------------------------------------

class AspectVGrid:
    """镜像 AspectVGrid.itemWidthThatFits：按可用空间求最大卡片宽度。"""

    @staticmethod
    def item_width_that_fits(count: int, width: float, height: float,
                             aspect_ratio: float) -> float:
        if count <= 0 or width <= 0 or height <= 0 or aspect_ratio <= 0:
            return 0.0

        item_count = float(count)
        column_count = 1.0
        while True:
            item_width = width / column_count
            item_height = item_width / aspect_ratio
            row_count = math.ceil(item_count / column_count)
            if row_count * item_height <= height:
                return float(math.floor(item_width))
            column_count += 1.0
            if not column_count < item_count:
                break

        return float(math.floor(min(width / item_count, height * aspect_ratio)))


# ---------------------------------------------------------------------------
# 动画策略与边界控制（镜像 day6/Memorize/Views/AnimationTiming.swift 与
# day6/Memorize/ViewModels/GameAnimationCoordinator.swift）
# ---------------------------------------------------------------------------

class AnimationTiming:
    """镜像 AnimationTiming：动画时长、错峰延迟与得分反馈幅度。"""

    flip_duration = 0.45
    deal_duration = 0.35
    deal_stagger = 0.06
    deal_max_stagger = 0.6
    score_pop_duration = 0.3
    score_pop_scale = 1.25
    score_delta_visible_duration = 0.7

    @staticmethod
    def deal_delay(index: int) -> float:
        if index <= 0:
            return 0.0
        return min(index * AnimationTiming.deal_stagger, AnimationTiming.deal_max_stagger)

    @staticmethod
    def score_delta(old_value: int, new_value: int) -> int:
        return new_value - old_value


class GameAnimationCoordinator:
    """镜像 GameAnimationCoordinator：翻牌去重、得分合并与牌局版本号。"""

    def __init__(self):
        self.board_revision = 0
        self.score_revision = 0
        self.active_flip_card_ids = set()

    @property
    def active_flip_count(self) -> int:
        return len(self.active_flip_card_ids)

    def begin_new_board(self) -> int:
        self.active_flip_card_ids.clear()
        self.board_revision += 1
        return self.board_revision

    def begin_flip(self, card_id: str) -> bool:
        if card_id in self.active_flip_card_ids:
            return False
        self.active_flip_card_ids.add(card_id)
        return True

    def end_flip(self, card_id: str) -> None:
        self.active_flip_card_ids.discard(card_id)

    def end_all_flips(self) -> None:
        self.active_flip_card_ids.clear()

    def score_did_change(self, old_value: int, new_value: int) -> Optional[int]:
        if old_value == new_value:
            return None
        self.score_revision += 1
        return self.score_revision


# ---------------------------------------------------------------------------
# M8：卡片外观与环形倒计时（镜像 Cardify.swift / Pie.swift / CountdownClock.swift）
# ---------------------------------------------------------------------------

class CountdownState:
    IDLE = "idle"
    RUNNING = "running"
    PAUSED = "paused"
    FINISHED = "finished"


class CountdownDefaults:
    duration = 60
    tick_interval = 1.0


class FakeCountdownClock:
    """镜像测试用 FakeCountdownClock：手动推进，不依赖真实等待。"""

    def __init__(self):
        self.start_count = 0
        self.stop_count = 0
        self.last_interval: Optional[float] = None
        self._on_tick = None

    @property
    def is_running(self) -> bool:
        return self._on_tick is not None

    def start(self, interval: float, on_tick) -> None:
        self.start_count += 1
        self.last_interval = interval
        self._on_tick = on_tick

    def stop(self) -> None:
        self.stop_count += 1
        self._on_tick = None

    def tick(self, times: int = 1) -> None:
        for _ in range(times):
            if self._on_tick is not None:
                self._on_tick()


class CardStyle:
    """镜像 CardStyle：卡片几何量按短边缩放并受限。"""

    aspect_ratio = 2 / 3

    @staticmethod
    def corner_radius(width: float, height: float) -> float:
        if width <= 0 or height <= 0:
            return 0.0
        base = min(width, height) * 0.12
        return min(max(base, 6.0), 20.0)

    @staticmethod
    def border_width(width: float, height: float) -> float:
        if width <= 0 or height <= 0:
            return 0.0
        base = min(width, height) * 0.01
        return min(max(base, 1.0), 3.0)

    @staticmethod
    def content_padding(width: float, height: float) -> float:
        if width <= 0 or height <= 0:
            return 0.0
        base = min(width, height) * 0.08
        return min(max(base, 2.0), 8.0)

    @staticmethod
    def shadow_radius(width: float, height: float) -> float:
        if width <= 0 or height <= 0:
            return 0.0
        base = min(width, height) * 0.03
        return min(max(base, 1.0), 6.0)


class PieGeometry:
    """镜像 PieGeometry：进度、角度与环宽。"""

    start_angle = -90.0

    @staticmethod
    def progress(remaining: int, total: int) -> float:
        if total <= 0:
            return 0.0
        if remaining <= 0:
            return 0.0
        if remaining >= total:
            return 1.0
        return float(remaining) / float(total)

    @staticmethod
    def end_angle(progress: float) -> float:
        clamped = min(max(progress, 0.0), 1.0)
        return -90.0 + 360.0 * clamped

    @staticmethod
    def ring_width(diameter: float) -> float:
        if diameter <= 0:
            return 0.0
        base = diameter * 0.1
        return min(max(base, 3.0), 10.0)


# ---------------------------------------------------------------------------
# 测试基类（镜像 XCTest 的辅助方法）
# ---------------------------------------------------------------------------

class MemorizeTestCase(unittest.TestCase):

    def makeTheme(self, name: str = "测试主题",
                  emojis: Optional[List[str]] = None,
                  numberOfPairs: Optional[int] = None) -> Theme:
        if emojis is None:
            emojis = ["🐶", "🐱", "🐭", "🐹"]
        return make_theme(name=name, emojis=emojis, number_of_pairs=numberOfPairs)

    def makeGame(self, pairs: int = 2) -> Game:
        return Game(self.makeTheme(), pairs, False)

    def makeViewModel(self, pairs: int = 2, delay: float = 0.8):
        timer = FakeMismatchTimer()
        view_model = GameViewModel(self.makeTheme(), pairs, False, delay, timer)
        return view_model, timer


# ---------------------------------------------------------------------------
# 套件一：GameModelTests（28 条）
# ---------------------------------------------------------------------------

class GameModelTests(MemorizeTestCase):

    # ---- Theme ----

    def testThemeTrimsNameAndEmojis(self):
        theme = make_theme(name="  动物  ", emojis=["  🐶 ", "", "🐱"], color="orange")
        self.assertEqual(theme.name, "动物")
        self.assertEqual(theme.emojis, ["🐶", "🐱"])
        self.assertEqual(theme.number_of_pairs, 2)

    def testThemeWithEmptyNameThrows(self):
        with self.assertRaises(ValidationError) as ctx:
            make_theme(name="   ", emojis=["🐶"], color="red")
        self.assertEqual(ctx.exception.code, "emptyName")

    def testThemeWithoutEmojisThrows(self):
        with self.assertRaises(ValidationError) as ctx:
            make_theme(name="空主题", emojis=[], color="red")
        self.assertEqual(ctx.exception.code, "emptyEmojiSet")

        with self.assertRaises(ValidationError) as ctx2:
            make_theme(name="空白主题", emojis=[" ", "\n"], color="red")
        self.assertEqual(ctx2.exception.code, "emptyEmojiSet")

    def testThemeWithNonPositivePairsThrows(self):
        for pairs in (0, -3):
            with self.assertRaises(ValidationError) as ctx:
                make_theme(name="非法对数", emojis=["🐶", "🐱"], color="red",
                           number_of_pairs=pairs)
            self.assertEqual(ctx.exception.code, "invalidNumberOfPairs")
            self.assertEqual(ctx.exception.value, pairs)

    def testThemeClampsPairsToEmojiCount(self):
        theme = self.makeTheme(numberOfPairs=99)
        self.assertEqual(theme.number_of_pairs, len(theme.emojis))

    def testBuiltInThemesAreValid(self):
        themes = built_in_themes()
        self.assertEqual(len(themes), 6)
        self.assertEqual(len({t.name for t in themes}), len(themes))
        for theme in themes:
            self.assertTrue(theme.name)
            self.assertTrue(theme.emojis)
            self.assertEqual(theme.number_of_pairs, len(theme.emojis))

    # ---- Card ----

    def testCardDefaultState(self):
        card = Card(content="🐶")
        self.assertFalse(card.is_face_up)
        self.assertFalse(card.is_matched)
        self.assertEqual(card.content, "🐶")

    def testCardTrimsContent(self):
        self.assertEqual(Card(content="  🐱  ").content, "🐱")

    def testCardEqualityUsesIdentity(self):
        card_id = str(uuid.uuid4())
        card = Card(id=card_id, content="🐶")
        same_after_flip = Card(id=card_id, content="🐶", is_face_up=True, is_matched=True)
        another = Card(content="🐶")
        self.assertEqual(card, same_after_flip)
        self.assertNotEqual(card, another)

    # ---- 牌组 ----

    def testDeckContainsTwoCardsPerPair(self):
        deck = Game.make_deck(["🐶", "🐱", "🐭"], 3, False)
        self.assertEqual(len(deck), 6)
        self.assertEqual({c.content for c in deck}, {"🐶", "🐱", "🐭"})
        self.assertEqual(len({c.id for c in deck}), len(deck))

    def testUnshuffledDeckKeepsPairsTogether(self):
        deck = Game.make_deck(["🐶", "🐱"], 2, False)
        self.assertEqual([c.content for c in deck], ["🐶", "🐶", "🐱", "🐱"])

    def testDeckClampsOutOfRangePairs(self):
        self.assertEqual(len(Game.make_deck(["🐶", "🐱"], 0, False)), 2)
        self.assertEqual(len(Game.make_deck(["🐶", "🐱"], 5, False)), 4)

    def testShuffleKeepsContentMultiset(self):
        emojis = ["🐶", "🐱", "🐭", "🐹"]
        shuffled = Game.make_deck(emojis, 4, True)
        self.assertEqual(sorted(c.content for c in shuffled), sorted(emojis + emojis))
        self.assertEqual(len({c.id for c in shuffled}), len(shuffled))

    def testGameInitializerClampsNumberOfPairs(self):
        theme = self.makeTheme(emojis=["🐶", "🐱"])
        game = Game(theme, 5, False)
        self.assertEqual(game.number_of_pairs, 2)
        self.assertEqual(len(game.cards), 4)

    def testGameUsesThemePairCountByDefault(self):
        theme = self.makeTheme(emojis=["🐶", "🐱", "🐭"])
        game = Game(theme)
        self.assertEqual(game.number_of_pairs, 3)
        self.assertEqual(len(game.cards), 6)
        self.assertEqual({c.content for c in game.cards}, set(theme.emojis))
        self.assertEqual(game.theme.name, theme.name)

    # ---- 翻牌与配对 ----

    def testNewGameHasCleanState(self):
        game = self.makeGame()
        self.assertEqual(len(game.cards), 4)
        self.assertEqual(game.score, 0)
        self.assertEqual(game.matched_pairs_count, 0)
        self.assertFalse(game.is_game_over)
        self.assertIsNone(game.index_of_face_up_card)
        self.assertFalse(game.has_pending_mismatch)
        self.assertTrue(all(not c.is_face_up and not c.is_matched for c in game.cards))

    def testChooseFlipsCard(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        self.assertTrue(game.cards[0].is_face_up)
        self.assertEqual(game.index_of_face_up_card, 0)
        self.assertEqual(game.score, 0)

    def testChoosingSameFaceUpCardTwiceIsIgnored(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[0])
        self.assertEqual(game.index_of_face_up_card, 0)
        self.assertEqual(game.score, 0)
        game.choose(game.cards[1])
        self.assertEqual(game.score, 2)

    def testMatchingPairScoresTwoAndStaysFaceUp(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        self.assertEqual(game.score, 2)
        self.assertEqual(game.matched_pairs_count, 1)
        self.assertTrue(game.cards[0].is_matched)
        self.assertTrue(game.cards[1].is_matched)
        self.assertTrue(game.cards[0].is_face_up)
        self.assertTrue(game.cards[1].is_face_up)
        self.assertIsNone(game.index_of_face_up_card)

    def testFirstMismatchKeepsScoreAndWaitsForFlipBack(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[2])
        self.assertEqual(game.score, 0)
        self.assertEqual(game.matched_pairs_count, 0)
        self.assertTrue(game.has_pending_mismatch)
        self.assertTrue(game.cards[0].is_face_up)
        self.assertTrue(game.cards[2].is_face_up)
        self.assertIsNone(game.index_of_face_up_card)

        game.flip_back_mismatch()
        self.assertFalse(game.has_pending_mismatch)
        self.assertFalse(game.cards[0].is_face_up)
        self.assertFalse(game.cards[2].is_face_up)

    def testFlipBackMismatchIsIdempotent(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[2])
        game.flip_back_mismatch()
        game.flip_back_mismatch()
        self.assertEqual(game.score, 0)
        self.assertFalse(game.has_pending_mismatch)
        self.assertTrue(all(not c.is_face_up for c in game.cards))

    def testChoosingNextCardAutoFlipsPendingMismatch(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[2])
        self.assertTrue(game.has_pending_mismatch)
        game.choose(game.cards[1])
        self.assertFalse(game.has_pending_mismatch)
        self.assertFalse(game.cards[0].is_face_up)
        self.assertFalse(game.cards[2].is_face_up)
        self.assertTrue(game.cards[1].is_face_up)
        self.assertEqual(game.index_of_face_up_card, 1)

    def testRepeatedMismatchPenalizesByOne(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[2])
        self.assertEqual(game.score, 0)
        game.flip_back_mismatch()
        game.choose(game.cards[0])
        game.choose(game.cards[2])
        self.assertEqual(game.score, -1)
        self.assertTrue(game.has_pending_mismatch)
        game.flip_back_mismatch()
        self.assertFalse(game.cards[0].is_face_up)
        self.assertFalse(game.cards[2].is_face_up)

    def testChoosingMatchedCardIsIgnored(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        self.assertEqual(game.score, 2)
        game.choose(game.cards[0])
        self.assertEqual(game.score, 2)
        self.assertEqual(game.matched_pairs_count, 1)

    def testChoosingUnknownCardIsIgnored(self):
        game = self.makeGame()
        game.choose(Card(content="🦊"))
        self.assertEqual(game.score, 0)
        self.assertIsNone(game.index_of_face_up_card)
        self.assertTrue(all(not c.is_face_up for c in game.cards))

    def testGameOverAfterAllPairsMatched(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        game.choose(game.cards[2])
        game.choose(game.cards[3])
        self.assertEqual(game.score, 4)
        self.assertEqual(game.matched_pairs_count, 2)
        self.assertTrue(game.is_game_over)

    # ---- 重开 ----

    def testNewGameResetsState(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        self.assertEqual(game.score, 2)
        game.new_game(shuffle=False)
        self.assertEqual(len(game.cards), 4)
        self.assertEqual(game.score, 0)
        self.assertEqual(game.matched_pairs_count, 0)
        self.assertFalse(game.is_game_over)
        self.assertIsNone(game.index_of_face_up_card)
        self.assertFalse(game.has_pending_mismatch)
        self.assertTrue(all(not c.is_face_up and not c.is_matched for c in game.cards))
        self.assertEqual(game.theme.name, "测试主题")

    def testStartNewGameSwitchesThemeAndResetsState(self):
        game = self.makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        self.assertEqual(game.score, 2)
        new_theme = self.makeTheme(name="水果", emojis=["🍎", "🍌"], numberOfPairs=1)
        game.start_new_game(new_theme, shuffle=False)
        self.assertEqual(game.theme.name, "水果")
        self.assertEqual(game.number_of_pairs, 1)
        self.assertEqual(len(game.cards), 2)
        self.assertEqual(game.score, 0)
        self.assertEqual(game.matched_pairs_count, 0)
        self.assertFalse(game.is_game_over)
        self.assertTrue(all(not c.is_face_up and not c.is_matched for c in game.cards))


# ---------------------------------------------------------------------------
# 套件二：GameViewModelTests（11 条）
# ---------------------------------------------------------------------------

class GameViewModelTests(MemorizeTestCase):

    def testInitialStateIsClean(self):
        view_model, _ = self.makeViewModel()
        self.assertEqual(len(view_model.cards), 4)
        self.assertEqual(view_model.score, 0)
        self.assertEqual(view_model.matched_pairs_count, 0)
        self.assertFalse(view_model.is_game_over)
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertEqual(view_model.theme.name, "测试主题")

    def testChooseFlipsCardWithoutLocking(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        self.assertTrue(view_model.cards[0].is_face_up)
        self.assertFalse(view_model.is_interaction_locked)
        self.assertEqual(view_model.game.index_of_face_up_card, 0)

    def testRepeatedTapOnSameCardKeepsSingleSelection(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[0])
        self.assertEqual(view_model.game.index_of_face_up_card, 0)
        self.assertEqual(view_model.score, 0)
        self.assertFalse(view_model.is_interaction_locked)

    def testMatchingPairScoresTwoAndStaysUnlocked(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[1])
        self.assertEqual(view_model.score, 2)
        self.assertEqual(view_model.matched_pairs_count, 1)
        self.assertTrue(view_model.cards[0].is_matched)
        self.assertTrue(view_model.cards[1].is_matched)
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)

    def testMismatchLocksInteractionAndIgnoresFurtherTaps(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.has_pending_mismatch)
        self.assertTrue(view_model.is_interaction_locked)
        score_before = view_model.score
        view_model.choose(view_model.cards[1])
        self.assertEqual(view_model.score, score_before)
        self.assertFalse(view_model.cards[1].is_face_up)
        self.assertIsNone(view_model.game.index_of_face_up_card)
        self.assertTrue(view_model.is_interaction_locked)

    def testCompleteMismatchFlipBackUnlocksAndFlipsCards(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.is_interaction_locked)
        view_model.complete_mismatch_flip_back()
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertFalse(view_model.cards[0].is_face_up)
        self.assertFalse(view_model.cards[2].is_face_up)

    def testCompleteMismatchFlipBackWithoutPendingMismatchIsNoOp(self):
        view_model, _ = self.makeViewModel()
        view_model.complete_mismatch_flip_back()
        self.assertEqual(view_model.score, 0)
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertTrue(all(not c.is_face_up for c in view_model.cards))

    def testRepeatedMismatchPenalizesByOne(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(view_model.score, 0)
        view_model.complete_mismatch_flip_back()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(view_model.score, -1)
        self.assertTrue(view_model.is_interaction_locked)

    def testNewGameClearsPendingStateAndUnlocks(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.is_interaction_locked)
        view_model.new_game()
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertEqual(view_model.score, 0)
        self.assertEqual(view_model.matched_pairs_count, 0)
        self.assertFalse(view_model.is_game_over)
        self.assertTrue(all(not c.is_face_up and not c.is_matched for c in view_model.cards))

    def testChooseThemeResetsGameAndUnlocks(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.is_interaction_locked)
        new_theme = self.makeTheme(name="水果", emojis=["🍎", "🍌"], numberOfPairs=1)
        view_model.choose_theme(new_theme)
        self.assertEqual(view_model.theme.name, "水果")
        self.assertEqual(len(view_model.cards), 2)
        self.assertEqual(view_model.score, 0)
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertFalse(view_model.is_game_over)

    def testChoosingAfterGameOverIsIgnored(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[1])
        view_model.choose(view_model.cards[2])
        view_model.choose(view_model.cards[3])
        self.assertTrue(view_model.is_game_over)
        self.assertEqual(view_model.score, 4)
        view_model.choose(view_model.cards[0])
        self.assertEqual(view_model.score, 4)
        self.assertTrue(view_model.is_game_over)


# ---------------------------------------------------------------------------
# 套件三：MismatchTimerTests（10 条）
# ---------------------------------------------------------------------------

class MismatchTimerTests(MemorizeTestCase):

    def testFirstFlipDoesNotSchedule(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        self.assertEqual(timer.scheduled_delays, [])
        self.assertEqual(timer.pending_count, 0)
        self.assertFalse(view_model.is_interaction_locked)

    def testMatchedPairDoesNotSchedule(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[1])
        self.assertEqual(timer.scheduled_delays, [])
        self.assertFalse(view_model.is_interaction_locked)

    def testMismatchSchedulesOnceWithDefaultDelay(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(timer.scheduled_delays, [0.8])
        self.assertEqual(timer.pending_count, 1)
        self.assertTrue(view_model.has_pending_mismatch)
        self.assertTrue(view_model.is_interaction_locked)

    def testCustomDelayIsUsed(self):
        view_model, timer = self.makeViewModel(delay=0.5)
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(timer.scheduled_delays, [0.5])
        self.assertEqual(view_model.mismatch_flip_delay, 0.5)

    def testLockedPeriodDoesNotScheduleAgain(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(timer.pending_count, 1)
        view_model.choose(view_model.cards[1])
        view_model.choose(view_model.cards[3])
        self.assertEqual(len(timer.scheduled_delays), 1)
        self.assertEqual(timer.pending_count, 1)
        self.assertTrue(view_model.is_interaction_locked)

    def testTimerFiresFlipsBackAndUnlocks(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.is_interaction_locked)
        timer.fire_all()
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertFalse(view_model.cards[0].is_face_up)
        self.assertFalse(view_model.cards[2].is_face_up)
        self.assertEqual(timer.pending_count, 0)

    def testCompleteWithoutPendingMismatchKeepsState(self):
        view_model, timer = self.makeViewModel()
        view_model.complete_mismatch_flip_back()
        self.assertEqual(view_model.score, 0)
        self.assertFalse(view_model.is_interaction_locked)
        self.assertTrue(all(not c.is_face_up for c in view_model.cards))
        self.assertEqual(timer.scheduled_delays, [])

    def testNewGameInvalidatesStaleCallback(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        view_model.new_game()
        timer.fire_all()
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertEqual(view_model.score, 0)
        self.assertTrue(all(not c.is_face_up and not c.is_matched for c in view_model.cards))

    def testThemeSwitchInvalidatesStaleCallback(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        new_theme = self.makeTheme(name="水果", emojis=["🍎", "🍌"], numberOfPairs=1)
        view_model.choose_theme(new_theme)
        timer.fire_all()
        self.assertEqual(view_model.theme.name, "水果")
        self.assertEqual(len(view_model.cards), 2)
        self.assertEqual(view_model.score, 0)
        self.assertFalse(view_model.is_interaction_locked)

    def testMismatchAfterNewGameSchedulesNewTimer(self):
        view_model, timer = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        view_model.new_game()

        # 重开会洗牌，固定下标可能取到同一 emoji 而配对成功，
        # 因此与 Swift 版一致，按内容挑选两张不同的卡片。
        first_index = 0
        candidates = [i for i, c in enumerate(view_model.cards)
                      if c.content != view_model.cards[first_index].content]
        self.assertTrue(candidates, "重开后找不到不同内容的卡片")
        second_index = candidates[0]

        view_model.choose(view_model.cards[first_index])
        view_model.choose(view_model.cards[second_index])
        self.assertEqual(timer.scheduled_delays, [0.8, 0.8])

        timer.fire_next()
        self.assertTrue(view_model.is_interaction_locked)
        self.assertTrue(view_model.has_pending_mismatch)

        timer.fire_next()
        self.assertFalse(view_model.is_interaction_locked)
        self.assertFalse(view_model.has_pending_mismatch)
        self.assertFalse(view_model.cards[first_index].is_face_up)
        self.assertFalse(view_model.cards[second_index].is_face_up)


# ---------------------------------------------------------------------------
# 套件四：GameFlowUITests（5 条，状态投影等价验证）
# ---------------------------------------------------------------------------

class GameFlowUITests(MemorizeTestCase):

    def setUp(self):
        # 镜像 MemorizeApp 的 -uitesting 确定性牌局：2 对、不洗牌。
        theme = built_in_themes()[0]
        self.view_model, self.timer = GameViewModel(theme, 2, False), None
        self.view_model.timer = FakeMismatchTimer()
        self.timer = self.view_model.timer

    def testMainScreenShowsCoreElements(self):
        self.assertEqual(theme_label(self.view_model), "主题：动物")
        self.assertEqual(score_label(self.view_model), "0")
        self.assertEqual(hint_label(self.view_model), "点击卡片翻开，找出全部对子")
        self.assertEqual([t.name for t in built_in_themes()],
                         ["动物", "运动", "表情", "旗帜", "天气", "食物"])
        self.assertEqual(len(self.view_model.cards), 4)
        self.assertEqual(card_label(self.view_model.cards[0]), "未翻开的卡片")

    def testMismatchLocksHintAndFlipsBackAfterDelay(self):
        self.view_model.choose(self.view_model.cards[0])
        self.assertEqual(card_label(self.view_model.cards[0]), "已翻开的卡片 🐶")

        self.view_model.choose(self.view_model.cards[2])
        self.assertEqual(hint_label(self.view_model), "配对失败，卡片即将翻回…")
        self.assertEqual(score_label(self.view_model), "0")

        self.view_model.choose(self.view_model.cards[3])
        self.assertEqual(card_label(self.view_model.cards[3]), "未翻开的卡片")

        self.timer.fire_all()
        self.assertEqual(hint_label(self.view_model), "点击卡片翻开，找出全部对子")
        self.assertEqual(card_label(self.view_model.cards[0]), "未翻开的卡片")
        self.assertEqual(card_label(self.view_model.cards[2]), "未翻开的卡片")

    def testMatchingPairScoresTwo(self):
        self.view_model.choose(self.view_model.cards[0])
        self.view_model.choose(self.view_model.cards[1])
        self.assertEqual(score_label(self.view_model), "2")
        self.assertEqual(card_label(self.view_model.cards[0]), "已配对的卡片 🐶")
        self.assertEqual(card_label(self.view_model.cards[1]), "已配对的卡片 🐶")
        self.assertEqual(hint_label(self.view_model), "点击卡片翻开，找出全部对子")

    def testThemeSwitchResetsScoreAndBoard(self):
        self.view_model.choose(self.view_model.cards[0])
        self.view_model.choose(self.view_model.cards[1])
        self.assertEqual(score_label(self.view_model), "2")

        sports = next(t for t in built_in_themes() if t.name == "运动")
        self.view_model.choose_theme(sports)

        self.assertEqual(theme_label(self.view_model), "主题：运动")
        self.assertEqual(score_label(self.view_model), "0")
        self.assertEqual(card_label(self.view_model.cards[0]), "未翻开的卡片")
        self.assertEqual(len(self.view_model.cards), 16)

    def testCompletionAlertAndRestart(self):
        self.view_model.choose(self.view_model.cards[0])
        self.view_model.choose(self.view_model.cards[1])
        self.view_model.choose(self.view_model.cards[2])
        self.view_model.choose(self.view_model.cards[3])

        # 结算弹窗出现的条件：游戏结束且得分为 4。
        self.assertTrue(self.view_model.is_game_over)
        self.assertEqual(self.view_model.score, 4)

        self.view_model.new_game()
        self.assertEqual(score_label(self.view_model), "0")
        self.assertEqual(card_label(self.view_model.cards[0]), "未翻开的卡片")
        self.assertEqual(card_label(self.view_model.cards[2]), "未翻开的卡片")


# ---------------------------------------------------------------------------
# 套件五：AspectVGridTests（8 条，布局算法等价验证）
# ---------------------------------------------------------------------------

class AspectVGridTests(MemorizeTestCase):

    def itemWidth(self, count: int, width: float, height: float,
                  aspectRatio: float) -> float:
        return AspectVGrid.item_width_that_fits(count, width, height, aspectRatio)

    def rows(self, count: int, itemWidth: float, availableWidth: float) -> int:
        if itemWidth <= 0:
            return count
        column_count = max(1, int(availableWidth / itemWidth))
        return math.ceil(count / column_count)

    def testZeroItemCountReturnsZero(self):
        self.assertEqual(self.itemWidth(0, 390, 700, 2 / 3), 0)

    def testZeroOrNegativeSizeReturnsZero(self):
        self.assertEqual(self.itemWidth(8, 0, 700, 2 / 3), 0)
        self.assertEqual(self.itemWidth(8, 390, 0, 2 / 3), 0)
        self.assertEqual(self.itemWidth(8, -390, 700, 2 / 3), 0)

    def testNonPositiveAspectRatioReturnsZero(self):
        self.assertEqual(self.itemWidth(8, 390, 700, 0), 0)
        self.assertEqual(self.itemWidth(8, 390, 700, -0.5), 0)

    def testPortraitLayoutChoosesThreeColumns(self):
        width = self.itemWidth(8, 390, 700, 2 / 3)
        self.assertEqual(width, 130)
        self.assertEqual(self.rows(8, width, 390), 3)
        self.assertLessEqual(3 * 195, 700)

    def testLandscapeLayoutChoosesMoreColumns(self):
        width = self.itemWidth(8, 700, 390, 2 / 3)
        self.assertEqual(width, 116)
        self.assertEqual(self.rows(8, width, 700), 2)
        self.assertLessEqual(2 * (116 / (2 / 3)), 390)

    def testSmallScreenWithManyCardsStillFits(self):
        width = self.itemWidth(16, 320, 480, 2 / 3)
        self.assertEqual(width, 80)
        self.assertEqual(self.rows(16, width, 320), 4)

    def testLayoutNeverOverflowsAvailableSpace(self):
        sizes = [(320, 480), (390, 700), (430, 932), (700, 390), (932, 430), (1024, 768)]
        ratios = [0.5, 2 / 3, 1, 1.5]
        counts = [2, 6, 8, 10, 12, 16, 20, 32]

        for size_width, size_height in sizes:
            for ratio in ratios:
                for count in counts:
                    width = self.itemWidth(count, size_width, size_height, ratio)
                    with self.subTest(count=count, size=(size_width, size_height), ratio=ratio):
                        self.assertGreater(width, 0)
                        self.assertLessEqual(width, size_width)
                        row_count = self.rows(count, width, size_width)
                        used_height = row_count * (width / ratio)
                        self.assertLessEqual(used_height, size_height)

    def testLayoutIsDeterministicForSameInput(self):
        first = self.itemWidth(8, 390, 700, 2 / 3)
        second = self.itemWidth(8, 390, 700, 2 / 3)
        self.assertEqual(first, second)
        self.assertEqual(first, 130)

    def testItemWidthIsRoundedDownToWholePoints(self):
        width = self.itemWidth(8, 391, 700, 2 / 3)
        self.assertEqual(width, math.floor(width))
        self.assertEqual(width, 130)


# ---------------------------------------------------------------------------
# 套件六：AnimationTimingTests（9 条，动画参数）
# ---------------------------------------------------------------------------

class AnimationTimingTests(MemorizeTestCase):

    def testDealDelayStartsAtZero(self):
        self.assertEqual(AnimationTiming.deal_delay(0), 0)
        self.assertEqual(AnimationTiming.deal_delay(-1), 0)
        self.assertEqual(AnimationTiming.deal_delay(-20), 0)

    def testDealDelayAppliesLinearStagger(self):
        stagger = AnimationTiming.deal_stagger
        self.assertAlmostEqual(AnimationTiming.deal_delay(1), stagger, places=4)
        self.assertAlmostEqual(AnimationTiming.deal_delay(3), stagger * 3, places=4)
        self.assertAlmostEqual(AnimationTiming.deal_delay(5), stagger * 5, places=4)

    def testDealDelayCapsAtMaximum(self):
        cap = AnimationTiming.deal_max_stagger
        for index in (10, 16, 100):
            self.assertAlmostEqual(AnimationTiming.deal_delay(index), cap, places=4)

    def testDealDelayIsMonotonic(self):
        previous = AnimationTiming.deal_delay(0)
        for index in range(1, 41):
            current = AnimationTiming.deal_delay(index)
            self.assertGreaterEqual(current, previous)
            previous = current

    def testDealDelayNeverExceedsCap(self):
        for index in range(0, 101):
            self.assertLessEqual(AnimationTiming.deal_delay(index),
                                 AnimationTiming.deal_max_stagger)

    def testFlipDurationIsSmoothAndPositive(self):
        self.assertGreater(AnimationTiming.flip_duration, 0.2)
        self.assertLessEqual(AnimationTiming.flip_duration, 0.6)
        self.assertAlmostEqual(AnimationTiming.flip_duration, 0.45, places=4)

    def testDealDurationIsShorterThanFlipDuration(self):
        self.assertLess(AnimationTiming.deal_duration, AnimationTiming.flip_duration)

    def testScoreDeltaReportsIncreaseDecreaseAndNoChange(self):
        self.assertEqual(AnimationTiming.score_delta(0, 2), 2)
        self.assertEqual(AnimationTiming.score_delta(2, 4), 2)
        self.assertEqual(AnimationTiming.score_delta(0, -1), -1)
        self.assertEqual(AnimationTiming.score_delta(3, 3), 0)

    def testScorePopScaleIsPerceptibleButNotExcessive(self):
        self.assertGreater(AnimationTiming.score_pop_scale, 1.1)
        self.assertLessEqual(AnimationTiming.score_pop_scale, 1.5)
        self.assertAlmostEqual(AnimationTiming.score_pop_scale, 1.25, places=4)


# ---------------------------------------------------------------------------
# 套件七：GameAnimationCoordinatorTests（10 条，动画边界）
# ---------------------------------------------------------------------------

class GameAnimationCoordinatorTests(MemorizeTestCase):

    def testInitialStateIsIdle(self):
        coordinator = GameAnimationCoordinator()
        self.assertEqual(coordinator.board_revision, 0)
        self.assertEqual(coordinator.score_revision, 0)
        self.assertEqual(coordinator.active_flip_count, 0)

    def testFirstFlipIsAccepted(self):
        coordinator = GameAnimationCoordinator()
        identifier = str(uuid.uuid4())
        self.assertTrue(coordinator.begin_flip(identifier))
        self.assertEqual(coordinator.active_flip_count, 1)
        self.assertIn(identifier, coordinator.active_flip_card_ids)

    def testDuplicateFlipWhileActiveIsRejected(self):
        coordinator = GameAnimationCoordinator()
        identifier = str(uuid.uuid4())
        self.assertTrue(coordinator.begin_flip(identifier))
        self.assertFalse(coordinator.begin_flip(identifier))
        self.assertEqual(coordinator.active_flip_count, 1)

    def testFlipCanRestartAfterEndFlip(self):
        coordinator = GameAnimationCoordinator()
        identifier = str(uuid.uuid4())
        self.assertTrue(coordinator.begin_flip(identifier))
        coordinator.end_flip(identifier)
        self.assertEqual(coordinator.active_flip_count, 0)
        self.assertTrue(coordinator.begin_flip(identifier))

    def testDistinctCardsCanFlipConcurrently(self):
        coordinator = GameAnimationCoordinator()
        self.assertTrue(coordinator.begin_flip(str(uuid.uuid4())))
        self.assertTrue(coordinator.begin_flip(str(uuid.uuid4())))
        self.assertEqual(coordinator.active_flip_count, 2)

    def testEndAllFlipsClearsActiveCards(self):
        coordinator = GameAnimationCoordinator()
        coordinator.begin_flip(str(uuid.uuid4()))
        coordinator.begin_flip(str(uuid.uuid4()))
        coordinator.end_all_flips()
        self.assertEqual(coordinator.active_flip_count, 0)

    def testScoreChangeIncrementsRevision(self):
        coordinator = GameAnimationCoordinator()
        self.assertEqual(coordinator.score_did_change(0, 2), 1)
        self.assertEqual(coordinator.score_revision, 1)
        self.assertEqual(coordinator.score_did_change(2, 4), 2)
        self.assertEqual(coordinator.score_revision, 2)

    def testUnchangedScoreDoesNotAnimate(self):
        coordinator = GameAnimationCoordinator()
        self.assertIsNone(coordinator.score_did_change(2, 2))
        self.assertIsNone(coordinator.score_did_change(0, 0))
        self.assertEqual(coordinator.score_revision, 0)

    def testRapidScoreChangesKeepMonotonicRevision(self):
        coordinator = GameAnimationCoordinator()
        revisions = []
        for _ in range(5):
            revision = coordinator.score_did_change(0, 2)
            if revision is not None:
                revisions.append(revision)
        self.assertEqual(revisions, [1, 2, 3, 4, 5])

    def testNewBoardClearsFlipsAndIncrementsRevision(self):
        coordinator = GameAnimationCoordinator()
        coordinator.begin_flip(str(uuid.uuid4()))
        revision = coordinator.begin_new_board()
        self.assertEqual(revision, 1)
        self.assertEqual(coordinator.board_revision, 1)
        self.assertEqual(coordinator.active_flip_count, 0)
        self.assertEqual(coordinator.score_revision, 0)
        self.assertEqual(coordinator.begin_new_board(), 2)


# ---------------------------------------------------------------------------
# 套件八：AnimationIntegrationTests（13 条，ViewModel 与动画边界协同）
# ---------------------------------------------------------------------------

class AnimationIntegrationTests(MemorizeTestCase):

    def testInitialAnimationStateIsIdle(self):
        view_model, _ = self.makeViewModel()
        self.assertEqual(view_model.board_revision, 0)
        self.assertEqual(view_model.score_revision, 0)
        self.assertEqual(view_model.score_change_delta, 0)
        self.assertEqual(view_model.animations.active_flip_count, 0)

    def testFirstFlipRegistersActiveAnimation(self):
        view_model, _ = self.makeViewModel()
        card = view_model.cards[0]
        view_model.choose(card)
        self.assertTrue(view_model.cards[0].is_face_up)
        self.assertEqual(view_model.animations.active_flip_count, 1)
        self.assertIn(card.id, view_model.animations.active_flip_card_ids)
        self.assertEqual(view_model.score_revision, 0)

    def testRepeatedTapOnSameCardDoesNotDuplicateFlipAnimation(self):
        view_model, _ = self.makeViewModel()
        card = view_model.cards[0]
        view_model.choose(card)
        view_model.choose(card)
        self.assertEqual(view_model.animations.active_flip_count, 1)
        self.assertEqual(view_model.score, 0)

    def testEndFlipReleasesAnimationSlot(self):
        view_model, _ = self.makeViewModel()
        card = view_model.cards[0]
        view_model.choose(card)
        self.assertEqual(view_model.animations.active_flip_count, 1)
        view_model.end_flip(card.id)
        self.assertEqual(view_model.animations.active_flip_count, 0)

    def testMatchingPairTriggersScoreAnimationWithDeltaTwo(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[1])
        self.assertEqual(view_model.score, 2)
        self.assertEqual(view_model.score_revision, 1)
        self.assertEqual(view_model.score_change_delta, 2)

    def testMismatchDoesNotTriggerScoreAnimation(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(view_model.score, 0)
        self.assertEqual(view_model.score_revision, 0)
        self.assertEqual(view_model.score_change_delta, 0)
        self.assertTrue(view_model.is_interaction_locked)

    def testMismatchFlipBackEndsAllFlipAnimations(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(view_model.animations.active_flip_count, 2)
        view_model.complete_mismatch_flip_back()
        self.assertEqual(view_model.animations.active_flip_count, 0)
        self.assertFalse(view_model.is_interaction_locked)

    def testRepeatedMismatchPenaltyReportsNegativeDelta(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        view_model.complete_mismatch_flip_back()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertEqual(view_model.score, -1)
        self.assertEqual(view_model.score_revision, 1)
        self.assertEqual(view_model.score_change_delta, -1)

    def testNewGameResetsBoardRevisionAndClearsAnimations(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        self.assertEqual(view_model.animations.active_flip_count, 1)
        view_model.new_game()
        self.assertEqual(view_model.board_revision, 1)
        self.assertEqual(view_model.animations.active_flip_count, 0)
        self.assertEqual(view_model.score_revision, 0)
        self.assertEqual(view_model.score_change_delta, 0)
        self.assertTrue(all(not c.is_face_up and not c.is_matched
                            for c in view_model.cards))

    def testThemeSwitchIncrementsBoardRevision(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        fruit = make_theme(name="水果", emojis=["🍎", "🍌"], number_of_pairs=1)
        view_model.choose_theme(fruit)
        self.assertEqual(view_model.board_revision, 1)
        self.assertEqual(view_model.animations.active_flip_count, 0)
        self.assertEqual(view_model.theme.name, "水果")
        self.assertEqual(view_model.score_change_delta, 0)

    def testLockedInteractionDoesNotStartNewAnimations(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.is_interaction_locked)
        active_before = view_model.animations.active_flip_count
        view_model.choose(view_model.cards[1])
        view_model.choose(view_model.cards[3])
        self.assertEqual(view_model.animations.active_flip_count, active_before)
        self.assertEqual(view_model.score_revision, 0)
        self.assertTrue(view_model.is_interaction_locked)

    def testRapidMatchingPairsIncrementScoreRevisionMonotonically(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[1])
        self.assertEqual(view_model.score_revision, 1)
        view_model.choose(view_model.cards[2])
        view_model.choose(view_model.cards[3])
        self.assertEqual(view_model.score_revision, 2)
        self.assertEqual(view_model.score_change_delta, 2)
        self.assertEqual(view_model.score, 4)
        self.assertTrue(view_model.is_game_over)

    def testGameOverSequenceKeepsAnimationStateConsistent(self):
        view_model, _ = self.makeViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[1])
        view_model.choose(view_model.cards[2])
        view_model.choose(view_model.cards[3])
        self.assertTrue(view_model.is_game_over)
        self.assertEqual(view_model.score_revision, 2)
        self.assertEqual(view_model.board_revision, 0)
        self.assertEqual(view_model.score_change_delta, 2)
        self.assertEqual(view_model.animations.active_flip_count, 4)


# ---------------------------------------------------------------------------
# 套件九：AnimationFlowUITests（3 条，动画边界的状态投影等价）
# ---------------------------------------------------------------------------

class AnimationFlowUITests(MemorizeTestCase):

    def setUp(self):
        super().setUp()
        self.view_model, self.timer = self.makeViewModel()

    def testRapidDoubleTapFlipsCardOnlyOnce(self):
        card = self.view_model.cards[0]
        self.view_model.choose(card)
        self.view_model.choose(card)
        self.assertEqual(card_label(self.view_model.cards[0]), "已翻开的卡片 🐶")
        self.assertEqual(score_label(self.view_model), "0")
        self.assertEqual(hint_label(self.view_model), "点击卡片翻开，找出全部对子")

    def testRapidTapsDuringMismatchLockAreIgnored(self):
        self.view_model.choose(self.view_model.cards[0])
        self.view_model.choose(self.view_model.cards[2])
        self.assertEqual(hint_label(self.view_model), "配对失败，卡片即将翻回…")
        self.view_model.choose(self.view_model.cards[3])
        self.assertEqual(card_label(self.view_model.cards[3]), "未翻开的卡片")
        self.assertEqual(score_label(self.view_model), "0")

    def testThemeSwitchDuringFlipResetsBoardAndAnimations(self):
        self.view_model.choose(self.view_model.cards[0])
        sports = next(t for t in built_in_themes() if t.name == "运动")
        self.view_model.choose_theme(sports)
        self.assertEqual(theme_label(self.view_model), "主题：运动")
        self.assertEqual(score_label(self.view_model), "0")
        self.assertEqual(card_label(self.view_model.cards[0]), "未翻开的卡片")
        self.assertEqual(self.view_model.board_revision, 1)


# ---------------------------------------------------------------------------
# 套件十：CardifyStyleTests（8 条，镜像 day7/MemorizeTests/CardifyStyleTests.swift）
# ---------------------------------------------------------------------------

class CardifyStyleTests(MemorizeTestCase):

    def testCornerRadiusScalesWithShortSide(self):
        self.assertAlmostEqual(CardStyle.corner_radius(100, 150), 12, delta=0.001)
        self.assertAlmostEqual(CardStyle.corner_radius(150, 100), 12, delta=0.001)
        self.assertAlmostEqual(CardStyle.corner_radius(80, 120), 9.6, delta=0.001)

    def testCornerRadiusClampsSmallCards(self):
        self.assertAlmostEqual(CardStyle.corner_radius(40, 60), 6, delta=0.001)
        self.assertAlmostEqual(CardStyle.corner_radius(10, 15), 6, delta=0.001)

    def testCornerRadiusClampsLargeCards(self):
        self.assertAlmostEqual(CardStyle.corner_radius(300, 450), 20, delta=0.001)
        self.assertAlmostEqual(CardStyle.corner_radius(600, 900), 20, delta=0.001)

    def testCornerRadiusRequiresPositiveSize(self):
        self.assertEqual(CardStyle.corner_radius(0, 0), 0)
        self.assertEqual(CardStyle.corner_radius(-40, 60), 0)
        self.assertEqual(CardStyle.corner_radius(40, 0), 0)

    def testBorderWidthScalesAndClamps(self):
        self.assertAlmostEqual(CardStyle.border_width(100, 150), 1, delta=0.001)
        self.assertAlmostEqual(CardStyle.border_width(200, 300), 2, delta=0.001)
        self.assertAlmostEqual(CardStyle.border_width(300, 450), 3, delta=0.001)
        self.assertAlmostEqual(CardStyle.border_width(40, 60), 1, delta=0.001)

    def testContentPaddingScalesAndClamps(self):
        self.assertAlmostEqual(CardStyle.content_padding(100, 150), 8, delta=0.001)
        self.assertAlmostEqual(CardStyle.content_padding(40, 60), 3.2, delta=0.001)
        self.assertAlmostEqual(CardStyle.content_padding(10, 15), 2, delta=0.001)
        self.assertAlmostEqual(CardStyle.content_padding(300, 450), 8, delta=0.001)

    def testShadowRadiusScalesAndClamps(self):
        self.assertAlmostEqual(CardStyle.shadow_radius(100, 150), 3, delta=0.001)
        self.assertAlmostEqual(CardStyle.shadow_radius(300, 450), 6, delta=0.001)
        self.assertAlmostEqual(CardStyle.shadow_radius(10, 15), 1, delta=0.001)

    def testAspectRatioIsTwoToThree(self):
        self.assertAlmostEqual(CardStyle.aspect_ratio, 2 / 3, delta=0.0001)
        self.assertEqual(CardStyle.corner_radius(100, 150), 12)


# ---------------------------------------------------------------------------
# 套件十一：PieGeometryTests（10 条，镜像 day7/MemorizeTests/PieGeometryTests.swift）
# ---------------------------------------------------------------------------

class PieGeometryTests(MemorizeTestCase):

    def testProgressIsZeroForNonPositiveTotal(self):
        self.assertEqual(PieGeometry.progress(30, 0), 0)
        self.assertEqual(PieGeometry.progress(30, -10), 0)

    def testProgressIsZeroWhenRemainingDepleted(self):
        self.assertEqual(PieGeometry.progress(0, 60), 0)
        self.assertEqual(PieGeometry.progress(-5, 60), 0)

    def testProgressIsOneWhenRemainingAtOrAboveTotal(self):
        self.assertEqual(PieGeometry.progress(60, 60), 1)
        self.assertEqual(PieGeometry.progress(90, 60), 1)

    def testProgressUsesRatioInMiddle(self):
        self.assertAlmostEqual(PieGeometry.progress(30, 60), 0.5, delta=0.0001)
        self.assertAlmostEqual(PieGeometry.progress(45, 60), 0.75, delta=0.0001)
        self.assertAlmostEqual(PieGeometry.progress(12, 60), 0.2, delta=0.0001)

    def testProgressNeverExceedsUnitRange(self):
        for remaining in range(-20, 81):
            progress = PieGeometry.progress(remaining, 60)
            self.assertGreaterEqual(progress, 0)
            self.assertLessEqual(progress, 1)

    def testEndAngleStartsAtMinusNinety(self):
        self.assertAlmostEqual(PieGeometry.start_angle, -90, delta=0.001)
        self.assertAlmostEqual(PieGeometry.end_angle(0), -90, delta=0.001)

    def testEndAngleQuarterTurn(self):
        self.assertAlmostEqual(PieGeometry.end_angle(0.25), 0, delta=0.001)

    def testEndAngleFullTurn(self):
        self.assertAlmostEqual(PieGeometry.end_angle(0.5), 90, delta=0.001)
        self.assertAlmostEqual(PieGeometry.end_angle(1), 270, delta=0.001)

    def testEndAngleClampsInvalidProgress(self):
        self.assertAlmostEqual(PieGeometry.end_angle(-0.5), -90, delta=0.001)
        self.assertAlmostEqual(PieGeometry.end_angle(1.5), 270, delta=0.001)

    def testRingWidthScalesAndClamps(self):
        self.assertAlmostEqual(PieGeometry.ring_width(40), 4, delta=0.001)
        self.assertAlmostEqual(PieGeometry.ring_width(200), 10, delta=0.001)
        self.assertAlmostEqual(PieGeometry.ring_width(10), 3, delta=0.001)
        self.assertEqual(PieGeometry.ring_width(0), 0)
        self.assertEqual(PieGeometry.ring_width(-10), 0)


# ---------------------------------------------------------------------------
# 套件十二：CountdownIntegrationTests（16 条，镜像 day7/MemorizeTests/CountdownIntegrationTests.swift）
# ---------------------------------------------------------------------------

class CountdownIntegrationTests(MemorizeTestCase):

    def makeCountdownViewModel(self, countdown: Optional[int] = None):
        clock = FakeCountdownClock()
        view_model = GameViewModel(self.makeTheme(), 2, False, 0.8,
                                   FakeMismatchTimer(), clock)
        if countdown is not None:
            view_model.start_countdown(countdown)
        return view_model, clock

    def testInitialCountdownIsIdle(self):
        view_model, clock = self.makeCountdownViewModel()

        self.assertEqual(view_model.countdown_state, CountdownState.IDLE)
        self.assertEqual(view_model.countdown_remaining, 0)
        self.assertEqual(view_model.countdown_total, 0)
        self.assertFalse(view_model.did_time_out)
        self.assertEqual(clock.start_count, 0)
        self.assertFalse(clock.is_running)

    def testStartCountdownBeginsTicking(self):
        view_model, clock = self.makeCountdownViewModel(60)

        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)
        self.assertEqual(view_model.countdown_remaining, 60)
        self.assertEqual(view_model.countdown_total, 60)
        self.assertEqual(clock.start_count, 1)
        self.assertAlmostEqual(clock.last_interval, CountdownDefaults.tick_interval, delta=0.0001)
        self.assertTrue(clock.is_running)

    def testInvalidDurationDoesNotStart(self):
        view_model, clock = self.makeCountdownViewModel()

        view_model.start_countdown(0)
        view_model.start_countdown(-5)

        self.assertEqual(view_model.countdown_state, CountdownState.IDLE)
        self.assertEqual(clock.start_count, 0)

    def testStartIfNeededOnlyStartsOnce(self):
        view_model, clock = self.makeCountdownViewModel()

        view_model.start_countdown_if_needed()
        view_model.start_countdown_if_needed()

        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)
        self.assertEqual(clock.start_count, 1)

    def testTickDecrementsRemaining(self):
        view_model, clock = self.makeCountdownViewModel(3)

        clock.tick()

        self.assertEqual(view_model.countdown_remaining, 2)
        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)

    def testCountdownFinishesAtZeroAndLocksInteraction(self):
        view_model, clock = self.makeCountdownViewModel(2)

        clock.tick(times=2)

        self.assertEqual(view_model.countdown_remaining, 0)
        self.assertEqual(view_model.countdown_state, CountdownState.FINISHED)
        self.assertTrue(view_model.did_time_out)
        self.assertTrue(view_model.is_interaction_locked)
        self.assertFalse(clock.is_running)

    def testTickAfterFinishedIsIgnored(self):
        view_model, clock = self.makeCountdownViewModel(1)
        clock.tick()

        clock.tick(times=3)

        self.assertEqual(view_model.countdown_remaining, 0)
        self.assertEqual(view_model.countdown_state, CountdownState.FINISHED)

    def testTickWhilePausedIsIgnored(self):
        view_model, clock = self.makeCountdownViewModel(10)

        view_model.pause_countdown()
        clock.tick(times=5)

        self.assertEqual(view_model.countdown_remaining, 10)
        self.assertEqual(view_model.countdown_state, CountdownState.PAUSED)

    def testPauseKeepsRemainingAndStopsClock(self):
        view_model, clock = self.makeCountdownViewModel(10)
        clock.tick(times=2)

        view_model.pause_countdown()

        self.assertEqual(view_model.countdown_state, CountdownState.PAUSED)
        self.assertEqual(view_model.countdown_remaining, 8)
        self.assertFalse(clock.is_running)

    def testResumeContinuesFromRemaining(self):
        view_model, clock = self.makeCountdownViewModel(10)
        view_model.pause_countdown()

        view_model.resume_countdown()

        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)
        self.assertEqual(view_model.countdown_remaining, 10)
        self.assertTrue(clock.is_running)
        self.assertEqual(clock.start_count, 2)

    def testToggleCountdownCyclesStates(self):
        view_model, _ = self.makeCountdownViewModel(10)

        view_model.toggle_countdown()
        self.assertEqual(view_model.countdown_state, CountdownState.PAUSED)

        view_model.toggle_countdown()
        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)

    def testStopCountdownResetsState(self):
        view_model, clock = self.makeCountdownViewModel(10)
        clock.tick(times=3)

        view_model.stop_countdown()

        self.assertEqual(view_model.countdown_state, CountdownState.IDLE)
        self.assertEqual(view_model.countdown_remaining, 0)
        self.assertEqual(view_model.countdown_total, 0)
        self.assertFalse(view_model.did_time_out)
        self.assertFalse(clock.is_running)

    def testNewGameRestartsCountdown(self):
        view_model, clock = self.makeCountdownViewModel(10)
        clock.tick(times=3)
        self.assertEqual(view_model.countdown_remaining, 7)

        view_model.new_game()

        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)
        self.assertEqual(view_model.countdown_remaining, 10)
        self.assertEqual(view_model.countdown_total, 10)
        self.assertEqual(view_model.board_revision, 1)
        self.assertEqual(view_model.score, 0)

    def testThemeSwitchRestartsCountdown(self):
        view_model, clock = self.makeCountdownViewModel(10)
        clock.tick(times=4)

        fruit = make_theme("水果", ["🍎", "🍌"], "pink", 1)
        view_model.choose_theme(fruit)

        self.assertEqual(view_model.countdown_state, CountdownState.RUNNING)
        self.assertEqual(view_model.countdown_remaining, 10)
        self.assertEqual(view_model.theme.name, "水果")

    def testTimeoutLockPersistsAfterMismatchFlipBack(self):
        view_model, clock = self.makeCountdownViewModel()
        view_model.choose(view_model.cards[0])
        view_model.choose(view_model.cards[2])
        self.assertTrue(view_model.is_interaction_locked)

        view_model.start_countdown(2)
        clock.tick(times=2)

        self.assertTrue(view_model.did_time_out)
        view_model.complete_mismatch_flip_back()

        self.assertTrue(view_model.is_interaction_locked, "时间到后翻回任务不应解除锁定")
        self.assertFalse(view_model.cards[0].is_face_up)

    def testProgressFollowsRemainingSeconds(self):
        view_model, clock = self.makeCountdownViewModel(10)
        clock.tick(times=5)

        self.assertEqual(view_model.countdown_remaining, 5)
        self.assertEqual(
            PieGeometry.progress(view_model.countdown_remaining, view_model.countdown_total),
            0.5
        )


# ---------------------------------------------------------------------------
# 执行器：逐条运行、记录结果、映射完整性校验
# ---------------------------------------------------------------------------

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DAY_DIR = os.path.dirname(BASE_DIR)

SUITE_FILES = [
    ("GameModelTests", os.path.join(DAY_DIR, "MemorizeTests", "GameModelTests.swift")),
    ("GameViewModelTests", os.path.join(DAY_DIR, "MemorizeTests", "GameViewModelTests.swift")),
    ("MismatchTimerTests", os.path.join(DAY_DIR, "MemorizeTests", "MismatchTimerTests.swift")),
    ("AspectVGridTests", os.path.join(DAY_DIR, "MemorizeTests", "AspectVGridTests.swift")),
    ("AnimationTimingTests", os.path.join(DAY_DIR, "MemorizeTests", "AnimationTimingTests.swift")),
    ("GameAnimationCoordinatorTests", os.path.join(DAY_DIR, "MemorizeTests", "GameAnimationCoordinatorTests.swift")),
    ("AnimationIntegrationTests", os.path.join(DAY_DIR, "MemorizeTests", "AnimationIntegrationTests.swift")),
    ("CardifyStyleTests", os.path.join(DAY_DIR, "MemorizeTests", "CardifyStyleTests.swift")),
    ("PieGeometryTests", os.path.join(DAY_DIR, "MemorizeTests", "PieGeometryTests.swift")),
    ("CountdownIntegrationTests", os.path.join(DAY_DIR, "MemorizeTests", "CountdownIntegrationTests.swift")),
    ("GameFlowUITests", os.path.join(DAY_DIR, "MemorizeUITests", "GameFlowUITests.swift")),
    ("AnimationFlowUITests", os.path.join(DAY_DIR, "MemorizeUITests", "AnimationFlowUITests.swift")),
]

SUITE_CLASSES = [GameModelTests, GameViewModelTests, MismatchTimerTests,
                 AspectVGridTests, AnimationTimingTests, GameAnimationCoordinatorTests,
                 AnimationIntegrationTests, CardifyStyleTests, PieGeometryTests,
                 CountdownIntegrationTests, GameFlowUITests, AnimationFlowUITests]


def collect_swift_tests():
    """从 Swift 测试文件提取测试方法名，用于映射完整性校验。"""
    mapping = {}
    for suite, path in SUITE_FILES:
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        mapping[suite] = re.findall(r"func\s+(test\w+)\s*\(", text)
    return mapping


def collect_python_tests():
    mapping = {}
    for suite in SUITE_CLASSES:
        mapping[suite.__name__] = sorted(
            name for name in dir(suite) if name.startswith("test")
        )
    return {k: sorted(v) for k, v in mapping.items()}


def main():
    expected = collect_swift_tests()
    actual = collect_python_tests()

    coverage = []
    coverage_ok = True
    for suite, names in expected.items():
        python_names = set(actual.get(suite, []))
        missing = [n for n in names if n not in python_names]
        extra = [n for n in python_names if n not in names]
        if missing or extra:
            coverage_ok = False
        coverage.append({
            "suite": suite,
            "swiftCount": len(names),
            "pythonCount": len(python_names),
            "missingInPython": missing,
            "extraInPython": extra,
        })

    total_expected = sum(item["swiftCount"] for item in coverage)

    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for case_class in SUITE_CLASSES:
        suite.addTests(loader.loadTestsFromTestCase(case_class))

    results = []
    for test in suite:
        class_name, method_name = test.id().split(".")[-2:]
        started = time.perf_counter()
        result = unittest.TestResult()
        test.run(result)
        duration_ms = int((time.perf_counter() - started) * 1000)

        failures = result.failures + result.errors
        status = "PASS" if result.wasSuccessful() else "FAIL"
        message = ""
        stack = ""
        if failures:
            failed_test, detail = failures[0]
            message = str(failed_test)
            stack = detail.strip()

        results.append({
            "suite": class_name,
            "case": method_name,
            "status": status,
            "durationMs": duration_ms,
            "message": message,
            "stackTrace": stack,
        })
        print("[%s] %s.%s (%dms)" % (status, class_name, method_name, duration_ms))

    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    failed = sum(1 for r in results if r["status"] == "FAIL")
    skipped = sum(1 for r in results if r["status"] == "SKIP")
    pass_rate = 100.0 if total == 0 else round(passed / total * 100, 2)

    suite_stats = {}
    for item in results:
        bucket = suite_stats.setdefault(item["suite"],
                                         {"total": 0, "passed": 0, "failed": 0})
        bucket["total"] += 1
        bucket["passed" if item["status"] == "PASS" else "failed"] += 1

    report = {
        "generatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
        "platform": "Windows",
        "runner": "Python 3 unittest（行为等价镜像）",
        "equivalence": "逻辑、布局算法、动画边界、卡片几何与倒计时状态机等价；UI 用例为状态投影级等价",
        "summary": {
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "passRate": pass_rate,
        },
        "suites": suite_stats,
        "coverage": {
            "ok": coverage_ok,
            "expectedTotal": total_expected,
            "details": coverage,
        },
        "results": results,
    }

    output_path = os.path.join(BASE_DIR, "test_results.json")
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)

    print("")
    print("=" * 64)
    print("总计 %d 条 | 通过 %d | 失败 %d | 跳过 %d | 通过率 %.2f%%"
          % (total, passed, failed, skipped, pass_rate))
    print("映射校验：Swift %d 条，Python %d 条，%s"
          % (total_expected, total, "一致" if coverage_ok else "不一致"))
    for item in coverage:
        print("  %-20s Swift=%2d Python=%2d 缺失=%s 多余=%s"
              % (item["suite"], item["swiftCount"], item["pythonCount"],
                 item["missingInPython"] or "无", item["extraInPython"] or "无"))
    print("结果文件：%s" % output_path)
    print("=" * 64)

    return 0 if (failed == 0 and coverage_ok and total == total_expected) else 1


if __name__ == "__main__":
    sys.exit(main())
