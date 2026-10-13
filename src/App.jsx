import React, { useEffect, useMemo, useState } from 'react';

const PAGE_SIZE = 72;
const MAIN_DECK_LIMIT = 40;
const SAME_CARD_LIMIT = 4;
const IMAGE_BASE = 'https://www.takaratomy.co.jp/products/conan-cardgame/storage/card/';

function firstValue(objects, keys) {
  for (const object of objects) {
    if (!object || typeof object !== 'object') continue;
    for (const key of keys) {
      const value = object[key];
      if (value !== undefined && value !== null && String(value).trim() !== '') {
        return value;
      }
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
  if (/^products\/conan-cardgame\/storage\/card\//i.test(clean)) {
    return `https://www.takaratomy.co.jp/${clean}`;
  }
  if (/^storage\/card\//i.test(clean)) {
    return `https://www.takaratomy.co.jp/products/conan-cardgame/${clean}`;
  }
  return `${IMAGE_BASE}${clean}`;
}

function numericValue(value) {
  if (value === '' || value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
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
  // These are translated only from the card's dedicated source fields.
  // Never substitute a sentence guessed from the general ability text.
  const hiramekiEffect = String(translated.hirameki || '').replace(/^【히라메키】\s*/u, '');
  const cutInEffect = String(translated.cut_in || '').replace(/^【컷인】\s*/u, '');

  const originalName = String(firstValue(objects, ['nameJp', 'title', 'name', 'cardName', 'card_name']));
  const originalType = String(firstValue(objects, ['typeJp', 'type', 'cardType', 'card_type']));
  const originalColor = String(firstValue(objects, ['colorJp', 'color', 'colour']));
  const originalSet = String(firstValue(objects, ['setJp', 'package', 'set', 'product']));
  const originalAbility = String(firstValue(objects, ['abilityJp', 'text', 'ability', 'feature', 'effect']));
  const originalFlavor = String(firstValue(objects, ['flavorJp', 'flavor_txt', 'flavor', 'flavorText', 'flavor_text']));
  const cardId = String(firstValue(objects, ['cardId', 'card_id']));
  const cardNum = String(firstValue(objects, ['cardNum', 'card_num']));
  const rarity = String(translated.rarityKo || firstValue(objects, ['rarity', 'rarityJp', 'rare', 'rarity_code', 'rarityCode']));
  const cost = numericValue(firstValue(objects, ['cost', 'costValue', 'cost_value']));
  const lp = numericValue(firstValue(objects, ['lp', 'LP']));

  return {
    key: id,
    databaseId: id,
    cardId,
    cardNum,
    name: String(translated.nameKo || firstValue([card], ['nameKo', 'translatedName']) || originalName || cardId || cardNum || '이름 없음'),
    originalName,
    type: String(translated.typeKo || firstValue([card], ['typeKo']) || originalType),
    originalType,
    color: String(translated.colorKo || firstValue([card], ['colorKo']) || originalColor),
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
  const type = `${card.type} ${card.originalType}`;
  return /パートナー|파트너/i.test(type) || /^P\d+/i.test(card.cardId);
}

function uniqueOptions(values) {
  return [...new Set(values.filter((value) => value !== '' && value !== null && value !== undefined).map(String))]
    .sort((a, b) => a.localeCompare(b, 'ko', { numeric: true }));
}

function formatNumber(value) {
  return value === null || value === undefined || value === '' ? '-' : value;
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
  const [deck, setDeck] = useState(() => {
    try { return JSON.parse(localStorage.getItem('conan-deck-main-v1') || '{}'); }
    catch { return {}; }
  });
  const [partnerId, setPartnerId] = useState(() => localStorage.getItem('conan-deck-partner-v1') || '');

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
        if (!rawCards.length) throw new Error('cards.json에서 카드 배열을 찾지 못했어요. JSON의 최상위 구조를 확인해 주세요.');
        const normalized = rawCards
          .map((card) => normalizeCard(card, translations))
          .filter((card) => card.key && card.key !== 'undefined');
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

  useEffect(() => {
    localStorage.setItem('conan-deck-main-v1', JSON.stringify(deck));
  }, [deck]);
  useEffect(() => {
    if (partnerId) localStorage.setItem('conan-deck-partner-v1', partnerId);
    else localStorage.removeItem('conan-deck-partner-v1');
  }, [partnerId]);
  useEffect(() => { setPage(1); }, [searchTerm, colorFilter, typeFilter, rarityFilter, costFilter, lpFilter]);

  // 카드 상세 모달이 열리면 배경 스크롤을 잠그고 키보드로 닫기/이동을 지원합니다.
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

  const colorOptions = useMemo(() => uniqueOptions(cards.map((card) => card.color)), [cards]);
  const typeOptions = useMemo(() => uniqueOptions(cards.map((card) => card.type)), [cards]);
  const rarityOptions = useMemo(() => uniqueOptions(cards.map((card) => card.rarity)), [cards]);
  const costOptions = useMemo(() => uniqueOptions(cards.map((card) => card.cost)), [cards]);
  const lpOptions = useMemo(() => uniqueOptions(cards.map((card) => card.lp)), [cards]);

  const filteredCards = useMemo(() => {
    const query = searchTerm.trim().toLocaleLowerCase();
    return cards.filter((card) => {
      const searchable = [
        card.name, card.originalName, card.cardId, card.cardNum,
        card.type, card.originalType, card.color, card.originalColor,
        card.ability, card.originalAbility, card.set, card.originalSet, card.rarity, card.hiramekiEffect, card.cutInEffect,
      ].join(' ').toLocaleLowerCase();
      if (query && !searchable.includes(query)) return false;
      if (colorFilter && card.color !== colorFilter) return false;
      if (typeFilter && card.type !== typeFilter) return false;
      if (rarityFilter && card.rarity !== rarityFilter) return false;
      if (costFilter !== '' && String(card.cost) !== costFilter) return false;
      if (lpFilter !== '' && String(card.lp) !== lpFilter) return false;
      return true;
    });
  }, [cards, searchTerm, colorFilter, typeFilter, rarityFilter, costFilter, lpFilter]);

  const visibleCards = filteredCards.slice(0, page * PAGE_SIZE);
  const mainDeckCount = Object.values(deck).reduce((sum, count) => sum + Number(count || 0), 0);
  const partnerCard = cards.find((card) => card.key === partnerId) || null;

  function addCard(card) {
    if (isPartnerCard(card)) {
      setPartnerId(card.key);
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
        window.alert(`메인 덱은 ${MAIN_DECK_LIMIT}장까지 넣을 수 있어요. 파트너는 별도 슬롯이에요.`);
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
    const output = {
      exportedAt: new Date().toISOString(),
      partner: partnerCard ? {
        databaseId: partnerCard.databaseId,
        cardId: partnerCard.cardId,
        cardNum: partnerCard.cardNum,
        name: partnerCard.name,
      } : null,
      mainDeckCount,
      mainDeck: Object.entries(deck).map(([key, count]) => {
        const card = cards.find((item) => item.key === key);
        return card ? {
          databaseId: card.databaseId,
          cardId: card.cardId,
          cardNum: card.cardNum,
          name: card.name,
          count: Number(count),
        } : null;
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

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-950 p-8 text-slate-100">
        <div className="text-center">
          <div className="mx-auto mb-4 h-10 w-10 animate-spin rounded-full border-2 border-slate-700 border-t-rose-500" />
          <h1 className="text-xl font-black tracking-tight">명탐정 코난 TCG 도감</h1>
          <p className="mt-2 text-sm text-slate-400">카드 데이터를 불러오는 중이에요…</p>
        </div>
      </main>
    );
  }
  if (loadError) {
    return (
      <main className="min-h-screen bg-slate-950 p-8 text-slate-100">
        <h1 className="text-2xl font-bold">카드 데이터를 불러오지 못했어요.</h1>
        <p className="mt-4 text-rose-300">{loadError}</p>
        <p className="mt-3 text-sm text-slate-400">프로젝트의 public/cards.json 파일이 실제로 존재하는지 확인해 주세요.</p>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#080d17] p-3 text-slate-100 md:p-5">
      <header className="mb-4 flex flex-wrap items-center justify-between gap-3 border-b border-white/10 pb-4">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-rose-600 text-xl font-black shadow-lg shadow-rose-950/40">C</div>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-xl font-black tracking-tight md:text-2xl">명탐정 코난 TCG 도감</h1>
              <span className="rounded-md border border-rose-400/30 bg-rose-500/10 px-2 py-0.5 text-[10px] font-bold tracking-[0.16em] text-rose-300">CARD DATABASE</span>
            </div>
            <p className="mt-1 text-xs text-slate-400">전체 {cards.length.toLocaleString()}장 · 검색하고 눌러서 상세 효과 확인</p>
          </div>
        </div>
        <a className="rounded-lg border border-white/10 px-3 py-2 text-xs font-semibold text-slate-300 transition hover:border-rose-400/50 hover:text-white" href="https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/" target="_blank" rel="noreferrer">일본 공식 카드 목록 ↗</a>
      </header>

      <div className="grid grid-cols-1 items-start gap-4 xl:grid-cols-[minmax(0,1fr)_320px]">
        <section className="min-w-0 rounded-2xl border border-white/10 bg-[#101827] p-3 md:p-4">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-baseline gap-2">
              <h2 className="text-base font-bold">카드 목록</h2>
              <span className="text-xs tabular-nums text-slate-400">{filteredCards.length.toLocaleString()}장</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="hidden text-[11px] text-slate-500 sm:inline">카드를 누르면 상세 정보가 열려요</span>
              <button onClick={clearFilters} className="rounded-lg border border-white/10 px-3 py-1.5 text-xs font-semibold text-slate-300 transition hover:border-rose-400/40 hover:bg-white/5">필터 초기화</button>
            </div>
          </div>

          <div className="mb-4 grid grid-cols-2 gap-2 md:grid-cols-6">
            <input value={searchTerm} onChange={(event) => setSearchTerm(event.target.value)} placeholder="이름 · 효과 · 카드 ID 검색" className="col-span-2 min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-3 py-2 text-sm outline-none transition placeholder:text-slate-600 focus:border-rose-400/70 md:col-span-2" />
            <select aria-label="색상 필터" value={colorFilter} onChange={(event) => setColorFilter(event.target.value)} className="min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 색상</option>{colorOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select aria-label="종류 필터" value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)} className="min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 종류</option>{typeOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select aria-label="레어도 필터" value={rarityFilter} onChange={(event) => setRarityFilter(event.target.value)} className="min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 레어도</option>{rarityOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <div className="grid grid-cols-2 gap-2">
              <select aria-label="코스트 필터" value={costFilter} onChange={(event) => setCostFilter(event.target.value)} className="min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">코스트</option>{costOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
              <select aria-label="LP 필터" value={lpFilter} onChange={(event) => setLpFilter(event.target.value)} className="min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">LP</option>{lpOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            </div>
          </div>

          {visibleCards.length === 0 ? (
            <p className="rounded-xl border border-dashed border-white/15 p-8 text-center text-sm text-slate-400">조건에 맞는 카드가 없어요.</p>
          ) : (
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-8 2xl:grid-cols-10">
              {visibleCards.map((card) => {
                const count = Number(deck[card.key] || 0);
                const isPartner = partnerId === card.key;
                return (
                  <article key={card.key} className="group flex min-w-0 flex-col overflow-hidden rounded-lg border border-white/[0.08] bg-[#090f1b] transition duration-150 hover:-translate-y-0.5 hover:border-rose-400/50 hover:shadow-lg hover:shadow-black/20">
                    <button onClick={() => setSelectedCard(card)} className="block w-full min-w-0 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-rose-400" title={`${card.name} 상세 정보 보기`} aria-label={`${card.name} 상세 정보 보기`}>
                      <div className="relative overflow-hidden bg-[#0d1524]">
                        {card.imageUrl ? <img loading="lazy" decoding="async" src={card.imageUrl} alt={card.name} className="aspect-[3/4] w-full object-contain transition duration-200 group-hover:scale-[1.025]" /> : <div className="flex aspect-[3/4] items-center justify-center p-2 text-center text-[10px] text-slate-500">이미지 없음</div>}
                        <div className="absolute left-1 top-1 max-w-[calc(100%-8px)] truncate rounded bg-black/75 px-1.5 py-0.5 text-[9px] font-semibold text-white backdrop-blur">{card.cardId || card.cardNum || card.databaseId}</div>
                        {count > 0 && <span className="absolute right-1 top-1 rounded-md bg-rose-600 px-1.5 py-0.5 text-[10px] font-black text-white shadow">×{count}</span>}
                        {isPartner && <span className="absolute bottom-1 right-1 rounded bg-amber-300 px-1.5 py-0.5 text-[9px] font-black text-slate-950">파트너</span>}
                      </div>
                      <div className="p-1.5 sm:p-2">
                        <h3 className="line-clamp-2 min-h-[2.2rem] break-keep text-[11px] font-semibold leading-[1.1rem] text-slate-100 sm:text-xs">{card.name}</h3>
                        <div className="mt-1 flex min-w-0 items-center justify-between gap-1 text-[9px] text-slate-500 sm:text-[10px]">
                          <span className="truncate">{card.rarity || card.type || '카드'}</span>
                          <span className="shrink-0">{formatNumber(card.cost)} / {formatNumber(card.lp)}</span>
                        </div>
                        {(card.hiramekiEffect || card.cutInEffect) && <div className="mt-1 flex flex-wrap gap-1">{card.hiramekiEffect && <span className="rounded bg-amber-400/10 px-1 py-0.5 text-[8px] font-bold text-amber-300">히라메키</span>}{card.cutInEffect && <span className="rounded bg-sky-400/10 px-1 py-0.5 text-[8px] font-bold text-sky-300">컷인</span>}</div>}
                      </div>
                    </button>
                    <button onClick={() => addCard(card)} aria-label={isPartnerCard(card) ? `${card.name} 파트너 지정` : `${card.name} 덱에 추가`} className="mt-auto border-t border-white/[0.07] bg-white/[0.025] px-1 py-1.5 text-[10px] font-semibold text-slate-400 transition hover:bg-rose-500/10 hover:text-rose-200 sm:text-[11px]">{isPartnerCard(card) ? (isPartner ? '✓ 파트너' : '+ 파트너') : (count > 0 ? `덱에 추가 + (${count})` : '덱에 추가 +')}</button>
                  </article>
                );
              })}
            </div>
          )}
          {visibleCards.length < filteredCards.length && <div className="mt-5 flex flex-col items-center gap-2 border-t border-white/[0.07] pt-4"><p className="text-[11px] tabular-nums text-slate-500">{visibleCards.length.toLocaleString()} / {filteredCards.length.toLocaleString()}장 표시 중</p><button onClick={() => setPage((current) => current + 1)} className="rounded-xl border border-white/10 px-5 py-2 text-xs font-semibold transition hover:border-rose-400/40 hover:bg-white/5">카드 더 불러오기 ↓</button></div>}
        </section>

        <aside className="flex min-w-0 flex-col rounded-2xl border border-white/10 bg-[#101827] p-3 md:p-4 xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)]">
          <div className="mb-3 flex items-center justify-between gap-2"><div><h2 className="text-base font-bold">내 덱</h2><p className="mt-0.5 text-[11px] text-slate-500">카드를 모아 덱을 구성하세요</p></div><span className={`rounded-lg px-2.5 py-1.5 text-xs font-black tabular-nums ${mainDeckCount === MAIN_DECK_LIMIT ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/10 text-rose-200'}`}>{mainDeckCount} / {MAIN_DECK_LIMIT}</span></div>
          <div className="mb-3 rounded-xl border border-white/[0.07] bg-[#090f1b] p-3">
            <div className="mb-2 text-xs font-bold text-slate-300">파트너 카드 · 별도 슬롯</div>
            {partnerCard ? <div className="flex items-center gap-3"><img src={partnerCard.imageUrl} alt="" className="h-16 w-12 rounded-md bg-slate-900 object-contain" /><div className="min-w-0 flex-1"><div className="truncate text-xs font-semibold">{partnerCard.name}</div><div className="mt-1 text-[10px] text-slate-500">{partnerCard.cardId || partnerCard.cardNum}</div><button onClick={() => setPartnerId('')} className="mt-1 text-[10px] font-semibold text-rose-300 hover:text-rose-200">파트너 해제 ×</button></div></div> : <p className="text-[11px] leading-5 text-slate-500">목록에서 파트너 카드를 선택하면 여기에 표시돼요.</p>}
          </div>
          <div className="min-h-28 flex-1 space-y-1.5 overflow-y-auto pr-1">
            {Object.keys(deck).length === 0 ? <p className="rounded-xl border border-dashed border-white/10 py-8 text-center text-xs leading-5 text-slate-500">아직 덱에 카드가 없어요.<br />목록에서 ‘덱에 추가’를 눌러 보세요.</p> : Object.entries(deck).map(([key, count]) => {
              const card = cards.find((item) => item.key === key);
              if (!card) return null;
              return <div key={key} className="flex items-center gap-2 rounded-lg border border-white/[0.06] bg-[#090f1b] p-1.5"><button onClick={() => setSelectedCard(card)} title="카드 상세 정보" className="shrink-0"><img src={card.imageUrl} alt="" className="h-12 w-9 rounded bg-slate-900 object-contain" /></button><button onClick={() => setSelectedCard(card)} className="min-w-0 flex-1 text-left"><div className="truncate text-[11px] font-medium">{card.name}</div><div className="mt-0.5 text-[10px] text-slate-500">{card.cardId || card.cardNum} · 비용 {formatNumber(card.cost)}</div></button><div className="flex items-center gap-1"><span className="min-w-4 text-center text-xs font-bold tabular-nums">{count}</span><button aria-label="한 장 제거" onClick={() => removeCard(key)} className="h-6 w-6 rounded-md bg-white/[0.06] text-sm font-bold hover:bg-white/10">−</button><button aria-label="한 장 추가" disabled={Number(count) >= SAME_CARD_LIMIT || mainDeckCount >= MAIN_DECK_LIMIT} onClick={() => addCard(card)} className="h-6 w-6 rounded-md bg-white/[0.06] text-sm font-bold hover:bg-white/10 disabled:opacity-30">+</button></div></div>;
            })}
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 border-t border-white/[0.08] pt-3"><button onClick={() => { setDeck({}); setPartnerId(''); }} className="rounded-lg bg-white/[0.06] px-3 py-2 text-xs font-semibold text-slate-300 transition hover:bg-white/10">덱 초기화</button><button onClick={exportDeck} className="rounded-lg bg-rose-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-rose-500">JSON 내보내기</button></div>
          <p className="mt-2 text-[10px] leading-4 text-slate-500">메인 덱 최대 40장 · 동일 카드 최대 4장<br />덱 구성은 이 브라우저에 자동 저장돼요.</p>
        </aside>
      </div>

      {selectedCard && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-2 backdrop-blur-sm sm:p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedCard(null); }}>
          <section role="dialog" aria-modal="true" aria-label={`${selectedCard.name} 상세 정보`} className="flex max-h-[94dvh] w-full max-w-5xl flex-col overflow-hidden rounded-2xl border border-white/15 bg-[#111a2a] shadow-2xl shadow-black/60">
            <div className="flex shrink-0 items-start justify-between gap-3 border-b border-white/10 px-4 py-3 sm:px-5">
              <div className="min-w-0"><p className="mb-1 text-[10px] font-bold tracking-[0.18em] text-rose-300">CARD DETAIL</p><h2 className="break-keep text-lg font-black sm:text-xl">{selectedCard.name}</h2><p className="mt-1 text-[11px] text-slate-500">{selectedCard.cardId || '-'} {selectedCard.cardNum ? `· ${selectedCard.cardNum}` : ''}</p></div>
              <div className="flex shrink-0 items-center gap-1.5">
                <button onClick={() => moveSelectedCard(-1)} disabled={filteredCards.length < 2} aria-label="이전 카드" title="이전 카드 (←)" className="h-9 w-9 rounded-lg border border-white/10 text-lg text-slate-300 transition hover:bg-white/10 disabled:opacity-30">‹</button>
                <button onClick={() => moveSelectedCard(1)} disabled={filteredCards.length < 2} aria-label="다음 카드" title="다음 카드 (→)" className="h-9 w-9 rounded-lg border border-white/10 text-lg text-slate-300 transition hover:bg-white/10 disabled:opacity-30">›</button>
                <button onClick={() => setSelectedCard(null)} aria-label="상세 창 닫기" title="닫기 (Esc)" className="ml-1 h-9 rounded-lg bg-rose-600 px-3 text-xs font-bold text-white transition hover:bg-rose-500">닫기 ✕</button>
              </div>
            </div>
            <div className="min-h-0 overflow-y-auto p-3 sm:p-5">
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-[220px_minmax(0,1fr)] sm:gap-5">
                <div className="flex flex-col items-center gap-3 sm:sticky sm:top-0 sm:self-start">
                  {selectedCard.imageUrl ? <img src={selectedCard.imageUrl} alt={selectedCard.name} className="max-h-[34vh] w-full max-w-[190px] rounded-xl bg-[#090f1b] object-contain sm:max-h-[58vh] sm:max-w-[220px]" /> : <div className="flex aspect-[3/4] w-full max-w-[190px] items-center justify-center rounded-xl bg-[#090f1b] text-sm text-slate-500">이미지 없음</div>}
                  <button onClick={() => addCard(selectedCard)} className="w-full max-w-[240px] rounded-xl bg-rose-600 px-4 py-2.5 text-xs font-bold text-white transition hover:bg-rose-500">{isPartnerCard(selectedCard) ? (partnerId === selectedCard.key ? '파트너로 지정됨' : '파트너로 지정') : `덱에 추가${Number(deck[selectedCard.key] || 0) ? ` · 현재 ${deck[selectedCard.key]}장` : ' +'}`}</button>
                  {filteredCards.length > 1 && <p className="text-[10px] text-slate-600">← → 키로 다른 카드 확인</p>}
                </div>
                <div className="min-w-0 space-y-3">
                  <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">{[['종류', selectedCard.type], ['색상', selectedCard.color], ['레어도', selectedCard.rarity], ['코스트', formatNumber(selectedCard.cost)], ['LP', formatNumber(selectedCard.lp)], ['수록 제품', selectedCard.set]].map(([label, value]) => <div key={label} className="rounded-lg border border-white/[0.07] bg-[#090f1b] p-2.5"><dt className="text-[10px] font-medium text-slate-500">{label}</dt><dd className="mt-1 break-words text-xs font-semibold text-slate-200">{value || '-'}</dd></div>)}</dl>
                  {(selectedCard.hiramekiEffect || selectedCard.cutInEffect) && <div className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><h3 className="mb-3 text-xs font-bold">게임 시스템 효과</h3><div className="space-y-3">{selectedCard.hiramekiEffect && <div><h4 className="mb-1 text-xs font-bold text-amber-300">히라메키</h4><p className="whitespace-pre-wrap break-words text-xs leading-5 text-slate-200">{selectedCard.hiramekiEffect}</p></div>}{selectedCard.cutInEffect && <div><h4 className="mb-1 text-xs font-bold text-sky-300">컷인</h4><p className="whitespace-pre-wrap break-words text-xs leading-5 text-slate-200">{selectedCard.cutInEffect}</p></div>}</div></div>}
                  <div className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><h3 className="mb-2 text-xs font-bold text-slate-300">카드 효과</h3><p className="whitespace-pre-wrap break-words text-xs leading-6 text-slate-200">{selectedCard.ability || '효과 텍스트 없음'}</p></div>
                  {selectedCard.flavor && <div className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><h3 className="mb-2 text-xs font-bold text-slate-300">플레이버 텍스트</h3><p className="whitespace-pre-wrap break-words text-xs leading-5 text-slate-300">{selectedCard.flavor}</p></div>}
                  {(selectedCard.originalName !== selectedCard.name || selectedCard.originalAbility !== selectedCard.ability) && <details className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><summary className="cursor-pointer text-xs font-semibold text-slate-300">일본어 원문 보기</summary><div className="mt-3 space-y-3 text-xs leading-5"><p><span className="text-slate-500">이름: </span>{selectedCard.originalName || '-'}</p><p className="whitespace-pre-wrap break-words"><span className="text-slate-500">효과: </span>{selectedCard.originalAbility || '-'}</p></div></details>}
                </div>
              </div>
            </div>
          </section>
        </div>
      )}
    </main>
  );
}
