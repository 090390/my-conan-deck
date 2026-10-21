import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import MatchTurnBoard from "./MatchTurnBoard";

function canLeaveBeforeMulligan(matchState) {
  const phase = String(matchState?.phase || "waiting").toLocaleLowerCase();
  if (phase === "waiting") return true;
  return phase === "mulligan"
    && matchState?.seat1_mulligan_done !== true
    && matchState?.seat2_mulligan_done !== true;
}

export default function MatchStartFlow({
  roomId,
  userId,
  players = [],
  cards = [],
  inviteCode = "",
  onReturnToLobby = null,
  onPhaseChange = () => {},
}) {
  const [matchState, setMatchState] = useState(null);
  const [selectedInstanceIds, setSelectedInstanceIds] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const cardsByKey = useMemo(
    () => new Map(cards.map((card) => [String(card.key), card])),
    [cards]
  );

  const refreshState = useCallback(async () => {
    if (!roomId) return;
    const { data, error: rpcError } = await supabase.rpc("get_private_match_state", {
      p_room_id: roomId,
    });
    if (rpcError) throw rpcError;

    const normalized = data && typeof data === "object"
      ? { ...data, phase: data.phase || "waiting", my_hand: Array.isArray(data.my_hand) ? data.my_hand : [] }
      : { phase: "waiting", my_hand: [] };

    setMatchState(normalized);
    onPhaseChange(normalized.phase, canLeaveBeforeMulligan(normalized));
    setSelectedInstanceIds((current) => current.filter((id) =>
      normalized.my_hand.some((card) => card.instance_id === id)
    ));
  }, [roomId, onPhaseChange]);

  useEffect(() => {
    if (!roomId) return undefined;
    let active = true;

    const load = async () => {
      try {
        const { data, error: rpcError } = await supabase.rpc("get_private_match_state", {
          p_room_id: roomId,
        });
        if (rpcError) throw rpcError;
        if (!active) return;
        const normalized = data && typeof data === "object"
          ? { ...data, phase: data.phase || "waiting", my_hand: Array.isArray(data.my_hand) ? data.my_hand : [] }
          : { phase: "waiting", my_hand: [] };
        setMatchState(normalized);
        onPhaseChange(normalized.phase, canLeaveBeforeMulligan(normalized));
        setSelectedInstanceIds((current) => current.filter((id) =>
          normalized.my_hand.some((card) => card.instance_id === id)
        ));
      } catch (err) {
        if (active) setError(err?.message || "게임 진행 상태를 불러오지 못했습니다.");
      }
    };

    void load();
    const channel = supabase
      .channel(`room-match-state-${roomId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "room_match_states",
          filter: `room_id=eq.${roomId}`,
        },
        () => { void load(); }
      )
      .subscribe((status) => {
        if (active && (status === "CHANNEL_ERROR" || status === "TIMED_OUT")) {
          setError("게임 실시간 연결에 문제가 있습니다. 새로고침 후 다시 확인해 주세요.");
        }
      });

    return () => {
      active = false;
      void supabase.removeChannel(channel);
    };
  }, [roomId, onPhaseChange]);

  async function runAction(action) {
    if (loading) return;
    setLoading(true);
    setError("");
    setNotice("");
    try {
      await action();
      await refreshState();
    } catch (err) {
      setError(err?.message || "요청을 처리하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  function startMatch() {
    return runAction(async () => {
      const { error: rpcError } = await supabase.rpc("start_private_match", {
        p_room_id: roomId,
      });
      if (rpcError) throw rpcError;
      setNotice("선후공 결정, 덱 셔플, 시작 손패 5장 배분을 완료했습니다.");
    });
  }

  function submitMulligan() {
    return runAction(async () => {
      const { error: rpcError } = await supabase.rpc("submit_private_mulligan", {
        p_room_id: roomId,
        p_return_instance_ids: selectedInstanceIds,
      });
      if (rpcError) throw rpcError;
      setSelectedInstanceIds([]);
      setNotice("멀리건 선택을 확정했습니다.");
    });
  }

  const phase = matchState?.phase || "waiting";
  const allReady = players.length === 2 && players.every((player) => player.is_ready === true);
  const myHand = matchState?.my_hand || [];
  const myMulliganDone = matchState?.my_mulligan_done === true;
  const seat1Done = matchState?.seat1_mulligan_done === true;
  const seat2Done = matchState?.seat2_mulligan_done === true;

  const sectionStyle = {
    marginTop: 16,
    padding: 16,
    border: "1px solid rgba(255,255,255,.10)",
    borderRadius: 12,
    background: "#0b1220",
  };
  const buttonStyle = {
    border: "1px solid rgba(255,255,255,.12)",
    borderRadius: 9,
    padding: "10px 14px",
    background: "#2563eb",
    color: "#fff",
    cursor: loading ? "wait" : "pointer",
    fontSize: 13,
    fontWeight: 750,
    opacity: loading ? 0.65 : 1,
  };

  return (
    <div style={sectionStyle}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div style={{ color: "#93c5fd", fontSize: 10, fontWeight: 850, letterSpacing: ".16em" }}>MATCH SETUP</div>
          <h3 style={{ margin: "5px 0 6px", fontSize: 17, fontWeight: 850, color: "#e8edf7" }}>
            {phase === "waiting" ? "게임 시작 준비" : phase === "mulligan" ? "시작 손패 · 멀리건" : "멀리건 완료"}
          </h3>
          <p style={{ margin: 0, fontSize: 12, lineHeight: 1.7, color: "#9aa8bd" }}>
            {phase === "waiting"
              ? "서버에서 선공을 무작위로 정하고, 각자 덱을 셔플한 뒤 시작 손패 5장을 배분합니다."
              : phase === "mulligan"
                ? "교체할 카드를 선택하세요. 선택한 카드는 덱에 돌려 섞고, 같은 장수만큼 새 카드를 뽑습니다."
                : "양쪽 멀리건이 끝났습니다. 선공 플레이어부터 첫 턴을 시작합니다."}
          </p>
        </div>
        <span style={{ border: "1px solid rgba(147,197,253,.22)", borderRadius: 7, padding: "5px 8px", color: "#93c5fd", fontSize: 11, fontWeight: 750 }}>
          {phase === "waiting" ? "1 / 3 · 시작" : phase === "mulligan" ? "2 / 3 · 멀리건" : "3 / 3 · 완료"}
        </span>
      </div>

      {phase === "waiting" && (
        <div style={{ marginTop: 14 }}>
          <button type="button" style={buttonStyle} disabled={!allReady || loading} onClick={startMatch}>
            {loading ? "게임 준비 중..." : "선후공 결정 · 덱 셔플 · 손패 5장 배분"}
          </button>
          {!allReady && <p style={{ color: "#fda4af", fontSize: 12 }}>두 플레이어 모두 준비 완료해야 시작할 수 있습니다.</p>}
        </div>
      )}

      {phase !== "waiting" && (
        <div style={{ marginTop: 12, display: "flex", flexWrap: "wrap", gap: 8 }}>
          <span style={{ background: "rgba(147,197,253,.10)", border: "1px solid rgba(147,197,253,.22)", borderRadius: 7, padding: "7px 9px", color: "#93c5fd", fontSize: 12, fontWeight: 800 }}>
            내 역할: {matchState?.first_player_user_id ? (matchState.first_player_user_id === userId ? "선공" : "후공") : "결정 중"}
          </span>
          <span style={{ background: "rgba(255,255,255,.05)", borderRadius: 7, padding: "7px 9px", color: "#dbe4f1", fontSize: 12 }}>
            내 덱: {matchState?.my_deck_count ?? "-"}장
          </span>
          {matchState?.my_partner_key && <span style={{ background: "rgba(251,191,36,.10)", borderRadius: 7, padding: "7px 9px", color: "#fcd34d", fontSize: 12 }}>파트너 에이리어 준비됨</span>}
          {matchState?.my_event_key && <span style={{ background: "rgba(125,211,252,.10)", borderRadius: 7, padding: "7px 9px", color: "#7dd3fc", fontSize: 12 }}>사건 에이리어 준비됨</span>}
        </div>
      )}

      {phase === "mulligan" && (
        <>
          <div style={{ marginTop: 16, display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, flexWrap: "wrap" }}>
            <h4 style={{ margin: 0, color: "#e8edf7", fontSize: 14 }}>내 시작 손패 ({myHand.length}장)</h4>
            <span style={{ color: "#9aa8bd", fontSize: 11 }}>교체 선택: {selectedInstanceIds.length}장</span>
          </div>
          {myMulliganDone ? (
            <p role="status" style={{ margin: "12px 0 0", color: "#86efac", fontSize: 13 }}>
              멀리건 제출 완료. 상대 플레이어가 선택을 확정할 때까지 기다리고 있습니다.
            </p>
          ) : (
            <>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(112px, 1fr))", gap: 8, marginTop: 10 }}>
                {myHand.map((handCard) => {
                  const card = cardsByKey.get(String(handCard.key));
                  const selected = selectedInstanceIds.includes(handCard.instance_id);
                  return (
                    <button
                      key={handCard.instance_id}
                      type="button"
                      onClick={() => setSelectedInstanceIds((current) =>
                        current.includes(handCard.instance_id)
                          ? current.filter((id) => id !== handCard.instance_id)
                          : [...current, handCard.instance_id]
                      )}
                      disabled={loading}
                      aria-pressed={selected}
                      style={{
                        minWidth: 0,
                        padding: 7,
                        textAlign: "left",
                        border: selected ? "2px solid #fb7185" : "1px solid rgba(255,255,255,.12)",
                        borderRadius: 9,
                        background: selected ? "rgba(244,63,94,.12)" : "#101827",
                        color: "#e8edf7",
                        opacity: loading ? 0.7 : 1,
                      }}
                    >
                      {card?.imageUrl ? (
                        <img src={card.imageUrl} alt={card.name || "카드"} style={{ display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5, background: "#070c14" }} />
                      ) : (
                        <div style={{ display: "grid", placeItems: "center", width: "100%", aspectRatio: "3 / 4", borderRadius: 5, background: "#070c14", color: "#74839a", fontSize: 11 }}>이미지 없음</div>
                      )}
                      <div style={{ marginTop: 7, fontSize: 11, fontWeight: 750, lineHeight: 1.4, overflowWrap: "anywhere" }}>{card?.name || handCard.key}</div>
                      <div style={{ marginTop: 5, fontSize: 10, color: selected ? "#fda4af" : "#9aa8bd" }}>{selected ? "멀리건으로 교체" : "유지"}</div>
                    </button>
                  );
                })}
              </div>
              <button type="button" style={{ ...buttonStyle, marginTop: 13, background: selectedInstanceIds.length ? "#9f1239" : "#166534" }} disabled={loading} onClick={submitMulligan}>
                {loading ? "확정 중..." : selectedInstanceIds.length ? `선택한 ${selectedInstanceIds.length}장 교체하기` : "이 손패 그대로 확정"}
              </button>
            </>
          )}
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 12, fontSize: 11, color: "#aab5c8" }}>
            <span>플레이어 1: {seat1Done ? "멀리건 완료" : "선택 중"}</span>
            <span>·</span>
            <span>플레이어 2: {seat2Done ? "멀리건 완료" : "선택 중"}</span>
          </div>
        </>
      )}

      {phase === "playing" && (
        <MatchTurnBoard roomId={roomId} userId={userId} cards={cards} inviteCode={inviteCode} onReturnToLobby={onReturnToLobby} />
      )}

      {notice && <p role="status" style={{ margin: "12px 0 0", color: "#86efac", fontSize: 12 }}>{notice}</p>}
      {error && <p role="alert" style={{ margin: "12px 0 0", color: "#fda4af", fontSize: 12, overflowWrap: "anywhere" }}>오류: {error}</p>}
    </div>
  );
}
