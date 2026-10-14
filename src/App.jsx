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

// 카드 색상 표기를 한 글자 태그로 통일합니다. 조합 색상은 표시 순서를 보존하되,
// 필터용 colorKey는 고정 순서로 만들어 '황흑'과 '흑황'을 같은 색 조합으로 취급합니다.
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

  // 구분 기호 없이 이어진 원문 표기(예: 赤黄, 黄黒)도 처리합니다.
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
    // 예상하지 못한 표기는 데이터가 손실되지 않도록 원래 표기를 보존합니다.
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

// 실제 화면에 표시할 키워드 태그는 자동 추론하지 않습니다.
// public/card-keyword-tags.json에 카드별로 검토 완료한 태그를 기록해 사용합니다.
function getRecordIdentifiers(record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return [];
  return ['databaseId', 'database_id', 'id', 'key', 'cardNum', 'card_num', 'cardId', 'card_id']
    .map((key) => String(record[key] ?? '').trim())
    .filter(Boolean);
}

function getKeywordTagRecord(tagData, identifiers = []) {
  if (!tagData || typeof tagData !== 'object') return null;
  const wanted = new Set(identifiers.map((value) => String(value ?? '').trim().toLocaleLowerCase()).filter(Boolean));
  const containerNames = ['cards', 'data', 'items', 'records', 'entries', 'cardTags', 'tagsByCard'];
  const roots = [tagData];
  for (const name of containerNames) {
    const container = tagData[name];
    if (container && typeof container === 'object') roots.push(container);
  }

  for (const root of roots) {
    if (Array.isArray(root)) {
      const match = root.find((record) => getRecordIdentifiers(record).some((id) => wanted.has(id.toLocaleLowerCase())));
      if (match) return match;
      continue;
    }
    if (typeof root !== 'object' || !root) continue;

    // 우선 카드 ID를 객체 키로 사용한 일반적인 맵 구조를 확인합니다(대소문자 차이도 허용).
    for (const identifier of identifiers) {
      const key = String(identifier ?? '').trim();
      if (key && Object.prototype.hasOwnProperty.call(root, key)) return root[key];
    }
    const lowerKeyMap = new Map(Object.keys(root).map((key) => [key.toLocaleLowerCase(), key]));
    for (const identifier of identifiers) {
      const matchKey = lowerKeyMap.get(String(identifier ?? '').trim().toLocaleLowerCase());
      if (matchKey) return root[matchKey];
    }

    // 배열이 아닌 레코드 목록에서도 레코드 안의 databaseId/cardNum 등으로 찾습니다.
    for (const value of Object.values(root)) {
      if (getRecordIdentifiers(value).some((id) => wanted.has(id.toLocaleLowerCase()))) return value;
    }
  }
  return null;
}

function normalizeTagValue(tag) {
  return String(tag ?? '').trim().replace(/^[\[【]\s*|\s*[\]】]$/gu, '').trim();
}

function tagFromReviewedCandidate(candidate) {
  if (!candidate || typeof candidate !== 'object') return '';
  // suggestedTag는 selected 여부와 관계없이 명시적으로 입력한 값이므로 우선 표시합니다.
  const suggested = normalizeTagValue(candidate.suggestedTag ?? candidate.suggested_tag);
  if (suggested) return suggested;
  if (candidate.selected !== true) return '';
  const finalTag = normalizeTagValue(candidate.finalTag ?? candidate.final_tag);
  if (finalTag) return finalTag;
  const keyword = String(candidate.keyword || '').trim();
  if (!['돌격', '신속', '질풍'].includes(keyword)) return '';
  if (candidate.classification !== 'self_gain' && candidate.classification !== 'grant_other') return '';
  const conditionalPrefix = candidate.conditionalGuess === true || candidate.conditional_guess === true ? '조건부 ' : '';
  return `${conditionalPrefix}${keyword}${candidate.classification === 'grant_other' ? ' 부여' : ''}`;
}

function normalizeKeywordTagList(record) {
  if (record === null || record === undefined) return [];
  const recordObject = Array.isArray(record) ? null : record;
  const directValues = Array.isArray(record)
    ? record
    : [
        ...(Array.isArray(recordObject?.tags) ? recordObject.tags : []),
        ...(Array.isArray(recordObject?.keywordTags) ? recordObject.keywordTags : []),
        ...(Array.isArray(recordObject?.keyword_tags) ? recordObject.keyword_tags : []),
        ...(Array.isArray(recordObject?.assignedTags) ? recordObject.assignedTags : []),
        ...(Array.isArray(recordObject?.suggestedTags) ? recordObject.suggestedTags : []),
        ...(recordObject?.tag ? [recordObject.tag] : []),
        ...(recordObject?.suggestedTag ? [recordObject.suggestedTag] : []),
        ...(recordObject?.suggested_tag ? [recordObject.suggested_tag] : []),
      ];
  // 검토 JSON(후보 안의 suggestedTag) 및 최종 태그 JSON(tags 배열) 모두 지원합니다.
  const candidateLists = [
    recordObject?.candidates,
    recordObject?.keywordCandidates,
    recordObject?.keyword_candidates,
    recordObject?.review?.candidates,
    recordObject?.analysis?.candidates,
  ].filter(Array.isArray);
  const candidateTags = candidateLists.flatMap((list) => list.map(tagFromReviewedCandidate)).filter(Boolean);
  return [...new Set([...directValues, ...candidateTags].map(normalizeTagValue).filter(Boolean))];
}

function resolveKeywordTags(tagData, identifiers = []) {
  return normalizeKeywordTagList(getKeywordTagRecord(tagData, identifiers));
}

function keywordTagClass(tag) {
  const value = String(tag || '');
  if (value.includes('돌격')) return 'keyword-assault';
  if (value.includes('신속')) return 'keyword-swift';
  if (value.includes('질풍')) return 'keyword-gale';
  return 'keyword-other';
}

function formatAbilityText(value) {
  const text = String(value ?? '').replace(/\r\n?/gu, '\n').trim();
  if (!text) return '';
  // 마침표 뒤에 새 선언/자동/상시/기동 헤더가 오면 그 능력부터 새 줄로 표시합니다.
  // \s*는 일반 공백뿐 아니라 일본어 전각 공백도 처리합니다.
  return text
    .replace(/([.!?。！？])\s*(?=【(?:선언|자동|상시|기동|宣言|自動|常時|起動)(?:】|\s))/gu, '$1\n')
    .replace(/[ \t　]+\n/gu, '\n')
    .replace(/\n{3,}/gu, '\n\n');
}

const TRAIT_TRANSLATIONS = {
  '高校生': '고등학생', '警察': '경찰', '探偵': '탐정', '黒ずくめの組織': '검은 조직',
  '警視庁': '경시청', '少年探偵団': '소년 탐정단', '毛利探偵事務所': '모리 탐정 사무소',
  '赤井家': '아카이 일가', 'FBI': 'FBI', '空手家': '가라테 선수', 'YAIBA': 'YAIBA',
  '長野県警': '나가노현경', '科学者': '과학자', '怪盗': '괴도', '公安': '공안',
  '鈴木財閥': '스즈키 재벌', '喫茶ポアロ': '카페 포아로', '神奈川県警': '가나가와현경',
  '大阪府警': '오사카부경', 'マジシャン': '마술사', '執事': '집사', '大学院生': '대학원생',
  '棋士': '기사', '女優': '여배우', 'ガジェット': '가젯', '小説家': '소설가', '犯人': '범인',
  '発明家': '발명가', 'サッカー選手': '축구 선수', '医師': '의사', '弁護士': '변호사',
  '教師': '교사', 'アイドル': '아이돌', 'CIA': 'CIA', 'ビッグジュエル': '빅 주얼',
  '京都府警': '교토부경', '群馬県警': '군마현경', '赤魔術': '적마술', '魔女': '마녀',
  'ヒーロー': '히어로', '寿司職人': '초밥 장인', '犬': '개', 'まじっく快斗': '매직 카이토',
  '猫': '고양이', '大学生': '대학생', '秘書': '비서', '図書館館長': '도서관장', 'メイド': '메이드',
  'アナウンサー': '아나운서', 'ボディガード': '보디가드', '静岡県警': '시즈오카현경',
  'シマリス': '줄무늬다람쥐', '鷹': '매', '家政婦': '가정부', 'ラーメン小倉': '라멘 오구라',
  '怪物': '괴물', '花見客': '꽃구경객', 'バーテンダー': '바텐더', '王女': '왕녀', '王子': '왕자',
  '邪神': '사신', 'ロボット': '로봇', '証券会社社員': '증권회사 직원', 'CGクリエイター': 'CG 크리에이터',
  'システムエンジニア': '시스템 엔지니어', '食品会社社員': '식품회사 직원', '大学教授': '대학 교수',
  '政治家': '정치가', '怪人': '괴인', '泥参会': '도산회', '俳優': '배우', '消防士': '소방관',
  '会社員': '회사원', 'NY市警': '뉴욕시경', '女流棋士': '여류 기사', '英語講師': '영어 강사',
  'シャッフルロマンス': '셔플 로맨스', '婚活パーティー': '맞선 파티',
  'お手伝い': '도우미', 'カメラマン': '카메라맨', 'デザイナー': '디자이너', '北海道警': '홋카이도경',
  '医大生': '의대생', '医療関係者': '의료 관계자', '千葉県警': '지바현경', '女王': '여왕',
  '絵描き': '화가', '酒屋': '주점',
};

function parseTraits(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return [];
  return [...new Set(raw.split(/[,，/、|｜]+/u).map((part) => part.trim()).filter(Boolean))];
}

function localizeTraits(value) {
  return parseTraits(value).map((trait) => TRAIT_TRANSLATIONS[trait] || trait);
}

