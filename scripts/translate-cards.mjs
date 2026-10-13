import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = process.cwd();
const inputPath = path.join(root, 'public', 'cards.json');
const outputPath = path.join(root, 'public', 'card-translations.ko.json');
const cachePath = path.join(root, 'data', 'translation-cache.json');
const glossaryPath = path.join(root, 'data', 'glossary.ko.json');
const nameReviewPath = path.join(root, 'data', 'name-review.tsv');
const apiUrl = process.env.DEEPL_API_URL || 'https://api-free.deepl.com/v2/translate';
const apiKey = process.env.DEEPL_AUTH_KEY;
const BATCH_SIZE = 35;
const MAX_TEXT_BYTES = 120_000;

const COLOR_MAP = {
  '青': '청', '青色': '청색', '赤': '적', '赤色': '적색', '黄': '황', '黄色': '황색',
  '緑': '녹', '緑色': '녹색', '白': '백', '白色': '백색', '黒': '흑', '黒色': '흑색',
  '紫': '자', '紫色': '자색', '無色': '무색',
};
const TYPE_MAP = {
  'パートナー': '파트너', 'キャラ': '캐릭터', 'キャラクター': '캐릭터',
  'イベント': '이벤트', '事件': '사건', '解決': '해결',
};
const FIELDS = [
  { output: 'nameKo', candidates: ['nameJp', 'title', 'name', 'cardName', 'card_name'] },
  { output: 'typeKo', candidates: ['typeJp', 'type', 'cardType', 'card_type'] },
  { output: 'colorKo', candidates: ['colorJp', 'color', 'colour', 'color_txt', 'card_color'] },
  { output: 'setKo', candidates: ['setJp', 'package', 'set', 'product', 'package_name'] },
  { output: 'abilityKo', candidates: ['abilityJp', 'text', 'ability', 'feature', 'effect', 'effect_text', 'card_text', 'detail'] },
  { output: 'flavorKo', candidates: ['flavorJp', 'flavor_txt', 'flavor', 'flavorText', 'flavor_text'] },
  { output: 'category1Ko', candidates: ['category1'] },
  { output: 'category2Ko', candidates: ['category2'] },
  { output: 'category3Ko', candidates: ['category3'] },
];

function readJsonIfExists(filePath, fallback) {
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return fallback; throw error; }
}
function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf8');
}
function getCardArray(input) {
  if (Array.isArray(input)) return input;
  if (Array.isArray(input?.data)) return input.data;
  if (Array.isArray(input?.cards)) return input.cards;
  if (Array.isArray(input?.items)) return input.items;
  throw new Error('cards.json에서 카드 배열을 찾지 못했어요. JSON 최상위 구조를 확인해 주세요.');
}
function sourceObjects(card) {
  return [card, card?.sourceData, card?.raw, card?.original]
    .filter((item) => item && typeof item === 'object');
}
function pick(card, candidates) {
  for (const object of sourceObjects(card)) {
    for (const key of candidates) {
      const value = object[key];
      if (value !== undefined && value !== null && String(value).trim() !== '') return String(value).trim();
    }
  }
  return '';
}
function cardKey(card, index) {
  return pick(card, ['id', 'databaseId', 'database_id', 'cardId', 'card_id', 'cardNum', 'card_num']) || `row_${index + 1}`;
}
function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}
function pause(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }
function parseLimit() {
  const args = process.argv.slice(2);
  const equalsArg = args.find((arg) => arg.startsWith('--limit='));
  if (equalsArg) return Math.max(1, Number(equalsArg.split('=')[1]) || 1);
  const index = args.indexOf('--limit');
  if (index >= 0) return Math.max(1, Number(args[index + 1]) || 1);
  return Infinity;
}

