
import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

const SOURCE_URL =
  'https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/';

const API_URL =
  'https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/cards';

const IMAGE_BASE =
  'https://www.takaratomy.co.jp/products/conan-cardgame/storage/card/';

const NO_IMAGE_URL =
  'https://www.takaratomy.co.jp/products/conan-cardgame/_image/noimage.jpg';

const OUTPUT_FILE = path.join(ROOT, 'public', 'cards.json');
const PARTIAL_FILE = path.join(ROOT, 'data', 'cards.partial.json');
const DIAGNOSTICS_FILE = path.join(ROOT, 'data', 'scrape-diagnostics.json');
const IMAGE_DIR = path.join(ROOT, 'public', 'card-images');

const DOWNLOAD_IMAGES = process.argv.includes('--download-images');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function str(value) {
  if (value == null) return '';

  if (typeof value === 'string') {
    return value.trim();
  }

  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }

  return '';
}

function first(raw, keys) {
  for (const key of keys) {
    const value = str(raw?.[key]);
    if (value) return value;
  }

  return '';
}

function getImageUrl(raw) {
  const mainPath = str(raw.main_path);

  if (!mainPath) return NO_IMAGE_URL;

  if (/^https?:\/\//i.test(mainPath)) {
    return mainPath;
  }

  return new URL(
    mainPath.replace(/^\/+/, ''),
    IMAGE_BASE
  ).href;
}

function mapCard(raw) {
  const cardNumber = first(raw, [
    'card_num',
    'card_number',
    'number'
  ]);

  const sourceRecordId = first(raw, ['id']);

  const cardId = first(raw, [
    'card_id',
    'display_id'
  ]);

  const category = [
    raw.category1,
    raw.category2,
    raw.category3
  ].map(str).filter(Boolean);

  const imageUrl = getImageUrl(raw);

  return {
    // 기본 식별 정보
    id: cardNumber || sourceRecordId || cardId,
    cardId,
    cardNumber,
    sourceRecordId,

    // 카드 정보
    nameJp: first(raw, [
      'title',
      'name',
      'card_name'
    ]),
    nameKo: '',

    type: first(raw, [
      'type',
      'card_type',
      'kind'
    ]),

    rarity: first(raw, [
      'rarity',
      'rare',
      'rarity_name'
    ]),

    color: first(raw, [
      'color',
      'color_name',
      'region'
    ]),

    cost: first(raw, [
      'cost',
      'cost_num',
      'level',
      'level_num',
      'lv'
    ]),

    lp: first(raw, ['lp', 'LP']),
    ap: first(raw, ['ap', 'AP']),

    set: first(raw, [
      'package',
      'set',
      'set_name',
      'package_name'
    ]),
    setKo: '',

    traits: category.join(' / '),

    // 원문 및 번역 필드
    abilityJp: first(raw, [
      'feature',
      'ability',
      'ability_text',
      'effect',
      'effect_text',
      'card_text',
      'text',
      'description',
      'skill'
    ]),
    abilityKo: '',

    // 이미지
    imageUrl,
    sourceImageUrl: imageUrl,
    localImagePath: '',

    // 출처
    sourceUrl: SOURCE_URL,

    // 원본 JSON을 그대로 보존
    // 실제 필드명이 위의 예상과 다르더라도
    // 원본 데이터에서 확인할 수 있음
    sourceData: raw
  };
}

async function fetchPage(context, pageNumber, queryString, requests) {
  let lastError;

  for (let attempt = 1; attempt <= 3; attempt++) {
    const url =
      API_URL +
      '?page=' + pageNumber +
      (queryString ? '&' + queryString : '');

    try {
      console.log(
        `페이지 ${pageNumber} 요청 중... (시도 ${attempt}/3)`
      );

      const response = await context.request.get(url, {
        timeout: 45000,
        headers: {
          Accept: 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          Referer: SOURCE_URL
        }
      });

      requests.push({
        page: pageNumber,
        url,
        status: response.status()
      });

      if (!response.ok()) {
        throw new Error(
          `HTTP ${response.status()}`
        );
      }

      const result = await response.json();

      if (!result || !Array.isArray(result.data)) {
        throw new Error(
          '응답에 data 배열이 없습니다.'
        );
      }

      if (result.data.length === 0) {
        throw new Error(
          '카드 데이터가 0장 반환됐습니다.'
        );
      }

      return result;
    } catch (error) {
      lastError = error;

      console.warn(
        `페이지 ${pageNumber} 요청 실패: ${error.message}`
      );

      if (attempt < 3) {
        await sleep(attempt * 1500);
      }
    }
  }

  throw new Error(
    `페이지 ${pageNumber} 요청을 3회 시도했지만 실패했습니다: ` +
    (lastError?.message || '알 수 없는 오류')
  );
}