function normalizeCard(card, translations, keywordTagData = {}) {
  const source = card?.sourceData && typeof card.sourceData === 'object'
    ? card.sourceData
    : card?.raw && typeof card.raw === 'object'
      ? card.raw
      : {};
  const objects = [card, source];
  // key는 기존 로컬 덱 저장값과 호환되도록 기존 우선순위를 유지합니다.
  const id = String(firstValue(objects, ['id', 'databaseId', 'database_id', 'cardId', 'card_id', 'cardNum', 'card_num']));
  const databaseId = String(firstValue(objects, ['databaseId', 'database_id', 'id']) || id);
  const translated = translations?.[id] || translations?.[databaseId] || {};
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
  const keywordTags = resolveKeywordTags(keywordTagData, [databaseId, id, cardId, cardNum]);
  const traitsSource = firstValue([translated, ...objects], ['traitsKo', 'traits_ko', 'traits', 'trait', 'featureTags', 'feature_tags']);
  const traits = localizeTraits(traitsSource);
  const rarity = String(translated.rarityKo || firstValue(objects, ['rarity', 'rarityJp', 'rare', 'rarity_code', 'rarityCode']));
  const cost = numericValue(firstValue(objects, ['cost', 'costValue', 'cost_value']));
  const lp = numericValue(firstValue(objects, ['lp', 'LP']));
  const ap = numericValue(firstValue(objects, ['ap', 'AP', 'attackPower', 'attack_power', 'power']));
  const roleText = objects.map((object) => firstValue([object], [
    'type', 'typeJp', 'typeKo', 'cardType', 'card_type', 'category1', 'category2', 'category3',
    'category1Ko', 'category2Ko', 'category3Ko', 'cardCategory', 'card_category',
  ])).filter(Boolean).join(' ');

  return {
    key: id,
    databaseId,
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
    ap,
    set: String(translated.setKo || firstValue([card], ['setKo']) || originalSet),
    originalSet,
    ability: String(translated.abilityKo || firstValue([card], ['abilityKo']) || originalAbility),
    originalAbility,
    hiramekiEffect,
    cutInEffect,
    keywordTags,
    traits,
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

function formatDeckCost(value) {
  const parsed = numericValue(value);
  if (parsed === null) return '';
  if (Number.isInteger(parsed) && parsed >= 1 && parsed <= 20) {
    return String.fromCodePoint(0x2460 + parsed - 1);
  }
  return String(parsed);
}

function getDeckCardType(card) {
  const role = getCardRole(card);
  if (role === 'event') return '이벤트';
  if (role === 'partner') return '파트너';
  const type = String(card?.type || card?.originalType || '').trim();
  if (/キャラ|character/i.test(type)) return '캐릭터';
  if (/事件|event/i.test(type)) return '이벤트';
  if (/파트너|パートナー|partner/i.test(type)) return '파트너';
  return type || '카드';
}

function getDeckCardNameLine(card) {
  const cost = formatDeckCost(card?.cost);
  return `${cost ? `${cost} ` : ''}${card?.name || '이름 없음'}`;
}

function getDeckCardStatsLine(card) {
  return `${getDeckCardType(card)} | ${formatNumber(card?.ap ?? card?.lp)}`;
}

function getDeckCardSummary(card) {
  return `${getDeckCardNameLine(card)}\n${getDeckCardStatsLine(card)}`;
}

function loadImageSourceForExport(src, timeoutMs = 8000) {
  return new Promise((resolve) => {
    if (!src) return resolve(null);
    const image = new Image();
    let finished = false;
    const finish = (result) => {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      resolve(result);
    };
    const timeout = setTimeout(() => finish(null), timeoutMs);
    // CORS를 명시해 캔버스에 그려도 저장이 막히지 않는 이미지인지 확인합니다.
    image.crossOrigin = 'anonymous';
    image.onload = () => finish(image.naturalWidth > 0 && image.naturalHeight > 0 ? image : null);
    image.onerror = () => finish(null);
    image.src = src;
  });
}

async function loadImageForExport(src) {
  if (!src) return null;
  // 원본 서버가 CORS를 허용하면 직접 사용하고, 허용하지 않는 경우 CORS 헤더를 제공하는
  // 이미지 프록시를 재시도해 캔버스 내보내기에서 카드 이미지가 빠지는 문제를 줄입니다.
  const directImage = await loadImageSourceForExport(src, 5000);
  if (directImage) return directImage;
  const proxyUrl = `https://wsrv.nl/?url=${encodeURIComponent(src)}&output=png`;
  return loadImageSourceForExport(proxyUrl, 10000);
}

function roundedCanvasRect(ctx, x, y, width, height, radius, fill, stroke = null) {
  const r = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + width, y, x + width, y + height, r);
  ctx.arcTo(x + width, y + height, x, y + height, r);
  ctx.arcTo(x, y + height, x, y, r);
  ctx.arcTo(x, y, x + width, y, r);
  ctx.closePath();
  if (fill) { ctx.fillStyle = fill; ctx.fill(); }
  if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1.5; ctx.stroke(); }
}

function drawWrappedCanvasText(ctx, text, x, y, maxWidth, lineHeight, maxLines = 2) {
  const characters = Array.from(String(text ?? ''));
  const lines = [];
  let line = '';
  for (const char of characters) {
    const candidate = line + char;
    if (line && ctx.measureText(candidate).width > maxWidth) {
      lines.push(line.trimEnd());
      line = char.trimStart();
    } else {
      line = candidate;
    }
  }
  if (line) lines.push(line.trimEnd());
  let visible = lines.slice(0, maxLines);
  if (lines.length > maxLines && visible.length) {
    let last = visible[visible.length - 1];
    while (last && ctx.measureText(`${last}…`).width > maxWidth) last = Array.from(last).slice(0, -1).join('');
    visible[visible.length - 1] = `${last}…`;
  }
  visible.forEach((content, index) => ctx.fillText(content, x, y + index * lineHeight));
  return visible.length;
}

