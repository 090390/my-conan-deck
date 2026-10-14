import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

function asNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function promptEvidenceCount(defaultValue, label = "증거 장수") {
  const value = window.prompt(`${label}를 입력하세요 (1~12).`, String(defaultValue));
  if (value === null) return null;
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n) || n < 1 || n > 12) {
    window.alert("증거 장수는 1~12 사이의 정수로 입력해 주세요.");
    return null;
  }
  return n;
}

export default function MatchTurnBoard({ roomId, userId, cards = [] }) {
  const [game, setGame] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [selectedNextHint, setSelectedNextHint] = useState("");
  const [selectedAttacker, setSelectedAttacker] = useState("");

  const cardsByKey = useMemo(
    () => new Map(cards.map((card) => [String(card.key), card])),
    [cards]
  );

  const refresh = useCallback(async () => {
    if (!roomId) return;
    const { data, error: rpcError } = await supabase.rpc("get_private_turn_state", {
      p_room_id: roomId,
    });
    if (rpcError) throw rpcError;
    setGame(data && typeof data === "object" ? data : null);
    setSelectedNextHint((current) => {
      const hand = Array.isArray(data?.my_hand) ? data.my_hand : [];
      const myBoardNow = (data?.boards || []).find((board) => board.user_id === userId);
      if (current === "__FILE_TOP__") return asNumber(myBoardNow?.file_count) > 0 ? current : "";
      return hand.some((card) => card.instance_id === current) ? current : "";
    });
    setSelectedAttacker((current) => {
      const myBoard = (data?.boards || []).find((board) => board.user_id === userId);
      return myBoard?.field_cards?.some((card) => card.instance_id === current && !card.rested) ? current : "";
    });
  }, [roomId, userId]);

  useEffect(() => {
    if (!roomId) return undefined;
    let active = true;
    const load = async () => {
      try {
        const { data, error: rpcError } = await supabase.rpc("get_private_turn_state", {
          p_room_id: roomId,
        });
        if (rpcError) throw rpcError;
        if (active) setGame(data && typeof data === "object" ? data : null);
      } catch (err) {
        if (active) setError(err?.message || "턴 상태를 불러오지 못했습니다.");
      }
    };
    void load();
    const channel = supabase
      .channel(`room-turn-board-${roomId}`)
      .on("postgres_changes", {
        event: "*", schema: "public", table: "room_match_states", filter: `room_id=eq.${roomId}`,
      }, () => void load())
      .on("postgres_changes", {
        event: "*", schema: "public", table: "room_player_turn_boards", filter: `room_id=eq.${roomId}`,
      }, () => void load())
      .subscribe((status) => {
        if (active && (status === "CHANNEL_ERROR" || status === "TIMED_OUT")) {
          setError("실시간 보드 연결에 문제가 있습니다. 새로고침 후 상태를 확인해 주세요.");
        }
      });
    return () => {
      active = false;
      void supabase.removeChannel(channel);
    };
  }, [roomId]);

  const runAction = useCallback(async (action, payload = {}) => {
    if (loading) return;
    setLoading(true);
    setError("");
    setNotice("");
    try {
      const { data, error: rpcError } = await supabase.rpc("perform_private_turn_action", {
        p_room_id: roomId,
        p_action: action,
        p_payload: payload,
      });
      if (rpcError) throw rpcError;
      if (data && typeof data === "object") {
        setGame(data);
        setSelectedNextHint((current) => {
          const hand = Array.isArray(data.my_hand) ? data.my_hand : [];
          const myBoardNow = (data.boards || []).find((board) => board.user_id === userId);
          if (action === "next_hint") return "";
          if (current === "__FILE_TOP__") return asNumber(myBoardNow?.file_count) > 0 ? current : "";
          return hand.some((card) => card.instance_id === current) ? current : "";
        });
        setNotice(data.last_action_label || "행동을 적용했습니다.");
      } else {
        await refresh();
      }
      setSelectedAttacker("");
    } catch (err) {
      setError(err?.message || "행동을 처리하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }, [roomId, loading, refresh]);

  const boards = Array.isArray(game?.boards) ? game.boards : [];
  const myBoard = boards.find((board) => board.user_id === userId);
  const opponentBoard = boards.find((board) => board.user_id !== userId);
  const currentTurnBoard = boards.find((board) => board.user_id === game?.current_turn_user_id);
  const myHand = Array.isArray(game?.my_hand) ? game.my_hand : [];
  const isMyTurn = game?.current_turn_user_id === userId;
  const firstPlayerUserId = game?.first_player_user_id;
  const winEvidenceThreshold = firstPlayerUserId === userId ? 7 : 6;
  const solutionFileThreshold = firstPlayerUserId === userId ? 7 : 6;
  const pending = game?.pending_action || null;
  const pendingIsForMe = pending?.target_user_id === userId;
  const actionBlockedByPending = Boolean(pending);
  const costLimit = asNumber(myBoard?.file_count) + (myBoard?.partner_assist_used ? 1 : 0);
  const styles = {
    panel: { marginTop: 16, padding: 16, border: "1px solid rgba(255,255,255,.10)", borderRadius: 12, background: "#0b1220", color: "#e8edf7" },
    button: { border: "1px solid rgba(255,255,255,.12)", borderRadius: 8, padding: "8px 11px", background: "#263d63", color: "white", cursor: loading ? "wait" : "pointer", fontSize: 12, fontWeight: 750, opacity: loading ? 0.6 : 1 },
    smallButton: { border: "1px solid rgba(255,255,255,.12)", borderRadius: 7, padding: "6px 8px", background: "#17243a", color: "#dbe4f1", cursor: loading ? "wait" : "pointer", fontSize: 11, fontWeight: 700, opacity: loading ? 0.6 : 1 },
    subPanel: { padding: 12, border: "1px solid rgba(255,255,255,.08)", borderRadius: 10, background: "#101827", minWidth: 0 },
    muted: { color: "#9aa8bd", fontSize: 11, lineHeight: 1.6 },
    card: { padding: 8, border: "1px solid rgba(255,255,255,.09)", borderRadius: 9, background: "#0d1524", minWidth: 0 },
  };

  function cardInfo(instance) {
    return cardsByKey.get(String(instance?.key)) || null;
  }

  function displayCardName(instance) {
    const info = cardInfo(instance);
    return info?.name || instance?.key || "알 수 없는 카드";
  }

  function renderCardThumb(instance, { showActions = false } = {}) {
    const info = cardInfo(instance);
    const isFileStep = game?.turn_step === "file" && isMyTurn && !game?.game_over;
    const canMainAct = game?.turn_step === "main" && isMyTurn && !game?.game_over && !actionBlockedByPending;
    const isCharacter = instance.card_type === "character";
    const isEvent = instance.card_type === "event";
    const canPlay = canMainAct && isCharacter && !myBoard?.character_played_this_turn && asNumber(instance.cost) <= costLimit;
    const canEvent = canMainAct && isEvent;
    const selectedForNext = selectedNextHint === instance.instance_id;
    return (
      <div key={instance.instance_id} style={styles.card}>
        {info?.imageUrl ? <img src={info.imageUrl} alt={info.name || "카드"} style={{ display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 6, background: "#080d16" }} /> : <div style={{ width: "100%", aspectRatio: "3 / 4", display: "grid", placeItems: "center", background: "#080d16", color: "#74839a", fontSize: 10 }}>이미지 없음</div>}
        <div style={{ marginTop: 6, fontSize: 11, lineHeight: 1.4, fontWeight: 750, overflowWrap: "anywhere" }}>{displayCardName(instance)}</div>
        <div style={{ marginTop: 4, fontSize: 10, color: "#9aa8bd" }}>코스트 {instance.cost ?? info?.cost ?? "-"} · AP {instance.ap ?? info?.ap ?? "-"} · LP {instance.lp ?? info?.lp ?? "-"}</div>
        {showActions && (
          <div style={{ display: "grid", gap: 5, marginTop: 8 }}>
            {isFileStep && <button type="button" style={styles.smallButton} disabled={loading} onClick={() => void runAction("place_file", { instance_id: instance.instance_id })}>파일에 놓기</button>}
            {canPlay && <button type="button" style={styles.smallButton} disabled={loading} onClick={() => void runAction("play_character", { instance_id: instance.instance_id })}>캐릭터 출동</button>}
            {canEvent && <button type="button" style={styles.smallButton} disabled={loading} onClick={() => void runAction("use_event", { instance_id: instance.instance_id })}>이벤트 사용</button>}
            {canMainAct && isCharacter && !myBoard?.character_played_this_turn && asNumber(instance.cost) <= costLimit && (
              <button type="button" style={{ ...styles.smallButton, borderColor: selectedForNext ? "#fb7185" : "rgba(255,255,255,.12)", color: selectedForNext ? "#fda4af" : "#dbe4f1" }} disabled={loading || !myBoard?.file_count} onClick={() => setSelectedNextHint(selectedForNext ? "" : instance.instance_id)}>{selectedForNext ? "넥스트 힌트 선택됨" : "넥스트 힌트 출동 선택"}</button>
            )}
          </div>
        )}
      </div>
    );
  }

  function askAndInvestigate(instance) {
    const base = Math.max(1, Math.min(12, asNumber(instance.lp, 1) || 1));
    const amount = promptEvidenceCount(base, "추리로 얻을 증거 장수");
    if (amount !== null) void runAction("investigate", { instance_id: instance.instance_id, evidence_count: amount });
  }

  function askPartnerDeduction() {
    const partner = cardInfo({ key: myBoard?.partner_key });
    const base = Math.max(1, Math.min(12, asNumber(partner?.lp, 1) || 1));
    const amount = promptEvidenceCount(base, "파트너 추리로 얻을 증거 장수");
    if (amount !== null) void runAction("partner_deduce", { evidence_count: amount });
  }

  if (!game) return <div style={styles.panel}><p style={styles.muted}>게임 보드를 불러오는 중...</p>{error && <p role="alert" style={{ color: "#fda4af" }}>{error}</p>}</div>;

  const canActMain = isMyTurn && game.turn_step === "main" && !game.game_over && !pending;
  const myFileTarget = asNumber(myBoard?.files_to_place);
  const myFilesPlaced = asNumber(myBoard?.files_placed_this_turn);

  return (
    <section style={styles.panel}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div style={{ color: "#93c5fd", fontSize: 10, fontWeight: 850, letterSpacing: ".16em" }}>LIVE MATCH</div>
          <h3 style={{ margin: "5px 0 6px", fontSize: 19, fontWeight: 850 }}>실제 턴 진행</h3>
          <p style={styles.muted}>턴 {game.turn_number} · {game.case_phase === "solution" ? "해결편" : "사건편"} · {game.current_turn_user_id === userId ? "내 차례" : "상대 차례"}</p>
        </div>
        <span style={{ padding: "6px 9px", border: "1px solid rgba(147,197,253,.25)", borderRadius: 8, color: "#93c5fd", fontSize: 11, fontWeight: 750 }}>
          {game.game_over ? "대전 종료" : game.turn_step === "begin" ? "턴 시작" : game.turn_step === "file" ? `파일 배치 ${currentTurnBoard?.files_placed_this_turn ?? 0}/${currentTurnBoard?.files_to_place ?? 0}` : "메인 단계"}
        </span>
      </div>

      {game.game_over && (
        <div role="status" style={{ marginTop: 12, padding: 12, borderRadius: 9, border: "1px solid rgba(134,239,172,.25)", background: "rgba(34,197,94,.08)", color: "#86efac", fontWeight: 800 }}>
          {game.winner_user_id === userId ? "승리했습니다!" : "상대 플레이어가 승리했습니다."}
        </div>
      )}

      {pending && (
        <div style={{ marginTop: 12, padding: 12, border: "1px solid rgba(251,191,36,.25)", borderRadius: 9, background: "rgba(245,158,11,.07)" }}>
          <strong style={{ color: "#fcd34d", fontSize: 12 }}>증거 공격 응답</strong>
          {pendingIsForMe ? (
            <>
              <p style={{ ...styles.muted, margin: "6px 0 10px" }}>상대가 내 증거 영역을 공격했습니다. 액티브 캐릭터로 가드하거나 가드하지 않을 수 있습니다.</p>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                {(myBoard?.field_cards || []).filter((card) => !card.rested).map((card) => (
                  <button key={card.instance_id} type="button" style={styles.smallButton} disabled={loading || game.game_over} onClick={() => void runAction("guard_with_character", { instance_id: card.instance_id })}>
                    {displayCardName(card)}로 가드 (AP {asNumber(card.ap) + asNumber(card.ap_bonus)})
                  </button>
                ))}
                <button type="button" style={{ ...styles.button, background: "#7f1d1d" }} disabled={loading || game.game_over} onClick={() => void runAction("decline_guard")}>가드하지 않기</button>
              </div>
            </>
          ) : <p style={{ ...styles.muted, margin: "6px 0 0" }}>상대가 가드 여부를 선택할 때까지 행동할 수 없습니다.</p>}
        </div>
      )}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(230px, 1fr))", gap: 10, marginTop: 14 }}>
        {[{ board: myBoard, mine: true }, { board: opponentBoard, mine: false }].map(({ board, mine }) => {
          if (!board) return null;
          const partner = cardInfo({ key: board.partner_key });
          const event = cardInfo({ key: board.event_key });
          return (
            <div key={board.user_id} style={styles.subPanel}>
              <h4 style={{ margin: "0 0 8px", fontSize: 13, fontWeight: 850 }}>{mine ? "내 보드" : "상대 보드"}{board.user_id === firstPlayerUserId ? " · 선공" : " · 후공"}</h4>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(4, minmax(0,1fr))", gap: 5 }}>
                {[["손패", board.hand_count], ["덱", board.deck_count], ["파일", board.file_count], ["증거", board.evidence_count], ["리무브", board.remove_count]].map(([label, count]) => (
                  <div key={label} style={{ padding: "7px 5px", borderRadius: 7, background: "#080d16", textAlign: "center" }}>
                    <div style={{ fontSize: 9, color: "#8796ac" }}>{label}</div><div style={{ marginTop: 2, fontSize: 15, fontWeight: 850, fontVariantNumeric: "tabular-nums" }}>{count ?? 0}</div>
                  </div>
                ))}
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginTop: 10 }}>
                <div style={{ borderRadius: 8, background: "#080d16", padding: 8 }}>
                  <div style={{ fontSize: 10, color: "#fcd34d", fontWeight: 800 }}>파트너 {board.partner_rested ? "· 슬립" : "· 액티브"}</div>
                  {partner?.imageUrl && <img src={partner.imageUrl} alt={partner.name} style={{ display: "block", width: "100%", maxHeight: 120, objectFit: "contain", marginTop: 5 }} />}
                  <div style={{ fontSize: 10, marginTop: 4, overflowWrap: "anywhere" }}>{partner?.name || board.partner_key}</div>
                  {mine && canActMain && !board.partner_rested && (
                    <div style={{ display: "grid", gap: 5, marginTop: 7 }}>
                      <button type="button" style={styles.smallButton} disabled={loading || board.next_hint_used} onClick={() => void runAction("partner_assist")}>어시스트 (+코스트 1)</button>
                      <button type="button" style={styles.smallButton} disabled={loading} onClick={askPartnerDeduction}>파트너 추리</button>
                    </div>
                  )}
                </div>
                <div style={{ borderRadius: 8, background: "#080d16", padding: 8 }}>
                  <div style={{ fontSize: 10, color: "#7dd3fc", fontWeight: 800 }}>사건 카드</div>
                  {event?.imageUrl && <img src={event.imageUrl} alt={event.name} style={{ display: "block", width: "100%", maxHeight: 120, objectFit: "contain", marginTop: 5 }} />}
                  <div style={{ fontSize: 10, marginTop: 4, overflowWrap: "anywhere" }}>{event?.name || board.event_key}</div>
                </div>
              </div>
              <div style={{ marginTop: 10 }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 8, alignItems: "center" }}><strong style={{ fontSize: 11 }}>현장 ({board.field_cards?.length || 0})</strong><span style={styles.muted}>액티브/슬립 상태 공개</span></div>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(110px, 1fr))", gap: 6, marginTop: 7 }}>
                  {(board.field_cards || []).map((fieldCard) => {
                    const selected = selectedAttacker === fieldCard.instance_id;
                    const canChooseAttack = !mine && canActMain && selectedAttacker;
                    return (
                      <div key={fieldCard.instance_id} style={{ border: selected ? "1px solid #fb7185" : "1px solid rgba(255,255,255,.08)", borderRadius: 8, padding: 7, background: "#080d16", minWidth: 0 }}>
                        {cardInfo(fieldCard)?.imageUrl && <img src={cardInfo(fieldCard).imageUrl} alt={displayCardName(fieldCard)} style={{ display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5 }} />}
                        <div style={{ marginTop: 5, fontSize: 10, fontWeight: 800, lineHeight: 1.4, overflowWrap: "anywhere" }}>{displayCardName(fieldCard)}</div>
                        <div style={{ marginTop: 3, fontSize: 9, color: "#9aa8bd" }}>AP {asNumber(fieldCard.ap) + asNumber(fieldCard.ap_bonus)} · {fieldCard.rested ? "슬립" : "액티브"}</div>
                        {mine && canActMain && !fieldCard.rested && (
                          <div style={{ display: "grid", gap: 4, marginTop: 6 }}>
                            <button type="button" style={styles.smallButton} disabled={loading} onClick={() => askAndInvestigate(fieldCard)}>추리</button>
                            <button type="button" style={{ ...styles.smallButton, borderColor: selected ? "#fb7185" : "rgba(255,255,255,.12)" }} disabled={loading} onClick={() => setSelectedAttacker(selected ? "" : fieldCard.instance_id)}>{selected ? "공격자 선택 해제" : "공격자로 선택"}</button>
                            <button type="button" style={styles.smallButton} disabled={loading || !opponentBoard?.evidence_count} onClick={() => void runAction("attack_evidence", { attacker_instance_id: fieldCard.instance_id, target_user_id: opponentBoard?.user_id })}>상대 증거 공격</button>
                          </div>
                        )}
                        {canChooseAttack && <button type="button" style={{ ...styles.smallButton, width: "100%", marginTop: 6, borderColor: "#fb7185", color: "#fda4af" }} disabled={loading} onClick={() => void runAction("attack_character", { attacker_instance_id: selectedAttacker, target_user_id: board.user_id, target_instance_id: fieldCard.instance_id })}>이 캐릭터 공격</button>}
                      </div>
                    );
                  })}
                  {!board.field_cards?.length && <p style={styles.muted}>현장에 캐릭터가 없습니다.</p>}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      <div style={{ ...styles.subPanel, marginTop: 10 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
          <h4 style={{ margin: 0, fontSize: 13, fontWeight: 850 }}>내 손패 ({myHand.length}장)</h4>
          <span style={styles.muted}>파일/증거의 카드 앞면과 덱 순서는 공개하지 않습니다.</span>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(112px, 1fr))", gap: 7, marginTop: 9 }}>
          {myHand.map((handCard) => renderCardThumb(handCard, { showActions: !game.game_over }))}
          {!myHand.length && <p style={styles.muted}>손패가 비어 있습니다.</p>}
        </div>
      </div>

      {!game.game_over && game.turn_step === "begin" && (
        <div style={{ marginTop: 12 }}>
          {isMyTurn ? <button type="button" style={styles.button} disabled={loading || actionBlockedByPending} onClick={() => void runAction("begin_turn")}>턴 시작 · 액티브화 · 1장 드로우</button> : <p style={styles.muted}>현재 플레이어가 턴 시작을 진행할 때까지 기다려 주세요.</p>}
        </div>
      )}

      {!game.game_over && game.turn_step === "file" && (
        <div style={{ marginTop: 12, padding: 10, borderRadius: 8, border: "1px solid rgba(147,197,253,.2)", background: "rgba(59,130,246,.06)" }}>
          <strong style={{ fontSize: 12, color: "#93c5fd" }}>필수 파일 배치: {myFilesPlaced}/{myFileTarget}</strong>
          <p style={{ ...styles.muted, margin: "5px 0 0" }}>{isMyTurn ? "손패에서 파일에 놓을 카드를 선택하세요." : "상대가 필수 파일 배치를 마칠 때까지 기다려 주세요."}</p>
        </div>
      )}

      {!game.game_over && game.turn_step === "main" && isMyTurn && !pending && (
        <div style={{ marginTop: 12, display: "flex", gap: 7, flexWrap: "wrap" }}>
          <button type="button" style={styles.button} disabled={loading || !myBoard?.file_count || myBoard?.character_played_this_turn || !selectedNextHint} onClick={() => void runAction("next_hint", { instance_id: selectedNextHint })}>넥스트 힌트 · 선택 캐릭터 출동</button>
          <button type="button" style={styles.button} disabled={loading || !myBoard?.file_count || myBoard?.character_played_this_turn} onClick={() => void runAction("next_hint", { instance_id: "__FILE_TOP__" })}>파일 맨 위 카드로 넥스트 힌트</button>
          <span style={{ ...styles.muted, alignSelf: "center" }}>현재 출동 코스트 상한: {costLimit} · 캐릭터 출동 {myBoard?.character_played_this_turn ? "완료" : "미사용"}</span>
          {game.case_phase === "incident" && myBoard?.file_count >= solutionFileThreshold && (
            <button type="button" style={{ ...styles.button, background: "#854d0e" }} disabled={loading} onClick={() => void runAction("declare_solution")}>해결편으로 전환</button>
          )}
          {game.case_phase === "solution" && myBoard?.evidence_count >= winEvidenceThreshold && (
            <button type="button" style={{ ...styles.button, background: "#166534" }} disabled={loading} onClick={() => void runAction("solve_case")}>사건 해결 선언 · 승리</button>
          )}
          <button type="button" style={{ ...styles.button, background: "#4b2637" }} disabled={loading || actionBlockedByPending} onClick={() => void runAction("end_turn")}>턴 종료</button>
        </div>
      )}

      {game.last_action_label && <p role="status" style={{ margin: "12px 0 0", color: "#86efac", fontSize: 12, lineHeight: 1.6 }}>{game.last_action_label}</p>}
      {notice && <p role="status" style={{ margin: "8px 0 0", color: "#86efac", fontSize: 12, lineHeight: 1.6 }}>{notice}</p>}
      {error && <p role="alert" style={{ margin: "8px 0 0", color: "#fda4af", fontSize: 12, lineHeight: 1.6, overflowWrap: "anywhere" }}>오류: {error}</p>}
      <p style={{ ...styles.muted, marginTop: 12, borderTop: "1px solid rgba(255,255,255,.07)", paddingTop: 10 }}>
        현재 자동화 범위: 기본 턴 순서, 영역 이동, 코스트/횟수 제한, AP 비교, 가드 선택, 파일/증거 장수, 해결편 전환과 승리 조건. 카드 고유 효과와 컷인 보정은 아직 자동 적용하지 않으므로 카드 텍스트에 따라 수동 처리해야 합니다.
      </p>
    </section>
  );
}