async function savePartial(cards, completedPage, total, lastPage) {
  await fs.mkdir(path.dirname(PARTIAL_FILE), {
    recursive: true
  });

  await fs.writeFile(
    PARTIAL_FILE,
    JSON.stringify({
      source: SOURCE_URL,
      scrapedAt: new Date().toISOString(),
      total: cards.length,
      sourceTotal: total,
      completedPage,
      lastPage,
      partial: true,
      cards
    }, null, 2),
    'utf8'
  );
}

function safeFilename(value) {
  return String(value || 'card')
    .replace(/[^a-zA-Z0-9_-]/g, '_');
}

async function downloadOneImage(context, card) {
  const sourceUrl = card.sourceImageUrl;

  if (
    !sourceUrl ||
    sourceUrl === NO_IMAGE_URL
  ) {
    return false;
  }

  try {
    const response = await context.request.get(sourceUrl, {
      timeout: 30000,
      headers: {
        Referer: SOURCE_URL
      }
    });

    if (!response.ok()) {
      throw new Error(`HTTP ${response.status()}`);
    }

    const contentType =
      response.headers()['content-type'] || '';

    if (!contentType.startsWith('image/')) {
      throw new Error(
        `이미지 응답이 아닙니다: ${contentType}`
      );
    }

    let extension = path.extname(
      new URL(sourceUrl).pathname
    ).toLowerCase();

    if (!['.jpg', '.jpeg', '.png', '.webp'].includes(extension)) {
      extension = '.jpg';
    }

    const filename =
      safeFilename(card.sourceRecordId || card.id) +
      extension;

    const destination = path.join(IMAGE_DIR, filename);

    await fs.writeFile(
      destination,
      await response.body()
    );

    card.imageUrl = '/card-images/' + filename;
    card.localImagePath = 'public/card-images/' + filename;

    return true;
  } catch (error) {
    console.warn(
      `이미지 다운로드 실패 (${card.cardNumber || card.id}): ` +
      error.message
    );

    // 이미지 다운로드에 실패해도
    // 공식 이미지 주소는 계속 사용할 수 있도록 보존
    card.imageUrl = card.sourceImageUrl;

    return false;
  }
}

async function downloadAllImages(context, cards) {
  await fs.mkdir(IMAGE_DIR, {
    recursive: true
  });

  let nextIndex = 0;
  let downloaded = 0;
  let failed = 0;

  const worker = async () => {
    while (true) {
      const index = nextIndex++;

      if (index >= cards.length) return;

      const success = await downloadOneImage(
        context,
        cards[index]
      );

      if (success) {
        downloaded++;
      } else {
        failed++;
      }

      const processed = downloaded + failed;

      if (processed % 50 === 0 || processed === cards.length) {
        console.log(
          `이미지 진행: ${processed}/${cards.length} ` +
          `(성공 ${downloaded}, 실패 ${failed})`
        );
      }

      // 공식 서버에 요청이 몰리지 않도록 짧게 대기
      await sleep(100);
    }
  };

  // 동시에 처리하는 이미지는 최대 4장
  await Promise.all(
    Array.from({ length: 4 }, () => worker())
  );

  return { downloaded, failed };
}

