import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

async function translateLocally(req, res) {
  const apiKey = process.env.GOOGLE_TRANSLATE_API_KEY;
  if (!apiKey) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: '자동 번역을 사용하려면 .env 파일에 GOOGLE_TRANSLATE_API_KEY를 설정해 주세요.' }));
    return;
  }
  let body = '';
  for await (const chunk of req) body += chunk;
  try {
    const { texts, source = 'ja', target = 'ko' } = JSON.parse(body || '{}');
    if (!Array.isArray(texts) || texts.length < 1 || texts.length > 20) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: 'texts에는 1~20개의 문자열을 넣어 주세요.' }));
      return;
    }
    const safeTexts = texts.map((item) => String(item || '').slice(0, 5000));
    if (safeTexts.reduce((sum, item) => sum + item.length, 0) > 12000) {
      res.statusCode = 413;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: '한 번에 번역할 수 있는 텍스트가 너무 길어요.' }));
      return;
    }
    const response = await fetch(`https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(apiKey)}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: safeTexts, source, target, format: 'text' }),
    });
    const payload = await response.json().catch(() => ({}));
    res.statusCode = response.ok ? 200 : 502;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify(response.ok ? { translations: payload.data?.translations?.map((item) => item.translatedText) || [] } : { error: payload.error?.message || 'Google 번역 서비스에서 오류가 발생했습니다.' }));
  } catch {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: '번역 요청을 처리하지 못했어요.' }));
  }
}

export default defineConfig({
  plugins: [
    react(),
    {
      name: 'local-translation-api',
      configureServer(server) {
        server.middlewares.use('/api/translate', (req, res, next) => {
          if (req.method !== 'POST') return next();
          translateLocally(req, res);
        });
      },
    },
  ],
});