function normalizeGlossary(input) {
  if (!input || Array.isArray(input) || typeof input !== 'object') return {};
  return Object.fromEntries(Object.entries(input)
    .filter(([source, target]) => source.trim() && typeof target === 'string' && target.trim())
    .sort(([a], [b]) => b.length - a.length || a.localeCompare(b)));
}
function matchedTerms(source, glossary) {
  return Object.entries(glossary).filter(([term]) => source.includes(term));
}
function protectTerms(source, glossary) {
  let prepared = source;
  const replacements = [];
  let counter = 1;
  for (const [term, target] of matchedTerms(source, glossary)) {
    if (!prepared.includes(term)) continue;
    let token;
    do { token = `ZXQTERM${String(counter++).padStart(5, '0')}QXZ`; }
    while (source.includes(token) || prepared.includes(token));
    prepared = prepared.split(term).join(token);
    replacements.push({ token, term, target });
  }
  const signature = sha256(JSON.stringify(replacements.map(({ term, target }) => [term, target])));
  return { prepared, replacements, signature };
}
function restoreTerms(translated, replacements, source) {
  let result = translated;
  for (const item of replacements) {
    const escaped = item.token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const matcher = new RegExp(escaped, 'gi');
    if (!matcher.test(result)) {
      throw new Error(`번역 API가 용어 보호 토큰을 유지하지 않았어요: ${item.term}. 해당 문장은 캐시하지 않았으니 다시 시도해 주세요.`);
    }
    result = result.replace(matcher, item.target);
  }
  return result;
}
function sourceSignature(source, protectedText) {
  return sha256(`${source}\0${protectedText.signature}`);
}
function escapeTsv(value) {
  return String(value ?? '').replace(/[\t\r\n]+/g, ' ').trim();
}

