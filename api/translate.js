export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'POST 요청만 지원합니다.' });
  }

  const apiKey = process.env.GOOGLE_TRANSLATE_API_KEY;
  if (!apiKey) {
    return res.status(503).json({ error: '자동 번역을 사용하려면 배포 환경 변수 GOOGLE_TRANSLATE_API_KEY에 Google Cloud Translation API 키를 설정해 주세요.' });
  }

  try {
    const { texts, source = 'ja', target = 'ko' } = req.body || {};
    if (!Array.isArray(texts) || texts.length === 0 || texts.length > 20) {
      return res.status(400).json({ error: 'texts에는 1~20개의 문자열을 넣어 주세요.' });
    }
    const safeTexts = texts.map((item) => String(item || '').slice(0, 5000));
    const totalChars = safeTexts.reduce((sum, item) => sum + item.length, 0);
    if (totalChars > 12000) return res.status(413).json({ error: '한 번에 번역할 수 있는 텍스트가 너무 길어요.' });

    const response = await fetch(`https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(apiKey)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: safeTexts, source, target, format: 'text' }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      return res.status(502).json({ error: payload.error?.message || 'Google 번역 서비스에서 오류가 발생했습니다.' });
    }
    const translated = payload.data?.translations?.map((item) => item.translatedText) || [];
    return res.status(200).json({ translations: translated });
  } catch {
    return res.status(500).json({ error: '번역 요청을 처리하지 못했어요.' });
  }
}