function drawExportCard(ctx, card, image, x, y, width, options = {}) {
  const scale = width / 165;
  const imageHeight = width * 4 / 3;
  const primaryFont = Math.max(12, 14 * scale);
  const secondaryFont = Math.max(10, 11 * scale);
  const captionHeight = Math.max(58, 62 * scale);
  const showStats = options.showStats !== false;
  const centerName = options.centerName === true;
  const height = imageHeight + captionHeight;
  roundedCanvasRect(ctx, x, y, width, height, 10 * scale, '#090f1b', '#344256');
  ctx.save();
  ctx.beginPath();
  ctx.rect(x + 1, y + 1, width - 2, imageHeight - 1);
  ctx.clip();
  ctx.fillStyle = '#0d1524';
  ctx.fillRect(x + 1, y + 1, width - 2, imageHeight - 1);
  if (image && image.naturalWidth && image.naturalHeight) {
    const padding = 4 * scale;
    const fit = Math.min((width - padding * 2) / image.naturalWidth, (imageHeight - padding * 2) / image.naturalHeight);
    const iw = image.naturalWidth * fit;
    const ih = image.naturalHeight * fit;
    ctx.drawImage(image, x + (width - iw) / 2, y + (imageHeight - ih) / 2, iw, ih);
  } else {
    ctx.fillStyle = '#182337';
    ctx.fillRect(x + 8 * scale, y + 8 * scale, width - 16 * scale, imageHeight - 16 * scale);
    ctx.fillStyle = '#fb7185';
    ctx.fillRect(x + 8 * scale, y + 8 * scale, 4 * scale, imageHeight - 16 * scale);
    ctx.fillStyle = '#e2e8f0';
    ctx.textAlign = 'center';
    ctx.font = `700 ${Math.max(11, 13 * scale)}px sans-serif`;
    drawWrappedCanvasText(ctx, card?.name || '이미지 없음', x + width / 2, y + imageHeight / 2, width - 28 * scale, Math.max(16, 18 * scale), 4);
    ctx.textAlign = 'left';
  }
  ctx.restore();
  ctx.fillStyle = '#f1f5f9';
  ctx.font = `750 ${primaryFont}px sans-serif`;
  ctx.textAlign = centerName ? 'center' : 'left';
  const nameX = centerName ? x + width / 2 : x + 8 * scale;
  const nameY = showStats
    ? y + imageHeight + 19 * scale
    : y + imageHeight + captionHeight / 2 + primaryFont * 0.35;
  drawWrappedCanvasText(ctx, getDeckCardNameLine(card), nameX, nameY, width - 16 * scale, primaryFont * 1.25, 2);
  if (showStats) {
    ctx.fillStyle = '#94a3b8';
    ctx.font = `550 ${secondaryFont}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.fillText(getDeckCardStatsLine(card), x + 8 * scale, y + height - 9 * scale);
  }
  ctx.textAlign = 'left';
  return { width, height };
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
    <nav aria-label="카드 목록 페이지" className="card-pagination-nav">
      <div className="pagination-controls">
        <button onClick={() => onChange(Math.max(1, currentPage - 1))} disabled={currentPage === 1} className="pagination-step">‹ 이전</button>
        {items.map((item, index) => typeof item === 'number' ? (
          <button key={item} aria-current={item === currentPage ? 'page' : undefined} onClick={() => onChange(item)} className={`pagination-number${item === currentPage ? ' is-active' : ''}`}>{item}</button>
        ) : <span key={`${item}-${index}`} className="pagination-ellipsis">…</span>)}
        <button onClick={() => onChange(Math.min(totalPages, currentPage + 1))} disabled={currentPage === totalPages} className="pagination-step">다음 ›</button>
      </div>
      <span className="pagination-current">{currentPage} / {totalPages} 페이지</span>
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
  const [deckSort, setDeckSort] = useState('added');
  const [deckLayout, setDeckLayout] = useState('10x4');
  const [deckImageFormat, setDeckImageFormat] = useState('png');
  const [exportingDeckImage, setExportingDeckImage] = useState(false);
  const [partnerId, setPartnerId] = useState(() => localStorage.getItem(PARTNER_STORAGE_KEY) || '');
  const [eventId, setEventId] = useState(() => localStorage.getItem(EVENT_STORAGE_KEY) || '');

  useEffect(() => {
    let cancelled = false;
    async function loadCards() {
      setLoading(true);
      setLoadError('');
      try {
        const [cardResponse, translations, loadedKeywordTagData] = await Promise.all([
          fetch('/cards.json').then((response) => {
            if (!response.ok) throw new Error(`cards.json 응답 오류 (${response.status})`);
            return response.json();
          }),
          fetch('/card-translations.ko.json')
            .then((response) => response.ok ? response.json() : {})
            .catch(() => ({})),
          fetch('/card-keyword-tags.json', { cache: 'no-store' })
            .then((response) => response.ok ? response.json() : { version: 1, cards: {} })
            .catch(() => ({ version: 1, cards: {} })),
        ]);
        const rawCards = getCardArray(cardResponse);
        if (!rawCards.length) throw new Error('cards.json에서 카드 배열을 찾지 못했어요. JSON의 최상위 구조를 확인해 주세요.');
        const normalized = rawCards.map((card) => normalizeCard(card, translations, loadedKeywordTagData)).filter((card) => card.key && card.key !== 'undefined');
        if (!cancelled) {
          setCards(normalized);
        }
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

  // 예전 버전에서 메인 덱에 들어간 사건 카드는 별도 슬롯으로 옮깁니다.
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
  // cards가 로드된 직후 한 번 기존 덱을 새 규칙에 맞춰 정리합니다.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cards]);

  useEffect(() => { setPage(1); }, [searchTerm, colorFilter, typeFilter, rarityFilter, costFilter, lpFilter]);

  const colorOptions = useMemo(() => {
    // 표시 순서가 다른 조합(예: 황흑/흑황)은 하나의 필터 선택지로 합칩니다.
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
        card.hiramekiEffect, card.cutInEffect, ...(card.keywordTags || []),
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
  const sortedDeckCards = [...deckCards].sort((a, b) => {
    if (deckSort === 'cost') {
      const aCost = numericValue(a.cost);
      const bCost = numericValue(b.cost);
      return (aCost === null ? Number.POSITIVE_INFINITY : aCost) - (bCost === null ? Number.POSITIVE_INFINITY : bCost)
        || String(a.name).localeCompare(String(b.name), 'ko', { numeric: true });
    }
    if (deckSort === 'cost-desc') {
      const aCost = numericValue(a.cost);
      const bCost = numericValue(b.cost);
      return (bCost === null ? Number.NEGATIVE_INFINITY : bCost) - (aCost === null ? Number.NEGATIVE_INFINITY : aCost)
        || String(a.name).localeCompare(String(b.name), 'ko', { numeric: true });
    }
    if (deckSort === 'color') {
      const aColor = a.colorKey || normalizeColorKey(a.color) || '';
      const bColor = b.colorKey || normalizeColorKey(b.color) || '';
      const aRank = aColor ? COLOR_ORDER.findIndex((tag) => aColor.includes(tag)) : -1;
      const bRank = bColor ? COLOR_ORDER.findIndex((tag) => bColor.includes(tag)) : -1;
      const normalizedARank = aRank < 0 ? Number.POSITIVE_INFINITY : aRank;
      const normalizedBRank = bRank < 0 ? Number.POSITIVE_INFINITY : bRank;
      return normalizedARank - normalizedBRank
        || aColor.localeCompare(bColor, 'ko', { numeric: true })
        || ((numericValue(a.cost) ?? Number.POSITIVE_INFINITY) - (numericValue(b.cost) ?? Number.POSITIVE_INFINITY))
        || String(a.name).localeCompare(String(b.name), 'ko', { numeric: true });
    }
    if (deckSort === 'ap') {
      const aAp = numericValue(a.ap ?? a.lp);
      const bAp = numericValue(b.ap ?? b.lp);
      return (bAp === null ? Number.NEGATIVE_INFINITY : bAp) - (aAp === null ? Number.NEGATIVE_INFINITY : aAp)
        || String(a.name).localeCompare(String(b.name), 'ko', { numeric: true });
    }
    return deckCards.findIndex((item) => item.deckSlotKey === a.deckSlotKey)
      - deckCards.findIndex((item) => item.deckSlotKey === b.deckSlotKey);
  });
  const deckSlots = Array.from({ length: MAIN_DECK_LIMIT }, (_, index) => sortedDeckCards[index] || null);

  // 모달 열림 상태에서는 배경 스크롤을 막고, Esc/좌우 방향키를 지원합니다.
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
        window.alert(`메인 덱은 ${MAIN_DECK_LIMIT}장까지 넣을 수 있어요. 파트너와 사건 카드는 별도 슬롯이에요.`);
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

  async function exportDeckImage() {
    if (!partnerCard || !eventCard || mainDeckCount !== MAIN_DECK_LIMIT) {
      window.alert(`이미지로 저장하려면 메인 덱 ${MAIN_DECK_LIMIT}장과 파트너 카드 1장, 사건 카드 1장이 필요해요.\n현재 메인 덱: ${mainDeckCount}/${MAIN_DECK_LIMIT}장 · 파트너: ${partnerCard ? '선택됨' : '미선택'} · 사건: ${eventCard ? '선택됨' : '미선택'}`);
      return;
    }
    if (exportingDeckImage) return;
    setExportingDeckImage(true);
    try {
      const slots = deckSlots.filter(Boolean);
      const imageUrls = [...new Set([partnerCard.imageUrl, eventCard.imageUrl, ...slots.map((card) => card.imageUrl)].filter(Boolean))];
      const loadedImages = new Map();
      await Promise.all(imageUrls.map(async (url) => loadedImages.set(url, await loadImageForExport(url))));

      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) throw new Error('이미지 저장용 캔버스를 만들지 못했어요.');
      const canvasWidth = 2050;
      const margin = 50;
      const columns = deckLayout === '8x5' ? 8 : 10;
      const rows = deckLayout === '8x5' ? 5 : 4;
      const gap = deckLayout === '8x5' ? 14 : 12;
      const cardWidth = (canvasWidth - margin * 2 - 24 - (columns - 1) * gap) / (columns + 1);
      const cardHeight = cardWidth * 4 / 3 + Math.max(58, 62 * (cardWidth / 165));
      const headerHeight = 110;
      const sectionHeight = 45;
      const top = margin + headerHeight + 20;
      const gridHeight = rows * cardHeight + (rows - 1) * gap;
      const footerHeight = 58;
      canvas.width = canvasWidth;
      canvas.height = top + sectionHeight + gridHeight + margin + footerHeight;

      ctx.fillStyle = '#080d17';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      // subtle header glow / panel
      roundedCanvasRect(ctx, margin, margin, canvasWidth - margin * 2, headerHeight, 18, '#101827', '#263449');
      ctx.fillStyle = '#fb7185';
      ctx.fillRect(margin + 24, margin + 22, 5, 62);
      ctx.textAlign = 'left';
      ctx.fillStyle = '#f8fafc';
      ctx.font = '850 34px sans-serif';
      ctx.fillText('내 덱 구성', margin + 44, margin + 49);
      ctx.fillStyle = '#a7b4c8';
      ctx.font = '600 16px sans-serif';
      ctx.fillText('명탐정 코난 TCG 도감  ·  메인 덱 40장 + 파트너 + 사건', margin + 44, margin + 77);
      ctx.textAlign = 'right';
      ctx.fillStyle = mainDeckCount === MAIN_DECK_LIMIT ? '#86efac' : '#fda4af';
      ctx.font = '800 22px sans-serif';
      ctx.fillText(`${mainDeckCount} / ${MAIN_DECK_LIMIT}장`, canvasWidth - margin - 24, margin + 48);
      ctx.fillStyle = '#8190a7';
      ctx.font = '500 13px sans-serif';
      ctx.fillText(new Date().toLocaleDateString('ko-KR'), canvasWidth - margin - 24, margin + 75);
      ctx.textAlign = 'left';

      const sideX = margin;
      const gridX = margin + cardWidth + 24;
      const labelY = top + 20;
      ctx.fillStyle = '#e9eff9';
      ctx.font = '800 17px sans-serif';
      ctx.fillText('파트너 · 사건', sideX, labelY);
      ctx.fillStyle = '#8190a7';
      ctx.font = '500 11px sans-serif';
      ctx.fillText('필수 카드 · 각 1장', sideX, labelY + 18);
      ctx.fillStyle = '#e9eff9';
      ctx.font = '800 17px sans-serif';
      ctx.fillText('메인 덱', gridX, labelY);
      ctx.fillStyle = '#8190a7';
      ctx.font = '500 11px sans-serif';
      ctx.fillText(`${columns} × ${rows} 배열 · ${deckSort === 'added' ? '추가한 순서' : deckSort === 'cost' ? '코스트 낮은순' : deckSort === 'cost-desc' ? '코스트 높은순' : deckSort === 'color' ? '색상별' : 'AP 높은순'}`, gridX, labelY + 18);

      const cardStartY = top + sectionHeight;
      drawExportCard(ctx, partnerCard, loadedImages.get(partnerCard.imageUrl), sideX, cardStartY, cardWidth, { showStats: false, centerName: true });
      drawExportCard(ctx, eventCard, loadedImages.get(eventCard.imageUrl), sideX, cardStartY + cardHeight + Math.max(14, gap), cardWidth, { showStats: false, centerName: true });
      slots.forEach((card, index) => {
        const row = Math.floor(index / columns);
        const col = index % columns;
        drawExportCard(ctx, card, loadedImages.get(card.imageUrl), gridX + col * (cardWidth + gap), cardStartY + row * (cardHeight + gap), cardWidth);
      });

      const footerY = cardStartY + gridHeight + 30;
      ctx.fillStyle = '#526176';
      ctx.fillRect(margin, footerY, canvasWidth - margin * 2, 1);
      ctx.fillStyle = '#8190a7';
      ctx.font = '500 12px sans-serif';
      ctx.fillText('Conan TCG Deck · 이 이미지는 현재 화면의 덱 정렬과 배열 설정을 반영합니다.', margin, footerY + 24);
      const mimeType = deckImageFormat === 'jpeg' ? 'image/jpeg' : 'image/png';
      const extension = deckImageFormat === 'jpeg' ? 'jpg' : 'png';
      const blob = await new Promise((resolve, reject) => canvas.toBlob((result) => result ? resolve(result) : reject(new Error('이미지 파일을 생성하지 못했어요.')), mimeType, 0.94));
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `conan-deck.${extension}`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1500);
      if (imageUrls.some((url) => !loadedImages.get(url))) {
        window.alert('이미지 파일은 저장했어요. 일부 카드 이미지는 원본 서버나 이미지 프록시의 접근 제한으로 불러오지 못해 카드명 표시로 대체했어요.');
      }
    } catch (error) {
      window.alert(error instanceof Error ? error.message : '이미지 저장 중 문제가 발생했어요.');
    } finally {
      setExportingDeckImage(false);
    }
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
    return <main className="flex min-h-screen items-center justify-center bg-slate-950 p-8 text-slate-100"><div className="text-center"><div className="mx-auto mb-4 h-10 w-10 animate-spin rounded-full border-2 border-slate-700 border-t-rose-500" /><h1 className="text-xl font-black tracking-tight">명탐정 코난 TCG 도감</h1><p className="mt-2 text-sm text-slate-400">카드 데이터를 불러오는 중이에요…</p></div></main>;
  }
  if (loadError) {
    return <main className="min-h-screen bg-slate-950 p-8 text-slate-100"><h1 className="text-2xl font-bold">카드 데이터를 불러오지 못했어요.</h1><p className="mt-4 text-rose-300">{loadError}</p><p className="mt-3 text-sm text-slate-400">프로젝트의 public/cards.json 파일이 실제로 존재하는지 확인해 주세요.</p></main>;
  }

  return (
    <main className="app-shell min-h-screen bg-[#080d17] p-3 text-slate-100 md:p-5">
      {/* Tailwind 미적용 환경에서도 카드 그리드와 상세 모달의 핵심 레이아웃이 유지되도록 하는 안전장치 */}
      <style>{`
        .conan-card-grid {
          display: grid !important;
          grid-template-columns: repeat(10, minmax(0, 1fr)) !important;
          gap: 8px !important;
          align-items: start;
        }
        .conan-card-grid > article { min-width: 0 !important; width: 100% !important; }
        .conan-card-grid > article > button:first-child { display: block; width: 100%; min-width: 0; padding: 0; text-align: left; }
        .conan-card-grid img { display: block; width: 100% !important; aspect-ratio: 3 / 4; object-fit: contain; }
        .card-detail-overlay {
          position: fixed !important; inset: 0 !important; z-index: 99999 !important;
          display: flex !important; align-items: center !important; justify-content: center !important;
          box-sizing: border-box; width: 100vw; height: 100vh; height: 100dvh;
          padding: 12px !important; background: rgba(0, 0, 0, .82) !important;
          backdrop-filter: blur(6px);
        }
        .card-detail-dialog {
          display: flex !important; flex-direction: column !important;
          width: min(100%, 1024px) !important; max-height: 94vh !important; max-height: 94dvh !important;
          overflow: hidden !important; border: 1px solid rgba(255,255,255,.15);
          border-radius: 16px; background: #111a2a; box-shadow: 0 24px 70px rgba(0,0,0,.65);
        }
        .card-detail-body { min-height: 0 !important; overflow-y: auto !important; padding: 16px; }
        .card-detail-layout { display: grid !important; grid-template-columns: minmax(0, 1fr) !important; gap: 16px !important; }
        .card-detail-layout > div:first-child { min-width: 0; }
        .card-detail-layout > div:first-child > img { display: block; max-width: 220px; max-height: 58vh; width: 100%; height: auto; object-fit: contain; margin: 0 auto; }
        @media (max-width: 1099px) { .conan-card-grid { grid-template-columns: repeat(8, minmax(0, 1fr)) !important; } }
        @media (max-width: 799px) { .conan-card-grid { grid-template-columns: repeat(6, minmax(0, 1fr)) !important; } }
        @media (max-width: 599px) { .conan-card-grid { grid-template-columns: repeat(4, minmax(0, 1fr)) !important; gap: 6px !important; } .card-detail-body { padding: 10px; } }
        @media (max-width: 419px) { .conan-card-grid { grid-template-columns: repeat(3, minmax(0, 1fr)) !important; } }
        @media (min-width: 640px) { .card-detail-layout { grid-template-columns: 220px minmax(0, 1fr) !important; } }

        /* Standalone visual fallback: keeps the intended UI polished even without Tailwind CSS. */
        .app-shell {
          box-sizing: border-box; min-height: 100vh; padding: 16px !important;
          color: #e8edf7 !important; background: #080d17 !important;
          font-family: Inter, Pretendard, "Noto Sans KR", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 14px; line-height: 1.5;
        }
        .app-shell *, .app-shell *::before, .app-shell *::after { box-sizing: border-box; }
        .app-shell button, .app-shell input, .app-shell select { font: inherit; }
        .app-shell button { cursor: pointer; }
        .app-shell button:disabled { cursor: not-allowed; opacity: .4; }
        .app-header {
          display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap;
          gap: 14px; margin: 0 0 20px !important; padding: 0 0 16px !important;
          border-bottom: 1px solid rgba(255,255,255,.1) !important;
        }
        .app-header h1 { margin: 0; color: #f8fafc; font-size: 23px; line-height: 1.25; font-weight: 850; letter-spacing: -.035em; }
        .app-header > div { display: flex; align-items: center; flex-wrap: wrap; gap: 9px; }
        .app-nav { display: flex; gap: 3px; padding: 4px !important; background: #101827 !important; border: 1px solid rgba(255,255,255,.1) !important; border-radius: 12px; }
        .app-shell .app-nav button { border: 0; border-radius: 8px; padding: 8px 14px; color: #aab5c8; background: transparent; font-size: 12px; font-weight: 750; }
        .app-shell .app-nav button:hover { color: white; background: rgba(255,255,255,.06); }
        .app-shell .app-nav button[class*="bg-rose-600"] { color: white; background: #e11d48; }
        .app-header a { display: inline-flex; align-items: center; min-height: 36px; border: 1px solid rgba(255,255,255,.12); border-radius: 9px; padding: 7px 11px; color: #cbd5e1; text-decoration: none; font-size: 12px; font-weight: 650; }
        .app-header a:hover { border-color: rgba(251,113,133,.55); color: white; }
        .app-panel { min-width: 0; padding: 14px !important; border: 1px solid rgba(255,255,255,.09) !important; border-radius: 16px !important; background: #101827 !important; box-shadow: 0 12px 36px rgba(0,0,0,.12); }
        .card-list-toolbar { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; margin: 0 0 14px !important; }
        .card-list-toolbar > div { display: flex; align-items: baseline; gap: 9px; }
        .card-list-toolbar h2, .deck-panel h2 { margin: 0; color: #f1f5f9; font-size: 16px; font-weight: 800; }

        .card-pagination-nav { display: flex !important; flex-direction: column; align-items: center; justify-content: center !important; gap: 9px; width: 100%; margin-top: 22px; padding-top: 17px; border-top: 1px solid rgba(255,255,255,.085); text-align: center; }
        .pagination-controls { display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 6px; width: 100%; }
        .app-shell .pagination-controls .pagination-step, .app-shell .pagination-controls .pagination-number { display: inline-flex; align-items: center; justify-content: center; min-width: 36px; height: 36px; border: 1px solid rgba(148,163,184,.17); border-radius: 10px; padding: 0 11px; color: #cbd5e1; background: #111b2b; font-size: 12px; line-height: 1; font-weight: 750; font-variant-numeric: tabular-nums; transition: border-color .15s ease, color .15s ease, background .15s ease, transform .15s ease; }
        .app-shell .pagination-controls .pagination-number { width: 36px; padding: 0; }
        .app-shell .pagination-controls .pagination-step:hover:not(:disabled), .app-shell .pagination-controls .pagination-number:hover:not(.is-active) { border-color: rgba(251,113,133,.55); color: #fff; background: #1a2639; }
        .app-shell .pagination-controls .pagination-number.is-active { border-color: #fb7185; color: #fff; background: #be123c; box-shadow: 0 5px 15px rgba(190,18,60,.22); }
        .pagination-controls .pagination-step:disabled { opacity: .32; cursor: not-allowed; }
        .pagination-ellipsis { display: inline-flex; align-items: center; justify-content: center; min-width: 16px; height: 34px; color: #64748b; font-size: 13px; }
        .pagination-current { color: #8290a6; font-size: 11px; font-weight: 650; font-variant-numeric: tabular-nums; letter-spacing: .02em; }

        .card-list-toolbar span { color: #9aa8bd; font-size: 12px; }
        .app-shell .app-panel button:not(.card-open-button):not(.card-tile-action) { border-radius: 8px; }
        .app-shell .card-list-toolbar > button { border: 1px solid rgba(255,255,255,.12); padding: 7px 11px; color: #d1d9e6; background: #151f30; font-size: 12px; font-weight: 650; }
        .app-shell .card-list-toolbar > button:hover { border-color: rgba(251,113,133,.45); background: rgba(255,255,255,.04); }
        .app-filters { display: grid !important; grid-template-columns: minmax(200px, 1.7fr) repeat(5, minmax(100px, 1fr)) !important; gap: 8px !important; margin: 0 0 15px !important; }
        .app-control { min-width: 0; width: 100%; height: 37px; padding: 7px 10px !important; border: 1px solid rgba(255,255,255,.11) !important; border-radius: 8px !important; outline: none; background: #090f1b !important; color: #e2e8f0 !important; font-size: 12px !important; }
        .app-control:focus { border-color: rgba(251,113,133,.75) !important; box-shadow: 0 0 0 3px rgba(225,29,72,.12); }
        .app-control::placeholder { color: #718096; }
        .app-control option { color: #e2e8f0; background: #101827; }
        .conan-card-grid {
          grid-template-columns: repeat(11, minmax(0, 1fr)) !important;
          align-items: stretch; gap: 8px !important;
        }
        .card-tile {
          display: flex !important; min-width: 0 !important; width: 100% !important; flex-direction: column !important;
          overflow: hidden !important; border: 1px solid rgba(148,163,184,.13) !important;
          border-radius: 10px !important; background: #090f1b !important;
          box-shadow: 0 2px 5px rgba(0,0,0,.16); transition: transform .16s ease, border-color .16s ease, box-shadow .16s ease;
        }
        .card-tile:hover { transform: translateY(-2px); border-color: rgba(251,113,133,.55) !important; box-shadow: 0 8px 18px rgba(0,0,0,.2); }
        .card-open-button { display: block !important; width: 100% !important; min-width: 0 !important; padding: 0 !important; border: 0 !important; border-radius: 0 !important; background: transparent !important; color: #f1f5f9 !important; text-align: left; }
        .card-image-wrap { position: relative; overflow: hidden; background: #0d1524 !important; }
        .conan-card-grid .card-image-wrap > img { display: block; width: 100% !important; aspect-ratio: 3 / 4 !important; height: auto !important; object-fit: contain !important; }
        .card-id-badge { position: absolute; z-index: 2; top: 5px; left: 5px; max-width: calc(100% - 10px); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; border-radius: 4px; padding: 2px 5px; background: rgba(0,0,0,.78); color: #fff; font-size: 9px; line-height: 1.35; font-weight: 700; }
        .card-count-badge { position: absolute; z-index: 2; top: 5px; right: 5px; border-radius: 5px; padding: 2px 5px; background: #e11d48; color: #fff; font-size: 10px; font-weight: 850; }
        .card-role-badge { position: absolute; z-index: 2; bottom: 5px; left: 5px; border-radius: 4px; padding: 2px 5px; color: #111827; font-size: 9px; font-weight: 850; }
        .card-role-partner { background: #fcd34d; }
        .card-role-event { background: #7dd3fc; }
        .card-tile-caption { min-width: 0; padding: 7px 7px 6px !important; }
        .card-tile-title-row { display: flex !important; align-items: flex-start; justify-content: space-between; gap: 4px; min-width: 0; min-height: 2.35em; margin-top: 0 !important; color: inherit !important; font-size: inherit !important; }
        .card-tile-caption > .card-tile-title-row { margin-top: 0 !important; }
        .card-tile-title { display: -webkit-box; flex: 1 1 auto; min-width: 0; min-height: 2.35em !important; margin: 0; overflow: hidden; -webkit-box-orient: vertical; -webkit-line-clamp: 2; color: #f1f5f9 !important; font-size: 11px !important; font-weight: 750 !important; line-height: 1.4 !important; overflow-wrap: anywhere; }
        .card-tile-caption > div { display: flex; justify-content: space-between; gap: 4px; margin-top: 5px !important; color: #8b9ab0 !important; font-size: 9px !important; }
        .card-tile-caption > div > span { min-width: 0; }
        .card-tile-caption > div > span:last-child { flex-shrink: 0; }
        .card-tile-action { display: block !important; width: 100% !important; margin-top: auto !important; border: 0 !important; border-top: 1px solid rgba(255,255,255,.07) !important; border-radius: 0 !important; padding: 7px 3px !important; background: rgba(255,255,255,.025) !important; color: #bdc8d8 !important; font-size: 10px !important; font-weight: 700 !important; text-align: center; }
        .card-tile-action:hover { background: rgba(225,29,72,.15) !important; color: #fecdd3 !important; }
        .card-tile-action[class*="text-amber"] { background: rgba(252,211,77,.08) !important; color: #fde68a !important; }
        .card-tile-action[class*="text-sky"] { background: rgba(125,211,252,.08) !important; color: #bae6fd !important; }
        .card-detail-dialog { color: #eef2f9 !important; }
        .card-detail-header { flex: 0 0 auto; display: flex; align-items: flex-start; justify-content: space-between; gap: 14px; padding: 15px 16px !important; border-bottom: 1px solid rgba(255,255,255,.09) !important; background: #111a2a; }
        .card-detail-header > div:first-child { min-width: 0; }
        .card-detail-header p { margin: 0 0 5px; color: #fda4af; font-size: 10px; font-weight: 750; letter-spacing: .16em; }
        .card-detail-header h2 { margin: 0; color: #f8fafc; font-size: 21px; line-height: 1.35; font-weight: 850; }
        .card-detail-header p:last-child { margin: 7px 0 0; color: #94a3b8; font-size: 12px; letter-spacing: 0; font-weight: 500; }
        .card-detail-header > div:last-child { display: flex; flex-shrink: 0; align-items: center; gap: 5px; }
        .card-detail-header button { min-width: 34px; height: 34px; padding: 0 10px; border: 1px solid rgba(255,255,255,.1); border-radius: 9px; color: #dbe4f1; background: #1c2739; font-size: 12px; font-weight: 700; }
        .card-detail-header button:hover { background: #29364b; }
        .card-detail-header button:last-child { border-color: #e11d48; color: #fff; background: #e11d48; }
        .card-detail-body { min-height: 0 !important; overflow-y: auto !important; padding: 16px !important; color: #e5eaf3; }
        .card-detail-layout { display: grid !important; grid-template-columns: minmax(0, 1fr) !important; gap: 16px !important; }
        .card-detail-layout > div:first-child { min-width: 0; display: flex; align-items: center; flex-direction: column; gap: 10px !important; }
        .card-detail-layout > div:first-child > img { display: block; max-width: 220px; max-height: 58vh; width: 100%; height: auto; object-fit: contain; margin: 0 auto; border: 1px solid rgba(255,255,255,.06); border-radius: 10px; background: #090f1b; }
        .card-detail-layout > div:first-child > button { display: block; width: 100%; max-width: 240px; min-height: 37px; border: 0; border-radius: 9px; padding: 9px 12px; color: #fff; background: #e11d48; font-size: 12px; font-weight: 750; }
        .card-detail-layout > div:first-child > button:hover { background: #f43f5e; }
        .card-detail-layout > div:first-child > p { margin: 0; color: #8190a7; font-size: 10px; }
        .card-detail-layout > div:nth-child(2) { min-width: 0; display: flex; flex-direction: column; gap: 12px; }
        .card-meta-grid { display: grid !important; grid-template-columns: repeat(2, minmax(0, 1fr)) !important; gap: 8px !important; margin: 0; }
        .card-meta-item { min-width: 0; display: flex; flex-direction: column; border: 1px solid rgba(255,255,255,.075) !important; border-radius: 9px !important; padding: 10px !important; background: #090f1b !important; }
        .card-meta-item dt { color: #9aa8bd !important; font-size: 11px !important; font-weight: 600 !important; }
        .card-meta-item dd { display: flex; flex: 1 1 auto; align-items: center; min-height: 20px; margin: 4px 0 0 !important; color: #f1f5f9 !important; font-size: 13px !important; font-weight: 650 !important; overflow-wrap: anywhere; }
        .card-meta-item:not(.card-meta-item-traits) dd { justify-content: flex-start !important; text-align: left !important; padding-left: 8px !important; box-sizing: border-box !important; }
        .card-detail-layout > div:nth-child(2) > div:not(.card-meta-grid), .card-detail-layout > div:nth-child(2) > details { border: 1px solid rgba(255,255,255,.07) !important; border-radius: 10px !important; padding: 12px !important; background: #090f1b !important; color: #e2e8f0 !important; }
        .card-detail-layout > div:nth-child(2) h3 { margin: 0 0 8px !important; color: #dce5f2 !important; font-size: 13px !important; font-weight: 800 !important; }
        .card-detail-layout > div:nth-child(2) h4 { margin: 0 0 4px !important; color: #fcd34d; font-size: 12px; font-weight: 750; }
        .card-detail-layout > div:nth-child(2) p { margin: 0; color: #d4dceb !important; font-size: 12px !important; line-height: 1.75 !important; overflow-wrap: anywhere; }
        .card-effect-text, .card-original-effect-text { white-space: pre-wrap !important; overflow-wrap: anywhere !important; word-break: normal; }
        .detail-keyword-badges { margin: 0 0 2px !important; }
        .card-detail-layout > div:nth-child(2) summary { color: #d1d9e6; cursor: pointer; font-size: 12px; font-weight: 650; }
        .card-detail-layout > div:nth-child(2) details > div { margin-top: 10px; display: grid; gap: 10px; }
        .effect-badges { display: flex !important; flex-wrap: wrap !important; gap: 4px !important; margin-top: 6px !important; }
        .effect-badge { display: inline-flex; align-items: center; border: 1px solid transparent; border-radius: 4px; padding: 2px 5px; font-size: 8px; line-height: 1.35; font-weight: 800; white-space: nowrap; }
        .effect-badge-hirameki { color: #fcd34d; background: rgba(251,191,36,.11); border-color: rgba(251,191,36,.18); }
        .effect-badge-cutin { color: #7dd3fc; background: rgba(56,189,248,.11); border-color: rgba(56,189,248,.18); }
        .keyword-assault { color: #fda4af; background: rgba(244,63,94,.12); border-color: rgba(251,113,133,.22); }
        .keyword-swift { color: #86efac; background: rgba(34,197,94,.12); border-color: rgba(74,222,128,.22); }
        .keyword-gale { color: #7dd3fc; background: rgba(14,165,233,.12); border-color: rgba(56,189,248,.22); }
        .effect-badge.conditional { border-style: solid; opacity: .95; }
        .keyword-other { color: #c4b5fd; background: rgba(139,92,246,.12); border-color: rgba(167,139,250,.22); }
        .detail-keyword-badges { padding: 2px 0; }
        .detail-keyword-badges .effect-badge { font-size: 11px !important; line-height: 1.4; padding: 3px 6px; font-weight: 700; }
        .keyword-tag-dots { display: flex; align-items: center; justify-content: flex-end; flex: 0 0 auto; flex-wrap: nowrap; gap: 3px; max-width: 38%; min-height: 0; margin: 3px 0 0; overflow: hidden; }
        .keyword-tag-dot { display: inline-block; width: 6px; height: 6px; flex: 0 0 6px; border-radius: 999px; box-shadow: 0 0 0 1px rgba(255,255,255,.18); }
        .keyword-dot-assault { background: #fb7185; }
        .keyword-dot-swift { background: #4ade80; }
        .keyword-dot-gale { background: #38bdf8; }
        .keyword-dot-other { background: #a78bfa; }
        .card-meta-item-traits { grid-column: 1 / -1; }
        .card-trait-list { display: flex; flex-wrap: wrap; gap: 5px; }
        .card-trait-chip { display: inline-flex; align-items: center; border: 1px solid rgba(148,163,184,.18); border-radius: 5px; background: rgba(148,163,184,.08); padding: 3px 6px; color: #dbe5f2; font-size: 11px; font-weight: 650; line-height: 1.4; }
        .deck-image-export-format { min-height: 36px; max-width: 88px; border: 1px solid #303b4d; border-radius: 9px; background: #111827; color: #e2e8f0; padding: 7px 9px; font-size: 12px; font-weight: 700; }
        .deck-board-scroll { width: 100%; overflow-x: auto; padding-bottom: 5px; }
        /* 왼쪽 특수 카드 폭은 오른쪽 10열 중 각 슬롯 폭과 맞춥니다. */
        .deck-board { display: grid !important; grid-template-columns: minmax(64px, calc((100% - 80px) / 11)) minmax(0, 1fr) !important; gap: 12px !important; min-width: 1000px; align-items: start; }
        .deck-board.deck-board-8x5 { grid-template-columns: minmax(90px, calc((100% - 66px) / 9)) minmax(0, 1fr) !important; }
        .deck-specials-column { grid-column: 1; min-width: 0; display: grid !important; grid-template-columns: minmax(0, 1fr) !important; gap: 6px !important; align-content: start; }
        .deck-main-column { grid-column: 2; min-width: 0; }
        .deck-board-heading { min-width: 0; min-height: 38px; display: flex; align-items: center; justify-content: space-between; gap: 5px; border-bottom: 1px solid rgba(255,255,255,.09); padding: 0 1px 7px; }
        .deck-board-heading strong { color: #e9eff9; font-size: 12px; font-weight: 800; line-height: 1.25; }
        .deck-board-heading small { display: block; margin-top: 2px; color: #8190a7; font-size: 9px; line-height: 1.35; }
        .deck-main-heading { margin-bottom: 6px; }
        .deck-special-heading { margin-bottom: 0; }
        .deck-special-heading small { max-width: 100%; }
        .deck-special-heading-copy { min-width: 0; }
        .deck-slot-status { display: inline-block; max-width: 100%; color: #9aa8bd; font-size: 8px; line-height: 1.25; overflow-wrap: anywhere; }
        .deck-slot-status.is-selected { color: #86efac; }
        .deck-slots-frame { border: 1px solid rgba(148,163,184,.23); border-radius: 12px; padding: 6px; background: rgba(4,9,18,.48); box-shadow: inset 0 1px 0 rgba(255,255,255,.025); }
        .deck-slots-grid { display: grid !important; grid-template-columns: repeat(10, minmax(0, 1fr)) !important; gap: 6px !important; align-content: start; }
        .deck-board-8x5 .deck-slots-grid { grid-template-columns: repeat(8, minmax(0, 1fr)) !important; }
        .deck-card-slot, .deck-special-card, .deck-empty-special { min-width: 0; width: 100%; overflow: hidden; position: relative; border: 1px solid rgba(148,163,184,.15); border-radius: 8px; background: #090f1b; }
        .deck-card-open, .deck-special-open { display: block !important; position: relative; width: 100% !important; min-width: 0; padding: 0 !important; border: 0 !important; border-radius: 0 !important; background: transparent !important; color: #e2e8f0 !important; text-align: left; }
        .deck-card-image, .deck-special-image, .deck-empty-special-image { display: block; width: 100% !important; height: auto !important; aspect-ratio: 3 / 4 !important; object-fit: contain !important; background: #0d1524; }
        .deck-card-name, .deck-special-name { display: -webkit-box; min-height: 2.5em; margin: 0; padding: 5px 4px 4px; overflow: hidden; -webkit-box-orient: vertical; -webkit-line-clamp: 2; color: #cbd5e1; font-size: 9px; line-height: 1.25; overflow-wrap: anywhere; }
        .deck-card-remove, .deck-special-remove { position: absolute; z-index: 3; top: 4px; right: 4px; display: flex !important; width: 19px !important; height: 19px !important; align-items: center; justify-content: center; padding: 0 !important; border: 1px solid rgba(255,255,255,.18) !important; border-radius: 50% !important; color: white !important; background: rgba(0,0,0,.82) !important; font-size: 14px !important; line-height: 1 !important; font-weight: 800 !important; }
        .deck-card-remove:hover, .deck-special-remove:hover { background: #e11d48 !important; }
        .deck-empty-slot { display: flex; min-width: 0; flex-direction: column; overflow: hidden; border: 1px solid rgba(148,163,184,.16); border-radius: 8px; background: rgba(255,255,255,.012); }
        .deck-empty-slot .deck-card-image { display: flex !important; align-items: center !important; justify-content: center !important; box-sizing: border-box !important; padding: 12px !important; color: #64748b !important; font-size: 13px !important; line-height: 1 !important; text-align: center !important; }
        .deck-empty-slot .deck-card-name { color: #64748b; }
        .deck-empty-special { border-style: solid; border-color: rgba(148,163,184,.24); background: rgba(255,255,255,.015); }
        .deck-empty-special-image { display: flex; align-items: center; justify-content: center; padding: 5px; color: #64748b; font-size: 10px; text-align: center; }
        .deck-empty-special .deck-special-name { color: #8b9ab0; text-align: center; }
        .deck-special-card { align-self: start; }
        .deck-special-card .deck-special-name { min-height: 2.4em; color: #f1f5f9; font-size: 10px; font-weight: 800; line-height: 1.35; }
        .deck-special-id { position: absolute; z-index: 2; top: 4px; right: 4px; display: block; max-width: calc(100% - 48px); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; border-radius: 4px; padding: 2px 4px; color: #e2e8f0; background: rgba(0,0,0,.8); font-size: 8px; line-height: 1.35; }
        .deck-special-role { position: absolute; z-index: 3; top: 4px; left: 4px; display: inline-block; border-radius: 4px; padding: 2px 4px; color: #0f172a; background: #fcd34d; font-size: 8px; line-height: 1.35; font-weight: 850; }
        .deck-special-role.is-event { background: #7dd3fc; }
        .deck-empty-hint { margin: 8px 0 0 !important; color: #8190a7 !important; font-size: 11px !important; }
        .deck-footnote { margin-top: 12px !important; }
        .deck-topbar { display: flex; align-items: flex-end; justify-content: space-between; flex-wrap: wrap; gap: 12px; margin: 0 0 16px !important; }
        .deck-topbar-info { display: block; min-width: 0; }
        .deck-heading-copy { min-width: 0; }
        .deck-title-row { display: flex; align-items: center; flex-wrap: wrap; gap: 10px; }
        .deck-title-row h2 { margin: 0; }
        .deck-title-row .deck-count-pill { padding: 5px 9px; font-size: 11px; }
        .deck-count-pill { display: inline-flex; flex-shrink: 0; align-items: center; justify-content: center; border: 1px solid rgba(251,113,133,.2); border-radius: 9px; padding: 7px 11px; color: #fecdd3; background: rgba(225,29,72,.11); font-size: 12px; line-height: 1.2; font-weight: 850; font-variant-numeric: tabular-nums; }
        .deck-action-buttons { display: flex; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: 8px; margin-left: auto; }
        .app-shell .deck-action-buttons .deck-reset-button { min-height: 36px; border: 1px solid #be123c !important; border-radius: 9px !important; padding: 8px 13px !important; color: #fff1f2 !important; background: #be123c !important; box-shadow: 0 5px 15px rgba(190,18,60,.15); font-size: 12px !important; font-weight: 800 !important; }
        .app-shell .deck-action-buttons .deck-reset-button:hover { border-color: #f43f5e !important; background: #e11d48 !important; }
        .app-shell .deck-action-buttons .deck-export-button { min-height: 36px; border: 1px solid #3f4858 !important; border-radius: 9px !important; padding: 8px 13px !important; color: #f8fafc !important; background: #05070b !important; box-shadow: inset 0 1px 0 rgba(255,255,255,.05); font-size: 12px !important; font-weight: 800 !important; }
        .app-shell .deck-action-buttons .deck-export-button:hover { border-color: #64748b !important; background: #171c26 !important; }
        .app-shell .deck-action-buttons .deck-export-button:disabled { cursor: wait; opacity: .65; }
        .deck-main-heading { align-items: center; }
        .deck-sort-tools { display: flex; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: 7px; min-width: 0; }
        .deck-sort-tools label { color: #94a3b8; font-size: 10px; white-space: nowrap; }
        .deck-sort-select, .deck-layout-select { max-width: 145px; min-width: 100px; height: 30px; border: 1px solid rgba(255,255,255,.13); border-radius: 7px; padding: 4px 7px; color: #e2e8f0; background: #090f1b; font-size: 10px; outline: none; }
        .deck-layout-select { min-width: 84px; max-width: 94px; }
        .deck-sort-select:focus, .deck-layout-select:focus { border-color: rgba(251,113,133,.7); }
        .app-shell .filters-reset-button { min-height: 30px; border: 1px solid #be123c !important; border-radius: 8px !important; padding: 6px 11px !important; color: #fff1f2 !important; background: #be123c !important; font-size: 11px !important; font-weight: 800 !important; transition: background .15s ease, border-color .15s ease; }
        .app-shell .filters-reset-button:hover { border-color: #f43f5e !important; background: #e11d48 !important; }
        .deck-board-8x5 .deck-card-name { min-height: 3.8em; font-size: 11px; line-height: 1.4; }
        .deck-board-8x5 .deck-special-card .deck-special-name { min-height: 2.4em; font-size: 11px; line-height: 1.4; }
        .deck-card-name, .deck-special-name { display: flex; flex-direction: column; gap: 2px; min-height: 3.5em; margin: 0; padding: 5px 4px 4px; overflow: hidden; color: #cbd5e1; font-size: 9px; line-height: 1.4; overflow-wrap: anywhere; word-break: normal; }
        .deck-card-primary { display: block; color: #f1f5f9; font-weight: 750; overflow-wrap: anywhere; }
        .deck-card-secondary { display: block; color: #94a3b8; font-size: .92em; font-weight: 550; line-height: 1.3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .deck-empty-slot .deck-card-name { color: #64748b; }
        .deck-special-name { align-items: center; text-align: center; }
        .deck-special-name .deck-card-primary { width: 100%; text-align: center; }
        @media (max-width: 600px) {
          .deck-board { min-width: 1000px; gap: 12px !important; }
          .deck-slots-grid, .deck-specials-column { gap: 6px !important; }
          .deck-board-heading strong { font-size: 11px; }
          .deck-board-heading small, .deck-slot-status { font-size: 8px; }
        }
        .deck-panel h2, .deck-panel h3 { color: #f1f5f9; }
        .deck-panel h3 { font-size: 13px; font-weight: 750; }
        .deck-panel article, .deck-panel aside section { border-radius: 9px; }
        .deck-panel p { line-height: 1.65; }
        .deck-panel img { display: block; object-fit: contain; }
        @media (max-width: 1100px) {
          .conan-card-grid { grid-template-columns: repeat(9, minmax(0, 1fr)) !important; }
          .app-filters { grid-template-columns: repeat(3, minmax(0, 1fr)) !important; }
          .app-search-control { grid-column: span 2; }
        }
        @media (max-width: 800px) {
          .app-shell { padding: 12px !important; }
          .conan-card-grid { grid-template-columns: repeat(7, minmax(0, 1fr)) !important; }
          .card-detail-header h2 { font-size: 18px; }
          .card-detail-layout { grid-template-columns: minmax(0, 1fr) !important; }
          .card-detail-layout > div:first-child > img { max-width: 185px; max-height: 34vh; }
        }
        @media (max-width: 600px) {
          .app-shell { padding: 9px !important; }
          .app-header h1 { font-size: 20px; }
          .app-panel { padding: 10px !important; border-radius: 12px !important; }
          .conan-card-grid { grid-template-columns: repeat(5, minmax(0, 1fr)) !important; gap: 6px !important; }
          .app-filters { grid-template-columns: repeat(2, minmax(0, 1fr)) !important; }
          .app-search-control { grid-column: span 2; }
          .card-tile-caption { padding: 5px !important; }
          .card-tile-title { font-size: 10px !important; }
          .card-detail-overlay { padding: 8px !important; }
          .card-detail-header { padding: 12px !important; }
          .card-detail-body { padding: 10px !important; }
          .card-meta-grid { grid-template-columns: repeat(2, minmax(0, 1fr)) !important; }
        }
        @media (max-width: 420px) {
          .conan-card-grid { grid-template-columns: repeat(4, minmax(0, 1fr)) !important; }
          .card-detail-header { gap: 8px; }
          .card-detail-header button { min-width: 29px; height: 31px; padding: 0 7px; }
        }
        @media (min-width: 801px) {
          .card-detail-layout { grid-template-columns: 220px minmax(0, 1fr) !important; }
          .card-meta-grid { grid-template-columns: repeat(3, minmax(0, 1fr)) !important; }
        }
      `}</style>
      <header className="app-header mb-5 flex flex-wrap items-center justify-between gap-3 border-b border-white/10 pb-4">
        <h1 className="text-xl font-black tracking-tight md:text-2xl">명탐정 코난 TCG 도감</h1>
        <div className="flex flex-wrap items-center gap-2">
          <nav aria-label="메인 메뉴" className="app-nav flex rounded-xl border border-white/10 bg-[#101827] p-1">
            <button onClick={() => setActiveView('cards')} className={`rounded-lg px-3 py-2 text-xs font-bold transition sm:px-4 ${activeView === 'cards' ? 'bg-rose-600 text-white shadow' : 'text-slate-400 hover:text-white'}`}>카드 목록</button>
            <button onClick={() => setActiveView('deck')} className={`rounded-lg px-3 py-2 text-xs font-bold transition sm:px-4 ${activeView === 'deck' ? 'bg-rose-600 text-white shadow' : 'text-slate-400 hover:text-white'}`}>내 덱 구성</button>
          </nav>
          <a className="rounded-lg border border-white/10 px-3 py-2 text-xs font-semibold text-slate-300 transition hover:border-rose-400/50 hover:text-white" href="https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/" target="_blank" rel="noreferrer">일본 공식 카드 목록 ↗</a>
        </div>
      </header>

      {activeView === 'cards' ? (
        <section id="card-list-top" className="app-panel card-list-panel min-w-0 rounded-2xl border border-white/10 bg-[#101827] p-3 md:p-4">
          <div className="card-list-toolbar mb-3 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-baseline gap-2"><h2 className="text-base font-bold">카드 목록</h2><span className="text-xs tabular-nums text-slate-400">검색 결과 {filteredCards.length.toLocaleString()}장</span></div>
            <div className="flex flex-wrap items-center gap-2"><button onClick={clearFilters} className="filters-reset-button">필터 초기화</button></div>
          </div>

          <div className="app-filters mb-4 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
            <input value={searchTerm} onChange={(event) => setSearchTerm(event.target.value)} placeholder="이름 · 효과 · 카드 ID" aria-label="카드 검색" className="app-control app-search-control min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-3 py-2 text-sm outline-none transition placeholder:text-slate-600 focus:border-rose-400/70" />
            <select aria-label="색상 필터" value={colorFilter} onChange={(event) => setColorFilter(event.target.value)} className="app-control min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 색상</option>{colorOptions.map(({ value, label }) => <option key={value} value={value}>{label}</option>)}</select>
            <select aria-label="종류 필터" value={typeFilter} onChange={(event) => setTypeFilter(event.target.value)} className="app-control min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 종류</option>{typeOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select aria-label="레어도 필터" value={rarityFilter} onChange={(event) => setRarityFilter(event.target.value)} className="app-control min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 레어도</option>{rarityOptions.map((value) => <option key={value} value={value}>{value}</option>)}</select>
            <select aria-label="코스트 필터" value={costFilter} onChange={(event) => setCostFilter(event.target.value)} className="app-control min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 코스트</option>{costOptions.map((value) => <option key={String(value)} value={String(value)}>{value}</option>)}</select>
            <select aria-label="LP 필터" value={lpFilter} onChange={(event) => setLpFilter(event.target.value)} className="app-control min-w-0 rounded-lg border border-white/10 bg-[#090f1b] px-2 py-2 text-xs outline-none focus:border-rose-400/70"><option value="">모든 LP</option>{lpOptions.map((value) => <option key={String(value)} value={String(value)}>{value}</option>)}</select>
          </div>

          {visibleCards.length === 0 ? <p className="rounded-xl border border-solid border-white/15 p-8 text-center text-sm text-slate-400">조건에 맞는 카드가 없어요.</p> : (
            <div className="conan-card-grid grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-7 xl:grid-cols-8 2xl:grid-cols-10">
              {visibleCards.map((card) => {
                const count = Number(deck[card.key] || 0);
                const isPartner = partnerId === card.key;
                const isEvent = eventId === card.key;
                const role = getCardRole(card);
                const keywordBadges = card.keywordTags || [];
                return (
                  <article key={card.key} className="card-tile group flex min-w-0 flex-col overflow-hidden rounded-lg border border-white/[0.08] bg-[#090f1b] transition duration-150 hover:-translate-y-0.5 hover:border-rose-400/50 hover:shadow-lg hover:shadow-black/20">
                    <button onClick={() => setSelectedCard(card)} className="card-open-button block w-full min-w-0 text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-rose-400" title={`${card.name} 상세 정보 보기`} aria-label={`${card.name} 상세 정보 보기`}>
                      <div className="card-image-wrap relative overflow-hidden bg-[#0d1524]">
                        {card.imageUrl ? <img loading="lazy" decoding="async" src={card.imageUrl} alt={card.name} className="aspect-[3/4] w-full object-contain transition duration-200 group-hover:scale-[1.025]" /> : <div className="flex aspect-[3/4] items-center justify-center p-2 text-center text-[10px] text-slate-500">이미지 없음</div>}
                        <div className="card-id-badge absolute left-1 top-1 max-w-[calc(100%-8px)] truncate rounded bg-black/75 px-1.5 py-0.5 text-[9px] font-semibold text-white backdrop-blur">{card.cardId || card.cardNum || card.databaseId}</div>
                        {count > 0 && <span className="card-count-badge absolute right-1 top-1 rounded-md bg-rose-600 px-1.5 py-0.5 text-[10px] font-black text-white shadow">×{count}</span>}
                        {isPartner && <span className="card-role-badge card-role-partner absolute bottom-1 left-1 rounded bg-amber-300 px-1.5 py-0.5 text-[9px] font-black text-slate-950">파트너</span>}
                        {isEvent && <span className="card-role-badge card-role-event absolute bottom-1 left-1 rounded bg-sky-300 px-1.5 py-0.5 text-[9px] font-black text-slate-950">사건</span>}
                      </div>
                      <div className="card-tile-caption p-1.5 sm:p-2">
                        <div className="card-tile-title-row">
                          <h3 className="card-tile-title line-clamp-2 min-h-[2.2rem] break-keep text-[11px] font-semibold leading-[1.1rem] text-slate-100 sm:text-xs">{card.name}</h3>
                          {keywordBadges.length > 0 && <div className="keyword-tag-dots" aria-label={`키워드 태그: ${keywordBadges.join(', ')}`}>{keywordBadges.map((tag) => <span key={tag} className={`keyword-tag-dot keyword-dot-${keywordTagClass(tag).replace('keyword-', '')}`} title={tag} aria-label={tag} />)}</div>}
                        </div>
                        <div className="mt-1 flex min-w-0 items-center justify-between gap-1 text-[9px] text-slate-500 sm:text-[10px]"><span className="truncate">{card.rarity || card.type || '카드'}</span><span className="shrink-0">{card.cost === null || card.cost === undefined ? formatNumber(card.lp) : `${formatNumber(card.cost)} / ${formatNumber(card.lp)}`}</span></div>
                        {(card.hiramekiEffect || card.cutInEffect) && <div className="effect-badges">{card.hiramekiEffect && <span className="effect-badge effect-badge-hirameki">히라메키</span>}{card.cutInEffect && <span className="effect-badge effect-badge-cutin">컷인</span>}</div>}
                      </div>
                    </button>
                    <button onClick={() => addCard(card)} aria-label={role === 'partner' ? `${card.name} 파트너 지정` : role === 'event' ? `${card.name} 사건 카드 지정` : `${card.name} 덱에 추가`} className={`card-tile-action mt-auto border-t border-white/[0.07] px-1 py-1.5 text-[10px] font-semibold transition sm:text-[11px] ${role === 'partner' ? 'bg-amber-300/10 text-amber-200 hover:bg-amber-300/20' : role === 'event' ? 'bg-sky-300/10 text-sky-200 hover:bg-sky-300/20' : 'bg-white/[0.025] text-slate-400 hover:bg-rose-500/10 hover:text-rose-200'}`}>
                      {role === 'partner' ? (isPartner ? '✓ 파트너 선택됨' : '+ 파트너 지정') : role === 'event' ? (isEvent ? '✓ 사건 선택됨' : '+ 사건 지정') : (count > 0 ? `덱에 추가 + (${count})` : '덱에 추가 +')}
                    </button>
                  </article>
                );
              })}
            </div>
          )}
          <Pagination currentPage={currentPage} totalPages={totalPages} onChange={goToPage} />
        </section>
      ) : (
        <section className="app-panel deck-panel min-w-0 rounded-2xl border border-white/10 bg-[#101827] p-3 md:p-4">
          <div className="deck-topbar">
            <div className="deck-topbar-info">
              <div className="deck-heading-copy">
                <div className="deck-title-row"><h2 className="text-base font-bold">내 덱 구성</h2><span className="deck-count-pill">{mainDeckCount} / {MAIN_DECK_LIMIT}장</span></div>
                <p className="mt-1 text-xs text-slate-400">메인 덱 최대 40장 · 같은 카드 최대 3장 · 파트너와 사건 카드는 별도 슬롯</p>
              </div>
            </div>
            <div className="deck-action-buttons">
              <button onClick={clearDeck} className="deck-reset-button">덱 초기화</button>
              <select className="deck-image-export-format" value={deckImageFormat} onChange={(event) => setDeckImageFormat(event.target.value)} aria-label="이미지 파일 형식"><option value="png">PNG</option><option value="jpeg">JPG</option></select>
              <button onClick={exportDeckImage} disabled={exportingDeckImage} className="deck-export-button">{exportingDeckImage ? '이미지 생성 중…' : '이미지 저장'}</button>
            </div>
          </div>

          <div className="deck-board-scroll">
            <div className={`deck-board ${deckLayout === '8x5' ? 'deck-board-8x5' : 'deck-board-10x4'}`}>
              <aside className="deck-specials-column" aria-label="파트너와 사건 카드">
                <div className="deck-board-heading deck-special-heading">
                  <div className="deck-special-heading-copy"><strong>파트너 · 사건</strong><small>필수 카드 · 각 1장</small></div>
                </div>
                {partnerCard ? (
                  <article className="deck-special-card">
                    <span className="deck-special-role">파트너</span>
                    <button onClick={() => setSelectedCard(partnerCard)} className="deck-special-open" title={getDeckCardSummary(partnerCard)}>
                      {partnerCard.imageUrl ? <img src={partnerCard.imageUrl} loading="lazy" alt={partnerCard.name} className="deck-special-image" /> : <div className="deck-special-image flex items-center justify-center text-[9px] text-slate-500">이미지 없음</div>}
                      <div className="deck-special-name"><span className="deck-card-primary">{getDeckCardNameLine(partnerCard)}</span></div>
                      <span className="deck-special-id">{partnerCard.cardId || partnerCard.cardNum || '파트너 카드'}</span>
                    </button>
                    <button onClick={() => setPartnerId('')} aria-label="파트너 카드 해제" title="파트너 해제" className="deck-special-remove">×</button>
                  </article>
                ) : (
                  <div className="deck-empty-special">
                    <span className="deck-special-role">파트너</span>
                    <div className="deck-empty-special-image">미선택</div>
                    <div className="deck-special-name">카드 목록에서 지정</div>
                  </div>
                )}

                {eventCard ? (
                  <article className="deck-special-card">
                    <span className="deck-special-role is-event">사건</span>
                    <button onClick={() => setSelectedCard(eventCard)} className="deck-special-open" title={getDeckCardSummary(eventCard)}>
                      {eventCard.imageUrl ? <img src={eventCard.imageUrl} loading="lazy" alt={eventCard.name} className="deck-special-image" /> : <div className="deck-special-image flex items-center justify-center text-[9px] text-slate-500">이미지 없음</div>}
                      <div className="deck-special-name"><span className="deck-card-primary">{getDeckCardNameLine(eventCard)}</span></div>
                      <span className="deck-special-id">{eventCard.cardId || eventCard.cardNum || '사건 카드'}</span>
                    </button>
                    <button onClick={() => setEventId('')} aria-label="사건 카드 해제" title="사건 카드 해제" className="deck-special-remove">×</button>
                  </article>
                ) : (
                  <div className="deck-empty-special">
                    <span className="deck-special-role is-event">사건</span>
                    <div className="deck-empty-special-image">미선택</div>
                    <div className="deck-special-name">카드 목록에서 지정</div>
                  </div>
                )}
              </aside>

              <div className="deck-main-column">
                <div className="deck-board-heading deck-main-heading">
                  <div><strong>메인 덱</strong><small>40칸 · 같은 카드 최대 3장</small></div>
                  <div className="deck-sort-tools">
                    <label htmlFor="deck-sort-select">정렬</label>
                    <select id="deck-sort-select" className="deck-sort-select" value={deckSort} onChange={(event) => setDeckSort(event.target.value)} aria-label="덱 정렬 기준">
                      <option value="added">추가한 순서</option>
                      <option value="cost">코스트 낮은순</option>
                      <option value="cost-desc">코스트 높은순</option>
                      <option value="color">색상별</option>
                      <option value="ap">AP 높은순</option>
                    </select>
                    <label htmlFor="deck-layout-select">배열</label>
                    <select id="deck-layout-select" className="deck-layout-select" value={deckLayout} onChange={(event) => setDeckLayout(event.target.value)} aria-label="덱 카드 배열">
                      <option value="10x4">10 × 4</option>
                      <option value="8x5">8 × 5</option>
                    </select>
                  </div>
                </div>
                <div className="deck-slots-frame">
                  <div className="deck-slots-grid">
                  {deckSlots.map((card, index) => card ? (
                    <article key={card.deckSlotKey} className="deck-card-slot">
                      <button onClick={() => setSelectedCard(card)} className="deck-card-open" title={getDeckCardSummary(card)}>
                        {card.imageUrl ? <img src={card.imageUrl} loading="lazy" alt={card.name} className="deck-card-image" /> : <div className="deck-card-image flex items-center justify-center text-[9px] text-slate-500">이미지 없음</div>}
                        <div className="deck-card-name"><span className="deck-card-primary">{getDeckCardNameLine(card)}</span><span className="deck-card-secondary">{getDeckCardStatsLine(card)}</span></div>
                      </button>
                      <button onClick={() => removeCard(card.key)} aria-label={`${card.name} 한 장 제거`} title="한 장 제거" className="deck-card-remove">−</button>
                    </article>
                  ) : (
                    <div key={`empty-${index}`} className="deck-empty-slot">
                      <div className="deck-card-image flex items-center justify-center text-xs text-slate-700">{index + 1}</div>
                      <div className="deck-card-name">빈 슬롯</div>
                    </div>
                  ))}
                  </div>
                </div>
                {mainDeckCount === 0 && <p className="deck-empty-hint">카드를 추가하려면 ‘카드 목록’ 탭으로 이동해 원하는 카드에서 ‘덱에 추가’를 눌러 주세요.</p>}
              </div>
            </div>
          </div>
          <p className="deck-footnote border-t border-white/[0.08] pt-3 text-[11px] leading-5 text-slate-500">덱 구성은 이 브라우저에 자동 저장돼요. 덱 이미지를 저장하려면 메인 덱 40장과 파트너 카드 1장, 사건 카드 1장을 모두 선택해야 해요.</p>
        </section>
      )}

      {selectedCard && (
        <div className="card-detail-overlay fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-2 backdrop-blur-sm sm:p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedCard(null); }}>
          <section role="dialog" aria-modal="true" aria-label={`${selectedCard.name} 상세 정보`} className="card-detail-dialog flex max-h-[94dvh] w-full max-w-5xl flex-col overflow-hidden rounded-2xl border border-white/15 bg-[#111a2a] shadow-2xl shadow-black/60">
            <div className="card-detail-header flex shrink-0 items-start justify-between gap-3 border-b border-white/10 px-4 py-3 sm:px-5">
              <div className="min-w-0"><p className="mb-1 text-[10px] font-bold tracking-[0.18em] text-rose-300">CARD DETAIL</p><h2 className="break-keep text-lg font-black sm:text-xl">{selectedCard.name}</h2><p className="mt-1 text-[11px] text-slate-500">{selectedCard.cardId || '-'} {selectedCard.cardNum ? `· ${selectedCard.cardNum}` : ''}</p></div>
              <div className="flex shrink-0 items-center gap-1.5"><button onClick={() => moveSelectedCard(-1)} disabled={filteredCards.length < 2} aria-label="이전 카드" title="이전 카드 (←)" className="h-9 w-9 rounded-lg border border-white/10 text-lg text-slate-300 transition hover:bg-white/10 disabled:opacity-30">‹</button><button onClick={() => moveSelectedCard(1)} disabled={filteredCards.length < 2} aria-label="다음 카드" title="다음 카드 (→)" className="h-9 w-9 rounded-lg border border-white/10 text-lg text-slate-300 transition hover:bg-white/10 disabled:opacity-30">›</button><button onClick={() => setSelectedCard(null)} aria-label="상세 창 닫기" title="닫기 (Esc)" className="ml-1 h-9 rounded-lg bg-rose-600 px-3 text-xs font-bold text-white transition hover:bg-rose-500">닫기 ✕</button></div>
            </div>
            <div className="card-detail-body min-h-0 overflow-y-auto p-3 sm:p-5">
              <div className="card-detail-layout grid grid-cols-1 gap-4 sm:grid-cols-[220px_minmax(0,1fr)] sm:gap-5">
                <div className="flex flex-col items-center gap-3 sm:sticky sm:top-0 sm:self-start">
                  {selectedCard.imageUrl ? <img src={selectedCard.imageUrl} alt={selectedCard.name} className="max-h-[34vh] w-full max-w-[190px] rounded-xl bg-[#090f1b] object-contain sm:max-h-[58vh] sm:max-w-[220px]" /> : <div className="flex aspect-[3/4] w-full max-w-[190px] items-center justify-center rounded-xl bg-[#090f1b] text-sm text-slate-500">이미지 없음</div>}
                  <button onClick={() => addCard(selectedCard)} className="w-full max-w-[240px] rounded-xl bg-rose-600 px-4 py-2.5 text-xs font-bold text-white transition hover:bg-rose-500">{getCardRole(selectedCard) === 'partner' ? (partnerId === selectedCard.key ? '파트너 선택 해제' : '파트너로 지정') : getCardRole(selectedCard) === 'event' ? (eventId === selectedCard.key ? '사건 카드 선택 해제' : '사건 카드로 지정') : `덱에 추가${Number(deck[selectedCard.key] || 0) ? ` · 현재 ${deck[selectedCard.key]}장` : ' +'}`}</button>
                  {filteredCards.length > 1 && <p className="text-[10px] text-slate-600">← → 키로 다른 카드 확인</p>}
                </div>
                <div className="min-w-0 space-y-3">
                  <dl className="card-meta-grid grid grid-cols-2 gap-2 sm:grid-cols-3">{[['종류', selectedCard.type], ['색상', selectedCard.color], ['레어도', selectedCard.rarity], ['코스트', selectedCard.cost === null || selectedCard.cost === undefined ? '' : selectedCard.cost], ['LP', formatNumber(selectedCard.lp)], ['수록 제품', selectedCard.set]].map(([label, value]) => <div key={label} className="card-meta-item rounded-lg border border-white/[0.07] bg-[#090f1b] p-2.5"><dt className="text-[10px] font-medium text-slate-500">{label}</dt><dd className="mt-1 break-words text-xs font-semibold text-slate-200">{label === '코스트' && (value === '' || value === null || value === undefined) ? '' : (value ?? '-')}</dd></div>)}<div className="card-meta-item card-meta-item-traits rounded-lg border border-white/[0.07] bg-[#090f1b] p-2.5"><dt className="text-[10px] font-medium text-slate-500">특징</dt><dd className="mt-1">{selectedCard.traits?.length ? <div className="card-trait-list">{selectedCard.traits.map((trait) => <span key={trait} className="card-trait-chip">{trait}</span>)}</div> : <span className="text-xs font-semibold text-slate-500">없음</span>}</dd></div></dl>
                  {selectedCard.keywordTags?.length > 0 && <div className="detail-keyword-badges effect-badges">{selectedCard.keywordTags.map((tag) => <span key={tag} className={`effect-badge ${keywordTagClass(tag)}${String(tag).startsWith('조건부 ') ? ' conditional' : ''}`}>{tag}</span>)}</div>}
                  {(selectedCard.hiramekiEffect || selectedCard.cutInEffect) && <div className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><h3 className="mb-3 text-xs font-bold">게임 시스템 효과</h3><div className="space-y-3">{selectedCard.hiramekiEffect && <div><h4 className="mb-1 text-xs font-bold text-amber-300">히라메키</h4><p className="whitespace-pre-wrap break-words text-xs leading-5 text-slate-200">{selectedCard.hiramekiEffect}</p></div>}{selectedCard.cutInEffect && <div><h4 className="mb-1 text-xs font-bold text-sky-300">컷인</h4><p className="whitespace-pre-wrap break-words text-xs leading-5 text-slate-200">{selectedCard.cutInEffect}</p></div>}</div></div>}
                  <div className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><h3 className="mb-2 text-xs font-bold text-slate-300">카드 효과</h3><div className="card-effect-text text-xs leading-6 text-slate-200">{formatAbilityText(selectedCard.ability) || '효과 텍스트 없음'}</div></div>
                  {selectedCard.flavor && <div className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><h3 className="mb-2 text-xs font-bold text-slate-300">플레이버 텍스트</h3><p className="whitespace-pre-wrap break-words text-xs leading-5 text-slate-300">{selectedCard.flavor}</p></div>}
                  {(selectedCard.originalName !== selectedCard.name || selectedCard.originalAbility !== selectedCard.ability) && <details className="rounded-xl border border-white/[0.07] bg-[#090f1b] p-3"><summary className="cursor-pointer text-xs font-semibold text-slate-300">일본어 원문 보기</summary><div className="mt-3 space-y-3 text-xs leading-5"><p><span className="text-slate-500">이름: </span>{selectedCard.originalName || '-'}</p><p className="card-original-effect-text whitespace-pre-wrap break-words"><span className="text-slate-500">효과: </span>{formatAbilityText(selectedCard.originalAbility) || '-'}</p></div></details>}
                </div>
              </div>
            </div>
          </section>
        </div>
      )}
    </main>
  );
}