async function main() {
  let browser;
  let context;

  const requests = [];
  const cardsByKey = new Map();

  let completedPage = 0;
  let expectedTotal = 2292;
  let lastPage = 46;
  let queryString = '';

  try {
    await fs.mkdir(
      path.dirname(OUTPUT_FILE),
      { recursive: true }
    );

    await fs.mkdir(
      path.dirname(PARTIAL_FILE),
      { recursive: true }
    );

    console.log('공식 사이트에 접속하는 중...');

    browser = await chromium.launch({
      headless: true
    });

    context = await browser.newContext({
      locale: 'ja-JP'
    });

    const page = await context.newPage();

    await page.goto(SOURCE_URL, {
      waitUntil: 'domcontentloaded',
      timeout: 60000
    });

    const cardList = page.locator('#cardList');

    await cardList.waitFor({
      state: 'attached',
      timeout: 30000
    });

    expectedTotal =
      Number(await cardList.getAttribute('data-total')) ||
      expectedTotal;

    lastPage =
      Number(await cardList.getAttribute('data-last-page')) ||
      lastPage;

    queryString =
      (await cardList.getAttribute('data-query')) || '';

    console.log(`전체 카드: ${expectedTotal}장`);
    console.log(`전체 페이지: ${lastPage}페이지`);

    // 공식 JSON API를 통해 모든 페이지를 순서대로 수집
    for (
      let pageNumber = 1;
      pageNumber <= lastPage;
      pageNumber++
    ) {
      const result = await fetchPage(
        context,
        pageNumber,
        queryString,
        requests
      );

      if (result.lastPage) {
        lastPage = Number(result.lastPage) || lastPage;
      }

      if (result.total) {
        expectedTotal =
          Number(result.total) || expectedTotal;
      }

      for (const raw of result.data) {
        const card = mapCard(raw);

        // 데이터베이스 ID로 중복 확인
        const key = String(
          raw.id ??
          raw.card_num ??
          raw.card_id ??
          ''
        );

        if (!key) {
          console.warn(
            '식별자가 없는 카드 데이터가 있어 건너뜁니다.'
          );
          continue;
        }

        if (!cardsByKey.has(key)) {
          cardsByKey.set(key, card);
        }
      }

      completedPage = pageNumber;

      const cards = [...cardsByKey.values()];

      console.log(
        `페이지 ${pageNumber}/${lastPage} 완료: ` +
        `이번 페이지 ${result.data.length}장, ` +
        `누적 ${cards.length}/${expectedTotal}장`
      );

      // 진행 상황을 매 페이지 저장
      await savePartial(
        cards,
        completedPage,
        expectedTotal,
        lastPage
      );

      // 요청 간 간격을 두어 서버 부담 줄이기
      await sleep(150);
    }

    let cards = [...cardsByKey.values()];

    if (cards.length !== expectedTotal) {
      throw new Error(
        `전체 카드 수가 일치하지 않습니다. ` +
        `수집 ${cards.length}장 / 예상 ${expectedTotal}장`
      );
    }

    console.log('모든 페이지의 카드 데이터를 수집했습니다.');

    if (DOWNLOAD_IMAGES) {
      console.log('카드 이미지를 다운로드합니다.');

      const imageResult = await downloadAllImages(
        context,
        cards
      );

      console.log(
        `이미지 다운로드 완료: ${imageResult.downloaded}장, ` +
        `실패 ${imageResult.failed}장`
      );
    } else {
      console.log(
        '이미지는 공식 주소로 연결됩니다. ' +
        '로컬 저장이 필요하면 --download-images 옵션을 사용하세요.'
      );
    }

    const output = {
      source: SOURCE_URL,
      scrapedAt: new Date().toISOString(),
      total: cards.length,
      sourceTotal: expectedTotal,
      cards
    };

    await fs.writeFile(
      OUTPUT_FILE,
      JSON.stringify(output, null, 2),
      'utf8'
    );

    await fs.rm(PARTIAL_FILE, {
      force: true
    });

    console.log('');
    console.log('====================================');
    console.log('카드 데이터 수집 완료!');
    console.log(`카드 수: ${cards.length}`);
    console.log(`저장 위치: ${OUTPUT_FILE}`);
    console.log('====================================');
  } catch (error) {
    console.error('');
    console.error('[수집 중단]', error.message);

    try {
      await fs.writeFile(
        DIAGNOSTICS_FILE,
        JSON.stringify({
          source: SOURCE_URL,
          failedAt: new Date().toISOString(),
          completedPage,
          lastPage,
          expectedTotal,
          collectedTotal: cardsByKey.size,
          error: error.message,
          recentRequests: requests.slice(-100)
        }, null, 2),
        'utf8'
      );

      await savePartial(
        [...cardsByKey.values()],
        completedPage,
        expectedTotal,
        lastPage
      );

      console.error(
        '진행 데이터와 진단 정보가 저장됐습니다.'
      );
    } catch (saveError) {
      console.error(
        '진단 파일 저장 실패:',
        saveError.message
      );
    }

    process.exitCode = 1;
  } finally {
    if (context) {
      await context.close().catch(() => {});
    }

    if (browser) {
      await browser.close().catch(() => {});
    }
  }
}

main().catch(error => {
  console.error('예기치 않은 오류:', error);
  process.exitCode = 1;
});
