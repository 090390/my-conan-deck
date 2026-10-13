import React, { useEffect, useMemo, useState } from 'react';

const PAGE_SIZE = 100;
const MAIN_DECK_LIMIT = 40;
const SAME_CARD_LIMIT = 3;
const IMAGE_BASE = 'https://www.takaratomy.co.jp/products/conan-cardgame/storage/card/';
const DECK_STORAGE_KEY = 'conan-deck-main-v1';
const PARTNER_STORAGE_KEY = 'conan-deck-partner-v1';
const EVENT_STORAGE_KEY = 'conan-deck-event-v1';

function firstValue(objects, keys) {
  for (const object of objects) {
    if (!object || typeof object !== 'object') continue;
    for (const key of keys) {
      const value = object[key];
      if (value !== undefined && value !== null && String(value).trim() !== '') return value;
    }
  }
  return '';
}

function getImageUrl(card, source) {
  const direct = firstValue([card, source], ['imageUrl', 'image_url', 'image', 'imageURL']);
  if (direct && /^https?:\/\//i.test(String(direct))) return String(direct);
  const path = firstValue([card, source], [
    'mainPath', 'main_path', 'mainImagePath', 'main_image_path',
    'mainThumb', 'main_thumb', 'subPath', 'sub_path',
  ]) || direct;
  if (!path) return '';
  const clean = String(path).replace(/^\/+/, '');
  if (/^products\/conan-cardgame\/storage\/card\//i.test(clean)) return `https://www.takaratomy.co.jp/${clean}`;
  if (/^storage\/card\//i.test(clean)) return `https://www.takaratomy.co.jp/products/conan-cardgame/${clean}`;
  return `${IMAGE_BASE}${clean}`;
}

function numericValue(value) {
  if (value === '' || value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

const COLOR_ORDER = ['청', '적', '황', '녹', '흑', '백'];
const COLOR_DEFINITIONS = [
  { tag: '청', aliases: ['청', '파랑', '파란색', '파랑색', '푸른색', '青色', '青', 'ブルー', 'blue'] },
  { tag: '적', aliases: ['적', '빨강', '빨간색', '빨강색', '赤色', '赤', 'レッド', 'red'] },
  { tag: '황', aliases: ['황', '노랑', '노란색', '노랑색', '黄色', '黄', 'イエロー', 'yellow'] },
  { tag: '녹', aliases: ['녹', '녹색', '초록', '초록색', '緑色', '緑', 'グリーン', 'green'] },
  { tag: '흑', aliases: ['흑', '검정', '검정색', '검은색', '黒色', '黒', '黑', 'ブラック', 'black'] },
  { tag: '백', aliases: ['백', '흰색', '하양', '하얀색', '白色', '白', 'ホワイト', 'white'] },
];
const COLOR_ALIAS_LOOKUP = COLOR_DEFINITIONS
  .flatMap(({ tag, aliases }) => aliases.map((alias) => ({ tag, alias: alias.toLocaleLowerCase() })))
  .sort((a, b) => b.alias.length - a.alias.length);
const COLOR_SPLIT_RE = /[\s,，、/&＋+・·|｜]+/u;

function parseColorToken(token) {
  const normalized = String(token).toLocaleLowerCase();
  const exact = COLOR_ALIAS_LOOKUP.find((entry) => entry.alias === normalized);
  if (exact) return [exact.tag];

  let remainder = normalized;
  const tags = [];
  while (remainder) {
    const match = COLOR_ALIAS_LOOKUP.find((entry) => remainder.startsWith(entry.alias));
    if (!match) return null;
    tags.push(match.tag);
    remainder = remainder.slice(match.alias.length);
  }
  return tags;
}

function normalizeColor(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return '';
  const cleaned = raw.replace(/[【】\[\]()（）]/gu, '').trim();
  const tokens = cleaned.split(COLOR_SPLIT_RE).filter(Boolean);
  if (!tokens.length) return '';

  const tags = [];
  for (const token of tokens) {
    const parsed = parseColorToken(token);
    if (!parsed) return cleaned;
    tags.push(...parsed);
  }
  return [...new Set(tags)].join('');
}

function normalizeColorKey(value) {
  const tags = new Set(normalizeColor(value).split(''));
  const recognized = COLOR_ORDER.filter((tag) => tags.has(tag));
  return recognized.length === tags.size ? recognized.join('') : normalizeColor(value);
}

function normalizeCard(card, translations) {
  const source = card?.sourceData && typeof card.sourceData === 'object'
    ? card.sourceData
    : card?.raw && typeof card.raw === 'object'
      ? card.raw
      : {};
  const objects = [card, source];
  const id = String(firstValue(objects, ['id', 'databaseId', 'database_id', 'cardId', 'card_id', 'cardNum', 'card_num']));
  const translated = translations?.[id] || {};
  const hiramekiEffect = String(translated.hirameki || '').replace(/^【히라메키】\s*/u, '');
  const cutInEffect = String(translated.cut_in || '').replace(/^【컷인】\s*/u, '');
  const originalName = String(firstValue(objects, ['nameJp', 'title', 'name', 'cardName', 'card_name']));
  const originalType = String(firstValue(objects, ['typeJp', 'type', 'cardType', 'card_type', 'category1', 'category_1']));
  const originalColor = String(firstValue(objects, ['colorJp', 'color', 'colour']));
  const originalSet = String(firstValue(objects, ['setJp', 'package', 'set', 'product']));
  const originalAbility = String(firstValue(objects, ['abilityJp', 'text', 'ability', 'feature', 'effect']));
  const originalFlavor = String(firstValue(objects, ['flavorJp', 'flavor_txt', 'flavor', 'flavorText', 'flavor_text']));
  const cardId = String(firstValue(objects, ['cardId', 'card_id']));
  const cardNum = String(firstValue(objects, ['cardNum', 'card_num']));
  const rarity = String(translated.rarityKo || firstValue(objects, ['rarity', 'rarityJp', 'rare', 'rarity_code', 'rarityCode']));
  const cost = numericValue(firstValue(objects, ['cost', 'costValue', 'cost_value']));
  const lp = numericValue(firstValue(objects, ['lp', 'LP']));
  const roleText = [
    ...objects.map((object) => firstValue([object], [
      'type', 'typeJp', 'typeKo', 'cardType', 'card_type', 'category1', 'category2', 'category3',
      'category1Ko', 'category2Ko', 'category3Ko', 'cardCategory', 'card_category',
    ])),
  ].filter(Boolean).join(' ');

  return {
    key: id,
    databaseId: id,
    cardId,
    cardNum,
    name: String(translated.nameKo || firstValue([card], ['nameKo', 'translatedName']) || originalName || cardId || cardNum || '이름 없음'),
    originalName,
    type: String(translated.typeKo || firstValue([card], ['typeKo']) || originalType),
    originalType,
    roleText,
    color: normalizeColor(translated.colorKo || firstValue([card], ['colorKo']) || originalColor),
    colorKey: normalizeColorKey(translated.colorKo || firstValue([card], ['colorKo']) || originalColor),
    originalColor,
    rarity,
    cost,
    lp,
    set: String(translated.setKo || firstValue([card], ['setKo']) || originalSet),
    originalSet,
    ability: String(translated.abilityKo || firstValue([card], ['abilityKo']) || originalAbility),
    originalAbility,
    hiramekiEffect,
    cutInEffect,
    flavor: String(translated.flavorKo || firstValue([card], ['flavorKo']) || originalFlavor),
    imageUrl: getImageUrl(card, source),
  };
}

function getCardArray(input) {
  if (Array.isArray(input)) return input;
  if (Array.isArray(input?.data)) return input.data;
  if (Array.isArray(input?.cards)) return input.cards;
  if (Array.isArray(input?.items)) return input.items;
  return [];
}

function isPartnerCard(card) {
  const type = `${card.type || ''} ${card.originalType || ''} ${card.roleText || ''}`;
  return /パートナー|파트너/i.test(type) || /^P\d+/i.test(card.cardId || '');
}

function isEventCard(card) {
  const type = `${card.type || ''} ${card.originalType || ''} ${card.roleText || ''}`;
  return /事件|사건|event/i.test(type);
}

function getCardRole(card) {
  if (isPartnerCard(card)) return 'partner';
  if (isEventCard(card)) return 'event';
  return 'main';
}

function uniqueOptions(values) {
  return [...new Set(values.filter((value) => value !== '' && value !== null && value !== undefined).map(String))]
    .sort((a, b) => a.localeCompare(b, 'ko', { numeric: true }));
}

function formatNumber(value) {
  return value === null || value === undefined || value === '' ? '-' : value;
}

function loadSavedDeck() {
  try {
    const saved = JSON.parse(localStorage.getItem(DECK_STORAGE_KEY) || '{}');
    if (!saved || typeof saved !== 'object' || Array.isArray(saved)) return {};
    const cleaned = {};
    let total = 0;
    for (const [key, rawCount] of Object.entries(saved)) {
      const requested = Math.max(0, Math.floor(Number(rawCount) || 0));
      const count = Math.min(requested, SAME_CARD_LIMIT, MAIN_DECK_LIMIT - total);
      if (count > 0) {
        cleaned[key] = count;
        total += count;
      }
      if (total >= MAIN_DECK_LIMIT) break;
    }
    return cleaned;
  } catch {
    return {};
  }
}

function getPageItems(current, total) {
  if (total <= 7) return Array.from({ length: total }, (_, index) => index + 1);
  if (current <= 3) return [1, 2, 3, 4, 5, 'right-ellipsis', total];
  if (current >= total - 2) return [1, 'left-ellipsis', total - 4, total - 3, total - 2, total - 1, total];
  return [1, 'left-ellipsis', current - 1, current, current + 1, 'right-ellipsis', total];
}

function Pagination({ currentPage, totalPages, onChange }) {
  if (totalPages <= 1) return null;
  const items = getPageItems(currentPage, totalPages);
  return (
    <nav aria-label="카드 목록 페이지" className="mt-5 flex flex-wrap items-center justify-center gap-1.5 border-t border-white/[0.08] pt-4">
      <button onClick={() => onChange(Math.max(1, currentPage - 1))} disabled={currentPage === 1} className="rounded-lg border border-white/15 bg-[#131d31] px-3 py-2 text-xs font-semibold text-slate-200 shadow-sm transition hover:bg-white/10 disabled:opacity-30">이전</button>
      {items.map((item, index) => typeof item === 'number' ? (
        <button key={item} aria-current={item === currentPage ? 'page' : undefined} onClick={() => onChange(item)} className={`h-9 min-w-9 rounded-lg border px-2 text-xs font-bold tabular-nums transition ${item === currentPage ? 'border-rose-400 bg-rose-600 text-white shadow-md shadow-rose-900/40' : 'border-white/10 bg-[#131d31] text-slate-300 hover:bg-white/10'}`}>{item}</button>
      ) : <span key={`${item}-${index}`} className="px-1 text-xs text-slate-500">…</span>)}
      <button onClick={() => onChange(Math.min(totalPages, currentPage + 1))} disabled={currentPage === totalPages} className="rounded-lg border border-white/15 bg-[#131d31] px-3 py-2 text-xs font-semibold text-slate-200 shadow-sm transition hover:bg-white/10 disabled:opacity-30">다음</button>
      <span className="ml-2 text-[11px] tabular-nums text-slate-400">{currentPage} / {totalPages} 페이지</span>
    </nav>
  );
}

export default function App() {
  const [cards, setCards] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [colorFilter, setColorFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [rarityFilter, setRarityFilter] = useState('');
  const [costFilter, setCostFilter] = useState('');
  const [lpFilter, setLpFilter] = useState('');
  const [page, setPage] = useState(1);
  const [selectedCard, setSelectedCard] = useState(null);
  const [activeView, setActiveView] = useState('cards');
  const [deck, setDeck] = useState(loadSavedDeck);
  const [partnerId, setPartnerId] = useState(() => localStorage.getItem(PARTNER_STORAGE_KEY) || '');
  const [eventId, setEventId] = useState(() => localStorage.getItem(EVENT_STORAGE_KEY) || '');

  useEffect(() => {
    let cancelled = false;
    async function loadCards() {
      setLoading(true);
      setLoadError('');
      try {
        const [cardResponse, translations] = await Promise.all([
          fetch('/cards.json').then((response) => {
            if (!response.ok) throw new Error(`cards.json 응답 오류 (${response.status})`);
            return response.json();
          }),
          fetch('/card-translations.ko.json')
            .then((response) => response.ok ? response.json() : {})
            .catch(() => ({})),
        ]);
        const rawCards = getCardArray(cardResponse);
        if (!rawCards.length) throw new Error('cards.json에서 카드 배열을 찾지 못했어요.');
        const normalized = rawCards.map((card) => normalizeCard(card, translations)).filter((card) => card.key && card.key !== 'undefined');
        if (!cancelled) setCards(normalized);
      } catch (error) {
        if (!cancelled) setLoadError(error instanceof Error ? error.message : String(error));
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    loadCards();
    return () => { cancelled = true; };
  }, []);

  useEffect(() => { localStorage.setItem(DECK_STORAGE_KEY, JSON.stringify(deck)); }, [deck]);
  useEffect(() => {
    if (partnerId) localStorage.setItem(PARTNER_STORAGE_KEY, partnerId);
    else localStorage.removeItem(PARTNER_STORAGE_KEY);
  }, [partnerId]);
  useEffect(() => {
    if (eventId) localStorage.setItem(EVENT_STORAGE_KEY, eventId);
    else localStorage.removeItem(EVENT_STORAGE_KEY);
  }, [eventId]);

  useEffect(() => {
    if (!cards.length) return;
    let changed = false;
    let migratedPartner = '';
    let migratedEvent = '';
    const nextDeck = {};
    for (const [key, count] of Object.entries(deck)) {
      const card = cards.find((item) => item.key === key);
      const role = card ? getCardRole(card) : 'main';
      if (role === 'partner') {
        migratedPartner ||= key;
        changed = true;
      } else if (role === 'event') {
        migratedEvent ||= key;
        changed = true;
      } else {
        nextDeck[key] = count;
      }
    }
    if (changed) setDeck(nextDeck);
    if (migratedPartner) setPartnerId((current) => current || migratedPartner);
    if (migratedEvent) setEventId((current) => current || migratedEvent);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cards]);

  useEffect(() => { setPage(1); }, [searchTerm, colorFilter, typeFilter, rarityFilter, costFilter, lpFilter]);

  const colorOptions = useMemo(() => {
    const optionsByKey = new Map();
    for (const card of cards) {
      if (!card.color) continue;
      const value = card.colorKey || normalizeColorKey(card.color);
      if (!optionsByKey.has(value)) optionsByKey.set(value, { value, label: card.color });
    }
    return [...optionsByKey.values()].sort((a, b) => a.label.localeCompare(b.label, 'ko', { numeric: true }));
  }, [cards]);
  const typeOptions = useMemo(() => uniqueOptions(cards.map((card) => card.type)), [cards]);
  const rarityOptions = useMemo(() => uniqueOptions(cards.map((card) => card.rarity)), [cards]);
  const costOptions = useMemo(() => uniqueOptions(cards.map((card) => card.cost)), [cards]);
  const lpOptions = useMemo(() => uniqueOptions(cards.map((card) => card.lp)), [cards]);

  const filteredCards = useMemo(() => {
    const query = searchTerm.trim().toLocaleLowerCase();
    return cards.filter((card) => {
      const searchable = [
        card.name, card.originalName, card.cardId, card.cardNum,
        card.type, card.originalType, card.color, card.colorKey, card.originalColor,
        card.ability, card.originalAbility, card.set, card.originalSet, card.rarity,
        card.hiramekiEffect, card.cutInEffect,
      ].join(' ').toLocaleLowerCase();
      if (query && !searchable.includes(query)) return false;
      if (colorFilter && (card.colorKey || normalizeColorKey(card.color)) !== colorFilter) return false;
      if (typeFilter && card.type !== typeFilter) return false;
      if (rarityFilter && card.rarity !== rarityFilter) return false;
      if (costFilter !== '' && String(card.cost) !== costFilter) return false;
      if (lpFilter !== '' && String(card.lp) !== lpFilter) return false;
      return true;
    });
  }, [cards, searchTerm, colorFilter, typeFilter, rarityFilter, costFilter, lpFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredCards.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const visibleCards = filteredCards.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);
  const mainDeckCount = Object.values(deck).reduce((sum, count) => sum + Number(count || 0), 0);
  const partnerCard = cards.find((card) => card.key === partnerId) || null;
  const eventCard = cards.find((card) => card.key === eventId) || null;
  const deckCards = Object.entries(deck).flatMap(([key, count]) => {
    const card = cards.find((item) => item.key === key);
    return card ? Array.from({ length: Math.min(Number(count) || 0, SAME_CARD_LIMIT) }, (_, copyIndex) => ({ ...card, deckSlotKey: `${key}-${copyIndex}` })) : [];
  }).slice(0, MAIN_DECK_LIMIT);
  const deckSlots = Array.from({ length: MAIN_DECK_LIMIT }, (_, index) => deckCards[index] || null);

  useEffect(() => {
    if (!selectedCard) return undefined;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    function handleModalKeys(event) {
      if (event.key === 'Escape') {
        setSelectedCard(null);
      } else if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
        event.preventDefault();
        setSelectedCard((current) => {
          if (!current || filteredCards.length < 2) return current;
          const index = filteredCards.findIndex((card) => card.key === current.key);
          if (index < 0) return current;
          const step = event.key === 'ArrowRight' ? 1 : -1;
          return filteredCards[(index + step + filteredCards.length) % filteredCards.length];
        });
      }
    }
    window.addEventListener('keydown', handleModalKeys);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', handleModalKeys);
    };
  }, [selectedCard, filteredCards]);

  function addCard(card) {
    const role = getCardRole(card);
    if (role === 'partner') {
      setPartnerId((current) => current === card.key ? '' : card.key);
      return;
    }
    if (role === 'event') {
      setEventId((current) => current === card.key ? '' : card.key);
      return;
    }
    setDeck((previous) => {
      const current = Number(previous[card.key] || 0);
      const total = Object.values(previous).reduce((sum, count) => sum + Number(count || 0), 0);
      if (current >= SAME_CARD_LIMIT) {
        window.alert(`같은 카드는 최대 ${SAME_CARD_LIMIT}장까지 넣을 수 있어요.`);
        return previous;
      }
      if (total >= MAIN_DECK_LIMIT) {
        window.alert(`메인 덱은 ${MAIN_DECK_LIMIT}장까지 넣을 수 있어요.`);
        return previous;
      }
      return { ...previous, [card.key]: current + 1 };
    });
  }

  function removeCard(cardKey) {
    setDeck((previous) => {
      const count = Number(previous[cardKey] || 0);
      if (count <= 1) {
        const next = { ...previous };
        delete next[cardKey];
        return next;
      }
      return { ...previous, [cardKey]: count - 1 };
    });
  }

  function clearFilters() {
    setSearchTerm('');
    setColorFilter('');
    setTypeFilter('');
    setRarityFilter('');
    setCostFilter('');
    setLpFilter('');
  }

  function exportDeck() {
    if (!partnerCard || !eventCard || mainDeckCount !== MAIN_DECK_LIMIT) {
      window.alert(`덱을 완성하려면 메인 덱 ${MAIN_DECK_LIMIT}장과 파트너 1장, 사건 카드 1장이 필요해요.`);
      return;
    }
    const output = {
      exportedAt: new Date().toISOString(),
      partner: { databaseId: partnerCard.databaseId, cardId: partnerCard.cardId, cardNum: partnerCard.cardNum, name: partnerCard.name },
      event: { databaseId: eventCard.databaseId, cardId: eventCard.cardId, cardNum: eventCard.cardNum, name: eventCard.name },
      mainDeckCount,
      mainDeck: Object.entries(deck).map(([key, count]) => {
        const card = cards.find((item) => item.key === key);
        return card ? { databaseId: card.databaseId, cardId: card.cardId, cardNum: card.cardNum, name: card.name, count: Number(count) } : null;
      }).filter(Boolean),
    };
    const blob = new Blob([JSON.stringify(output, null, 2)], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'conan-deck.json';
    link.click();
    URL.revokeObjectURL(url);
  }

  function moveSelectedCard(step) {
    if (!selectedCard || filteredCards.length < 2) return;
    const index = filteredCards.findIndex((card) => card.key === selectedCard.key);
    if (index < 0) return;
    setSelectedCard(filteredCards[(index + step + filteredCards.length) % filteredCards.length]);
  }

  function goToPage(nextPage) {
    setPage(Math.max(1, Math.min(totalPages, nextPage)));
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function clearDeck() {
    if (!window.confirm('메인 덱, 파트너, 사건 카드를 모두 초기화할까요?')) return;
    setDeck({});
    setPartnerId('');
    setEventId('');
  }

  if (loading) {
    return <main className="flex min-h-screen items-center justify-center bg-[#080d17] p-8 text-slate-100"><div className="text-center"><div className="mx-auto mb-4 h-10 w-10 animate-spin rounded-full border-2 border-slate-700 border-t-rose-500" /><h1 className="text-xl font-black tracking-tight">명탐정 코난 TCG 도감</h1><p className="mt-2 text-sm text-slate-400">카드 데이터를 불러오는 중이에요…</p></div></main>;
  }
  if (loadError) {
    return <main className="min-h-screen bg-[#080d17] p-8 text-slate-100"><h1 className="text-2xl font-bold">카드 데이터를 불러오지 못했어요.</h1><p className="mt-4 text-rose-300">{loadError}</p></main>;
  }

  return (
    <main className="min-h-screen bg-[#080d17] p-3 text-slate-100 md:p-6">
      {/* 카드 그리드 및 모달 오버레이 정돈을 위한 전용 스타일 */}
      <style>{`
        .conan-card-grid {
          display: grid !important;
          grid-template-columns: repeat(10, minmax(0, 1fr)) !important;
          gap: 10px !important;
          align-items: start;
        }
        .conan-card-grid > article { min-width: 0 !important; width: 100% !important; }
        .conan-card-grid img { display: block; width: 100% !important; aspect-ratio: 3 / 4; object-fit: contain; }
        
        @media (max-width: 1279px) { .conan-card-grid { grid-template-columns: repeat(8, minmax(0, 1fr)) !important; } }
        @media (max-width: 1023px) { .conan-card-grid { grid-template-columns: repeat(6, minmax(0, 1fr)) !important; } }
        @media (max-width: 767px)  { .conan-card-grid { grid-template-columns: repeat(4, minmax(0, 1fr)) !important; gap: 8px !important; } }
        @media (max-width: 479px)  { .conan-card-grid { grid-template-columns: repeat(3, minmax(0, 1fr)) !important; gap: 6px !important; } }
      `}</style>

      {/* 상단 헤더 영역 */}
      <header className="mb-5 flex flex-wrap items-center justify-between gap-3 border-b border-white/10 pb-4">
        <div>
          <h1 className="text-xl font-black tracking-tight text-white md:text-2xl">명탐정 코난 TCG 도감</h1>
          <p className="text-xs text-slate-400 mt-0.5">카드를 누르면 상세 정보가 열려요</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <nav aria-label="메인 메뉴" className="flex rounded-xl border border-white/10 bg-[#101827] p-1 shadow-inner">
            <button onClick={() => setActiveView('cards')} className={`rounded-lg px-3.5 py-2 text-xs font-bold transition sm:px-5 ${activeView === 'cards' ? 'bg-rose-600 text-white shadow-md shadow-rose-900/50' : 'text-slate-400 hover:text-white'}`}>카드 목록</button>
            <button onClick={() => setActiveView('deck')} className={`rounded-lg px-3.5 py-2 text-xs font-bold transition sm:px-5 ${activeView === 'deck' ? 'bg-rose-600 text-white shadow-md shadow-rose-900/50' : 'text-slate-400 hover:text-white'}`}>내 덱 구성</button>
          </nav>
          <a className="rounded-xl border border-white/10 bg-[#101827] px-3.5 py-2 text-xs font-semibold text-slate-300 transition hover:border-rose-400/50 hover:text-white" href="https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/" target="_blank" rel="noreferrer">일본 공식 카드 목록 ↗</a>
        </div>
      </header>

      {activeView === 'cards' ? (
        <section id="card-list-top" className="min-w-0 rounded-2xl border border-white/10 bg-[#101827] p-4 shadow-xl md:p-5">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-baseline gap-2.5">
              <h2 className="text-base font-bold text-white">카드 목록</h2>
              <span className="text-xs font-medium tabular-nums text-rose-400">검색 결과 {filteredCards.length.toLocaleString()}장</span>
            </div>
            <button onClick={clearFilters} className="rounded-xl border border-white/10 bg-[#162032] px-3.5 py-1.5 text-xs font-semibold text-slate-300 transition hover:border-rose-400/40 hover:bg-white/5 hover:text-white">필터 초기화</button>
          </div>

          <div className="mb-5 grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-6">
            <input value={searchTerm} onChange={(event) => setSearchTerm(event.target.value)} placeholder="이름 · 효과 · 카드 ID" aria-label="카드 검색" className="min-w-0 rounded-xl border border-white/10 bg-[#090f1b] px-3.5 py-2.5 text-xs text-slate-200 outline-none transition placeholder:text-slate-500 focus:border-rose-400/70 focus:ring-1 focus:ring-rose-400/30" />
            <select aria-label="색상 필터" value={colorFilter} onChange={(event) => setColorFilter(event.target.value)} className="min-w-0 rounded-xl border border-white/10 bg-[#090f1b] px-3 py-2.5 text-xs text-slate-200 outline-none focus:border-rose-400/70"><option value="">모든 색상</option>{colorOptions.map(({ value, label }) => <option key={value} value={value}>{label}</option>)}</select>
            <select aria-label="종류 필터" value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)} className="min-w-0 rounded-xl border border-white/10 bg-[#090f1b] px-3 py-2.5 text-xs text-slate-200 outline-none focus:border-rose-400/70"><option value="">모든 종류</option>{typeOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select aria-label="레어도 필터" value={rarityFilter} onChange={(event) => setRarityFilter(event.target.value)} className="min-w-0 rounded-xl border border-white/10 bg-[#090f1b] px-3 py-2.5 text-xs text-slate-200 outline-none focus:border-rose-400/70"><option value="">모든 레어도</option>{rarityOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select aria-label="코스트 필터" value={costFilter} onChange={(event) => setCostFilter(event.target.value)} className="min-w-0 rounded-xl border border-white/10 bg-[#090f1b] px-3 py-2.5 text-xs text-slate-200 outline-none focus:border-rose-400/70"><option value="">모든 코스트</option>{costOptions.map((value) => <option key={String(value)} value={String(value)}>{value}</option>)}</select>
            <select aria-label="LP 필터" value={lpFilter} onChange={(event) => setLpFilter(event.target.value)} className="min-w-0 rounded-xl border border-white/10 bg-[#090f1b] px-3 py-2.5 text-xs text-slate-200 outline-none focus:border-rose-400/70"><option value="">모든 LP</option>{lpOptions.map((value) => <option key={String(value)} value={String(value)}>{value}</option>)}</select>
          </div>

          {visibleCards.length === 0 ? (
            <p className="rounded-2xl border border-dashed border-white/15 p-12 text-center text-sm text-slate-400">조건에 맞는 카드가 없어요.</p>
          ) : (
            <div className="conan-card-grid">
              {visibleCards.map((card) => {
                const count = Number(deck[card.key] || 0);
                const isPartner = partnerId === card.key;
                const isEvent = eventId === card.key;
                const role = getCardRole(card);
                return (
                  <article key={card.key} className="group flex min-w-0 flex-col overflow-hidden rounded-xl border border-white/[0.08] bg-[#0c1422] shadow-sm transition duration-200 hover:-translate-y-1 hover:border-rose-400/60 hover:shadow-xl hover:shadow-rose-950/30">
                    <button onClick={() => setSelectedCard(card)} className="block w-full min-w-0 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-rose-400" title={`${card.name} 상세 정보 보기`}>
                      <div className="relative overflow-hidden bg-[#070b13]">
                        {card.imageUrl ? <img loading="lazy" decoding="async" src={card.imageUrl} alt={card.name} className="aspect-[3/4] w-full object-contain transition duration-200 group-hover:scale-105" /> : <div className="flex aspect-[3/4] items-center justify-center p-2 text-center text-[10px] text-slate-500">이미지 없음</div>}
                        <div className="absolute left-1 top-1 max-w-[calc(100%-8px)] truncate rounded bg-black/80 px-1.5 py-0.5 text-[9px] font-bold text-white backdrop-blur-sm">{card.cardId || card.cardNum || card.databaseId}</div>
                        {count > 0 && <span className="absolute right-1 top-1 rounded-md bg-rose-600 px-1.5 py-0.5 text-[10px] font-black text-white shadow-md">×{count}</span>}
                        {isPartner && <span className="absolute bottom-1 left-1 rounded bg-amber-400 px-1.5 py-0.5 text-[9px] font-black text-slate-950 shadow">파트너</span>}
                        {isEvent && <span className="absolute bottom-1 left-1 rounded bg-sky-400 px-1.5 py-0.5 text-[9px] font-black text-slate-950 shadow">사건</span>}
                      </div>
                      <div className="p-2">
                        <h3 className="line-clamp-2 min-h-[2.3rem] break-keep text-[11px] font-bold leading-tight text-slate-100 sm:text-xs">{card.name}</h3>
                        <div className="mt-1 flex min-w-0 items-center justify-between gap-1 text-[9px] font-medium text-slate-400 sm:text-[10px]">
                          <span className="truncate">{card.rarity || card.type || '카드'}</span>
                          <span className="shrink-0 font-bold text-slate-300">{formatNumber(card.cost)} / {formatNumber(card.lp)}</span>
                        </div>
                      </div>
                    </button>
                    <button onClick={() => addCard(card)} aria-label={role === 'partner' ? `${card.name} 파트너 지정` : role === 'event' ? `${card.name} 사건 카드 지정` : `${card.name} 덱에 추가`} className={`mt-auto border-t border-white/[0.08] px-1 py-2 text-[10px] font-bold transition sm:text-[11px] ${role === 'partner' ? 'bg-amber-400/10 text-amber-300 hover:bg-amber-400/20' : role === 'event' ? 'bg-sky-400/10 text-sky-300 hover:bg-sky-400/20' : 'bg-white/[0.02] text-slate-300 hover:bg-rose-600/15 hover:text-rose-200'}`}>
                      {role === 'partner' ? (isPartner ? '✓ 파트너 선택됨' : '+ 파트너 지정') : role === 'event' ? (isEvent ? '✓ 사건 선택됨' : '+ 사건 지정') : (count > 0 ? `덱 추가 + (${count})` : '덱 추가 +')}
                    </button>
                  </article>
                );
              })}
            </div>
          )}
          <Pagination currentPage={currentPage} totalPages={totalPages} onChange={goToPage} />
        </section>
      ) : (
        <section className="min-w-0 rounded-2xl border border-white/10 bg-[#101827] p-4 shadow-xl md:p-5">
          <div className="mb-5 flex flex-wrap items-center justify-between gap-3 border-b border-white/10 pb-4">
            <div>
              <h2 className="text-base font-bold text-white">내 덱 구성</h2>
              <p className="mt-0.5 text-xs text-slate-400">메인 덱 최대 40장 · 동일 카드 최대 3장 · 파트너 및 사건 카드 전용 슬롯</p>
            </div>
            <div className="flex items-center gap-2">
              <span className={`rounded-xl px-3.5 py-2 text-xs font-black tabular-nums shadow-sm ${mainDeckCount === MAIN_DECK_LIMIT ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30' : 'bg-rose-500/15 text-rose-200 border border-rose-500/30'}`}>{mainDeckCount} / {MAIN_DECK_LIMIT}장</span>
              <button onClick={clearDeck} className="rounded-xl border border-white/10 bg-[#162032] px-3.5 py-2 text-xs font-semibold text-slate-300 transition hover:bg-white/10 hover:text-white">초기화</button>
              <button onClick={exportDeck} className="rounded-xl bg-rose-600 px-4 py-2 text-xs font-bold text-white shadow-md shadow-rose-900/40 transition hover:bg-rose-500">JSON 내보내기</button>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1fr)_240px]">
            <div className="min-w-0">
              <div className="mb-2.5 flex items-center justify-between gap-2">
                <h3 className="text-xs font-bold tracking-wider text-slate-300 uppercase">메인 덱 슬롯</h3>
                <span className="text-[11px] text-slate-500">총 40칸</span>
              </div>
              <div className="grid grid-cols-5 gap-2 sm:grid-cols-8 lg:grid-cols-10">
                {deckSlots.map((card, index) => card ? (
                  <article key={card.deckSlotKey} className="relative min-w-0 overflow-hidden rounded-xl border border-white/15 bg-[#090f1b] shadow-md">
                    <button onClick={() => setSelectedCard(card)} className="block w-full text-left" title={`${card.name} 상세 정보`}>
                      {card.imageUrl ? <img src={card.imageUrl} loading="lazy" alt={card.name} className="aspect-[3/4] w-full object-contain" /> : <div className="flex aspect-[3/4] items-center justify-center p-1 text-[9px] text-slate-500">이미지 없음</div>}
                      <div className="truncate px-1.5 py-1 text-[10px] font-semibold text-slate-200 bg-black/60">{card.name}</div>
                    </button>
                    <button onClick={() => removeCard(card.key)} aria-label={`${card.name} 한 장 제거`} title="한 장 제거" className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-rose-600 text-xs font-black text-white shadow hover:bg-rose-500">−</button>
                  </article>
                ) : (
                  <div key={`empty-${index}`} className="flex min-w-0 flex-col overflow-hidden rounded-xl border border-dashed border-white/15 bg-white/[0.01]">
                    <div className="flex aspect-[3/4] items-center justify-center text-xs font-bold text-slate-600">{index + 1}</div>
                    <div className="truncate px-1 py-1 text-center text-[9px] text-slate-600">빈 슬롯</div>
                  </div>
                ))}
              </div>
              {mainDeckCount === 0 && <p className="mt-4 text-xs text-slate-400">‘카드 목록’ 탭에서 원하는 카드를 골라 덱에 추가해 보세요.</p>}
            </div>

            <aside className="grid grid-cols-1 gap-3.5 sm:grid-cols-2 xl:grid-cols-1">
              <section className="rounded-2xl border border-amber-400/30 bg-[#090f1b] p-4 shadow-lg">
                <div className="mb-2.5 flex items-center justify-between gap-2">
                  <h3 className="text-xs font-black text-amber-300 tracking-wider uppercase">파트너 카드</h3>
                  <span className={`rounded px-2 py-0.5 text-[10px] font-bold ${partnerCard ? 'bg-emerald-500/20 text-emerald-300' : 'bg-rose-500/20 text-rose-300'}`}>{partnerCard ? '선택 완료' : '필수 미선택'}</span>
                </div>
                {partnerCard ? (
                  <>
                    <button onClick={() => setSelectedCard(partnerCard)} className="w-full text-left group" title={`${partnerCard.name} 상세 정보`}>
                      <img src={partnerCard.imageUrl} alt={partnerCard.name} className="mx-auto aspect-[3/4] max-h-52 w-auto max-w-full rounded-xl object-contain shadow-md transition group-hover:scale-105" />
                      <p className="mt-2.5 text-center text-xs font-bold text-white truncate">{partnerCard.name}</p>
                      <p className="mt-0.5 text-center text-[10px] text-slate-400">{partnerCard.cardId || partnerCard.cardNum}</p>
                    </button>
                    <button onClick={() => setPartnerId('')} className="mt-3 w-full rounded-xl border border-white/10 bg-[#162032] py-2 text-xs font-semibold text-slate-300 transition hover:bg-white/10">파트너 해제</button>
                  </>
                ) : (
                  <p className="py-10 text-center text-xs text-slate-500 leading-relaxed">카드 목록에서 파트너 카드를 지정해 주세요.</p>
                )}
              </section>

              <section className="rounded-2xl border border-sky-400/30 bg-[#090f1b] p-4 shadow-lg">
                <div className="mb-2.5 flex items-center justify-between gap-2">
                  <h3 className="text-xs font-black text-sky-300 tracking-wider uppercase">사건 카드</h3>
                  <span className={`rounded px-2 py-0.5 text-[10px] font-bold ${eventCard ? 'bg-emerald-500/20 text-emerald-300' : 'bg-rose-500/20 text-rose-300'}`}>{eventCard ? '선택 완료' : '필수 미선택'}</span>
                </div>
                {eventCard ? (
                  <>
                    <button onClick={() => setSelectedCard(eventCard)} className="w-full text-left group" title={`${eventCard.name} 상세 정보`}>
                      <img src={eventCard.imageUrl} alt={eventCard.name} className="mx-auto aspect-[3/4] max-h-52 w-auto max-w-full rounded-xl object-contain shadow-md transition group-hover:scale-105" />
                      <p className="mt-2.5 text-center text-xs font-bold text-white truncate">{eventCard.name}</p>
                      <p className="mt-0.5 text-center text-[10px] text-slate-400">{eventCard.cardId || eventCard.cardNum}</p>
                    </button>
                    <button onClick={() => setEventId('')} className="mt-3 w-full rounded-xl border border-white/10 bg-[#162032] py-2 text-xs font-semibold text-slate-300 transition hover:bg-white/10">사건 카드 해제</button>
                  </>
                ) : (
                  <p className="py-10 text-center text-xs text-slate-500 leading-relaxed">카드 목록에서 사건 카드를 지정해 주세요.</p>
                )}
              </section>
            </aside>
          </div>
        </section>
      )}

      {/* 카드 클릭 시 나타나는 깔끔하게 다듬어진 상세 모달 오버레이 */}
      {selectedCard && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-3 backdrop-blur-md sm:p-6" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedCard(null); }}>
          <section role="dialog" aria-modal="true" aria-label={`${selectedCard.name} 상세 정보`} className="flex max-h-[92dvh] w-full max-w-4xl flex-col overflow-hidden rounded-2xl border border-white/20 bg-[#111a2a] shadow-2xl shadow-black/80">
            
            {/* 모달 상단 헤더 (원하시는 대로 버튼들이 오른쪽 상단에 깔끔하게 배치됨) */}
            <div className="flex shrink-0 items-center justify-between border-b border-white/10 px-5 py-4 bg-[#0d1524]">
              <div className="min-w-0 pr-4">
                <span className="text-[10px] font-black tracking-widest text-rose-400 uppercase">CARD DETAIL</span>
                <h2 className="mt-0.5 truncate text-base font-black text-white sm:text-lg">{selectedCard.name}</h2>
                <p className="text-xs font-semibold text-slate-400 mt-0.5">{selectedCard.cardId || '-'} {selectedCard.cardNum ? `· ${selectedCard.cardNum}` : ''}</p>
              </div>
              <div className="flex shrink-0 items-center gap-1.5">
                <button onClick={() => moveSelectedCard(-1)} disabled={filteredCards.length < 2} aria-label="이전 카드" title="이전 카드 (←)" className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/15 bg-[#172236] text-lg font-bold text-slate-200 transition hover:bg-white/10 disabled:opacity-30">‹</button>
                <button onClick={() => moveSelectedCard(1)} disabled={filteredCards.length < 2} aria-label="다음 카드" title="다음 카드 (→)" className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/15 bg-[#172236] text-lg font-bold text-slate-200 transition hover:bg-white/10 disabled:opacity-30">›</button>
                <button onClick={() => setSelectedCard(null)} aria-label="상세 창 닫기" title="닫기 (Esc)" className="ml-1.5 rounded-xl bg-rose-600 px-4 py-2 text-xs font-bold text-white shadow-md shadow-rose-900/40 transition hover:bg-rose-500">닫기 ✕</button>
              </div>
            </div>

            {/* 모달 내부 스크롤 영역 (2열로 깔끔하게 정리된 스펙과 텍스트) */}
            <div className="min-h-0 overflow-y-auto p-4 sm:p-6">
              <div className="grid grid-cols-1 gap-6 sm:grid-cols-[240px_minmax(0,1fr)]">
                
                {/* 좌측: 카드 이미지와 추가 버튼 */}
                <div className="flex flex-col items-center gap-4">
                  {selectedCard.imageUrl ? (
                    <img src={selectedCard.imageUrl} alt={selectedCard.name} className="max-h-[38vh] w-full max-w-[220px] rounded-xl bg-[#080d17] object-contain shadow-lg sm:max-h-[52vh]" />
                  ) : (
                    <div className="flex aspect-[3/4] w-full max-w-[220px] items-center justify-center rounded-xl bg-[#080d17] text-sm text-slate-500 shadow-lg">이미지 없음</div>
                  )}
                  <button onClick={() => addCard(selectedCard)} className="w-full max-w-[220px] rounded-xl bg-rose-600 px-4 py-3 text-xs font-bold text-white shadow-lg shadow-rose-900/50 transition hover:bg-rose-500">
                    {getCardRole(selectedCard) === 'partner' ? (partnerId === selectedCard.key ? '파트너 선택 해제' : '파트너로 지정') : getCardRole(selectedCard) === 'event' ? (eventId === selectedCard.key ? '사건 카드 선택 해제' : '사건 카드로 지정') : `덱에 추가${Number(deck[selectedCard.key] || 0) ? ` · 현재 ${deck[selectedCard.key]}장` : ' +'}`}
                  </button>
                  {filteredCards.length > 1 && <p className="text-[10px] font-medium text-slate-500">키보드 방향키(← →)로 카드 전환 가능</p>}
                </div>

                {/* 우측: 정돈된 스펙 그리드 및 효과 텍스트 */}
                <div className="min-w-0 space-y-4">
                  {/* 스펙 표 */}
                  <dl className="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
                    {[
                      ['종류', selectedCard.type],
                      ['색상', selectedCard.color],
                      ['레어도', selectedCard.rarity],
                      ['코스트', formatNumber(selectedCard.cost)],
                      ['LP', formatNumber(selectedCard.lp)],
                      ['수록 제품', selectedCard.set]
                    ].map(([label, value]) => (
                      <div key={label} className="rounded-xl border border-white/[0.08] bg-[#080d17] p-3 shadow-inner">
                        <dt className="text-[10px] font-bold text-slate-400">{label}</dt>
                        <dd className="mt-1 break-words text-xs font-bold text-slate-100">{value || '-'}</dd>
                      </div>
                    ))}
                  </dl>

                  {/* 히라메키 / 컷인 시스템 효과 */}
                  {(selectedCard.hiramekiEffect || selectedCard.cutInEffect) && (
                    <div className="rounded-xl border border-white/[0.08] bg-[#080d17] p-4 shadow-inner space-y-3">
                      <h3 className="text-xs font-black text-rose-400 uppercase tracking-wider">시스템 효과</h3>
                      {selectedCard.hiramekiEffect && (
                        <div>
                          <h4 className="text-[11px] font-bold text-amber-300 mb-1">히라메키</h4>
                          <p className="whitespace-pre-wrap break-words text-xs leading-relaxed text-slate-200">{selectedCard.hiramekiEffect}</p>
                        </div>
                      )}
                      {selectedCard.cutInEffect && (
                        <div>
                          <h4 className="text-[11px] font-bold text-sky-300 mb-1">컷인</h4>
                          <p className="whitespace-pre-wrap break-words text-xs leading-relaxed text-slate-200">{selectedCard.cutInEffect}</p>
                        </div>
                      )}
                    </div>
                  )}

                  {/* 카드 본문 효과 */}
                  <div className="rounded-xl border border-white/[0.08] bg-[#080d17] p-4 shadow-inner">
                    <h3 className="mb-2 text-xs font-black text-slate-300 uppercase tracking-wider">카드 효과</h3>
                    <p className="whitespace-pre-wrap break-words text-xs leading-relaxed text-slate-100">{selectedCard.ability || '효과 텍스트 없음'}</p>
                  </div>

                  {/* 플레이버 텍스트 */}
                  {selectedCard.flavor && (
                    <div className="rounded-xl border border-white/[0.08] bg-[#080d17] p-4 shadow-inner">
                      <h3 className="mb-1.5 text-xs font-bold text-slate-400">플레이버 텍스트</h3>
                      <p className="whitespace-pre-wrap break-words text-xs italic leading-relaxed text-slate-300">{selectedCard.flavor}</p>
                    </div>
                  )}

                  {/* 일본어 원문 토글 */}
                  {(selectedCard.originalName !== selectedCard.name || selectedCard.originalAbility !== selectedCard.ability) && (
                    <details className="rounded-xl border border-white/[0.08] bg-[#080d17] p-3 text-xs">
                      <summary className="cursor-pointer font-bold text-slate-400 hover:text-white">일본어 원문 보기</summary>
                      <div className="mt-3 space-y-2 text-xs leading-relaxed text-slate-300 border-t border-white/10 pt-3">
                        <p><span className="text-slate-500 font-semibold">이름: </span>{selectedCard.originalName || '-'}</p>
                        <p className="whitespace-pre-wrap break-words"><span className="text-slate-500 font-semibold">효과: </span>{selectedCard.originalAbility || '-'}</p>
                      </div>
                    </details>
                  )}
                </div>

              </div>
            </div>

          </section>
        </div>
      )}
    </main>
  );
}
