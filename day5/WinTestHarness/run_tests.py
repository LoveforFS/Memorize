# -*- coding: utf-8 -*-
"""
D5 模块 Windows 行为等价测试执行器。

设计目标：
1. 不修改 day5/MemorizeTests 与 day5/MemorizeUITests 中的任何 Swift 测试文件；
2. 在 Windows + Python 3 上以 unittest 真实执行 63 条用例（D4 的 54 条 + D5 新增 9 条）；
3. 每条用例与 Swift 测试方法一一对应，断言内容保持一致；
4. 输出结构化结果（名、状态、耗时、失败信息与堆栈），并校验映射完整性。

说明：本执行器是对 Swift 模型/视图模型/布局算法与断言的行为等价镜像，
不是 XCTest 原生执行；UI 用例以状态投影方式验证与 Swift 版相同的可见结论。
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
                 mismatch_flip_delay: float = 0.8, timer=None):
        theme = theme if theme is not None else built_in_themes()[0]
        timer = timer if timer is not None else FakeMismatchTimer()
        self.game = Game(theme, number_of_pairs, shuffle)
        self.cards = list(self.game.cards)
        self.score = self.game.score
        self.is_interaction_locked = False
        self.mismatch_flip_delay = mismatch_flip_delay
        self.timer = timer
        self.pending_timer_token: Optional[str] = None

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
        self.game.choose(card)
        self._sync_from_game()
        if self.game.has_pending_mismatch:
            self.is_interaction_locked = True
            self._schedule_flip_back()

    def complete_mismatch_flip_back(self) -> None:
        self.pending_timer_token = None
        if not self.game.has_pending_mismatch:
            return
        self.game.flip_back_mismatch()
        self._sync_from_game()
        self.is_interaction_locked = False

    def new_game(self) -> None:
        self.pending_timer_token = None
        self.is_interaction_locked = False
        self.game.new_game()
        self._sync_from_game()

    def choose_theme(self, theme: Theme) -> None:
        self.pending_timer_token = None
        self.is_interaction_locked = False
        self.game.start_new_game(theme)
        self._sync_from_game()

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
        # 镜像 Swift：重开洗牌后按内容挑选两张不同的卡片，避免固定下标取到同一 emoji。
        first_index = 0
        second_index = next(
            (i for i, c in enumerate(view_model.cards)
             if c.content != view_model.cards[first_index].content),
            None,
        )
        self.assertIsNotNone(second_index, "重开后找不到不同内容的卡片")
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
# 执行器：逐条运行、记录结果、映射完整性校验
# ---------------------------------------------------------------------------

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DAY_DIR = os.path.dirname(BASE_DIR)

SUITE_FILES = [
    ("GameModelTests", os.path.join(DAY_DIR, "MemorizeTests", "GameModelTests.swift")),
    ("GameViewModelTests", os.path.join(DAY_DIR, "MemorizeTests", "GameViewModelTests.swift")),
    ("MismatchTimerTests", os.path.join(DAY_DIR, "MemorizeTests", "MismatchTimerTests.swift")),
    ("AspectVGridTests", os.path.join(DAY_DIR, "MemorizeTests", "AspectVGridTests.swift")),
    ("GameFlowUITests", os.path.join(DAY_DIR, "MemorizeUITests", "GameFlowUITests.swift")),
]

SUITE_CLASSES = [GameModelTests, GameViewModelTests, MismatchTimerTests,
                 AspectVGridTests, GameFlowUITests]


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
        "equivalence": "逻辑、布局算法与断言等价；UI 用例为状态投影级等价",
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