async function translateBatch(entries, glossary) {
  const body = new URLSearchParams();
  body.set('source_lang', 'JA');
  body.set('target_lang', 'KO');
  body.set('preserve_formatting', '1');
  body.set('context', 'Translate Japanese Detective Conan trading card game text into Korean. Preserve all ZXQTERM00000QXZ-style tokens exactly as written; they stand for fixed Korean glossary terms. Use consistent trading-card terminology and do not add explanations.');
  for (const entry of entries) body.append('text', entry.protectedText.prepared);

  let lastError;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    try {
      const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
          Authorization: `DeepL-Auth-Key ${apiKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body,
      });
      if (response.ok) {
        const data = await response.json();
        if (!Array.isArray(data.translations) || data.translations.length !== entries.length) {
          throw new Error('번역 API가 예상과 다른 형식으로 응답했어요.');
        }
        return data.translations.map((item, index) => restoreTerms(String(item.text ?? ''), entries[index].protectedText.replacements, entries[index].source));
      }
      const bodyText = await response.text();
      lastError = new Error(`DeepL API 오류 ${response.status}: ${bodyText.slice(0, 500)}`);
      if (response.status !== 429 && response.status < 500) break;
    } catch (error) {
      lastError = error;
    }
    await pause(1500 * (attempt + 1));
  }
  throw lastError || new Error('번역 요청에 실패했어요.');
}

function createNameReview(cards, translations) {
  const lines = [['database_id', 'card_num', 'japanese_title', 'korean_translation'].join('\t')];
  for (let index = 0; index < cards.length; index += 1) {
    const card = cards[index];
    const key = cardKey(card, index);
    const title = pick(card, ['nameJp', 'title', 'name', 'cardName', 'card_name']);
    if (!title) continue;
    const cardNum = pick(card, ['card_num', 'cardNum', 'card_id', 'cardId']);
    const translated = translations[key]?.nameKo || '';
    lines.push([key, cardNum, title, translated].map(escapeTsv).join('\t'));
  }
  fs.mkdirSync(path.dirname(nameReviewPath), { recursive: true });
  fs.writeFileSync(nameReviewPath, lines.join('\n') + '\n', 'utf8');
}

async function main() {
  if (!fs.existsSync(inputPath)) throw new Error('public/cards.json 파일이 없어요. 수집한 원본 JSON을 이 위치에 저장해 주세요.');
  if (!apiKey) throw new Error('DEEPL_AUTH_KEY 환경변수가 없어요. PowerShell에서 $env:DEEPL_AUTH_KEY="발급받은 키" 를 먼저 실행해 주세요.');

  const rawInput = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  const allCards = getCardArray(rawInput);
  const cards = allCards.slice(0, parseLimit());
  const glossary = normalizeGlossary(readJsonIfExists(glossaryPath, {}));
  const translations = readJsonIfExists(outputPath, {});
  const cache = readJsonIfExists(cachePath, {});
  const metaPath = path.join(root, 'data', 'translation-meta.json');
  const storedMeta = readJsonIfExists(metaPath, {});
  const tasksByKey = new Map();
  const references = [];
  let preservedExisting = 0;

  for (let index = 0; index < cards.length; index += 1) {
    const card = cards[index];
    const id = cardKey(card, index);
    translations[id] = { ...(translations[id] || {}) };
    translations[id]._translationMeta = { ...(translations[id]._translationMeta || {}), ...(storedMeta[id] || {}) };

    for (const field of FIELDS) {
      const sourceText = pick(card, field.candidates);
      if (!sourceText) continue;
      if (field.output === 'colorKo' && COLOR_MAP[sourceText]) {
        translations[id][field.output] = COLOR_MAP[sourceText];
        translations[id]._translationMeta[field.output] = sourceSignature(sourceText, { signature: 'fixed-map' });
        continue;
      }
      if (field.output === 'typeKo' && TYPE_MAP[sourceText]) {
        translations[id][field.output] = TYPE_MAP[sourceText];
        translations[id]._translationMeta[field.output] = sourceSignature(sourceText, { signature: 'fixed-map' });
        continue;
      }

      const protectedText = protectTerms(sourceText, glossary);
      const signature = sourceSignature(sourceText, protectedText);
      const previousSignature = translations[id]._translationMeta[field.output];
      const hasExistingTranslation = Boolean(translations[id][field.output]);
      const matched = protectedText.replacements.length > 0;

      if (hasExistingTranslation && previousSignature === signature) continue;
      // Preserve translations created by the previous script unless a newly defined glossary term affects them.
      if (hasExistingTranslation && !previousSignature && !matched) {
        preservedExisting += 1;
        continue;
      }

      const cacheKey = sha256(`${field.output}\0${sourceText}\0${signature}`);
      references.push({ id, field: field.output, source: sourceText, signature, cacheKey, protectedText });
      if (!cache[cacheKey]) {
        if (!tasksByKey.has(cacheKey)) tasksByKey.set(cacheKey, { source: sourceText, cacheKey, protectedText, references: [] });
      }
      if (tasksByKey.has(cacheKey)) tasksByKey.get(cacheKey).references.push({ id, field: field.output, signature });
      else {
        // Cached result is applied without a network call below.
        if (cache[cacheKey] !== undefined) {
          translations[id][field.output] = cache[cacheKey];
          translations[id]._translationMeta[field.output] = signature;
        }
      }
    }
  }

  const uniqueTasks = [...tasksByKey.values()];
  console.log(`번역 대상 카드: ${cards.length}장 / 전체 ${allCards.length}장`);
  console.log(`용어집 항목: ${Object.keys(glossary).length}개`);
  console.log(`새로 번역하거나 용어집 반영을 위해 다시 번역할 문구: ${uniqueTasks.length}개`);
  if (preservedExisting) console.log(`이전 번역 중 용어집 영향이 없는 기존 번역 ${preservedExisting}개는 보존했어요.`);

  for (let start = 0; start < uniqueTasks.length;) {
    const batch = [];
    let bytes = 0;
    while (start < uniqueTasks.length && batch.length < BATCH_SIZE) {
      const task = uniqueTasks[start];
      const byteCount = Buffer.byteLength(task.protectedText.prepared, 'utf8');
      if (batch.length && bytes + byteCount > MAX_TEXT_BYTES) break;
      batch.push(task);
      bytes += byteCount;
      start += 1;
    }
    const results = await translateBatch(batch, glossary);
    for (let index = 0; index < batch.length; index += 1) {
      const task = batch[index];
      const translated = results[index];
      cache[task.cacheKey] = translated;
      for (const reference of task.references) {
        translations[reference.id][reference.field] = translated;
        translations[reference.id]._translationMeta[reference.field] = reference.signature;
      }
    }
    writeJson(outputPath, translations);
    writeJson(cachePath, cache);
    console.log(`진행: ${Math.min(start, uniqueTasks.length)} / ${uniqueTasks.length}개 문구 처리`);
    await pause(250);
  }

  // Output metadata is not needed by the site; remove it from the published translation JSON.
  // Metadata is held in a sidecar file so translation invalidation can work across runs.
  const meta = { ...storedMeta };
  for (const [id, row] of Object.entries(translations)) {
    if (row._translationMeta) meta[id] = { ...(meta[id] || {}), ...row._translationMeta };
  }
  writeJson(metaPath, meta);
  for (const row of Object.values(translations)) delete row._translationMeta;
  writeJson(outputPath, translations);

  createNameReview(cards, translations);
  console.log(`\n완료: ${outputPath}`);
  console.log(`고유 명사 검수용 카드명 목록: ${nameReviewPath}`);
  console.log(`용어집: ${glossaryPath}`);
  console.log('기계 번역은 초안이에요. 카드 효과의 공식 용어와 규칙 해석은 검수해 주세요.');
}

main().catch((error) => {
  console.error('\n번역 실패:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
