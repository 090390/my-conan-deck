import { useState } from "react";
import { supabase } from "../lib/supabase";

const panel = {
  width: "min(100%, 980px)", maxHeight: "94dvh", display: "flex", flexDirection: "column",
  overflow: "hidden", border: "1px solid rgba(147,197,253,.34)", borderRadius: 13,
  background: "#101827", color: "#e8edf7", boxShadow: "0 24px 80px rgba(0,0,0,.65)",
};
const field = {
  width: "100%", minWidth: 0, boxSizing: "border-box", padding: "10px 11px",
  border: "1px solid rgba(148,163,184,.28)", borderRadius: 7,
  background: "#080d16", color: "#f1f5f9", font: "inherit", fontSize: 12,
};
const DIAGNOSTIC_CODE_PATTERN = /^(MT|ER)-(?:[0-9A-F]{4}-[0-9A-F]{4}|[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8})$/;

function dateLabel(value) {
  if (!value) return "기록 없음";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "일시 미상" : date.toLocaleString("ko-KR");
}
async function copyText(value) {
  try { await navigator.clipboard.writeText(value); }
  catch { window.prompt("아래 코드를 직접 복사해 주세요.", value); }
}
function JsonDetails({ title, value }) {
  if (!value || (typeof value === "object" && !Object.keys(value).length)) return null;
  return <details style={{ marginTop: 7 }}>
    <summary style={{ cursor: "pointer", color: "#93c5fd", fontSize: 10, fontWeight: 800 }}>{title}</summary>
    <pre style={{ maxHeight: 260, overflow: "auto", margin: "7px 0 0", padding: 9, border: "1px solid rgba(148,163,184,.15)", borderRadius: 6, background: "#070c14", color: "#cbd5e1", fontSize: 9, lineHeight: 1.55, whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{JSON.stringify(value, null, 2)}</pre>
  </details>;
}

export default function MatchDiagnosticsAdmin() {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState(null);

  async function lookup(event) {
    event.preventDefault();
    const normalizedCode = code.trim().toUpperCase();
    if (!DIAGNOSTIC_CODE_PATTERN.test(normalizedCode)) {
      setError("대전 추적 코드(MT-…) 또는 오류 보고 코드(ER-…)를 정확히 입력해 주세요.");
      setResult(null);
      return;
    }
    setLoading(true);
    setError("");
    setResult(null);
    try {
      const { data, error: rpcError } = await supabase.rpc("lookup_private_match_diagnostics_v1", {
        p_code: normalizedCode,
      });
      if (rpcError) throw rpcError;
      if (!data?.ok) setError(data?.message || "진단 기록을 조회하지 못했습니다.");
      else if (!data?.found) setError(data?.message || "해당 코드의 기록을 찾지 못했습니다.");
      else setResult(data);
    } catch (err) {
      setError(err?.message || "진단 기록을 조회하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  return <>
    <button type="button" onClick={() => { setOpen(true); setError(""); }}
      className="rounded-lg border border-white/10 px-3 py-2 text-xs font-semibold text-slate-300 transition hover:border-sky-400/50 hover:text-white"
      style={{ border: "1px solid rgba(125,211,252,.24)", borderRadius: 8, background: "rgba(14,116,144,.12)", color: "#bae6fd", padding: "8px 12px", fontSize: 12, fontWeight: 700, cursor: "pointer" }}>
      대전 진단 조회
    </button>
    {open && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpen(false); }}
      style={{ position: "fixed", inset: 0, zIndex: 130000, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(2,6,14,.9)" }}>
      <section role="dialog" aria-modal="true" aria-label="대전 진단 기록 조회" style={panel}>
        <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 14, borderBottom: "1px solid rgba(255,255,255,.1)" }}>
          <div><h2 style={{ margin: 0, fontSize: 17, fontWeight: 900 }}>대전 진단 기록 조회</h2>
            <p style={{ margin: "4px 0 0", color: "#94a3b8", fontSize: 10, lineHeight: 1.5 }}>정확한 진단 코드를 알고 있으면 누구나 해당 대전의 행동 기록과 오류 상세를 확인할 수 있습니다.</p></div>
          <button type="button" onClick={() => setOpen(false)} style={{ border: "1px solid rgba(148,163,184,.24)", borderRadius: 7, padding: "7px 10px", background: "#1e293b", color: "#e2e8f0", fontSize: 11 }}>닫기 ✕</button>
        </header>
        <div style={{ minHeight: 0, overflowY: "auto", padding: 13, display: "grid", gap: 12 }}>
          <form onSubmit={lookup} style={{ display: "grid", gridTemplateColumns: "minmax(0,1fr) auto", alignItems: "end", gap: 8, padding: 10, border: "1px solid rgba(148,163,184,.18)", borderRadius: 9, background: "#0b1220" }}>
            <label style={{ display: "grid", gap: 5, color: "#cbd5e1", fontSize: 10 }}>진단 코드
              <input value={code} onChange={(event) => setCode(event.target.value.toUpperCase())} placeholder="MT-… / ER-…" style={field} autoCapitalize="characters" spellCheck={false} />
            </label>
            <button type="submit" disabled={loading} style={{ minHeight: 38, border: 0, borderRadius: 7, padding: "8px 14px", background: "#075985", color: "white", fontSize: 11, fontWeight: 850, cursor: loading ? "wait" : "pointer", opacity: loading ? .6 : 1 }}>{loading ? "조회 중…" : "기록 조회"}</button>
          </form>
          <p style={{ margin: 0, color: "#94a3b8", fontSize: 10, lineHeight: 1.6 }}>정확한 코드를 알고 있는 사람은 누구나 해당 대전의 기록을 조회할 수 있습니다. 따라서 코드는 기록 열람 키처럼 취급해 주세요. 오류 보고 코드는 발생 후 60일 동안 조회할 수 있습니다. 일반 행동 기록은 30일 보관하며, 오류가 기록된 대전의 전후 기록은 해당 오류의 60일 보존 기간에 맞춰 유지합니다. 조회는 IP별 1분에 10회까지 가능합니다.</p>
          {error && <p role="alert" style={{ margin: 0, padding: 9, border: "1px solid rgba(251,113,133,.3)", borderRadius: 7, background: "rgba(190,24,93,.08)", color: "#fda4af", fontSize: 11, lineHeight: 1.6 }}>{error}</p>}
          {result?.session && <section style={{ display: "grid", gap: 9 }}>
            <article style={{ display: "grid", gap: 7, padding: 11, border: "1px solid rgba(125,211,252,.28)", borderRadius: 9, background: "rgba(8,47,73,.2)" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                <strong style={{ color: "#bae6fd", fontSize: 12 }}>대전 요약</strong>
                <button type="button" onClick={() => void copyText(result.session.trace_code)} style={{ border: "1px solid rgba(125,211,252,.35)", borderRadius: 6, padding: "5px 8px", background: "#0c2b43", color: "#e0f2fe", fontSize: 10 }}>추적 코드 복사</button>
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 7 }}>
                <code style={{ color: "white", fontSize: 15, fontWeight: 900, letterSpacing: ".08em" }}>{result.session.trace_code}</code>
                <span style={{ borderRadius: 4, padding: "3px 6px", background: "#1e3a5f", color: "#bfdbfe", fontSize: 9 }}>{result.session.match_mode === "ai" ? "AI 대전" : "플레이어 대전"}</span>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(170px,1fr))", gap: 7, color: "#cbd5e1", fontSize: 10 }}>
                <span>시작: {dateLabel(result.session.started_at)}</span><span>종료: {dateLabel(result.session.ended_at)}</span>
                <span>최근 기록: {dateLabel(result.session.last_activity_at)}</span><span>종료 사유: {result.session.ended_reason || "종료 기록 없음"}</span>
              </div>
              <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>{(result.session.participants || []).map((player) =>
                <span key={player.user_id || player.seat} style={{ padding: "4px 7px", border: "1px solid rgba(148,163,184,.18)", borderRadius: 5, background: "#0b1220", color: "#dbeafe", fontSize: 9 }}>{player.display_name} · 좌석 {player.seat}</span>)}</div>
            </article>
            {!!(result.errors || []).length && <section style={{ display: "grid", gap: 7 }}>
              <h3 style={{ margin: 0, color: "#fda4af", fontSize: 12 }}>오류 보고 ({result.errors.length})</h3>
              {result.errors.map((entry) => <article key={entry.id} style={{ padding: 10, border: "1px solid rgba(251,113,133,.25)", borderRadius: 8, background: "#1b101b" }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap" }}>
                  <code style={{ color: "#fecdd3", fontSize: 12, fontWeight: 900 }}>{entry.report_code}</code>
                  <span style={{ color: "#9ca3af", fontSize: 9 }}>{dateLabel(entry.reported_at)} · 만료 {dateLabel(entry.expires_at)}</span>
                </div>
                <p style={{ margin: "8px 0 4px", color: "#fff1f2", fontSize: 11, lineHeight: 1.65, whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{entry.error_message}</p>
                <div style={{ color: "#fda4af", fontSize: 9 }}>행동: {entry.action}{entry.error_code ? " · 오류 코드: " + entry.error_code : ""}</div>
                <JsonDetails title="오류 발생 시점의 추가 정보" value={entry.context} />
              </article>)}
            </section>}
            <section style={{ display: "grid", gap: 7 }}>
              <h3 style={{ margin: 0, color: "#bfdbfe", fontSize: 12 }}>행동 기록 ({(result.events || []).length}개)</h3>
              {!(result.events || []).length && <p style={{ color: "#94a3b8", fontSize: 10 }}>보관 중인 행동 기록이 없습니다.</p>}
              {(result.events || []).map((entry) => <article key={entry.id} style={{ padding: 9, border: "1px solid rgba(148,163,184,.15)", borderRadius: 7, background: entry.event_type === "error_reported" ? "#1b101b" : "#080d16" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
                  <strong style={{ color: entry.event_type === "error_reported" ? "#fda4af" : "#93c5fd", fontSize: 10 }}>{entry.event_type} · 턴 {entry.turn_number ?? "-"}</strong>
                  <span style={{ color: "#94a3b8", fontSize: 9 }}>{dateLabel(entry.created_at)}</span>
                </div>
                <div style={{ marginTop: 4, color: "#e2e8f0", fontSize: 10 }}>{entry.actor_label || (entry.actor_user_id ? "플레이어" : "시스템")} · {entry.action_label || "행동 정보 없음"}</div>
                <div style={{ color: "#94a3b8", fontSize: 9, marginTop: 3 }}>단계: {entry.phase || "-"} / {entry.turn_step || "-"} · 버전: {entry.state_version ?? "-"}</div>
                <JsonDetails title="행동 전 상태" value={entry.before_state} />
                <JsonDetails title="행동 후 상태" value={entry.after_state} />
                <JsonDetails title="추가 이벤트 정보" value={entry.context} />
              </article>)}
            </section>
          </section>}
        </div>
      </section>
    </div>}
  </>;
}
