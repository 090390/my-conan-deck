import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';

const filePath = path.join(process.cwd(), 'data', 'glossary.ko.json');
function readGlossary() {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    if (!value || Array.isArray(value) || typeof value !== 'object') throw new Error('용어집은 JSON 객체여야 해요.');
    return value;
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw error;
  }
}
function saveGlossary(glossary) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(Object.fromEntries(Object.entries(glossary).sort(([a], [b]) => a.localeCompare(b))), null, 2) + '\n', 'utf8');
}
function usage() {
  console.log(`
코난 TCG 용어집 도구

사용법:
  node scripts/glossary.mjs
  node scripts/glossary.mjs add "일본어 원문" "한국어 표기"
  node scripts/glossary.mjs remove "일본어 원문"
  node scripts/glossary.mjs list

파일: data/glossary.ko.json
`);
}

const [command, ...args] = process.argv.slice(2);
try {
  const glossary = readGlossary();
  if (command === 'list') {
    const entries = Object.entries(glossary).sort(([a], [b]) => a.localeCompare(b));
    if (!entries.length) console.log('용어집이 비어 있어요.');
    else for (const [source, target] of entries) console.log(`${source}\t→\t${target}`);
    console.log(`총 ${entries.length}개`);
  } else if (command === 'add') {
    const [source, target] = args;
    if (!source?.trim() || !target?.trim()) { usage(); process.exitCode = 1; }
    else {
      glossary[source.trim()] = target.trim();
      saveGlossary(glossary);
      console.log(`저장했어요: ${source.trim()} → ${target.trim()}`);
      console.log('이후 translate-cards.mjs 실행부터 이 표기를 사용해요. 이미 번역한 카드도 해당 원문이 포함된 문장은 다시 번역해 반영해요.');
    }
  } else if (command === 'remove') {
    const source = args[0];
    if (!source?.trim()) { usage(); process.exitCode = 1; }
    else if (!(source.trim() in glossary)) console.log(`용어집에 없는 항목이에요: ${source.trim()}`);
    else {
      delete glossary[source.trim()];
      saveGlossary(glossary);
      console.log(`삭제했어요: ${source.trim()}`);
    }
  } else if (!command) {
    const rl = readline.createInterface({ input, output });
    console.log('고유 명사 용어집 편집기');
    console.log('일본어 원문을 입력한 다음 한국어 표기를 입력해 주세요. 빈 원문을 입력하면 종료해요.');
    console.log('현재 용어 수:', Object.keys(glossary).length);
    try {
      while (true) {
        const source = (await rl.question('\n일본어 원문 (종료하려면 Enter): ')).trim();
        if (!source) break;
        const current = glossary[source] ? `현재 표기: ${glossary[source]}. 새 표기를 입력하거나 ! 를 입력하면 기존 표기를 유지해요.\n` : '';
        const target = (await rl.question(`${current}한국어 표기: `)).trim();
        if (!target || target === '!') {
          console.log('변경하지 않았어요.');
          continue;
        }
        glossary[source] = target;
        saveGlossary(glossary);
        console.log(`저장했어요: ${source} → ${target}`);
      }
    } finally { rl.close(); }
    console.log(`완료: ${Object.keys(glossary).length}개 용어를 ${filePath}에 저장했어요.`);
  } else usage();
} catch (error) {
  console.error('용어집 처리 중 오류:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
