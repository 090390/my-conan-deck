import React, { useState } from 'react';

// 예시 카드 데이터베이스 (실제 사용 시 JSON 파일이나 API로 분리)
const INITIAL_CARDS = [
  {
    id: 'CT-001',
    name: '江戸川コナン (에도가와 코난)',
    translatedName: '에도가와 코난',
    type: '캐릭터',
    cost: 2,
    color: 'red',
    text: '【등장시】 자신의 덱 위에서 카드 3장을 보고 원하는 순서대로 되돌립니다.',
    imageUrl: 'https://via.placeholder.com/150/ef4444/ffffff?text=Conan+Red',
  },
  {
    id: 'CT-002',
    name: '毛利蘭 (모리 란)',
    translatedName: '모리 란',
    type: '캐릭터',
    cost: 3,
    color: 'blue',
    text: '【어택시】 이 카드의 AP를 +1000 한다.',
    imageUrl: 'https://via.placeholder.com/150/3b82f6/ffffff?text=Ran+Blue',
  },
  {
    id: 'CT-003',
    name: '怪盗キッド (괴도 키드)',
    translatedName: '괴도 키드',
    type: '캐릭터',
    cost: 4,
    color: 'purple',
    text: '【퇴장시】 상대의 패를 1장 무작위로 버리게 한다.',
    imageUrl: 'https://via.placeholder.com/150/a855f7/ffffff?text=Kidd+Purple',
  },
  {
    id: 'CT-004',
    name: '真実はいつもひとつ！ (진실은 언제나 하나!)',
    translatedName: '진실은 언제나 하나!',
    type: '이벤트',
    cost: 1,
    color: 'red',
    text: '자신의 코난 캐릭터 1장의 체력을 회복하고 드로우를 1장 한다.',
    imageUrl: 'https://via.placeholder.com/150/f87171/ffffff?text=Event+Red',
  },
];

export default function DeckBuilder() {
  const [cards] = useState(INITIAL_CARDS);
  // 덱 상태: { [cardId]: 개수 } 형태
  const [deck, setDeck] = useState({});
  const [searchTerm, setSearchTerm] = useState('');

  // 덱에 카드 추가 (최대 4장 제한 등 규칙 적용 가능)
  const addToDeck = (card) => {
    setDeck((prev) => {
      const currentCount = prev[card.id] || 0;
      if (currentCount >= 4) {
        alert('동일한 카드는 최대 4장까지만 넣을 수 있습니다.');
        return prev;
      }
      return { ...prev, [card.id]: currentCount + 1 };
    });
  };

  // 덱에서 카드 제거
  const removeFromDeck = (cardId) => {
    setDeck((prev) => {
      const currentCount = prev[cardId] || 0;
      if (currentCount <= 1) {
        const copy = { ...prev };
        delete copy[cardId];
        return copy;
      }
      return { ...prev, [cardId]: currentCount - 1 };
    });
  };

  // 총 덱 매수 계산
  const totalDeckCount = Object.values(deck).reduce((acc, count) => acc + count, 0);

  // 검색 필터링된 카드 목록
  const filteredCards = cards.filter((card) =>
    card.translatedName.toLowerCase().includes(searchTerm.toLowerCase()) ||
    card.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="flex flex-col md:flex-row h-screen bg-gray-900 text-white p-4 gap-4">
      
      {/* [왼쪽 영역] 카드 검색 및 도감 목록 */}
      <div className="w-full md:w-3/5 flex flex-col bg-gray-800 rounded-lg p-4 shadow-lg overflow-hidden">
        <h2 className="text-xl font-bold mb-3 text-red-400">카드 도감 (한국어 번역)</h2>
        
        {/* 검색바 */}
        <input
          type="text"
          placeholder="카드 이름 검색 (한국어/일본어)..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="p-2 mb-4 bg-gray-700 rounded border border-gray-600 focus:outline-none focus:border-red-500"
        />

        {/* 카드 그리드 */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 overflow-y-auto pr-1 flex-1">
          {filteredCards.map((card) => (
            <div
              key={card.id}
              className="bg-gray-700 rounded-lg p-2 flex flex-col justify-between border border-gray-600 hover:border-red-400 transition"
            >
              <div>
                <img src={card.imageUrl} alt={card.name} className="w-full h-32 object-cover rounded mb-2" />
                <div className="text-xs text-gray-400">{card.id} | 코스트: {card.cost}</div>
                <div className="font-semibold text-sm truncate">{card.translatedName}</div>
                <div className="text-xs text-gray-300 mt-1 line-clamp-2">{card.text}</div>
              </div>
              <button
                onClick={() => addToDeck(card)}
                className="mt-2 w-full bg-red-600 hover:bg-red-500 text-white text-xs py-1.5 rounded font-medium transition"
              >
                덱에 추가 +
              </button>
            </div>
          ))}
        </div>
      </div>

      {/* [오른쪽 영역] 현재 구성된 덱 정보 */}
      <div className="w-full md:w-2/5 flex flex-col bg-gray-800 rounded-lg p-4 shadow-lg overflow-hidden">
        <div className="flex justify-between items-center mb-3">
          <h2 className="text-xl font-bold text-blue-400">내 덱 구성</h2>
          <span className={`text-sm font-semibold px-2.5 py-1 rounded ${totalDeckCount === 50 ? 'bg-green-600' : 'bg-gray-700 text-yellow-400'}`}>
            총 매수: {totalDeckCount} / 50
          </span>
        </div>

        {/* 덱에 담긴 카드 리스트 */}
        <div className="flex-1 overflow-y-auto pr-1 space-y-2">
          {Object.keys(deck).length === 0 ? (
            <div className="flex items-center justify-center h-full text-gray-500 text-sm">
              왼쪽 도감에서 카드를 추가해 덱을 구성해보세요.
            </div>
          ) : (
            Object.entries(deck).map(([cardId, count]) => {
              const card = cards.find((c) => c.id === cardId);
              if (!card) return null;
              return (
                <div
                  key={cardId}
                  className="flex items-center justify-between bg-gray-700 p-2 rounded border border-gray-600"
                >
                  <div className="flex items-center space-x-3">
                    <img src={card.imageUrl} alt={card.name} className="w-10 h-10 object-cover rounded" />
                    <div>
                      <div className="text-sm font-medium">{card.translatedName}</div>
                      <div className="text-xs text-gray-400">코스트: {card.cost}</div>
                    </div>
                  </div>
                  <div className="flex items-center space-x-2">
                    <span className="text-sm font-bold bg-gray-800 px-2 py-1 rounded">
                      {count}장
                    </span>
                    <button
                      onClick={() => removeFromDeck(cardId)}
                      className="bg-red-900/60 hover:bg-red-700 text-red-200 w-7 h-7 rounded flex items-center justify-center font-bold"
                    >
                      -
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>

        {/* 하단 액션 버튼 */}
        <div className="mt-4 pt-3 border-t border-gray-700 flex gap-2">
          <button
            onClick={() => setDeck({})}
            className="w-1/2 bg-gray-700 hover:bg-gray-600 text-gray-300 py-2 rounded text-sm font-medium transition"
          >
            초기화
          </button>
          <button
            onClick={() => alert(JSON.stringify(deck, null, 2))}
            className="w-1/2 bg-blue-600 hover:bg-blue-500 text-white py-2 rounded text-sm font-medium transition"
          >
            덱 저장/내보내기
          </button>
        </div>
      </div>

    </div>
  );
}