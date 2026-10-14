import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const C = {
  bg: "#080d17", panel: "#101827", panel2: "#0b1220", border: "rgba(148,163,184,.22)",
  text: "#e8edf7", muted: "#94a3b8", blue: "#93c5fd", red: "#fda4af", green: "#86efac", gold: "#fcd34d",
};

function n(value, fallback = 0) {
  const valueNumber = Number(value);
  return Number.isFinite(valueNumber) ? valueNumber : fallback;
}
function promptCount(label, defaultValue = 1, max = 20) {
  const raw = window.prompt(`${label} (1~${max}장)`, String(defaultValue));
  if (raw === null) return null;
  const value = Math.floor(Number(raw));
  if (!Number.isInteger(value) || value < 1 || value > max) {
    window.alert(`1~${max} 사이의 정수를 입력해 주세요.`);
    return null;
  }
  return value;
}

export default function MatchTurnBoard({ roomId, userId, cards = [], onLeaveField = null }) {
  const [game, setGame] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [selectedNextHint, setSelectedNextHint] = useState("");
  const [selectedAttacker, setSelectedAttacker] = useState("");
  const [allowActiveTargets, setAllowActiveTargets] = useState(false);
  const [showRemoveArea, setShowRemoveArea] = useState(false);
  const [detailCard, setDetailCard] = useState(null);

  const cardsByKey = useMemo(() => new Map(cards.map((card) => [String(card.key), card])), [cards]);

  const refresh = useCallback(async () => {
    if (!roomId) return;
    const { data, error: rpcError } = await supabase.rpc("get_private_turn_state_v2", { p_room_id: roomId });
    if (rpcError) throw rpcError;
    setGame(data && typeof data === "object" ? data : null);
    const hand = Array.isArray(data?.my_hand) ? data.my_hand : [];
    const mine = (data?.boards || []).find((board) => board.user_id === userId);
    setSelectedNextHint((current) => current === "__FILE_TOP__"
      ? (n(mine?.file_count) > 0 ? current : "")
      : (hand.some((card) => card.instance_id === current) ? current : ""));
  }, [roomId, userId]);

  useEffect(() => {
    if (!roomId) return undefined;
    let active = true;
    const load = async () => {
      try {
        const { data, error: rpcError } = await supabase.rpc("get_private_turn_state_v2", { p_room_id: roomId });
        if (rpcError) throw rpcError;
        if (!active) return;
        setGame(data && typeof data === "object" ? data : null);
      } catch (err) {
        if (active) setError(err?.message || "게임 상태를 불러오지 못했습니다.");
      }
    };
    void load();
    const channel = supabase.channel(`room-turn-v2-${roomId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "room_match_states", filter: `room_id=eq.${roomId}` }, () => void load())
      .on("postgres_changes", { event: "*", schema: "public", table: "room_player_turn_boards", filter: `room_id=eq.${roomId}` }, () => void load())
      .on("postgres_changes", { event: "*", schema: "public", table: "room_players", filter: `room_id=eq.${roomId}` }, () => void load())
      .subscribe((status) => {
        if (active && (status === "CHANNEL_ERROR" || status === "TIMED_OUT")) {
          setError("실시간 연결에 문제가 있어요. 새로고침 후 상태를 확인해 주세요.");
        }
      });
    return () => { active = false; void supabase.removeChannel(channel); };
  }, [roomId]);

  const runAction = useCallback(async (action, payload = {}) => {
    if (loading) return;
    setLoading(true); setError(""); setNotice("");
    try {
      const { data, error: rpcError } = await supabase.rpc("perform_private_turn_action_v2", {
        p_room_id: roomId, p_action: action, p_payload: payload,
      });
      if (rpcError) throw rpcError;
      setGame(data && typeof data === "object" ? data : null);
      setNotice(data?.last_action_label || "행동을 반영했습니다.");
      if (action === "next_hint") setSelectedNextHint("");
      if (["attack_character", "attack_evidence", "guard_with_character", "decline_guard"].includes(action)) setSelectedAttacker("");
      if (action === "move_field_card" && payload.owner_user_id === userId) setDetailCard(null);
    } catch (err) {
      setError(err?.message || "행동을 처리하지 못했습니다.");
    } finally { setLoading(false); }
  }, [roomId, userId, loading]);

  const boards = Array.isArray(game?.boards) ? game.boards : [];
  const myBoard = boards.find((board) => board.user_id === userId);
  const opponentBoard = boards.find((board) => board.user_id !== userId);
  const currentTurnBoard = boards.find((board) => board.user_id === game?.current_turn_user_id);
  const myHand = Array.isArray(game?.my_hand) ? game.my_hand : [];
  const myRemoveCards = Array.isArray(game?.my_remove_cards) ? game.my_remove_cards : [];
  const pending = game?.pending_action || null;
  const pendingIsForMe = pending?.target_user_id === userId;
  const isMyTurn = game?.current_turn_user_id === userId;
  const myRole = game?.first_player_user_id === userId ? "선공" : "후공";
  const fileTarget = n(myBoard?.files_to_place);
  const filesPlaced = n(myBoard?.files_placed_this_turn);
  const costLimit = n(myBoard?.file_count) + (myBoard?.partner_assist_used ? 1 : 0);
  const canActMain = isMyTurn && game?.turn_step === "main" && !game?.game_over && !pending;

  const st = {
    root: { minHeight: "100vh", padding: "clamp(10px, 2vw, 22px)", background: C.bg, color: C.text, fontFamily: 'Inter, Pretendard, "Noto Sans KR", sans-serif' },
    panel: { minWidth: 0, padding: 12, border: `2px solid ${C.border}`, borderRadius: 7, background: C.panel2 },
    zoneTitle: { margin: "0 0 10px", fontSize: 12, letterSpacing: ".04em", color: C.blue, fontWeight: 900 },
    button: { border: "1px solid rgba(255,255,255,.16)", borderRadius: 7, padding: "8px 10px", background: "#263d63", color: "white", cursor: loading ? "wait" : "pointer", fontSize: 11, fontWeight: 800, opacity: loading ? 0.6 : 1 },
    smallButton: { border: "1px solid rgba(255,255,255,.13)", borderRadius: 6, padding: "5px 7px", background: "#17243a", color: "#dbe4f1", cursor: loading ? "wait" : "pointer", fontSize: 10, lineHeight: 1.3, fontWeight: 750, opacity: loading ? 0.6 : 1 },
    muted: { margin: 0, color: C.muted, fontSize: 10, lineHeight: 1.5 },
    counts: { display: "grid", gridTemplateColumns: "repeat(2, minmax(0,1fr))", gap: 6 },
    countCell: { background: "#070c14", border: "1px solid rgba(255,255,255,.07)", borderRadius: 6, textAlign: "center", padding: "8px 4px" },
    faceDown: { width: "100%", aspectRatio: "3 / 4", border: "1px solid #b7c3da", borderRadius: 6, background: "repeating-linear-gradient(135deg,#1b2a49,#1b2a49 6px,#24395f 6px,#24395f 12px)", boxShadow: "inset 0 0 0 3px rgba(255,255,255,.06)" },
  };

  function infoFor(instance) { return cardsByKey.get(String(instance?.key)) || null; }
  function nameOf(instance) { return infoFor(instance)?.name || instance?.key || "알 수 없는 카드"; }
  function openDetails(instance) { setDetailCard(instance); }
  function invokePromptDraw() {
    const count = promptCount("효과 처리: 드로우", 1, 20);
    if (count !== null) void runAction("draw_cards", { count });
  }
  function invokeInvestigate(instance, isPartner = false) {
    const data = isPartner ? infoFor({ key: myBoard?.partner_key }) : instance;
    const suggested = Math.max(1, Math.min(12, n(data?.lp, 1) || 1));
    const count = promptCount(isPartner ? "파트너 추리로 얻을 증거" : "이 캐릭터의 추리로 얻을 증거", suggested, 12);
    if (count !== null) void runAction(isPartner ? "partner_deduce" : "investigate", isPartner ? { evidence_count: count } : { instance_id: instance.instance_id, evidence_count: count });
  }
  function moveField(card, ownerId, destination) {
    const labels = { hand: "소유자의 손패", deck: "소유자의 덱 아래", remove: "리무브 영역" };
    if (!window.confirm(`${nameOf(card)} 카드를 ${labels[destination]}로 이동할까요? 효과 처리를 위한 수동 이동입니다.`)) return;
    void runAction("move_field_card", { instance_id: card.instance_id, owner_user_id: ownerId, destination });
  }

  function CardArt({ instance, compact = false, rested = false, onClick = null, faceDown = false }) {
    const info = infoFor(instance);
    const style = {
      display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5,
      background: "#070c14", cursor: onClick ? "pointer" : "default",
      transform: rested ? "rotate(90deg) scale(.72)" : "none", transformOrigin: "center center", transition: "transform .12s ease",
    };
    if (faceDown) return <div style={st.faceDown} aria-label="뒷면 카드" />;
    return info?.imageUrl
      ? <img src={info.imageUrl} alt={info.name || "카드"} onClick={onClick || undefined} style={style} />
      : <div role={onClick ? "button" : "img"} tabIndex={onClick ? 0 : undefined} onClick={onClick || undefined} onKeyDown={onClick ? (event) => { if (event.key === "Enter" || event.key === " ") onClick(); } : undefined} style={{ ...style, display: "grid", placeItems: "center", color: C.muted, border: 0, fontSize: 10 }}>이미지 없음</div>;
  }

  function ZoneCard({ instance, rested = false, ownerId, mine = false, eventResolving = false }) {
    const isEvent = instance.card_type === "event";
    const canAttackThis = Boolean(selectedAttacker) && !mine && !isEvent && canActMain && (rested || allowActiveTargets);
    const canManage = !game?.game_over && !pending;
    return (
      <article key={instance.instance_id} style={{ minWidth: 0, width: "100%", border: `1px solid ${canAttackThis ? "#fb7185" : "rgba(148,163,184,.16)"}`, borderRadius: 7, padding: 6, background: "#080d16" }}>
        <button type="button" onClick={() => openDetails(instance)} title={`${nameOf(instance)} 상세 정보`} style={{ display: "block", width: "100%", border: 0, background: "transparent", color: C.text, padding: 0 }}>
          <div style={{ position: "relative", overflow: "hidden", aspectRatio: "3 / 4", display: "grid", placeItems: "center", background: "#0c1422", borderRadius: 5 }}>
            <CardArt instance={instance} rested={rested} />
            <span style={{ position: "absolute", left: 4, top: 4, padding: "2px 4px", borderRadius: 4, background: rested ? "rgba(190,24,93,.94)" : "rgba(22,101,52,.9)", color: "white", fontSize: 8, fontWeight: 900 }}>{rested ? "슬립" : "액티브"}</span>
            {isEvent && <span style={{ position: "absolute", right: 4, top: 4, padding: "2px 4px", borderRadius: 4, background: "rgba(3,105,161,.92)", color: "white", fontSize: 8, fontWeight: 900 }}>이벤트</span>}
          </div>
        </button>
        <div style={{ marginTop: 5, fontSize: 10, fontWeight: 800, lineHeight: 1.35, overflowWrap: "anywhere" }}>{nameOf(instance)}</div>
        <div style={{ marginTop: 3, color: C.muted, fontSize: 9 }}>AP {n(instance.ap) + n(instance.ap_bonus)} · 코스트 {instance.cost ?? "-"}</div>
        {eventResolving && mine && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 6, background: "#075985" }} disabled={loading} onClick={() => void runAction("finish_event", { instance_id: instance.instance_id })}>효과 처리 완료 → 리무브</button>}
        {canAttackThis && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 6, borderColor: "#fb7185", color: C.red }} disabled={loading} onClick={() => void runAction("attack_character", { attacker_instance_id: selectedAttacker, target_user_id: ownerId, target_instance_id: instance.instance_id })}>이 캐릭터 공격</button>}
        {mine && !isEvent && canActMain && !rested && <div style={{ display: "grid", gap: 4, marginTop: 6 }}>
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => invokeInvestigate(instance)}>추리</button>
          <button type="button" style={{ ...st.smallButton, borderColor: selectedAttacker === instance.instance_id ? "#fb7185" : "rgba(255,255,255,.13)" }} disabled={loading} onClick={() => setSelectedAttacker((current) => current === instance.instance_id ? "" : instance.instance_id)}>{selectedAttacker === instance.instance_id ? "공격자 선택 해제" : "공격자로 선택"}</button>
          <button type="button" style={st.smallButton} disabled={loading || !opponentBoard?.evidence_count} onClick={() => void runAction("attack_evidence", { attacker_instance_id: instance.instance_id, target_user_id: opponentBoard?.user_id })}>상대 증거 공격</button>
        </div>}
        {canManage && <details style={{ marginTop: 6 }}><summary style={{ cursor: "pointer", fontSize: 9, color: "#8796ac" }}>효과 처리 · 카드 이동</summary><div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 4, marginTop: 5 }}>
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "hand")}>손패로 이동</button>
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "deck")}>덱 아래로 이동</button>
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "remove")}>리무브로 이동</button>
        </div></details>}
      </article>
    );
  }

  if (!game) return <main style={st.root}><div style={st.panel}>게임 필드를 불러오는 중…{error && <p style={{ color: C.red }}>{error}</p>}</div></main>;

  const caseEventCard = caseBoard && cardsByKey.get(String(caseBoard.event_key));
  const eventsDiffer = Boolean(myBoard && opponentBoard && myBoard.event_key !== opponentBoard.event_key);
  const solutionFileThreshold = game.first_player_user_id === userId ? 7 : 6;
  const winEvidenceThreshold = solutionFileThreshold;
  const roleText = game.first_player_user_id === userId ? "선공" : "후공";
  const currentTurnRole = game.current_turn_user_id === userId ? "내 턴" : "상대 턴";
  const canManualEffect = !game.game_over && !pending;

  return (
    <main style={st.root}>
      <style>{`
        .mock-board-grid { display:grid; grid-template-columns:minmax(145px,1.05fr) minmax(0,7fr) minmax(145px,1.05fr); grid-template-rows:auto auto auto; gap:10px; align-items:stretch; }
        .mock-zone-case {grid-column:1;grid-row:1;} .mock-zone-center {grid-column:2;grid-row:1 / span 2;} .mock-zone-deck {grid-column:3;grid-row:1;}
        .mock-zone-evidence {grid-column:1;grid-row:2 / span 1;} .mock-zone-remove {grid-column:3;grid-row:2 / span 1;} .mock-zone-files {grid-column:1 / span 2;grid-row:3;}
        .mock-zone-special-remove {grid-column:3;grid-row:3;}
        .mock-field-row {display:grid;grid-template-columns:repeat(auto-fit,minmax(105px,1fr));gap:7px;align-items:start;}
        .mock-card-modal-layout { display:grid; grid-template-columns:minmax(150px,250px) minmax(0,1fr); gap:14px; padding:14px; overflow-y:auto; }
        @media(max-width:680px){.mock-card-modal-layout{grid-template-columns:minmax(0,1fr)}.mock-card-modal-layout>div:first-child img{max-width:200px;display:block;margin:0 auto}}
        @media(max-width:820px){.mock-board-grid{grid-template-columns:minmax(115px,1fr) minmax(0,3fr) minmax(115px,1fr);gap:7px}.mock-zone-center{grid-column:1 / span 3;grid-row:2}.mock-zone-evidence{grid-column:1;grid-row:3}.mock-zone-remove{grid-column:3;grid-row:3}.mock-zone-files{grid-column:1 / span 2;grid-row:4}.mock-zone-special-remove{grid-column:3;grid-row:4}.mock-zone-case{grid-column:1;grid-row:1}.mock-zone-deck{grid-column:3;grid-row:1}}
      `}</style>

      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap", marginBottom: 12, paddingBottom: 12, borderBottom: "1px solid rgba(255,255,255,.1)" }}>
        <div>
          <div style={{ color: C.blue, fontSize: 10, fontWeight: 900, letterSpacing: ".18em" }}>CONAN TCG · PRIVATE MATCH</div>
          <h1 style={{ margin: "3px 0", fontSize: 21, fontWeight: 900 }}>게임 필드</h1>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 6 }}>
            <span style={{ border: "1px solid rgba(147,197,253,.25)", borderRadius: 5, padding: "4px 7px", color: C.blue, fontSize: 10 }}>내 역할: {roleText}</span>
            <span style={{ border: "1px solid rgba(255,255,255,.13)", borderRadius: 5, padding: "4px 7px", color: C.text, fontSize: 10 }}>턴 {game.turn_number} · {currentTurnRole}</span>
            <span style={{ border: "1px solid rgba(255,255,255,.13)", borderRadius: 5, padding: "4px 7px", color: game.case_phase === "solution" ? C.green : C.gold, fontSize: 10 }}>{game.case_phase === "solution" ? "해결편" : "사건편"}</span>
            {game.game_over && <span style={{ border: "1px solid rgba(134,239,172,.3)", borderRadius: 5, padding: "4px 7px", color: C.green, fontSize: 10 }}>{game.winner_user_id === userId ? "승리" : "패배"}</span>}
          </div>
        </div>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <button type="button" style={st.button} disabled={loading} onClick={() => void refresh()}>상태 새로고침</button>
          {onLeaveField && <button type="button" style={{ ...st.button, background: "#273244" }} onClick={onLeaveField}>전체 화면 해제</button>}
        </div>
      </header>

      {(error || notice) && <div role={error ? "alert" : "status"} style={{ marginBottom: 10, padding: 9, borderRadius: 6, border: `1px solid ${error ? "rgba(253,164,175,.3)" : "rgba(134,239,172,.24)"}`, color: error ? C.red : C.green, background: error ? "rgba(190,24,93,.07)" : "rgba(22,101,52,.07)", fontSize: 11 }}>{error || notice}</div>}
      {game.last_action_label && <p style={{ ...st.muted, marginBottom: 10 }}>최근 처리: {game.last_action_label}</p>}

      {pending && <section style={{ ...st.panel, marginBottom: 10, borderColor: "rgba(252,211,77,.45)" }}>
        <h2 style={{ ...st.zoneTitle, color: C.gold }}>증거 공격 · 가드 선택</h2>
        {pendingIsForMe ? <>
          <p style={{ ...st.muted, marginBottom: 8 }}>상대가 내 증거 영역을 공격했어. 액티브 캐릭터로 가드하거나 가드하지 않을 수 있어.</p>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {(myBoard?.field_cards || []).filter((card) => !card.rested && card.card_type !== "event").map((card) => <button key={card.instance_id} type="button" style={st.button} disabled={loading} onClick={() => void runAction("guard_with_character", { instance_id: card.instance_id })}>{nameOf(card)}로 가드 (AP {n(card.ap)+n(card.ap_bonus)})</button>)}
            <button type="button" style={{ ...st.button, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("decline_guard")}>가드하지 않기</button>
          </div>
        </> : <p style={st.muted}>상대가 가드 여부를 선택할 때까지 기다려 줘.</p>}
      </section>}

      <section className="mock-board-grid" aria-label="대전 필드">
        <div className="mock-zone-case" style={st.panel}>
          <h2 style={st.zoneTitle}>사건</h2>
          {caseEventCard?.imageUrl ? <button type="button" onClick={() => openDetails({ key: caseBoard.event_key, instance_id: `case-${caseBoard.event_key}` })} style={{ width: "100%", padding: 0, border: 0, background: "transparent" }}><img src={caseEventCard.imageUrl} alt={caseEventCard.name} style={{ display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5 }} /></button> : <div style={{ ...st.faceDown }} />}
          <div style={{ marginTop: 6, fontSize: 10, fontWeight: 800, lineHeight: 1.35 }}>{caseEventCard?.name || caseBoard?.event_key || "사건 미지정"}</div>
          {eventsDiffer && <p style={{ ...st.muted, marginTop: 5, color: C.red }}>두 플레이어가 다른 사건 카드를 선택했어. 현재는 플레이어 1의 사건 카드를 공통 사건으로 표시해.</p>}
          <div style={{ marginTop: 4, color: C.muted, fontSize: 9 }}>{game.case_phase === "solution" ? "해결편" : "사건편"}</div>
          {canActMain && game.case_phase === "incident" && n(myBoard?.file_count) >= solutionFileThreshold && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7 }} disabled={loading} onClick={() => void runAction("declare_solution")}>해결편으로 전환</button>}
          {canActMain && game.case_phase === "solution" && n(myBoard?.evidence_count) >= winEvidenceThreshold && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7, background: "#166534" }} disabled={loading} onClick={() => void runAction("solve_case")}>사건 해결 선언</button>}
        </div>

        <div className="mock-zone-center" style={{ ...st.panel, display: "flex", flexDirection: "column", gap: 10 }}>
          <h2 style={{ ...st.zoneTitle, textAlign: "center", fontSize: 15, marginBottom: 0 }}>현장</h2>
          <div style={{ padding: 9, borderRadius: 7, border: "1px solid rgba(148,163,184,.13)", background: "#090f1b" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: 8, marginBottom: 8 }}><strong style={{ color: C.muted, fontSize: 10 }}>{opponentBoard?.display_name || "상대"} · 현장</strong><span style={st.muted}>{opponentBoard?.field_cards?.length || 0}장</span></div>
            <div className="mock-field-row">
              {(opponentBoard?.field_cards || []).map((card) => <ZoneCard key={card.instance_id} instance={card} rested={Boolean(card.rested)} ownerId={opponentBoard.user_id} mine={false} eventResolving={Boolean(card.resolving)} />)}
              {!opponentBoard?.field_cards?.length && <p style={st.muted}>현장에 카드가 없어.</p>}
            </div>
          </div>

          <div style={{ border: "2px solid rgba(147,197,253,.28)", borderRadius: 7, padding: 8, background: "rgba(59,130,246,.045)" }}>
            <h3 style={{ ...st.zoneTitle, textAlign: "center", marginBottom: 8 }}>파트너 에이리어</h3>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 8 }}>
              {[{ board: opponentBoard, mine: false }, { board: myBoard, mine: true }].map(({ board, mine }) => {
                if (!board) return null;
                const partner = cardsByKey.get(String(board.partner_key));
                return <div key={board.user_id} style={{ display: "grid", gridTemplateColumns: "minmax(55px,90px) minmax(0,1fr)", gap: 8, alignItems: "center", padding: 6, border: "1px solid rgba(255,255,255,.09)", borderRadius: 6, background: "#080d16" }}>
                  {partner?.imageUrl ? <button type="button" onClick={() => openDetails({ key: board.partner_key, instance_id: `partner-${board.user_id}` })} style={{ border: 0, background: "transparent", padding: 0 }}><img src={partner.imageUrl} alt={partner.name} style={{ width: "100%", maxHeight: 122, objectFit: "contain", transform: board.partner_rested ? "rotate(90deg) scale(.72)" : "none" }} /></button> : <div style={st.faceDown} />}
                  <div style={{ minWidth: 0 }}><div style={{ color: C.muted, fontSize: 8, marginBottom: 3 }}>{board.display_name || (mine ? "내 파트너" : "상대 파트너")}</div><div style={{ fontSize: 10, fontWeight: 850, overflowWrap: "anywhere" }}>{partner?.name || board.partner_key}</div><div style={{ color: board.partner_rested ? C.red : C.green, fontSize: 9, marginTop: 4 }}>{board.partner_rested ? "슬립" : "액티브"}{mine && board.partner_assist_used ? " · 어시스트 사용" : ""}</div>
                    {mine && canActMain && !board.partner_rested && <div style={{ display: "grid", gap: 4, marginTop: 6 }}><button type="button" style={st.smallButton} disabled={loading || board.next_hint_used} onClick={() => void runAction("partner_assist")}>어시스트 (+코스트 1)</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => invokeInvestigate(null, true)}>파트너 추리</button></div>}
                  </div>
                </div>;
              })}
            </div>
          </div>

          <div style={{ padding: 9, borderRadius: 7, border: "1px solid rgba(148,163,184,.13)", background: "#090f1b" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: 8, marginBottom: 8 }}><strong style={{ color: C.muted, fontSize: 10 }}>내 현장</strong><span style={st.muted}>{myBoard?.field_cards?.length || 0}장 · {isMyTurn ? "내 턴" : "상대 턴"}</span></div>
            <div className="mock-field-row">
              {(myBoard?.field_cards || []).map((card) => <ZoneCard key={card.instance_id} instance={card} rested={Boolean(card.rested)} ownerId={userId} mine eventResolving={Boolean(card.resolving)} />)}
              {!myBoard?.field_cards?.length && <p style={st.muted}>아직 현장에 낸 카드가 없어.</p>}
            </div>
          </div>
        </div>

        <div className="mock-zone-deck" style={st.panel}>
          <h2 style={st.zoneTitle}>덱</h2>
          <div style={st.faceDown} />
          <div style={{ marginTop: 7, fontSize: 11, textAlign: "center", fontWeight: 850 }}>내 덱 {game.my_deck_count ?? "-"}장</div>
          <div style={{ marginTop: 3, fontSize: 10, textAlign: "center", color: C.muted }}>상대 덱 {opponentBoard?.deck_count ?? "-"}장</div>
          <p style={{ ...st.muted, textAlign: "center", marginTop: 4 }}>카드 순서는 비공개</p>
          {canManualEffect && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 8 }} disabled={loading} onClick={invokePromptDraw}>효과 처리: N장 드로우</button>}
        </div>

        <div className="mock-zone-evidence" style={st.panel}>
          <h2 style={st.zoneTitle}>증거 에이리어</h2>
          <div style={{ ...st.counts, gridTemplateColumns: "repeat(2,minmax(0,1fr))" }}><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>내 증거</div><div style={{ fontSize: 22, fontWeight: 900 }}>{myBoard?.evidence_count ?? 0}</div></div><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>상대 증거</div><div style={{ fontSize: 22, fontWeight: 900 }}>{opponentBoard?.evidence_count ?? 0}</div></div></div>
          <p style={{ ...st.muted, marginTop: 7 }}>뒷면 · 카드 정보는 공개되지 않음</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,minmax(0,1fr))", gap: 4, marginTop: 8 }}>{Array.from({ length: Math.min(12, n(myBoard?.evidence_count)) }, (_, i) => <div key={i} style={{ ...st.faceDown, aspectRatio: "3/4" }} />)}</div>
        </div>

        <div className="mock-zone-remove" style={st.panel}>
          <h2 style={st.zoneTitle}>리무브 에이리어</h2>
          <div style={{ ...st.counts, gridTemplateColumns: "repeat(2,minmax(0,1fr))" }}><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>내 리무브</div><div style={{ fontSize: 22, fontWeight: 900 }}>{myBoard?.remove_count ?? 0}</div></div><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>상대 리무브</div><div style={{ fontSize: 22, fontWeight: 900 }}>{opponentBoard?.remove_count ?? 0}</div></div></div>
          <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 8 }} onClick={() => setShowRemoveArea((value) => !value)}>{showRemoveArea ? "리무브 목록 닫기" : "리무브 영역 보기"}</button>
          {showRemoveArea && <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 5, marginTop: 8, maxHeight: 350, overflowY: "auto" }}>{myRemoveCards.map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} style={{ border: "1px solid rgba(255,255,255,.1)", borderRadius: 5, padding: 4, background: "#080d16", color: C.text, minWidth: 0 }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<div style={{ fontSize: 9, overflowWrap: "anywhere" }}>{nameOf(card)}</div></button>)}</div>}
        </div>

        <div className="mock-zone-files" style={st.panel}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}><h2 style={{ ...st.zoneTitle, marginBottom: 0 }}>파일 에이리어</h2><strong style={{ fontSize: 11 }}>내 파일 {myBoard?.file_count ?? 0}장 · 상대 파일 {opponentBoard?.file_count ?? 0}장</strong></div>
          <p style={{ ...st.muted, marginTop: 6 }}>각 플레이어의 덱 위에서 뒷면으로 배치한 카드 · 넥스트 힌트 시 본인 파일의 가장 최근 카드 회수</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 10, marginTop: 8 }}>
            {[{ label: "내 파일", count: myBoard?.file_count }, { label: "상대 파일", count: opponentBoard?.file_count }].map((stack) => <div key={stack.label} style={{ minWidth: 0, padding: 7, borderRadius: 6, background: "#070c14", border: "1px solid rgba(255,255,255,.06)" }}><div style={{ color: C.muted, fontSize: 9, marginBottom: 5 }}>{stack.label} · {stack.count || 0}장</div><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(28px,1fr))", gap: 4 }}>{Array.from({ length: Math.min(24, n(stack.count)) }, (_, i) => <div key={i} style={st.faceDown} title="뒤집힌 파일 카드" />)}</div>{!stack.count && <div style={{ color: C.muted, fontSize: 9 }}>파일이 아직 없어.</div>}</div>)}
          </div>
        </div>

        <div className="mock-zone-special-remove" style={st.panel}>
          <h2 style={st.zoneTitle}>해제한 파트너 두는 곳</h2>
          <div style={{ minHeight: 96, border: "1px solid rgba(148,163,184,.24)", borderRadius: 6, padding: 8, background: "#080d16", display: "grid", placeItems: "center", textAlign: "center" }}>
            <p style={st.muted}>파트너가 효과로 해제될 때 사용하는 자리</p>
          </div>
          <label style={{ display: "flex", alignItems: "flex-start", gap: 6, marginTop: 9, fontSize: 9, color: C.muted, lineHeight: 1.45 }}><input type="checkbox" checked={allowActiveTargets} onChange={(event) => setAllowActiveTargets(event.target.checked)} /> 효과에 따라 액티브 상태의 상대 캐릭터도 공격 대상으로 선택</label>
        </div>
      </section>

      {!game.game_over && <section style={{ ...st.panel, marginTop: 10 }}>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 10, flexWrap: "wrap", alignItems: "baseline" }}><h2 style={st.zoneTitle}>턴 컨트롤</h2><span style={{ color: C.muted, fontSize: 10 }}>현재 코스트 상한 {costLimit} · 기본 출동 {myBoard?.character_played_this_turn ? "사용함" : "미사용"}</span></div>
        {game.turn_step === "begin" && (isMyTurn ? <button type="button" style={st.button} disabled={loading || pending} onClick={() => void runAction("begin_turn")}>턴 시작 · 액티브화 · 손패 1장 드로우</button> : <p style={st.muted}>상대가 턴을 시작할 때까지 대기해.</p>)}
        {game.turn_step === "file" && <div><p style={{ ...st.muted, marginBottom: 8 }}>{isMyTurn ? `덱 위에서 파일 ${Math.max(0, fileTarget - filesPlaced)}장을 뒤집어 배치해.` : `상대가 파일 ${currentTurnBoard?.files_to_place ?? 0}장을 배치하고 있어.`}</p>{isMyTurn && <button type="button" style={st.button} disabled={loading} onClick={() => void runAction("place_files")}>덱 위에서 파일 {Math.max(0, fileTarget - filesPlaced)}장 배치</button>}</div>}
        {canActMain && <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 5 }}>
          <button type="button" style={st.button} disabled={loading || !myBoard?.file_count || !myBoard?.base_action_done || !selectedNextHint || selectedNextHint === "__FILE_TOP__"} onClick={() => void runAction("next_hint", { instance_id: selectedNextHint })}>넥스트 힌트 · 선택 캐릭터 출동</button>
          <button type="button" style={{ ...st.button, background: "#4b2637" }} disabled={loading || pending} onClick={() => void runAction("end_turn")}>턴 종료</button>
        </div>}
        {myBoard?.base_action_done && game.turn_step === "main" && <p style={{ ...st.muted, marginTop: 8 }}>기본 행동을 완료했어. 파일이 남아 있는 동안 넥스트 힌트를 연속 사용할 수 있어.</p>}
      </section>}

      <section style={{ ...st.panel, marginTop: 10 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}><h2 style={st.zoneTitle}>내 손패 · {myHand.length}장</h2><span style={st.muted}>카드 이미지를 누르면 상세 설명이 열려.</span></div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(104px,1fr))", gap: 7, marginTop: 9 }}>
          {myHand.map((card) => {
            const info = infoFor(card);
            const normalPlay = canActMain && card.card_type === "character" && !myBoard?.character_played_this_turn && n(card.cost) <= costLimit;
            const nextSelected = selectedNextHint === card.instance_id;
            return <article key={card.instance_id} style={{ minWidth: 0, padding: 6, border: `1px solid ${nextSelected ? "#fb7185" : "rgba(148,163,184,.15)"}`, borderRadius: 7, background: "#080d16" }}>
              <button type="button" onClick={() => openDetails(card)} style={{ display: "block", width: "100%", border: 0, background: "transparent", color: C.text, padding: 0 }}><CardArt instance={card} /><div style={{ fontSize: 10, fontWeight: 800, lineHeight: 1.35, marginTop: 5, textAlign: "left", overflowWrap: "anywhere" }}>{info?.name || card.key}</div></button>
              <div style={{ fontSize: 9, color: C.muted, marginTop: 3 }}>코스트 {card.cost ?? "-"} · AP {card.ap ?? "-"}</div>
              {canActMain && card.card_type === "character" && <div style={{ display: "grid", gap: 4, marginTop: 6 }}>
                {normalPlay && <button type="button" style={st.smallButton} disabled={loading} onClick={() => void runAction("play_character", { instance_id: card.instance_id })}>기본 출동</button>}
                {card.card_type === "character" && n(card.cost) <= costLimit && <button type="button" style={{ ...st.smallButton, borderColor: nextSelected ? "#fb7185" : "rgba(255,255,255,.13)", color: nextSelected ? C.red : C.text }} disabled={loading || !myBoard?.base_action_done || !myBoard?.file_count} onClick={() => setSelectedNextHint(nextSelected ? "" : card.instance_id)}>{nextSelected ? "넥스트 힌트 선택됨" : "넥스트 힌트 선택"}</button>}
              </div>}
              {canActMain && card.card_type === "event" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 6, background: "#075985" }} disabled={loading} onClick={() => void runAction("play_event", { instance_id: card.instance_id })}>현장에 이벤트 사용</button>}
              {canManualEffect && card.card_type === "character" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, background: "#3b2f5c" }} disabled={loading || n(card.cost) > costLimit} onClick={() => void runAction("extra_play_character", { instance_id: card.instance_id, effect_override: true })}>효과로 추가 출동</button>}
            </article>;
          })}
          {!myHand.length && <p style={st.muted}>손패가 비어 있어.</p>}
        </div>
      </section>

      {detailCard && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setDetailCard(null); }} style={{ position: "fixed", inset: 0, zIndex: 99999, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.83)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label={`${nameOf(detailCard)} 카드 상세`} style={{ width: "min(100%, 980px)", maxHeight: "94dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(255,255,255,.16)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.65)" }}>
          <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 12, borderBottom: "1px solid rgba(255,255,255,.09)" }}><div><div style={{ color: C.red, fontSize: 9, letterSpacing: ".14em", fontWeight: 900 }}>CARD DETAIL</div><h2 style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 900 }}>{nameOf(detailCard)}</h2></div><button type="button" style={st.button} onClick={() => setDetailCard(null)}>닫기 ✕</button></header>
          <div className="mock-card-modal-layout">
            <div>{infoFor(detailCard)?.imageUrl && <img src={infoFor(detailCard).imageUrl} alt={nameOf(detailCard)} style={{ width: "100%", maxHeight: "58vh", objectFit: "contain", background: "#080d16", borderRadius: 8 }} />}</div>
            <div style={{ minWidth: 0, display: "grid", gap: 9, alignContent: "start" }}>
              <dl style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 6, margin: 0 }}>{[["종류", infoFor(detailCard)?.type], ["색상", infoFor(detailCard)?.color], ["레어도", infoFor(detailCard)?.rarity], ["코스트", detailCard.cost ?? infoFor(detailCard)?.cost], ["AP", detailCard.ap ?? infoFor(detailCard)?.ap], ["LP", detailCard.lp ?? infoFor(detailCard)?.lp], ["수록 제품", infoFor(detailCard)?.set]].map(([label, value]) => <div key={label} style={{ padding: 8, borderRadius: 6, background: "#080d16", border: "1px solid rgba(255,255,255,.07)" }}><dt style={{ color: C.muted, fontSize: 9 }}>{label}</dt><dd style={{ margin: "3px 0 0", fontSize: 11, fontWeight: 750, overflowWrap: "anywhere" }}>{value ?? "-"}</dd></div>)}</dl>
              {(infoFor(detailCard)?.traits?.length > 0) && <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>특징</h3><p style={{ margin: 0, fontSize: 11, lineHeight: 1.6 }}>{infoFor(detailCard).traits.join(" · ")}</p></div>}
              {(infoFor(detailCard)?.keywordTags?.length > 0) && <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>특수 태그</h3><p style={{ margin: 0, fontSize: 11, lineHeight: 1.6 }}>{infoFor(detailCard).keywordTags.join(" · ")}</p></div>}
              {(infoFor(detailCard)?.hiramekiEffect || infoFor(detailCard)?.cutInEffect) && <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>게임 시스템 효과</h3>{infoFor(detailCard)?.hiramekiEffect && <p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.65, margin: "4px 0" }}><b style={{ color: "#fb923c" }}>히라메키</b>　{infoFor(detailCard).hiramekiEffect}</p>}{infoFor(detailCard)?.cutInEffect && <p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.65, margin: "4px 0" }}><b style={{ color: "#7dd3fc" }}>컷인</b>　{infoFor(detailCard).cutInEffect}</p>}</div>}
              <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>카드 효과</h3><p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.75, margin: 0 }}>{infoFor(detailCard)?.ability || "효과 텍스트 없음"}</p></div>
              {infoFor(detailCard)?.originalAbility && <details style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><summary style={{ cursor: "pointer", fontSize: 11 }}>일본어 원문 보기</summary><p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.7 }}>{infoFor(detailCard).originalAbility}</p></details>}
            </div>
          </div>
        </section>
      </div>}
    </main>
  );
}
