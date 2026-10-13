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

  const originalName = String(firstValue(objects, ['nameJp', 'title', 'name', 'cardName', 'card_name']));
  const originalType = String(firstValue(objects, ['typeJp', 'type', 'cardType', 'card_type']));
  const originalColor = String(firstValue(objects, ['colorJp', 'color', 'colour']));
  const originalSet = String(firstValue(objects, ['setJp', 'package', 'set', 'product']));
  const originalAbility = String(firstValue(objects, ['abilityJp', 'text', 'ability', 'feature', 'effect']));
  const originalFlavor = String(firstValue(objects, ['flavorJp', 'flavor_txt', 'flavor', 'flavorText', 'flavor_text']));
  const cardId = String(firstValue(objects, ['cardId', 'card_id']));
  const cardNum = String(firstValue(objects, ['cardNum', 'card_num']));
  const rarity = String(firstValue(objects, ['rarity', 'rarityJp']));
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
        card.ability, card.originalAbility, card.set, card.originalSet,
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

  if (loading) {
    return <main className="min-h-screen bg-slate-950 p-8 text-slate-100"><h1 className="text-2xl font-bold">코난 카드 도감</h1><p className="mt-4">카드 데이터를 불러오는 중이에요…</p></main>;
  }
  if (loadError) {
    return <main className="min-h-screen bg-slate-950 p-8 text-slate-100"><h1 className="text-2xl font-bold">카드 데이터를 불러오지 못했어요.</h1><p className="mt-4 text-rose-300">{loadError}</p><p className="mt-3 text-sm text-slate-400">프로젝트의 public/cards.json 파일이 실제로 존재하는지 확인해 주세요.</p></main>;
  }

  return (
    <main className="min-h-screen bg-slate-950 p-3 text-slate-100 md:p-5">
      <header className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black tracking-tight md:text-3xl">명탐정 코난 TCG 도감</h1>
          <p className="mt-1 text-sm text-slate-400">전체 {cards.length.toLocaleString()}장 · 한국어 번역은 별도 파일로 관리</p>
        </div>
        <a className="text-sm text-sky-300 underline" href="https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/" target="_blank" rel="noreferrer">일본 공식 카드 목록</a>
      </header>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1fr)_340px]">
        <section className="min-w-0 rounded-2xl border border-slate-800 bg-slate-900 p-3 md:p-4">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-lg font-bold">카드 목록 <span className="text-sm font-normal text-slate-400">{filteredCards.length.toLocaleString()}장 검색됨</span></h2>
            <button onClick={clearFilters} className="rounded-lg border border-slate-700 px-3 py-1.5 text-sm hover:bg-slate-800">필터 초기화</button>
          </div>
          <div className="mb-4 grid grid-cols-2 gap-2 md:grid-cols-3 xl:grid-cols-6">
            <input value={searchTerm} onChange={(event) => setSearchTerm(event.target.value)} placeholder="이름·효과·ID 검색" className="col-span-2 min-w-0 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm outline-none focus:border-sky-500 md:col-span-3 xl:col-span-2" />
            <select value={colorFilter} onChange={(event) => setColorFilter(event.target.value)} className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-sm"><option value="">모든 색상</option>{colorOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)} className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-sm"><option value="">모든 종류</option>{typeOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select value={rarityFilter} onChange={(event) => setRarityFilter(event.target.value)} className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-sm"><option value="">모든 레어도</option>{rarityOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select value={costFilter} onChange={(event) => setCostFilter(event.target.value)} className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-sm"><option value="">모든 코스트</option>{costOptions.map((value) => <option key={value} value={value}>코스트 {value}</option>)}</select>
            <select value={lpFilter} onChange={(event) => setLpFilter(event.target.value)} className="rounded-lg border border-slate-700 bg-slate-950 px-2 py-2 text-sm"><option value="">모든 LP</option>{lpOptions.map((value) => <option key={value} value={value}>LP {value}</option>)}</select>
          </div>

          {visibleCards.length === 0 ? <p className="rounded-xl border border-dashed border-slate-700 p-8 text-center text-slate-400">조건에 맞는 카드가 없어요.</p> : (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-5">
              {visibleCards.map((card) => (
                <article key={card.key} className="flex min-w-0 flex-col overflow-hidden rounded-xl border border-slate-800 bg-slate-950 transition hover:border-sky-600">
                  <button onClick={() => setSelectedCard(card)} className="block w-full text-left" title="상세 정보 보기">
                    {card.imageUrl ? <img loading="lazy" src={card.imageUrl} alt={card.name} className="aspect-[3/4] w-full bg-slate-900 object-contain" /> : <div className="flex aspect-[3/4] items-center justify-center bg-slate-900 p-3 text-center text-sm text-slate-500">이미지 없음</div>}
                    <div className="p-2.5">
                      <div className="mb-1 flex flex-wrap gap-1 text-[11px] text-slate-400"><span>{card.cardId || card.cardNum || card.databaseId}</span>{card.rarity && <span>· {card.rarity}</span>}</div>
                      <h3 className="line-clamp-2 min-h-10 text-sm font-semibold leading-5">{card.name}</h3>
                      <p className="mt-1 text-xs text-slate-400">{card.color || '색상 미상'} · {card.type || '종류 미상'}</p>
                      <p className="mt-1 text-xs text-slate-300">코스트 {formatNumber(card.cost)} / LP {formatNumber(card.lp)}</p>
                    </div>
                  </button>
                  <button onClick={() => addCard(card)} className="mt-auto border-t border-slate-800 bg-slate-900 px-2 py-2 text-xs font-semibold text-sky-300 hover:bg-slate-800">{isPartnerCard(card) ? (partnerId === card.key ? '파트너로 지정됨' : '파트너로 지정') : '메인 덱에 추가 +'}</button>
                </article>
              ))}
            </div>
          )}
          {visibleCards.length < filteredCards.length && <div className="mt-5 text-center"><button onClick={() => setPage((current) => current + 1)} className="rounded-xl border border-slate-700 px-5 py-2 text-sm hover:bg-slate-800">더 보기 ({visibleCards.length.toLocaleString()} / {filteredCards.length.toLocaleString()})</button></div>}
        </section>

        <aside className="flex min-w-0 flex-col rounded-2xl border border-slate-800 bg-slate-900 p-3 md:p-4 xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)]">
          <div className="mb-3 flex items-center justify-between gap-2"><h2 className="text-lg font-bold">내 덱</h2><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${mainDeckCount === MAIN_DECK_LIMIT ? 'bg-emerald-900 text-emerald-200' : 'bg-slate-800 text-amber-200'}`}>{mainDeckCount} / {MAIN_DECK_LIMIT}장</span></div>
          <div className="mb-3 rounded-xl border border-slate-800 bg-slate-950 p-3">
            <div className="mb-2 text-sm font-semibold">파트너 (별도 슬롯)</div>
            {partnerCard ? <div className="flex items-center gap-3"><img src={partnerCard.imageUrl} alt="" className="h-16 w-12 rounded bg-slate-900 object-contain" /><div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{partnerCard.name}</div><div className="text-xs text-slate-400">{partnerCard.cardId || partnerCard.cardNum}</div><button onClick={() => setPartnerId('')} className="mt-1 text-xs text-rose-300 underline">파트너 해제</button></div></div> : <p className="text-xs text-slate-500">카드 목록에서 파트너 카드를 지정해 주세요.</p>}
          </div>
          <div className="min-h-28 flex-1 space-y-2 overflow-y-auto pr-1">
            {Object.keys(deck).length === 0 ? <p className="py-5 text-center text-sm text-slate-500">아직 메인 덱에 카드가 없어요.</p> : Object.entries(deck).map(([key, count]) => {
              const card = cards.find((item) => item.key === key);
              if (!card) return null;
              return <div key={key} className="flex items-center gap-2 rounded-xl border border-slate-800 bg-slate-950 p-2"><img src={card.imageUrl} alt="" className="h-14 w-10 shrink-0 rounded bg-slate-900 object-contain" /><div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{card.name}</div><div className="text-xs text-slate-500">{card.cardId || card.cardNum} · 코스트 {formatNumber(card.cost)}</div></div><div className="flex items-center gap-1"><span className="min-w-5 text-center text-sm">{count}</span><button aria-label="한 장 제거" onClick={() => removeCard(key)} className="h-7 w-7 rounded bg-slate-800 font-bold hover:bg-slate-700">−</button><button aria-label="한 장 추가" disabled={Number(count) >= SAME_CARD_LIMIT || mainDeckCount >= MAIN_DECK_LIMIT} onClick={() => addCard(card)} className="h-7 w-7 rounded bg-slate-800 font-bold hover:bg-slate-700 disabled:opacity-30">+</button></div></div>;
            })}
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 border-t border-slate-800 pt-3"><button onClick={() => { setDeck({}); setPartnerId(''); }} className="rounded-lg bg-slate-800 px-3 py-2 text-sm hover:bg-slate-700">덱 초기화</button><button onClick={exportDeck} className="rounded-lg bg-sky-700 px-3 py-2 text-sm font-semibold hover:bg-sky-600">덱 JSON 내보내기</button></div>
          <p className="mt-2 text-[11px] leading-4 text-slate-500">메인 덱은 최대 40장, 같은 카드는 최대 4장으로 설정했어요. 덱 구성은 현재 브라우저에 자동 저장돼요.</p>
        </aside>
      </div>

      {selectedCard && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-3" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedCard(null); }}>
        <section role="dialog" aria-modal="true" aria-label="카드 상세 정보" className="max-h-[94vh] w-full max-w-4xl overflow-y-auto rounded-2xl border border-slate-700 bg-slate-900 p-4 shadow-2xl md:p-5">
          <div className="mb-3 flex items-start justify-between gap-3"><div><h2 className="text-xl font-bold">{selectedCard.name}</h2><p className="mt-1 text-xs text-slate-400">카드 ID {selectedCard.cardId || '-'} · 카드 번호 {selectedCard.cardNum || '-'}</p></div><button onClick={() => setSelectedCard(null)} className="rounded-lg bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700">닫기 ✕</button></div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-[220px_minmax(0,1fr)]">
            {selectedCard.imageUrl ? <img src={selectedCard.imageUrl} alt={selectedCard.name} className="mx-auto max-h-[65vh] w-full max-w-[220px] rounded-xl bg-slate-950 object-contain" /> : <div className="flex min-h-64 items-center justify-center rounded-xl bg-slate-950 text-slate-500">이미지 없음</div>}
            <div className="space-y-3">
              <dl className="grid grid-cols-2 gap-2 text-sm">
                {[['종류', selectedCard.type], ['색상', selectedCard.color], ['레어도', selectedCard.rarity], ['코스트', formatNumber(selectedCard.cost)], ['LP', formatNumber(selectedCard.lp)], ['수록 제품', selectedCard.set]].map(([label, value]) => <div key={label} className="rounded-lg border border-slate-800 bg-slate-950 p-2"><dt className="text-xs text-slate-500">{label}</dt><dd className="mt-1 break-words font-medium">{value || '-'}</dd></div>)}
              </dl>
              <div className="rounded-xl border border-slate-800 bg-slate-950 p-3"><h3 className="mb-2 text-sm font-bold">카드 효과</h3><p className="whitespace-pre-wrap break-words text-sm leading-6">{selectedCard.ability || '효과 텍스트 없음'}</p></div>
              {selectedCard.flavor && <div className="rounded-xl border border-slate-800 bg-slate-950 p-3"><h3 className="mb-2 text-sm font-bold">플레이버 텍스트</h3><p className="whitespace-pre-wrap break-words text-sm leading-6">{selectedCard.flavor}</p></div>}
              {(selectedCard.originalName !== selectedCard.name || selectedCard.originalAbility !== selectedCard.ability) && <details className="rounded-xl border border-slate-800 bg-slate-950 p-3"><summary className="cursor-pointer text-sm font-semibold">일본어 원문 보기</summary><div className="mt-3 space-y-3 text-sm"><p><span className="text-slate-500">이름: </span>{selectedCard.originalName || '-'}</p><p className="whitespace-pre-wrap break-words leading-6"><span className="text-slate-500">효과: </span>{selectedCard.originalAbility || '-'}</p></div></details>}
              <button onClick={() => addCard(selectedCard)} className="w-full rounded-xl bg-sky-700 px-4 py-3 text-sm font-bold hover:bg-sky-600">{isPartnerCard(selectedCard) ? '파트너로 지정' : '덱에 추가'}</button>
            </div>
          </div>
        </section>
      </div>}
    </main>
  );
}
