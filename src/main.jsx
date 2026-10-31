import React, { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import App from './App.jsx';

class AppRenderErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null, componentStack: "" };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('App render failed:', error, info);
    this.setState({ componentStack: info?.componentStack || "" });
  }

  render() {
    if (this.state.error) {
      const message = this.state.error?.message || String(this.state.error);
      return (
        <main role="alert" style={{ minHeight: '100vh', boxSizing: 'border-box', padding: 'clamp(24px, 6vw, 64px)', background: '#080d18', color: '#e9edf6', fontFamily: 'Inter, Pretendard, "Noto Sans KR", sans-serif' }}>
          <section style={{ width: 'min(720px, 100%)', margin: '8vh auto 0', padding: 24, border: '1px solid #543344', borderRadius: 16, background: '#111a2b' }}>
            <h1 style={{ margin: 0, color: '#fff', fontSize: 22, fontWeight: 850 }}>화면을 표시하는 중 오류가 발생했어요.</h1>
            <p style={{ margin: '16px 0 0', color: '#ff9aaa', fontSize: 13, lineHeight: 1.7, overflowWrap: 'anywhere' }}>{message}</p>
            <p style={{ margin: '12px 0 0', color: '#a7b4c8', fontSize: 13, lineHeight: 1.7 }}>오류가 표시되도록 복구 화면을 띄웠습니다. 새로고침 후에도 반복되면 아래 오류 위치 정보를 함께 보내 주세요.</p>
            <details style={{ marginTop: 12, color: '#a7b4c8', fontSize: 11, lineHeight: 1.5 }}>
              <summary style={{ cursor: 'pointer' }}>오류 위치 정보 보기</summary>
              <pre style={{ maxHeight: 220, overflow: 'auto', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', color: '#fda4af', fontSize: 10 }}>{String(this.state.error?.stack || this.state.error)}{this.state.componentStack}</pre>
            </details>
            <button type="button" onClick={() => window.location.reload()} style={{ marginTop: 20, minHeight: 40, border: '1px solid #9f3449', borderRadius: 9, padding: '8px 16px', color: '#fff', background: '#be123c', fontSize: 13, fontWeight: 750, cursor: 'pointer' }}>새로고침</button>
          </section>
        </main>
      );
    }
    return this.props.children;
  }
}

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error('앱을 표시할 #root 요소를 찾지 못했습니다.');
}

createRoot(rootElement).render(
  <StrictMode>
    <AppRenderErrorBoundary>
      <App />
    </AppRenderErrorBoundary>
  </StrictMode>,
);
