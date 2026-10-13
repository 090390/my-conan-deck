import React, { useState } from 'react';
import cardsData from './data/cards.json';

export default function App() {
  const [selectedCard, setSelectedCard] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');

  // 검색어 필터링 (카드 이름 또는 번호)
  const filteredCards = cardsData.filter(
    (card) =>
      card.name.ko.toLowerCase().includes(searchTerm.toLowerCase()) ||
      card.name.ja.toLowerCase().includes(searchTerm.toLowerCase()) ||
      card.cardNumber.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="min-h-screen bg-gray-900 text-gray-100 p-4 md:p-8">
      {/* 상단 타이틀 및 검색 바 */}
      <header className="max-w-7xl mx-auto mb-8 flex flex-col md:flex-row items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl md:text-3xl font-extrabold tracking-wider text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-indigo-500">
            名探偵コナン TCG 덱 빌더
          </h1>
          <p className="text-sm text-gray-400 mt-1">
            총 {cardsData.length}장의 카드 중 {filteredCards.length}장 표시 중
          </p>
        </div>

        <div className="w-full md:w-72">
          <input
            type="text"
            placeholder="카드 이름 또는 번호 검색..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full px-4 py-2 bg-gray-800 border border-gray-700 rounded-lg focus:outline-none focus:border-blue-500 text-sm text-gray-200"
          />
        </div>
      </header>

      {/* 카드 그리드 영역 (한 줄에 약 8~10개 배치되도록 촘촘한 반응형 그리드 적용) */}
      <main className="max-w-7xl mx-auto">
        <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10 gap-2 md:gap-3">
          {filteredCards.map((card) => (
            <div
              key={card.id}
              onClick={() => setSelectedCard(card)}
              className="group relative cursor-pointer bg-gray-800 rounded border border-gray-700 overflow-hidden hover:border-blue-400 hover:shadow-lg hover:shadow-blue-500/20 transition-all duration-200"
            >
              {/* 카드 이미지 */}
              <div className="aspect-[63/88] w-full bg-gray-900 overflow-hidden">
                <img
                  src={card.imageUrl}
                  alt={card.name.ko}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
                  loading="lazy"
                />
              </div>
              {/* 하단 미니 정보 */}
              <div className="p-1 bg-gray-900/90 text-[10px] truncate text-center">
                <span className="text-gray-400 block">{card.cardNumber}</span>
                <span className="font-medium text-gray-200 truncate block">
                  {card.name.ko}
                </span>
              </div>
            </div>
          ))}
        </div>

        {filteredCards.length === 0 && (
          <div className="text-center py-20 text-gray-500">
            검색 결과가 없습니다.
          </div>
        )}
      </main>

      {/* 카드 클릭 시 나타나는 상세 오버레이(모달) 팝업 */}
      {selectedCard && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
          onClick={() => setSelectedCard(null)}
        >
          <div
            className="bg-gray-800 border border-gray-700 rounded-2xl max-w-2xl w-full p-6 relative shadow-2xl flex flex-col md:flex-row gap-6"
            onClick={(e) => e.stopPropagation()}
          >
            {/* 닫기 버튼 */}
            <button
              onClick={() => setSelectedCard(null)}
              className="absolute top-4 right-4 text-gray-400 hover:text-white bg-gray-700/50 hover:bg-gray-700 w-8 h-8 rounded-full flex items-center justify-center transition-colors"
            >
              ✕
            </button>

            {/* 좌측: 확대된 카드 이미지 */}
            <div className="w-full md:w-1/2 flex justify-center items-center">
              <img
                src={selectedCard.imageUrl}
                alt={selectedCard.name.ko}
                className="max-h-[400px] rounded-lg shadow-md object-contain"
              />
            </div>

            {/* 우측: 상세 정보 및 텍스트 */}
            <div className="w-full md:w-1/2 flex flex-col justify-between">
              <div>
                <span className="text-xs font-semibold px-2 py-1 bg-blue-500/20 text-blue-400 rounded">
                  {selectedCard.cardNumber}
                </span>
                <h2 className="text-xl font-bold mt-2 text-white">
                  {selectedCard.name.ko}
                </h2>
                <p className="text-sm text-gray-400 mb-4">
                  {selectedCard.name.ja}
                </p>

                <div className="bg-gray-900/60 p-4 rounded-xl border border-gray-700/50 text-sm">
                  <h3 className="text-xs font-bold text-gray-400 mb-2 uppercase tracking-wider">
                    카드 효과
                  </h3>
                  <p className="text-gray-200 whitespace-pre-line leading-relaxed">
                    {selectedCard.text.ko || '등록된 효과 텍스트가 없습니다.'}
                  </p>
                </div>
              </div>

              <div className="mt-6 flex justify-end">
                <button
                  onClick={() => setSelectedCard(null)}
                  className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium rounded-lg transition-colors"
                >
                  확인
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}