import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "../lib/supabase";

const DEFAULT_GREETING = "안녕하세요. 이번 게임 잘 부탁드리겠습니다.";

export default function MatchGreetingStep({ roomId, userId, players = [], onComplete = () => {} }) {
  const [greeting, setGreeting] = useState(null);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [secondsLeft, setSecondsLeft] = useState(30);
  const [showBubbles, setShowBubbles] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const completedSignature = useRef("");
  const onCompleteRef = useRef(onComplete);

  useEffect(() => {
    onCompleteRef.current = onComplete;
  }, [onComplete]);

  const refreshGreeting = useCallback(async () => {
    if (!roomId) return;
    const { data, error: rpcError } = await supabase.rpc("get_private_match_greeting_v1", { p_room_id: roomId });
    if (rpcError) throw rpcError;
    setGreeting(data && typeof data === "object" ? data : null);
    setSecondsLeft(Number(data?.seconds_left ?? 0));
    const myMessage = Number(data?.my_seat) === 1 ? data?.seat1_message : data?.seat2_message;
    setSubmitted(Boolean(myMessage));
  }, [roomId]);

  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        const { data, error: rpcError } = await supabase.rpc("get_private_match_greeting_v1", { p_room_id: roomId });
        if (rpcError) throw rpcError;
        if (!active) return;
        setGreeting(data && typeof data === "object" ? data : null);
        setSecondsLeft(Number(data?.seconds_left ?? 0));
        const myMessage = Number(data?.my_seat) === 1 ? data?.seat1_message : data?.seat2_message;
        setSubmitted(Boolean(myMessage));
      } catch (err) {
        if (active) setError(err?.message || "시작 전 인사 단계를 불러오지 못했습니다.");
      }
    };
    void load();
    const timer = window.setInterval(() => {
      void load();
    }, 1000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [roomId]);

  useEffect(() => {
    if (greeting?.is_ready_for_review) setShowBubbles(true);
    if (!greeting?.is_complete) return;
    const signature = [greeting.seat1_message, greeting.seat2_message, greeting.completed_at].join("|");
    if (completedSignature.current === signature) return;
    completedSignature.current = signature;
    onCompleteRef.current();
  }, [greeting?.is_ready_for_review, greeting?.is_complete, greeting?.seat1_message, greeting?.seat2_message, greeting?.completed_at]);

  async function submitGreeting(event) {
    event.preventDefault();
    if (loading || submitted || !message.trim()) return;
    setLoading(true);
    setError("");
    try {
      const { data, error: rpcError } = await supabase.rpc("submit_private_match_greeting_v1", {
        p_room_id: roomId,
        p_message: message.trim(),
      });
      if (rpcError) throw rpcError;
      setGreeting(data && typeof data === "object" ? data : null);
      setSubmitted(true);
      await refreshGreeting();
    } catch (err) {
      setError(err?.message || "인사말을 전송하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  async function confirmGreeting() {
    if (loading || greeting?.my_confirmed || !greeting?.is_ready_for_review) return;
    setLoading(true);
    setError("");
    try {
      const { data, error: rpcError } = await supabase.rpc("confirm_private_match_greeting_v1", {
        p_room_id: roomId,
      });
      if (rpcError) throw rpcError;
      setGreeting(data && typeof data === "object" ? data : null);
    } catch (err) {
      setError(err?.message || "인사말 확인을 처리하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  const mySeat = Number(greeting?.my_seat || players.find((player) => player.user_id === userId)?.seat || 1);
  const myName = mySeat === 1 ? greeting?.seat1_name : greeting?.seat2_name;
  const opponentName = mySeat === 1 ? greeting?.seat2_name : greeting?.seat1_name;
  const myDisplayName = myName || players.find((player) => player.user_id === userId)?.temporary_nickname || "나";
  const opponentDisplayName = opponentName || "상대";

  return (
    <main style={{ minHeight: "100dvh", display: "grid", placeItems: "center", padding: 18, background: "#080d17", color: "#e8edf7", fontFamily: 'Inter, Pretendard, "Noto Sans KR", sans-serif' }}>
      <section style={{ width: "min(100%, 660px)", padding: "clamp(20px,4vw,34px)", border: "1px solid rgba(147,197,253,.35)", borderRadius: 16, background: "linear-gradient(155deg,#152238,#0b1220)", boxShadow: "0 24px 80px rgba(0,0,0,.45)" }}>
        <div style={{ color: "#93c5fd", fontSize: 10, fontWeight: 900, letterSpacing: ".18em" }}>BEFORE THE MATCH</div>
        <h1 style={{ margin: "8px 0 5px", fontSize: 24, fontWeight: 950 }}>게임 시작 전 인사</h1>
        <p style={{ margin: 0, color: "#9aa8bd", fontSize: 12, lineHeight: 1.7 }}>서로 인사말을 한마디씩 남겨 주세요. 최대 140자이며, 30초가 지나면 입력하지 않은 쪽은 기본 인사말로 처리됩니다.</p>
        {showBubbles ? (
          <div style={{ display: "grid", gap: 12, marginTop: 24 }}>
            <div style={{ justifySelf: "start", maxWidth: "85%" }}><div style={{ margin: "0 0 4px 7px", color: "#93c5fd", fontSize: 11, fontWeight: 800 }}>{greeting?.seat1_name || "플레이어 1"}</div><div style={{ padding: "12px 15px", borderRadius: "15px 15px 15px 3px", background: "#1e3a5f", border: "1px solid rgba(147,197,253,.35)", fontSize: 13, lineHeight: 1.7 }}>{greeting?.seat1_message || DEFAULT_GREETING}</div></div>
            <div style={{ justifySelf: "end", maxWidth: "85%" }}><div style={{ margin: "0 7px 4px 0", textAlign: "right", color: "#fcd34d", fontSize: 11, fontWeight: 800 }}>{greeting?.seat2_name || "플레이어 2"}</div><div style={{ padding: "12px 15px", borderRadius: "15px 15px 3px 15px", background: "#3a2d19", border: "1px solid rgba(252,211,77,.32)", fontSize: 13, lineHeight: 1.7 }}>{greeting?.seat2_message || DEFAULT_GREETING}</div></div>
            <div style={{ display: "grid", gap: 10, marginTop: 8, paddingTop: 14, borderTop: "1px solid rgba(255,255,255,.08)" }}>
              <p style={{ margin: 0, textAlign: "center", color: "#cbd5e1", fontSize: 11, lineHeight: 1.6 }}>
                내 확인: {greeting?.my_confirmed ? "완료" : "아직"} · 상대 확인: {greeting?.opponent_confirmed ? "완료" : "대기 중"}
              </p>
              {greeting?.my_confirmed ? (
                <p style={{ margin: 0, textAlign: "center", color: "#86efac", fontSize: 11 }}>인사말을 확인했습니다. 상대 플레이어의 확인을 기다리고 있습니다.</p>
              ) : (
                <button type="button" disabled={loading} onClick={() => void confirmGreeting()} style={{ justifySelf: "center", border: "1px solid rgba(134,239,172,.38)", borderRadius: 8, padding: "10px 22px", background: "#166534", color: "#f0fdf4", fontSize: 12, fontWeight: 850, opacity: loading ? .6 : 1 }}>
                  {loading ? "확인 중…" : "인사말 확인"}
                </button>
              )}
            </div>
          </div>
        ) : (
          <form onSubmit={submitGreeting} style={{ marginTop: 22 }}>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 10, marginBottom: 6, color: "#cbd5e1", fontSize: 11 }}><label htmlFor="match-greeting-message">{myDisplayName}의 인사말</label><span>{message.length}/140자 · 남은 시간 {secondsLeft}초</span></div>
            {submitted ? (
              <div style={{ padding: 13, borderRadius: 9, border: "1px solid rgba(134,239,172,.25)", background: "rgba(22,101,52,.12)", color: "#86efac", fontSize: 12, lineHeight: 1.7 }}>인사말을 전송했습니다. 상대의 인사말 또는 30초 제한 시간이 끝나면 공개됩니다.</div>
            ) : (
              <>
                <textarea id="match-greeting-message" value={message} maxLength={140} rows={3} onChange={(event) => setMessage(event.target.value)} placeholder={DEFAULT_GREETING} style={{ boxSizing: "border-box", width: "100%", resize: "vertical", padding: 12, borderRadius: 9, border: "1px solid rgba(148,163,184,.28)", background: "#070c14", color: "#e8edf7", fontSize: 13, lineHeight: 1.6, outline: "none" }} />
                <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8 }}><button type="submit" disabled={loading || !message.trim() || secondsLeft <= 0} style={{ border: "1px solid rgba(147,197,253,.38)", borderRadius: 8, padding: "10px 16px", background: "#1d4ed8", color: "white", fontSize: 12, fontWeight: 850, opacity: loading || !message.trim() || secondsLeft <= 0 ? .55 : 1 }}>{loading ? "전송 중…" : "인사말 전송"}</button></div>
              </>
            )}
          </form>
        )}
        {error && <p role="alert" style={{ marginTop: 12, color: "#fda4af", fontSize: 11 }}>{error}</p>}
      </section>
    </main>
  );
}
