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
function promptCount(label, defaultValue = 1, max = 20, min = 1) {
  const raw = window.prompt(`${label} (${min}~${max}장)`, String(defaultValue));
  if (raw === null) return null;
  const value = Math.floor(Number(raw));
  if (!Number.isInteger(value) || value < min || value > max) {
    window.alert(`${min}~${max} 사이의 정수를 입력해 주세요.`);
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
  const [allowFreshlyPlayed, setAllowFreshlyPlayed] = useState(false);
  const [showRemoveArea, setShowRemoveArea] = useState(false);
  const [detailCard, setDetailCard] = useState(null);
  const [peekOrderIds, setPeekOrderIds] = useState([]);
  const [dismissedSharedPeekSignature, setDismissedSharedPeekSignature] = useState("");
  const [blockedToast, setBlockedToast] = useState("");
  const [minimizedModal, setMinimizedModal] = useState("");
  const [opponentDeckAfterWin, setOpponentDeckAfterWin] = useState(null);
  const [loadingOpponentDeck, setLoadingOpponentDeck] = useState(false);

  const myPeekSignature = useMemo(() => {
    const peek = game?.my_deck_peek;
    return peek?.source_user_id ? `${peek.source_user_id}:${(peek.cards || []).map((card) => card.instance_id).join("|")}` : "";
  }, [game?.my_deck_peek]);
  const sharedPeekSignature = useMemo(() => (game?.shared_deck_peek_cards || []).map((entry) => `${entry.source_user_id}:${entry.card?.instance_id}:${Boolean(entry.returned)}`).join("|"), [game?.shared_deck_peek_cards]);

  useEffect(() => {
    if (!myPeekSignature) setPeekOrderIds([]);
    else setPeekOrderIds(myPeekSignature.split(":").slice(1).join(":").split("|").filter(Boolean));
  }, [myPeekSignature]);

  useEffect(() => {
    if (!sharedPeekSignature) setDismissedSharedPeekSignature("");
  }, [sharedPeekSignature]);

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
          setError("실시간 연결에 문제가 발생했습니다. 새로고침 후 상태를 확인해 주세요.");
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
      if (["declare_contact", "attack_character", "attack_evidence", "guard_with_character", "decline_guard", "contact_use_cutin", "contact_pass_cutin"].includes(action)) setSelectedAttacker("");
      if ((action === "move_field_card" || action === "move_hand_card") && (payload.owner_user_id || userId) === userId) setDetailCard(null);
    } catch (err) {
      const message = err?.message || "행동을 처리하지 못했습니다.";
      setError(message);
      showBlockedReason(message);
    } finally { setLoading(false); }
  }, [roomId, userId, loading]);

  const boards = Array.isArray(game?.boards) ? game.boards : [];
  const myBoard = boards.find((board) => board.user_id === userId);
  const opponentBoard = boards.find((board) => board.user_id !== userId);
  const currentTurnBoard = boards.find((board) => board.user_id === game?.current_turn_user_id);
  const myHand = Array.isArray(game?.my_hand) ? game.my_hand : [];
  const myRemoveCards = Array.isArray(game?.my_remove_cards) ? game.my_remove_cards : [];
  const opponentRemoveCards = Array.isArray(game?.opponent_remove_cards) ? game.opponent_remove_cards : [];
  const pending = game?.pending_action || null;
  const pendingIsForMe = pending?.target_user_id === userId;
  const isContactPending = pending?.type === "character_contact";
  const isMisleadPending = pending?.type === "mislead_response";
  const isMyTurn = game?.current_turn_user_id === userId;
  const myRole = game?.first_player_user_id === userId ? "선공" : "후공";
  const fileTarget = n(myBoard?.files_to_place);
  const filesPlaced = n(myBoard?.files_placed_this_turn);
  const costLimit = n(myBoard?.file_count) + (myBoard?.partner_assist_used ? 1 : 0);
  const canActMain = isMyTurn && game?.turn_step === "main" && !game?.game_over && !pending && !myBoard?.next_hint_pending && (!game?.deck_peek_locked || Boolean(game?.my_deck_peek));
  const myEventCard = myBoard ? cardsByKey.get(String(myBoard.event_key)) : null;
  const opponentEventCard = opponentBoard ? cardsByKey.get(String(opponentBoard.event_key)) : null;

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
  function openDetails(instance) { setDetailCard(instance); setMinimizedModal(""); }
  function minimizeOnDoubleClick(event, key) {
    if (event.target?.closest?.("button, input, textarea, select, a, summary")) return;
    setMinimizedModal(key);
  }
  function showBlockedReason(reason) {
    setBlockedToast(String(reason || "지금은 이 행동을 사용할 수 없습니다."));
    window.setTimeout(() => setBlockedToast(""), 4800);
  }
  async function openOpponentDeckAfterGame() {
    if (loadingOpponentDeck) return;
    setLoadingOpponentDeck(true);
    try {
      const { data, error: rpcError } = await supabase.rpc("get_opponent_full_deck_after_game", { p_room_id: roomId });
      if (rpcError) throw rpcError;
      setOpponentDeckAfterWin(data && typeof data === "object" ? data : { cards: [] });
    } catch (err) {
      showBlockedReason(err?.message || "상대 덱을 불러오지 못했습니다.");
    } finally { setLoadingOpponentDeck(false); }
  }
  function promptApBonus(card, ownerId) {
    const amount = promptCount(`${nameOf(card)}에 이번 턴 동안 추가할 AP`, 1000, 10000);
    if (amount !== null) void runAction("add_ap_bonus", { instance_id: card.instance_id, owner_user_id: ownerId, amount });
  }
  function invokePromptDraw() {
    const count = promptCount("효과 처리: 드로우", 1, 20);
    if (count !== null) void runAction("draw_cards", { count });
  }
  function invokeDeckPeek(sourceUserId, availableCount) {
    if (!sourceUserId || n(availableCount) < 1) return;
    const count = promptCount("덱 위에서 살펴볼 카드 수", Math.min(3, n(availableCount)), Math.min(100, n(availableCount)));
    if (count !== null) void runAction("peek_deck", { source_user_id: sourceUserId, count });
  }
  function invokeExposeEvidence(targetUserId, availableCount, label) {
    if (!targetUserId || n(availableCount) < 1) return;
    const count = promptCount(`${label}에서 위쪽(최근에 쌓인) 증거 공개`, Math.min(1, n(availableCount)), Math.min(20, n(availableCount)));
    if (count !== null) void runAction("expose_evidence", { target_user_id: targetUserId, count });
  }
  function invokeRemoveTopDeck() {
    const available = n(game?.my_deck_count);
    if (available < 1) { showBlockedReason("리무브할 덱 카드가 없습니다."); return; }
    const count = promptCount("리무브할 내 덱 위쪽 카드 수", 1, available);
    if (count !== null) void runAction("remove_top_deck", { count });
  }
  function invokeInvestigate(instance, isPartner = false) {
    if (isPartner) {
      void runAction("partner_deduce", { evidence_count: 1 });
      return;
    }
    const suggested = Math.max(0, Math.min(3, n(instance?.lp, 1)));
    const count = promptCount("캐릭터 추리로 얻을 증거", suggested, 3, 0);
    if (count !== null) void runAction("investigate", { instance_id: instance.instance_id, evidence_count: count, allow_newly_played: allowFreshlyPlayed });
  }
  function moveField(card, ownerId, destination) {
    const labels = { hand: "소유자의 손패", deck: "소유자의 덱 아래", remove: "리무브 영역" };
    if (!window.confirm(`${nameOf(card)} 카드를 ${labels[destination]}로 이동할까요? 효과 처리를 위한 수동 이동입니다.`)) return;
    void runAction("move_field_card", { instance_id: card.instance_id, owner_user_id: ownerId, destination });
  }

  function CardArt({ instance, compact = false, rested = false, status: statusProp = "", onClick = null, faceDown = false }) {
    const info = infoFor(instance);
    const cardStatus = statusProp === "stunned" || instance?.status === "stunned"
      ? "stunned"
      : (rested || instance?.rested ? "rested" : (statusProp || instance?.status || "active"));
    const transform = cardStatus === "stunned" ? "rotate(180deg) scale(.76)" : cardStatus === "rested" || rested || instance?.rested ? "rotate(90deg) scale(.72)" : "none";
    const style = {
      display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5,
      background: "#070c14", cursor: onClick ? "pointer" : "default",
      transform, transformOrigin: "center center", transition: "transform .12s ease",
    };
    if (faceDown) return <div style={st.faceDown} aria-label="뒷면 카드" />;
    return info?.imageUrl
      ? <img src={info.imageUrl} alt={info.name || "카드"} onClick={onClick || undefined} style={style} />
      : <div role={onClick ? "button" : "img"} tabIndex={onClick ? 0 : undefined} onClick={onClick || undefined} onKeyDown={onClick ? (event) => { if (event.key === "Enter" || event.key === " ") onClick(); } : undefined} style={{ ...style, display: "grid", placeItems: "center", color: C.muted, border: 0, fontSize: 10 }}>이미지 없음</div>;
  }

  function ZoneCard({ instance, rested = false, ownerId, mine = false, eventResolving = false }) {
    const isEvent = instance.card_type === "event";
    const cardStatus = instance.status === "stunned"
      ? "stunned"
      : (instance.rested ? "rested" : (instance.status || "active"));
    const notReadyYet = Boolean(instance.summoned_this_turn) && !allowFreshlyPlayed;
    const canOfferContact = Boolean(selectedAttacker) && !mine && !isEvent && canActMain;
    const canManage = !game?.game_over && !pending;
    const ownerLabel = ownerId === userId ? "내" : "상대";
    return (
      <article key={instance.instance_id} style={{ minWidth: 0, width: "100%", border: `1px solid ${canOfferContact ? "#fb7185" : "rgba(148,163,184,.16)"}`, borderRadius: 7, padding: 4, background: "#080d16" }}>
        <button type="button" onClick={() => openDetails(instance)} title={`${nameOf(instance)} 상세 정보`} style={{ display: "block", width: "100%", border: 0, background: "transparent", color: C.text, padding: 0 }}>
          <div style={{ position: "relative", overflow: "hidden", aspectRatio: "3 / 4", display: "grid", placeItems: "center", background: "#0c1422", borderRadius: 5 }}>
            <CardArt instance={instance} rested={rested} status={cardStatus} />
            <span style={{ position: "absolute", left: 3, top: 3, padding: "2px 3px", borderRadius: 4, background: cardStatus === "stunned" ? "rgba(126,34,206,.95)" : cardStatus === "rested" || rested ? "rgba(190,24,93,.94)" : "rgba(22,101,52,.9)", color: "white", fontSize: 7, fontWeight: 900 }}>{cardStatus === "stunned" ? "스턴" : cardStatus === "rested" || rested ? "슬립" : "액티브"}</span>
            {String(instance.rarity || "").toUpperCase() === "MR" && <span style={{ position: "absolute", right: 3, bottom: 3, padding: "2px 3px", borderRadius: 4, background: "#a16207", color: "white", fontSize: 7, fontWeight: 900 }}>MR</span>}
            {isEvent && <span style={{ position: "absolute", right: 3, top: 3, padding: "2px 3px", borderRadius: 4, background: "rgba(3,105,161,.92)", color: "white", fontSize: 7, fontWeight: 900 }}>이벤트</span>}
          </div>
        </button>
        <div style={{ marginTop: 4, fontSize: 9, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere" }}>{nameOf(instance)}</div>
        <div style={{ marginTop: 2, color: C.muted, fontSize: 8 }}>AP {n(instance.ap) + n(instance.ap_bonus)} · 코스트 {instance.cost ?? "-"}</div>
        {eventResolving && mine && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, background: "#075985" }} disabled={loading} onClick={() => void runAction("finish_event", { instance_id: instance.instance_id })}>효과 처리 완료 → 리무브</button>}
        {canOfferContact && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, borderColor: "#fb7185", color: C.red }} disabled={loading} onClick={() => {
          if (cardStatus === "active" && !allowActiveTargets) { showBlockedReason("액티브 상태의 캐릭터는 기본적으로 공격 대상으로 지정할 수 없습니다. 효과 예외 옵션을 활성화해 주세요."); return; }
          void runAction("declare_contact", { attacker_instance_id: selectedAttacker, target_user_id: ownerId, target_instance_id: instance.instance_id, allow_active_target: allowActiveTargets, allow_newly_played: allowFreshlyPlayed });
        }}>컨택 시작</button>}
        {mine && !isEvent && canActMain && <div style={{ display: "grid", gap: 4, marginTop: 5 }}>
          <button type="button" style={{ ...st.smallButton, opacity: cardStatus !== "active" || notReadyYet ? .72 : 1 }} disabled={loading} title={cardStatus !== "active" ? "슬립/스턴 상태에서는 추리할 수 없습니다." : notReadyYet ? "이번 턴에 출동한 카드는 기본적으로 행동할 수 없습니다." : ""} onClick={() => { if (cardStatus !== "active") { showBlockedReason("슬립/스턴 상태의 캐릭터는 추리할 수 없습니다."); return; } if (notReadyYet) { showBlockedReason("등장 후 1턴이 지나지 않아 행동할 수 없습니다. 효과 예외 옵션을 활성화해 주세요."); return; } invokeInvestigate(instance); }}>추리</button>
          <button type="button" style={{ ...st.smallButton, opacity: cardStatus !== "active" || notReadyYet ? .72 : 1, borderColor: selectedAttacker === instance.instance_id ? "#fb7185" : "rgba(255,255,255,.13)" }} disabled={loading} onClick={() => { if (cardStatus !== "active") { showBlockedReason("슬립/스턴 상태의 캐릭터는 공격자로 지정할 수 없습니다."); return; } if (notReadyYet) { showBlockedReason("등장 후 1턴이 지나지 않아 공격자로 선택할 수 없습니다. 효과 예외 옵션을 활성화해 주세요."); return; } setSelectedAttacker((current) => current === instance.instance_id ? "" : instance.instance_id); }}>{selectedAttacker === instance.instance_id ? "공격자 선택 해제" : "공격자로 선택"}</button>
          <button type="button" style={{ ...st.smallButton, opacity: cardStatus !== "active" || notReadyYet ? .72 : 1 }} disabled={loading} onClick={() => { if (cardStatus !== "active") { showBlockedReason("슬립/스턴 상태의 캐릭터는 공격할 수 없습니다."); return; } if (notReadyYet && !allowFreshlyPlayed) { showBlockedReason("등장 후 1턴이 지나지 않아 공격할 수 없습니다. 효과 예외 옵션을 활성화해 주세요."); return; } if (!opponentBoard?.evidence_count) { showBlockedReason("상대 증거 에이리어에 공격할 증거가 없습니다."); return; } void runAction("attack_evidence", { attacker_instance_id: instance.instance_id, target_user_id: opponentBoard?.user_id, allow_newly_played: allowFreshlyPlayed }); }}>상대 증거 공격</button>
        </div>}
        {canManage && <details style={{ marginTop: 5 }}><summary style={{ cursor: "pointer", fontSize: 8, color: "#8796ac" }}>효과 처리 · 카드 이동</summary><div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 4, marginTop: 5 }}>
          {!isEvent && cardStatus === "active" && <button type="button" style={{ ...st.smallButton, color: C.gold }} disabled={loading} onClick={() => { if (window.confirm(`${nameOf(instance)} 카드를 슬립 상태로 만들까요?`)) void runAction("rest_character_manual", { instance_id: instance.instance_id, owner_user_id: ownerId }); }}>효과 처리: 이 캐릭터를 슬립</button>}
          {!isEvent && <button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${nameOf(instance)} 카드를 스턴 상태로 만들까요?`)) void runAction("stun_character", { instance_id: instance.instance_id, owner_user_id: ownerId }); }}>효과로 스턴</button>}
          {!isEvent && cardStatus !== "active" && <button type="button" style={{ ...st.smallButton, color: C.green }} disabled={loading} onClick={() => void runAction("activate_character", { instance_id: instance.instance_id, owner_user_id: ownerId })}>효과 처리: 액티브로 되돌리기</button>}
          {!isEvent && <button type="button" style={st.smallButton} disabled={loading} onClick={() => promptApBonus(instance, ownerId)}>효과 처리: AP +N (이번 턴)</button>}
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "hand")}>손패로 이동</button>
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "deck")}>덱 아래로 이동</button>
          <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "remove")}>리무브로 이동</button>
        </div></details>}
      </article>
    );
  }

  if (!game) return <main style={st.root}><div style={st.panel}>게임 필드를 불러오는 중…{error && <p style={{ color: C.red }}>{error}</p>}</div></main>;

  const solutionFileThreshold = game.first_player_user_id === userId ? 7 : 6;
  const winEvidenceThreshold = solutionFileThreshold;
  const roleText = game.first_player_user_id === userId ? "선공" : "후공";
  const currentTurnRole = game.current_turn_user_id === userId ? "내 턴" : "상대 턴";
  const canManualEffect = !game.game_over && !pending && !myBoard?.next_hint_pending && (!game.deck_peek_locked || Boolean(game.my_deck_peek));
  const canTransitionSolution = canActMain && myBoard?.case_phase === "incident" && n(myBoard?.file_count) >= solutionFileThreshold
    && !myBoard?.partner_rested && !myBoard?.partner_assist_used && !myBoard?.next_hint_used && !myBoard?.next_hint_pending;
  const canWinCase = canActMain && myBoard?.case_phase === "solution" && n(myBoard?.evidence_count) >= winEvidenceThreshold
    && !myBoard?.partner_rested && !myBoard?.partner_assist_used;
  const activeSharedPeekCards = Array.isArray(game.shared_deck_peek_cards) ? game.shared_deck_peek_cards : [];
  // Define the current private peek before checking which cards have been selected for sharing.
  // Keeping this declaration order matters: const values are in the temporal dead zone until initialized.
  const ownPeek = game.my_deck_peek || null;
  const ownPeekCards = Array.isArray(ownPeek?.cards) ? ownPeek.cards : [];
  const allOwnPeekCardsShared = ownPeekCards.length > 0 && ownPeekCards.every((card) => (ownPeek?.shared_instance_ids || []).includes(card.instance_id));
  const deckRemovalPending = pending?.type === "deck_remove_reveal";
  const deckRemovalCards = Array.isArray(pending?.cards) ? pending.cards : [];
  const deckRemovalAcknowledged = Array.isArray(pending?.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
  const opponentDeckCardGroup = (card) => {
    const type = String(card?.card_type || infoFor(card)?.type || infoFor(card)?.originalType || infoFor(card)?.roleText || "").toLowerCase();
    if (/event|事件|사건/.test(type)) return "event";
    if (/partner|パートナー|파트너/.test(type) || /^p\d+/i.test(String(card?.key || ""))) return "special";
    return "character";
  };
  const opponentDeckCards = [...(opponentDeckAfterWin?.cards || [])].sort((a, b) => {
    const groupOrder = { character: 0, event: 1, special: 2 };
    const groupDiff = groupOrder[opponentDeckCardGroup(a)] - groupOrder[opponentDeckCardGroup(b)];
    return groupDiff || n(b?.cost ?? infoFor(b)?.cost, -1) - n(a?.cost ?? infoFor(a)?.cost, -1) || nameOf(a).localeCompare(nameOf(b), "ko");
  });
  const opponentDeckGroups = [
    { key: "character", label: "캐릭터 카드", cards: opponentDeckCards.filter((card) => opponentDeckCardGroup(card) === "character") },
    { key: "event", label: "이벤트 카드", cards: opponentDeckCards.filter((card) => opponentDeckCardGroup(card) === "event") },
    { key: "special", label: "파트너 · 기타 특수 카드", cards: opponentDeckCards.filter((card) => opponentDeckCardGroup(card) === "special") },
  ];
  const ownPeekOrder = peekOrderIds.map((id) => ownPeekCards.find((card) => card.instance_id === id)).filter(Boolean);
  const canSelectNextHintCard = isMyTurn && game?.turn_step === "main" && !game?.game_over && !pending && Boolean(myBoard?.next_hint_pending);
  const revealedEvidenceCard = pending?.type === "evidence_attack_reveal" ? pending.revealed_evidence_card : null;
  const winnerBoard = boards.find((board) => board.user_id === game?.winner_user_id);
  const winnerName = game?.winner_display_name || winnerBoard?.display_name || "플레이어";
  const minimizedModalLabels = { remove: "리무브 영역", peek: "덱 위 카드 살펴보기", sharedPeek: "상대가 공개한 카드", contact: "컨택 · 컷인 선택", evidence: "증거 카드 공개", detail: "카드 상세 정보", opponentDeck: "상대 덱 보기", deckRemove: "덱 위 카드 리무브 확인" };
  const minimizedModalExists = Boolean(
    (minimizedModal === "remove" && showRemoveArea) ||
    (minimizedModal === "peek" && ownPeek) ||
    (minimizedModal === "sharedPeek" && activeSharedPeekCards.length > 0) ||
    (minimizedModal === "contact" && isContactPending) ||
    (minimizedModal === "evidence" && revealedEvidenceCard) ||
    (minimizedModal === "detail" && detailCard) ||
    (minimizedModal === "opponentDeck" && opponentDeckAfterWin)
  );
  const contactAttackerBoard = boards.find((board) => board.user_id === pending?.attacker_user_id);
  const contactTargetBoard = boards.find((board) => board.user_id === pending?.target_user_id);
  const contactAttackerCard = (contactAttackerBoard?.field_cards || []).find((card) => card.instance_id === pending?.attacker_instance_id);
  const contactTargetCard = (contactTargetBoard?.field_cards || []).find((card) => card.instance_id === pending?.target_instance_id);

  return (
    <main style={st.root}>
      <style>{`
        .mock-sticky-status { position: sticky; top: 0; z-index: 1000; padding-top: 4px; background: rgba(8,13,23,.97); backdrop-filter: blur(12px); border-bottom: 1px solid rgba(148,163,184,.18); box-shadow: 0 8px 20px rgba(0,0,0,.16); }
        .mock-board-grid { display:grid; grid-template-columns:minmax(145px,1.05fr) minmax(0,7fr) minmax(145px,1.05fr); grid-template-rows:auto auto auto; gap:10px; align-items:stretch; }
        .mock-zone-case {grid-column:1;grid-row:1;} .mock-zone-center {grid-column:2;grid-row:1 / span 2;} .mock-zone-deck {grid-column:3;grid-row:1;}
        .mock-zone-evidence {grid-column:1;grid-row:2 / span 1;} .mock-zone-remove {grid-column:3;grid-row:2 / span 1;} .mock-zone-files {grid-column:1 / span 3;grid-row:3;}
        .mock-file-row {display:flex;align-items:center;gap:8px;min-width:0;padding:7px;background:#070c14;border:1px solid rgba(255,255,255,.07);border-radius:6px;}
        .mock-file-card-strip {display:flex;align-items:center;gap:3px;min-width:0;flex:1;overflow-x:auto;padding:4px 2px;}
        .mock-file-card {position:relative;flex:0 0 34px;width:34px;height:30px;display:grid;place-items:center;}
        .mock-file-card:before {content:"";width:22px;height:30px;display:block;border:1px solid #b7c3da;border-radius:4px;background:repeating-linear-gradient(135deg,#1b2a49,#1b2a49 4px,#24395f 4px,#24395f 8px);transform:rotate(90deg);box-shadow:inset 0 0 0 2px rgba(255,255,255,.06);}
        .mock-file-assist {flex:0 0 174px;min-width:140px;min-height:52px;display:flex;align-items:center;gap:8px;padding:5px;border:1px dashed rgba(252,211,77,.4);border-radius:6px;background:rgba(161,98,7,.08);}
        .mock-field-row {display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px;align-items:start;}
        .mock-field-row > article { width:100%; min-width:0; }
        .mock-field-empty { grid-column:1 / -1; min-height:55px; display:grid; place-items:center; }
        .mock-card-modal-layout { display:grid; grid-template-columns:minmax(150px,250px) minmax(0,1fr); gap:14px; padding:14px; overflow-y:auto; }
        @media(max-width:680px){.mock-card-modal-layout{grid-template-columns:minmax(0,1fr)}.mock-card-modal-layout>div:first-child img{max-width:200px;display:block;margin:0 auto}}
        @media(max-width:820px){.mock-file-row{gap:5px;padding:5px}.mock-file-assist{flex-basis:145px;min-width:125px}.mock-file-row>strong{flex-basis:65px!important}.mock-board-grid{grid-template-columns:minmax(115px,1fr) minmax(0,3fr) minmax(115px,1fr);gap:7px}.mock-zone-center{grid-column:1 / span 3;grid-row:2}.mock-zone-evidence{grid-column:1;grid-row:3}.mock-zone-remove{grid-column:3;grid-row:3}.mock-zone-files{grid-column:1 / span 3;grid-row:4}.mock-zone-case{grid-column:1;grid-row:1}.mock-zone-deck{grid-column:3;grid-row:1}}
      `}</style>

      <div className="mock-sticky-status">
      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap", marginBottom: 12, paddingBottom: 12, borderBottom: "1px solid rgba(255,255,255,.1)" }}>
        <div>
          <div style={{ color: C.blue, fontSize: 10, fontWeight: 900, letterSpacing: ".18em" }}>CONAN TCG · PRIVATE MATCH</div>
          <h1 style={{ margin: "3px 0", fontSize: 21, fontWeight: 900 }}>게임 필드</h1>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 6 }}>
            <span style={{ border: "1px solid rgba(147,197,253,.25)", borderRadius: 5, padding: "4px 7px", color: C.blue, fontSize: 10 }}>내 역할: {roleText}</span>
            <span style={{ border: "1px solid rgba(255,255,255,.13)", borderRadius: 5, padding: "4px 7px", color: C.text, fontSize: 10 }}>턴 {game.turn_number} · {currentTurnRole}</span>
            <span style={{ border: "1px solid rgba(255,255,255,.13)", borderRadius: 5, padding: "4px 7px", color: myBoard?.case_phase === "solution" ? C.green : C.gold, fontSize: 10 }}>{myBoard?.case_phase === "solution" ? "해결편" : "사건편"}</span>
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
      </div>

      {pending?.type === "evidence_attack" && <div style={{ position: "fixed", inset: 0, zIndex: 100140, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label="증거 공격 가드 선택" style={{ width: "min(100%, 620px)", maxHeight: "90dvh", overflowY: "auto", ...st.panel, borderColor: "rgba(252,211,77,.55)", boxShadow: "0 24px 70px rgba(0,0,0,.72)" }}>
          <h2 style={{ ...st.zoneTitle, color: C.gold, fontSize: 16 }}>증거 공격 · 가드 선택</h2>
          {pendingIsForMe ? <>
            <p style={{ ...st.muted, marginBottom: 12, fontSize: 11 }}>상대가 내 증거 영역을 공격했습니다. 액티브 캐릭터로 가드하거나 가드하지 않을 수 있습니다.</p>
            <div style={{ display: "grid", gap: 7 }}>
              {(myBoard?.field_cards || []).filter((card) => !card.rested && card.card_type !== "event" && (card.status || "active") === "active").map((card) => <button key={card.instance_id} type="button" style={{ ...st.button, textAlign: "left" }} disabled={loading} onClick={() => void runAction("guard_with_character", { instance_id: card.instance_id })}>{nameOf(card)}로 가드 (AP {n(card.ap)+n(card.ap_bonus)})</button>)}
              <button type="button" style={{ ...st.button, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("decline_guard")}>가드하지 않기</button>
            </div>
          </> : <p style={{ ...st.muted, fontSize: 11 }}>상대가 가드 여부를 선택하고 있습니다. 선택이 완료되면 다음 창에서 공격 대상 증거가 공개됩니다.</p>}
        </section>
      </div>}

      {isMisleadPending && <section style={{ ...st.panel, marginBottom: 10, borderColor: "rgba(232,121,249,.45)" }}>
        <h2 style={{ ...st.zoneTitle, color: "#e879f9" }}>미스리드 응답</h2>
        <p style={{ ...st.muted, marginBottom: 8 }}>상대가 추리를 선언하여 증거 {n(pending.evidence_count)}장을 획득하려고 합니다. 미스리드를 사용하면 획득 수를 지정한 만큼 줄일 수 있습니다.</p>
        {pending.target_user_id === userId ? <>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 7 }}>
            {(myBoard?.field_cards || []).filter((card) => n(card.mislead_value) > 0 && !card.rested && (card.status || "active") === "active" && (!card.summoned_this_turn || allowFreshlyPlayed)).map((card) => <button key={card.instance_id} type="button" style={{ ...st.button, background: "#581c87" }} disabled={loading} onClick={() => void runAction("resolve_mislead", { instance_id: card.instance_id, allow_newly_played: allowFreshlyPlayed })}>{nameOf(card)} · 미스리드 {n(card.mislead_value)}</button>)}
          </div>
          <button type="button" style={{ ...st.button, background: "#273244" }} disabled={loading} onClick={() => void runAction("pass_mislead")}>미스리드 사용 안 함</button>
        </> : <p style={st.muted}>상대가 미스리드 사용 여부를 선택하고 있습니다.</p>}
      </section>}

      <section className="mock-board-grid" aria-label="대전 필드">
        <div className="mock-zone-case" style={st.panel}>
          <h2 style={st.zoneTitle}>사건</h2>
          <div style={{ padding: 5, border: "1px solid rgba(255,255,255,.08)", borderRadius: 6, background: "#080d16" }}>
            <div style={{ color: C.muted, fontSize: 8, marginBottom: 4 }}>상대 사건 · 위쪽</div>
            {opponentEventCard?.imageUrl ? <button type="button" onClick={() => openDetails({ key: opponentBoard.event_key, instance_id: `event-${opponentBoard.event_key}-opponent` })} style={{ width: "100%", padding: 0, border: 0, background: "transparent" }}><img src={opponentEventCard.imageUrl} alt={opponentEventCard.name} style={{ display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5 }} /></button> : <div style={st.faceDown} />}
            <div style={{ marginTop: 4, fontSize: 9, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere" }}>{opponentEventCard?.name || opponentBoard?.event_key || "미선택"}</div>
          </div>
          <div style={{ marginTop: 7, padding: 5, border: "1px solid rgba(255,255,255,.08)", borderRadius: 6, background: "#080d16" }}>
            <div style={{ color: C.muted, fontSize: 8, marginBottom: 4 }}>내 사건 · 아래쪽</div>
            {myEventCard?.imageUrl ? <button type="button" onClick={() => openDetails({ key: myBoard.event_key, instance_id: `event-${myBoard.event_key}-mine` })} style={{ width: "100%", padding: 0, border: 0, background: "transparent" }}><img src={myEventCard.imageUrl} alt={myEventCard.name} style={{ display: "block", width: "100%", aspectRatio: "3 / 4", objectFit: "contain", borderRadius: 5 }} /></button> : <div style={st.faceDown} />}
            <div style={{ marginTop: 4, fontSize: 9, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere" }}>{myEventCard?.name || myBoard?.event_key || "미선택"}</div>
          </div>
          <div style={{ marginTop: 4, color: C.muted, fontSize: 9 }}>{myBoard?.case_phase === "solution" ? "해결편" : "사건편"}</div>
          {canTransitionSolution && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7, background: "#7f1d1d", borderColor: "#fb7185" }} disabled={loading} onClick={() => void runAction("declare_solution")}>파트너 어시스트 후 해결편 전환</button>}
          {canWinCase && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7, background: "#166534" }} disabled={loading} onClick={() => void runAction("solve_case")}>사건 해결 선언</button>}
        </div>

        <div className="mock-zone-center" style={{ ...st.panel, display: "flex", flexDirection: "column", gap: 10 }}>
          <h2 style={{ ...st.zoneTitle, textAlign: "center", fontSize: 15, marginBottom: 0 }}>현장</h2>
          <div style={{ padding: 9, borderRadius: 7, border: "1px solid rgba(148,163,184,.13)", background: "#090f1b" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: 8, marginBottom: 8 }}><strong style={{ color: C.muted, fontSize: 10 }}>{opponentBoard?.display_name || "상대"} · 현장</strong><span style={st.muted}>{opponentBoard?.field_cards?.length || 0}장</span></div>
            <div className="mock-field-row">
              {(opponentBoard?.field_cards || []).map((card) => <ZoneCard key={card.instance_id} instance={card} rested={Boolean(card.rested)} ownerId={opponentBoard.user_id} mine={false} eventResolving={Boolean(card.resolving)} />)}
              {!opponentBoard?.field_cards?.length && <p style={st.muted}>현장에 카드가 없습니다.</p>}
            </div>
          </div>

          <div style={{ border: "2px solid rgba(147,197,253,.28)", borderRadius: 7, padding: 8, background: "rgba(59,130,246,.045)" }}>
            <h3 style={{ ...st.zoneTitle, textAlign: "center", marginBottom: 8 }}>파트너 에이리어</h3>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 8 }}>
              {[{ board: opponentBoard, mine: false }, { board: myBoard, mine: true }].map(({ board, mine }) => {
                if (!board || board.partner_assist_used) return null;
                const partner = cardsByKey.get(String(board.partner_key));
                return <div key={board.user_id} style={{ display: "grid", gridTemplateColumns: "minmax(55px,90px) minmax(0,1fr)", gap: 8, alignItems: "center", padding: 6, border: "1px solid rgba(255,255,255,.09)", borderRadius: 6, background: "#080d16" }}>
                  {partner?.imageUrl ? <button type="button" onClick={() => openDetails({ key: board.partner_key, instance_id: `partner-${board.user_id}` })} style={{ border: 0, background: "transparent", padding: 0 }}><img src={partner.imageUrl} alt={partner.name} style={{ width: "100%", maxHeight: 122, objectFit: "contain", transform: board.partner_rested ? "rotate(90deg) scale(.72)" : "none" }} /></button> : <div style={st.faceDown} />}
                  <div style={{ minWidth: 0 }}><div style={{ color: C.muted, fontSize: 8, marginBottom: 3 }}>{board.display_name || (mine ? "내 파트너" : "상대 파트너")}</div><div style={{ fontSize: 10, fontWeight: 850, overflowWrap: "anywhere" }}>{partner?.name || board.partner_key}</div><div style={{ color: board.partner_rested ? C.red : C.green, fontSize: 9, marginTop: 4 }}>{board.partner_rested ? "슬립" : "액티브"}</div>
                    {mine && canActMain && !board.partner_rested && !board.next_hint_pending && <div style={{ display: "grid", gap: 4, marginTop: 6 }}><button type="button" style={st.smallButton} disabled={loading || board.next_hint_used || board.next_hint_pending} onClick={() => { if (board.next_hint_used || board.next_hint_pending) { showBlockedReason("넥스트 힌트를 선언한 후에는 파트너 어시스트를 사용할 수 없습니다."); return; } void runAction("partner_assist"); }}>어시스트 · 코스트 +1</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => invokeInvestigate(null, true)}>파트너 추리 · 증거 1장</button></div>}
                  </div>
                </div>;
              })}
            </div>
          </div>

          <div style={{ border: "1px solid rgba(252,211,77,.3)", borderRadius: 7, padding: 8, background: "rgba(161,98,7,.06)" }}>
            <h3 style={{ ...st.zoneTitle, color: C.gold, textAlign: "center", marginBottom: 7 }}>MR 파트너 영역</h3>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 8 }}>
              {[{ board: opponentBoard, mine: false }, { board: myBoard, mine: true }].map(({ board, mine }) => {
                const mr = board?.partner_mr_card;
                const info = mr ? infoFor(mr) : null;
                return <div key={`mr-${board?.user_id || (mine ? "mine" : "opponent")}`} style={{ minWidth: 0, padding: 6, border: "1px solid rgba(255,255,255,.08)", borderRadius: 6, background: "#080d16" }}>
                  <div style={{ color: C.muted, fontSize: 8, marginBottom: 4 }}>{mine ? "내 MR" : "상대 MR"}</div>
                  {mr ? <>
                    <button type="button" onClick={() => openDetails(mr)} style={{ width: "100%", padding: 0, border: 0, background: "transparent" }}>{info?.imageUrl ? <img src={info.imageUrl} alt={nameOf(mr)} style={{ width: "100%", maxHeight: 110, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}</button>
                    <div style={{ fontSize: 9, fontWeight: 800, overflowWrap: "anywhere", marginTop: 4 }}>{nameOf(mr)}</div>
                    {!game.game_over && !pending && <div style={{ display: "grid", gap: 3, marginTop: 5 }}><button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(mr, board.user_id, "hand")}>손패로 이동</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(mr, board.user_id, "remove")}>리무브로 이동</button></div>}
                  </> : <div style={{ minHeight: 55, display: "grid", placeItems: "center", color: C.muted, fontSize: 9 }}>없음</div>}
                </div>;
              })}
            </div>
          </div>

          <div style={{ padding: 9, borderRadius: 7, border: "1px solid rgba(148,163,184,.13)", background: "#090f1b" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: 8, marginBottom: 8 }}><strong style={{ color: C.muted, fontSize: 10 }}>내 현장</strong><span style={st.muted}>{myBoard?.field_cards?.length || 0}장 · {isMyTurn ? "내 턴" : "상대 턴"}</span></div>
            <div className="mock-field-row">
              {(myBoard?.field_cards || []).map((card) => <ZoneCard key={card.instance_id} instance={card} rested={Boolean(card.rested)} ownerId={userId} mine eventResolving={Boolean(card.resolving)} />)}
              {!myBoard?.field_cards?.length && <p style={st.muted}>아직 현장에 출동한 카드가 없습니다.</p>}
            </div>
          </div>
        </div>

        <div className="mock-zone-deck" style={st.panel}>
          <h2 style={st.zoneTitle}>덱</h2>
          <div style={st.faceDown} />
          <div style={{ marginTop: 7, fontSize: 11, textAlign: "center", fontWeight: 850 }}>내 덱 {game.my_deck_count ?? "-"}장</div>
          <div style={{ marginTop: 3, fontSize: 10, textAlign: "center", color: C.muted }}>상대 덱 {opponentBoard?.deck_count ?? "-"}장</div>
          <p style={{ ...st.muted, textAlign: "center", marginTop: 4 }}>{game.deck_peek_waiting_for_ack && !game.my_deck_peek ? (activeSharedPeekCards.length > 0 ? "공개된 덱 카드를 확인해 주세요" : "상대가 공개된 카드를 확인할 때까지 대기합니다") : game.deck_peek_in_progress && !game.my_deck_peek ? "상대가 덱을 살펴보고 있습니다" : "카드 순서는 기본적으로 비공개입니다"}</p>
          {canManualEffect && <div style={{ display: "grid", gap: 5, marginTop: 8 }}>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading || Boolean(game.deck_peek_locked)} onClick={() => void runAction("shuffle_deck")}>내 덱 전체 셔플</button>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading || n(game.my_deck_count) < 1 || Boolean(game.deck_peek_locked)} onClick={() => invokeDeckPeek(userId, n(game.my_deck_count))}>내 덱 위 N장 살펴보기</button>
            <button type="button" style={{ ...st.smallButton, width: "100%", borderColor: "rgba(252,211,77,.5)", color: C.gold }} disabled={loading || n(game.my_deck_count) < 1 || Boolean(game.deck_peek_locked)} onClick={() => void runAction("peek_deck", { source_user_id: userId, count: n(game.my_deck_count) })}>내 덱에서 골라 상대에게 잠시 공개</button>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading || n(opponentBoard?.deck_count) < 1 || Boolean(game.deck_peek_locked)} onClick={() => invokeDeckPeek(opponentBoard?.user_id, n(opponentBoard?.deck_count))}>상대 덱 위 N장 살펴보기</button>
            <button type="button" style={{ ...st.smallButton, width: "100%", background: "#4a1d2b", borderColor: "rgba(253,164,175,.4)" }} disabled={loading || n(game.my_deck_count) < 1 || Boolean(game.deck_peek_locked) || Boolean(pending)} onClick={invokeRemoveTopDeck}>N장 리무브 · 양쪽 확인</button>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading} onClick={invokePromptDraw}>효과 처리: N장 드로우</button>
          </div>}
        </div>

        <div className="mock-zone-evidence" style={st.panel}>
          <h2 style={st.zoneTitle}>증거 에이리어</h2>
          <div style={{ ...st.counts, gridTemplateColumns: "repeat(2,minmax(0,1fr))" }}><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>내 증거</div><div style={{ fontSize: 22, fontWeight: 900 }}>{myBoard?.evidence_count ?? 0}</div></div><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>상대 증거</div><div style={{ fontSize: 22, fontWeight: 900 }}>{opponentBoard?.evidence_count ?? 0}</div></div></div>
          {[{ board: opponentBoard, mine: false }, { board: myBoard, mine: true }].map(({ board, mine }) => {
            const publicCards = Array.isArray(board?.evidence_public_cards) ? board.evidence_public_cards : [];
            const hiddenCount = Math.max(0, n(board?.evidence_count) - publicCards.length);
            return <div key={`evidence-${mine ? "mine" : "opponent"}`} style={{ marginTop: 8, padding: 6, border: "1px solid rgba(255,255,255,.07)", borderRadius: 6, background: "#080d16" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 6, marginBottom: 7 }}><span style={{ fontSize: 9, color: C.muted, fontWeight: 800 }}>{mine ? "내 증거" : "상대 증거"} · 뒷면 {hiddenCount}장 / 공개 {publicCards.length}장</span><span style={{ fontSize: 8, color: "#6b7b94" }}>공개 카드는 아래에 표시됩니다.</span></div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                {Array.from({ length: Math.min(12, hiddenCount) }, (_, i) => <div key={`hidden-${i}`} style={{ width: 27, flex: "0 0 27px" }}><div style={{ ...st.faceDown, aspectRatio: "3/4" }} /></div>)}
                {publicCards.map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} title={`${nameOf(card)} · 공개 증거`} style={{ width: 42, flex: "0 0 42px", padding: 2, border: "1px solid rgba(252,211,77,.5)", borderRadius: 5, background: "#111827" }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={{ ...st.faceDown, aspectRatio: "3/4" }} />}<span style={{ display: "block", fontSize: 7, lineHeight: 1.2, color: C.gold, overflowWrap: "anywhere" }}>{nameOf(card)}</span></button>)}
              </div>
              {canManualEffect && n(board?.evidence_count) > 0 && <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8, paddingTop: 7, borderTop: "1px solid rgba(255,255,255,.06)" }}><button type="button" style={{ ...st.smallButton, minWidth: 104, background: "#263d63" }} disabled={loading} onClick={() => invokeExposeEvidence(board.user_id, n(board.evidence_count), mine ? "내 증거" : "상대 증거")}>위 N장 공개</button></div>}
            </div>;
          })}
        </div>

        <div className="mock-zone-remove" style={st.panel}>
          <h2 style={st.zoneTitle}>리무브 에이리어</h2>
          <div style={{ ...st.counts, gridTemplateColumns: "repeat(2,minmax(0,1fr))" }}><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>내 리무브</div><div style={{ fontSize: 22, fontWeight: 900 }}>{myBoard?.remove_count ?? 0}</div></div><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>상대 리무브</div><div style={{ fontSize: 22, fontWeight: 900 }}>{opponentBoard?.remove_count ?? 0}</div></div></div>
          <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 8 }} onClick={() => setShowRemoveArea(true)}>리무브 영역 보기</button>
        </div>

        <div className="mock-zone-files" style={st.panel}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}><h2 style={{ ...st.zoneTitle, marginBottom: 0 }}>파일 에이리어</h2><strong style={{ fontSize: 11 }}>내 파일 {myBoard?.file_count ?? 0}장 · 상대 파일 {opponentBoard?.file_count ?? 0}장</strong></div>
          <p style={{ ...st.muted, marginTop: 6 }}>두 플레이어의 파일 카드는 뒷면으로 가로 배치됩니다. 넥스트 힌트 사용 시 내 파일의 가장 최근 카드를 회수합니다.</p>
          <div style={{ display: "grid", gap: 6, marginTop: 8 }}>
            <div className="mock-file-row"><strong style={{ color: C.muted, fontSize: 9, flex: "0 0 72px" }}>상대 파일 · {n(opponentBoard?.file_count)}장</strong><div className="mock-file-card-strip" aria-label="상대 파일 카드">{Array.from({ length: Math.min(40, n(opponentBoard?.file_count)) }, (_, i) => <div key={i} className="mock-file-card" title="뒷면 파일 카드" />)}{!n(opponentBoard?.file_count) && <span style={{ color: C.muted, fontSize: 9 }}>파일 없음</span>}</div></div>
            <div className="mock-file-row"><strong style={{ color: C.muted, fontSize: 9, flex: "0 0 72px" }}>내 파일 · {n(myBoard?.file_count)}장</strong><div className="mock-file-card-strip" aria-label="내 파일 카드">{Array.from({ length: Math.min(40, n(myBoard?.file_count)) }, (_, i) => <div key={i} className="mock-file-card" title="뒷면 파일 카드" />)}{!n(myBoard?.file_count) && <span style={{ color: C.muted, fontSize: 9 }}>파일 없음</span>}</div>
              <div className="mock-file-assist">
                {myBoard?.partner_assist_used ? <>
                  {cardsByKey.get(String(myBoard?.partner_key))?.imageUrl ? <button type="button" onClick={() => openDetails({ key: myBoard.partner_key, instance_id: `partner-${userId}` })} style={{ flex: "0 0 43px", padding: 0, border: 0, background: "transparent" }}><img src={cardsByKey.get(String(myBoard.partner_key)).imageUrl} alt={cardsByKey.get(String(myBoard.partner_key)).name} style={{ width: "100%", maxHeight: 45, objectFit: "contain", transform: "rotate(90deg)" }} /></button> : <div style={{ width: 36 }} />}
                  <div style={{ minWidth: 0 }}><div style={{ fontSize: 8, color: C.gold, fontWeight: 900 }}>어시스트된 파트너</div><div style={{ fontSize: 8, color: C.red, overflowWrap: "anywhere" }}>{cardsByKey.get(String(myBoard?.partner_key))?.name || myBoard?.partner_key || "파트너"} · 슬립</div></div>
                </> : <><div style={{ width: 29, height: 38, flex: "0 0 29px", borderRadius: 4, border: "1px dashed rgba(252,211,77,.4)", display: "grid", placeItems: "center", color: C.gold, fontSize: 15 }}>＋</div><div style={{ minWidth: 0 }}><div style={{ fontSize: 8, color: C.gold, fontWeight: 900 }}>어시스트 파트너</div><div style={{ fontSize: 8, color: C.muted }}>파트너 어시스트 시 이곳에 표시됩니다</div></div></>}
              </div>
            </div>
          </div>
        </div>
      </section>

      {!game.game_over && <section style={{ ...st.panel, marginTop: 10 }}>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 10, flexWrap: "wrap", alignItems: "baseline" }}><h2 style={st.zoneTitle}>턴 컨트롤</h2><span style={{ color: C.muted, fontSize: 10 }}>현재 코스트 상한 {costLimit} · 기본 출동 {myBoard?.character_played_this_turn ? "사용함" : "미사용"}</span></div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 12, marginBottom: 9 }}>
          <label style={{ display: "flex", alignItems: "flex-start", gap: 6, fontSize: 9, color: C.muted, lineHeight: 1.45 }}><input type="checkbox" checked={allowActiveTargets} onChange={(event) => setAllowActiveTargets(event.target.checked)} /> 효과에 따라 액티브 상대 캐릭터도 공격 대상으로 허용</label>
          <label style={{ display: "flex", alignItems: "flex-start", gap: 6, fontSize: 9, color: C.muted, lineHeight: 1.45 }}><input type="checkbox" checked={allowFreshlyPlayed} onChange={(event) => setAllowFreshlyPlayed(event.target.checked)} /> 효과로 이번 턴 출동한 캐릭터도 즉시 행동 가능</label>
        </div>
        {game.turn_step === "begin" && (isMyTurn ? <button type="button" style={st.button} disabled={loading || pending} onClick={() => void runAction("begin_turn")}>턴 시작 · 액티브화 · 손패 1장 드로우</button> : <p style={st.muted}>상대가 턴을 시작할 때까지 대기합니다.</p>)}
        {game.turn_step === "file" && <div><p style={{ ...st.muted, marginBottom: 8 }}>{isMyTurn ? `덱 위에서 파일 ${Math.max(0, fileTarget - filesPlaced)}장을 뒤집어 배치합니다.` : `상대가 파일 ${currentTurnBoard?.files_to_place ?? 0}장을 배치하고 있습니다.`}</p>{isMyTurn && <button type="button" style={st.button} disabled={loading} onClick={() => void runAction("place_files")}>덱 위에서 파일 {Math.max(0, fileTarget - filesPlaced)}장 배치</button>}</div>}
        {canSelectNextHintCard && <p style={{ ...st.muted, color: C.gold, marginTop: 8 }}>파일을 손패로 가져왔습니다. 아래 손패에서 출동할 캐릭터를 선택해 주세요. 선택 중에는 다른 행동이 일시 중지됩니다.</p>}
        {canActMain && <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 5 }}>
          {myBoard?.base_action_done && n(myBoard?.file_count) > 0 && <button type="button" style={st.button} disabled={loading} onClick={() => void runAction("next_hint_take_file")}>넥스트 힌트 선언 · 파일을 손패로</button>}
          <button type="button" style={{ ...st.button, background: "#4b2637" }} disabled={loading || pending} onClick={() => void runAction("end_turn")}>턴 종료</button>
        </div>}
        {myBoard?.base_action_done && game.turn_step === "main" && <p style={{ ...st.muted, marginTop: 8 }}>기본 행동을 완료했습니다. 파일이 남아 있는 동안 넥스트 힌트를 연속으로 사용할 수 있습니다. 넥스트 힌트 후에도 파트너 추리는 가능하지만 어시스트는 사용할 수 없습니다.</p>}
      </section>}

      <section style={{ ...st.panel, marginTop: 10 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap" }}><h2 style={{ ...st.zoneTitle, marginBottom: 0 }}>내 손패 · {myHand.length}장</h2><div style={{ display: "flex", alignItems: "center", justifyContent: "flex-end", flexWrap: "wrap", gap: 7 }}><span style={{ padding: "5px 8px", borderRadius: 7, border: "1px solid rgba(134,239,172,.25)", background: "rgba(22,101,52,.12)", color: C.green, fontSize: 9, fontWeight: 850 }}>{costLimit}코스트의 카드까지 현장 출동 가능 · 파일 {n(myBoard?.file_count)}장{myBoard?.partner_assist_used ? " + 파트너 어시스트 1" : ""}</span><span style={st.muted}>카드 이미지를 선택하면 상세 설명을 확인할 수 있습니다.</span></div></div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(104px,1fr))", gap: 7, marginTop: 9 }}>
          {myHand.map((card) => {
            const info = infoFor(card);
            const normalPlay = canActMain && card.card_type === "character" && !myBoard?.character_played_this_turn && n(card.cost) <= costLimit;
            const nextSelected = selectedNextHint === card.instance_id;
            return <article key={card.instance_id} style={{ minWidth: 0, padding: 6, border: `1px solid ${nextSelected ? "#fb7185" : "rgba(148,163,184,.15)"}`, borderRadius: 7, background: "#080d16" }}>
              <button type="button" onClick={() => openDetails(card)} style={{ display: "block", width: "100%", border: 0, background: "transparent", color: C.text, padding: 0 }}><CardArt instance={card} /><div style={{ fontSize: 10, fontWeight: 800, lineHeight: 1.35, marginTop: 5, textAlign: "left", overflowWrap: "anywhere" }}>{info?.name || card.key}</div></button>
              <div style={{ fontSize: 9, color: C.muted, marginTop: 3 }}>코스트 {card.cost ?? "-"} · AP {card.ap ?? "-"}</div>
              {(canActMain || canSelectNextHintCard) && card.card_type === "character" && <div style={{ display: "grid", gap: 4, marginTop: 6 }}>
                {canActMain && !myBoard?.next_hint_pending && <button type="button" style={{ ...st.smallButton, opacity: n(card.cost) > costLimit || myBoard?.character_played_this_turn || (myBoard?.field_cards?.length || 0) >= 5 ? .72 : 1 }} disabled={loading} onClick={() => {
                  if (n(card.cost) > costLimit) { showBlockedReason(`필요 코스트를 충족하지 않아 사용할 수 없습니다. 현재 코스트 상한은 ${costLimit}입니다.`); return; }
                  if (myBoard?.character_played_this_turn) { showBlockedReason("이번 턴의 기본 출동을 이미 사용했습니다. 추가 출동은 효과 처리 버튼을 이용해 주세요."); return; }
                  if ((myBoard?.field_cards?.length || 0) >= 5 && String(card.rarity || "").toUpperCase() !== "MR") { showBlockedReason("현장에 이미 카드가 5장 있습니다. 먼저 현장 카드를 이동해 주세요."); return; }
                  void runAction("play_character", { instance_id: card.instance_id });
                }}>기본 출동</button>}
                {canSelectNextHintCard && <button type="button" style={{ ...st.smallButton, borderColor: "#fb7185", color: C.red, opacity: n(card.cost) > (costLimit + 1) ? .72 : 1 }} disabled={loading} onClick={() => {
                  const nextCostLimit = n(myBoard?.file_count) + 1 + (myBoard?.partner_assist_used ? 1 : 0);
                  if (n(card.cost) > nextCostLimit) { showBlockedReason(`필요 코스트를 충족하지 않아 넥스트 힌트로 출동할 수 없습니다. 선언 전 기준 코스트 상한은 ${nextCostLimit}입니다.`); return; }
                  void runAction("next_hint", { instance_id: card.instance_id });
                }}>이 카드로 넥스트 힌트 출동</button>}
              </div>}
              {canActMain && card.card_type === "event" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 6, background: "#075985", opacity: n(card.cost) > costLimit || (myBoard?.field_cards?.length || 0) >= 5 ? .72 : 1 }} disabled={loading} onClick={() => {
                if (n(card.cost) > costLimit) { showBlockedReason(`필요 코스트를 충족하지 않아 이벤트를 사용할 수 없습니다. 현재 코스트 상한은 ${costLimit}입니다.`); return; }
                if ((myBoard?.field_cards?.length || 0) >= 5) { showBlockedReason("현장에 이미 카드가 5장 있습니다. 먼저 현장 카드를 이동해 주세요."); return; }
                void runAction("play_event", { instance_id: card.instance_id });
              }}>현장에 이벤트 사용</button>}
              {canManualEffect && card.card_type === "character" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, background: "#3b2f5c" }} disabled={loading} onClick={() => { if ((myBoard?.field_cards?.length || 0) >= 5 && String(card.rarity || "").toUpperCase() !== "MR") { showBlockedReason("현장에 이미 카드가 5장 있습니다. 먼저 현장 카드를 이동해 주세요."); return; } void runAction("extra_play_character", { instance_id: card.instance_id, effect_override: true }); }}>효과로 추가 출동<br />(제한 무시)</button>}
              {canManualEffect && <div style={{ display: "grid", gap: 4, marginTop: 5 }}><button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${info?.name || card.key}를 손패에서 리무브 영역으로 옮길까요?`)) void runAction("move_hand_card", { instance_id: card.instance_id, destination: "remove" }); }}>손패에서 리무브</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${info?.name || card.key}를 덱 맨 아래로 옮길까요?`)) void runAction("move_hand_card", { instance_id: card.instance_id, destination: "deck" }); }}>손패에서 덱 아래로</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${info?.name || card.key}를 덱 맨 위로 옮길까요?`)) void runAction("move_hand_card", { instance_id: card.instance_id, destination: "deck_top" }); }}>손패에서 덱 위로</button></div>}
            </article>;
          })}
          {!myHand.length && <p style={st.muted}>손패가 비어 있습니다.</p>}
        </div>
      </section>

      {canWinCase && <div style={{ position: "fixed", zIndex: 99980, right: 14, bottom: 14, maxWidth: "min(390px, calc(100vw - 28px))", display: "flex", alignItems: "center", gap: 9, padding: "10px 13px", border: "1px solid #22c55e", borderRadius: 10, color: "#f0fdf4", background: "rgba(20,83,45,.97)", boxShadow: "0 8px 30px rgba(20,83,45,.35)", pointerEvents: "none" }}><span style={{ display: "grid", placeItems: "center", width: 27, height: 27, flex: "0 0 27px", borderRadius: "50%", background: "#16a34a", color: "white", fontSize: 20, fontWeight: 1000 }}>!</span><strong style={{ fontSize: 11, lineHeight: 1.45 }}>사건 해결 선언이 가능합니다</strong></div>}
      {canTransitionSolution && <div style={{ position: "fixed", zIndex: 99980, left: 14, bottom: 14, maxWidth: "min(390px, calc(100vw - 28px))", display: "flex", alignItems: "center", gap: 9, padding: "10px 13px", border: "1px solid #ef4444", borderRadius: 10, color: "#fff1f2", background: "rgba(127,29,29,.96)", boxShadow: "0 8px 30px rgba(127,29,29,.35)", pointerEvents: "none" }}><span style={{ display: "grid", placeItems: "center", width: 27, height: 27, flex: "0 0 27px", borderRadius: "50%", background: "#ef4444", color: "white", fontSize: 20, fontWeight: 1000 }}>!</span><strong style={{ fontSize: 11, lineHeight: 1.45 }}>지금부터 해결편으로 전환할 수 있습니다</strong></div>}

      {showRemoveArea && minimizedModal !== "remove" && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowRemoveArea(false); }} style={{ position: "fixed", inset: 0, zIndex: 100000, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.84)", backdropFilter: "blur(4px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "remove")} role="dialog" aria-modal="true" aria-label="리무브 영역 목록" style={{ width: "min(100%, 920px)", maxHeight: "92dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(148,163,184,.24)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 12, borderBottom: "1px solid rgba(255,255,255,.09)" }}><div><h2 style={{ margin: 0, fontSize: 17 }}>리무브 영역</h2><p style={{ ...st.muted, marginTop: 4 }}>내 리무브 {myRemoveCards.length}장 · 상대 리무브 {opponentRemoveCards.length}장</p></div><button type="button" style={st.button} onClick={() => setShowRemoveArea(false)}>닫기 ✕</button></header>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 10, padding: 12, overflowY: "auto" }}>{[{ label: "내 리무브", cards: myRemoveCards }, { label: "상대 리무브", cards: opponentRemoveCards }].map((pile) => <div key={pile.label} style={{ minWidth: 0, padding: 8, border: "1px solid rgba(255,255,255,.08)", borderRadius: 8, background: "#080d16" }}><h3 style={{ margin: "0 0 8px", fontSize: 11, color: C.blue }}>{pile.label} · {pile.cards.length}장</h3><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(86px,1fr))", gap: 6 }}>{pile.cards.map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} style={{ border: "1px solid rgba(255,255,255,.1)", borderRadius: 6, padding: 5, background: "#101827", color: C.text, minWidth: 0 }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<div style={{ fontSize: 9, lineHeight: 1.3, overflowWrap: "anywhere", marginTop: 4 }}>{nameOf(card)}</div></button>)}</div>{!pile.cards.length && <p style={st.muted}>비어 있습니다.</p>}</div>)}</div>
        </section>
      </div>}

      {deckRemovalPending && <div style={{ position: "fixed", inset: 0, zIndex: 100180, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.91)", backdropFilter: "blur(7px)" }}>
        <section role="dialog" aria-modal="true" aria-label="덱 위 카드 리무브 공개 확인" style={{ width: "min(100%, 860px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(253,164,175,.55)", borderRadius: 14, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.75)" }}>
          <header style={{ padding: 14, borderBottom: "1px solid rgba(255,255,255,.09)" }}><h2 style={{ margin: 0, color: C.red, fontSize: 18 }}>덱 위 카드 공개 · 리무브 확인</h2><p style={{ ...st.muted, marginTop: 5, fontSize: 11 }}>덱에서 이동할 카드 {deckRemovalCards.length}장을 양쪽 플레이어가 확인합니다. 두 사람 모두 확인하면 해당 카드가 리무브 에이리어로 이동합니다.</p></header>
          <div style={{ padding: 12, overflowY: "auto" }}><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(100px,1fr))", gap: 8 }}>{deckRemovalCards.map((card, index) => <button key={`${card.instance_id || card.key}-${index}`} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 6, border: "1px solid rgba(253,164,175,.25)", borderRadius: 7, background: "#080d16", color: C.text, textAlign: "left" }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 9, fontWeight: 800, overflowWrap: "anywhere" }}>{nameOf(card)}</span><span style={{ display: "block", marginTop: 3, color: C.muted, fontSize: 8 }}>코스트 {card.cost ?? infoFor(card)?.cost ?? "-"}</span></button>)}</div>
          </div>
          <footer style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap", padding: 12, borderTop: "1px solid rgba(255,255,255,.09)" }}><span style={st.muted}>확인 완료 {deckRemovalAcknowledged.length}/2명</span>{deckRemovalAcknowledged.includes(userId) ? <button type="button" style={{ ...st.button, background: "#374151" }} disabled>{"확인 완료 · 상대 확인 대기"}</button> : <button type="button" style={{ ...st.button, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("acknowledge_deck_remove")}>카드를 확인했고 리무브에 동의</button>}</footer>
        </section>
      </div>}

      {ownPeek && minimizedModal !== "peek" && <div style={{ position: "fixed", inset: 0, zIndex: 100010, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.82)", backdropFilter: "blur(4px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "peek")} role="dialog" aria-modal="true" aria-label="덱 위 카드 살펴보기" style={{ width: "min(100%, 980px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(147,197,253,.3)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <header style={{ padding: 13, borderBottom: "1px solid rgba(255,255,255,.09)" }}><h2 style={{ margin: 0, fontSize: 16 }}>덱 위 카드 살펴보기</h2><p style={{ ...st.muted, marginTop: 5 }}>{ownPeek.source_user_id === userId ? "내 덱" : `${ownPeek.source_display_name || "상대"}의 덱`} 위에서 꺼낸 {ownPeekCards.length}장 · 이 창은 본인에게만 표시됩니다. 위에서 아래 순서가 덱 맨 위부터의 순서입니다.</p></header>
          <div style={{ padding: 12, overflowY: "auto", display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(115px,1fr))", gap: 8 }}>
            {ownPeekOrder.map((card, index) => {
              const shared = (ownPeek.shared_instance_ids || []).includes(card.instance_id);
              return <article key={card.instance_id} style={{ padding: 7, border: `1px solid ${shared ? "rgba(252,211,77,.8)" : "rgba(255,255,255,.12)"}`, borderRadius: 8, background: "#080d16", minWidth: 0 }}>
                <button type="button" onClick={() => openDetails(card)} style={{ display: "block", width: "100%", padding: 0, border: 0, background: "transparent", color: C.text }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", maxHeight: 220, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<div style={{ marginTop: 4, textAlign: "left", fontSize: 10, fontWeight: 800, overflowWrap: "anywhere" }}>{index + 1}. {nameOf(card)}</div></button>
                <div style={{ display: "flex", gap: 4, marginTop: 7 }}><button type="button" style={st.smallButton} disabled={loading || index === 0} onClick={() => setPeekOrderIds((ids) => { const next = [...ids]; [next[index - 1], next[index]] = [next[index], next[index - 1]]; return next; })}>↑ 위</button><button type="button" style={st.smallButton} disabled={loading || index === ownPeekOrder.length - 1} onClick={() => setPeekOrderIds((ids) => { const next = [...ids]; [next[index], next[index + 1]] = [next[index + 1], next[index]]; return next; })}>↓ 아래</button></div>
                {ownPeek.source_user_id === userId && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, color: C.green, borderColor: "rgba(134,239,172,.25)" }} disabled={loading} onClick={() => { if (shared) { showBlockedReason("상대에게 공개하도록 지정한 카드는 공개 선택을 취소한 뒤 손패로 가져올 수 있습니다."); return; } void runAction("take_deck_peek_card", { instance_id: card.instance_id }); }}>이 카드를 손패로 가져오기</button>}
                <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, color: shared ? C.gold : C.text, borderColor: shared ? "rgba(252,211,77,.65)" : "rgba(255,255,255,.13)" }} disabled={loading} onClick={() => void runAction("share_deck_peek_card", { instance_id: card.instance_id })}>{shared ? "상대에게 공개 중 · 취소" : "이 카드 상대에게 공개"}</button>
              </article>;
            })}
          </div>
          <footer style={{ display: "flex", gap: 7, justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", padding: 12, borderTop: "1px solid rgba(255,255,255,.09)" }}><button type="button" style={{ ...st.smallButton, color: C.gold, borderColor: "rgba(252,211,77,.4)" }} disabled={loading || !ownPeekCards.length} onClick={() => void runAction("share_all_deck_peek_cards")}>{allOwnPeekCardsShared ? "전체 공개 선택 취소" : "전체 카드를 상대에게 공개"}</button><div style={{ display: "flex", gap: 7, flexWrap: "wrap", justifyContent: "flex-end" }}><button type="button" style={{ ...st.button, background: "#164e63" }} disabled={loading || ownPeekOrder.length !== ownPeekCards.length} onClick={() => void runAction("return_deck_peek", { destination: "top", instance_order: peekOrderIds })}>원래 순서로 덱 위에 되돌리기</button><button type="button" style={st.button} disabled={loading || ownPeekOrder.length !== ownPeekCards.length} onClick={() => void runAction("return_deck_peek", { destination: "bottom", instance_order: peekOrderIds })}>지정 순서로 덱 아래에 넣기</button></div></footer>
        </section>
      </div>}

      {activeSharedPeekCards.length > 0 && dismissedSharedPeekSignature !== sharedPeekSignature && minimizedModal !== "sharedPeek" && <div style={{ position: "fixed", inset: 0, zIndex: 100015, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.8)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "sharedPeek")} role="dialog" aria-modal="true" aria-label="상대가 공개한 덱 카드" style={{ width: "min(100%, 760px)", maxHeight: "90dvh", overflowY: "auto", padding: 13, border: "1px solid rgba(252,211,77,.55)", borderRadius: 12, background: "#111a2a", color: C.text }}><h2 style={{ margin: "0 0 5px", fontSize: 16 }}>상대가 덱에서 공개한 카드</h2><p style={{ ...st.muted, marginBottom: 10 }}>상대가 공개 대상으로 지정한 카드만 표시됩니다.</p><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(110px,1fr))", gap: 8 }}>{activeSharedPeekCards.map((entry) => <button key={`${entry.source_user_id}-${entry.card?.instance_id}`} type="button" onClick={() => openDetails(entry.card)} style={{ padding: 7, border: "1px solid rgba(252,211,77,.3)", borderRadius: 7, background: "#080d16", color: C.text }}>{infoFor(entry.card)?.imageUrl ? <img src={infoFor(entry.card).imageUrl} alt={nameOf(entry.card)} style={{ width: "100%", maxHeight: 210, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 10, fontWeight: 800, overflowWrap: "anywhere" }}>{nameOf(entry.card)}</span><span style={{ display: "block", fontSize: 8, color: C.gold }}>{entry.source_display_name || "상대 덱"}</span></button>)}</div><div style={{ display: "flex", justifyContent: "flex-end", marginTop: 11 }}><button type="button" style={st.button} disabled={loading} onClick={() => activeSharedPeekCards.every((entry) => entry.returned) ? void runAction("acknowledge_shared_deck_peek") : setDismissedSharedPeekSignature(sharedPeekSignature)}>{activeSharedPeekCards.every((entry) => entry.returned) ? "공개 카드 확인 완료" : "확인 (덱 반환 후 다시 알림)"}</button></div></section>
      </div>}

      {isContactPending && minimizedModal !== "contact" && <div style={{ position: "fixed", inset: 0, zIndex: 100030, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "contact")} role="dialog" aria-modal="true" aria-label="컨택 및 컷인 선택" style={{ width: "min(100%, 700px)", maxHeight: "90dvh", overflowY: "auto", padding: 15, border: "1px solid rgba(251,113,133,.6)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <div style={{ color: C.red, fontSize: 9, letterSpacing: ".15em", fontWeight: 900 }}>CONTACT</div><h2 style={{ margin: "4px 0 7px", fontSize: 18 }}>컨택 발생 · 컷인 선택</h2><p style={{ ...st.muted, marginBottom: 10 }}>수비자가 먼저 컷인 사용 여부를 선택하고, 수비자가 패스하면 공격자가 선택합니다. 컷인은 컨택당 최대 1회 사용할 수 있으며, 선택이 완료되면 최종 AP를 비교합니다.</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 9 }}>
            {[{ title: "공격자", board: contactAttackerBoard, card: contactAttackerCard, ap: n(pending.attacker_ap) + n(pending.attacker_bonus) }, { title: "수비자", board: contactTargetBoard, card: contactTargetCard, ap: n(pending.target_ap) + n(pending.target_bonus) }].map((entry) => <div key={entry.title} style={{ padding: 8, border: "1px solid rgba(255,255,255,.1)", borderRadius: 8, background: "#080d16", minWidth: 0 }}><div style={{ fontSize: 9, color: C.muted }}>{entry.title} · {entry.board?.display_name || "플레이어"}</div>{entry.card && <button type="button" onClick={() => openDetails(entry.card)} style={{ display: "block", width: "100%", padding: 0, marginTop: 6, border: 0, background: "transparent", color: C.text }}>{infoFor(entry.card)?.imageUrl ? <img src={infoFor(entry.card).imageUrl} alt={nameOf(entry.card)} style={{ width: "100%", maxHeight: 175, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", fontSize: 10, marginTop: 5, overflowWrap: "anywhere" }}>{nameOf(entry.card)}</span></button>}<strong style={{ display: "block", marginTop: 8, fontSize: 16 }}>AP {entry.ap}</strong></div>)}
          </div>
          {pending.next_responder_user_id === userId ? <><p style={{ fontSize: 11, color: C.gold, margin: "12px 0 7px" }}>{userId === pending.target_user_id ? "수비자 차례: 컷인 사용 여부를 선택해 주세요." : "수비자가 패스했습니다. 이제 공격자가 컷인 사용 여부를 선택합니다."}</p><div style={{ display: "grid", gap: 6 }}>{myHand.filter((card) => n(card.cut_in_bonus) > 0).map((card) => <button key={card.instance_id} type="button" style={{ ...st.button, background: "#164e63" }} disabled={loading} onClick={() => void runAction("contact_use_cutin", { instance_id: card.instance_id })}>{nameOf(card)} · 컷인 +{n(card.cut_in_bonus)}</button>)}</div>{myHand.every((card) => n(card.cut_in_bonus) <= 0) && <p style={{ ...st.muted, marginTop: 6 }}>컷인 사용 여부를 선택해 주세요. 사용하지 않으면 다음 단계로 진행됩니다.</p>}<button type="button" style={{ ...st.button, background: "#273244", width: "100%", marginTop: 8 }} disabled={loading} onClick={() => void runAction("contact_pass_cutin")}>{userId === pending.target_user_id ? "컷인 없이 공격자에게 넘기기" : "컷인 없이 최종 AP 비교"}</button></> : <p style={{ margin: "12px 0 0", fontSize: 11, color: C.muted }}>{pending.next_responder_user_id === pending.target_user_id ? "수비자가 컷인 사용 여부를 선택하고 있습니다." : "공격자가 컷인 사용 여부를 선택하고 있습니다."}</p>}
        </section>
      </div>}

      {revealedEvidenceCard && minimizedModal !== "evidence" && <div style={{ position: "fixed", inset: 0, zIndex: 100030, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "evidence")} role="dialog" aria-modal="true" aria-label="공개된 증거 카드" style={{ width: "min(100%, 460px)", maxHeight: "90dvh", overflowY: "auto", padding: 15, border: "1px solid rgba(252,211,77,.55)", borderRadius: 12, background: "#111a2a", color: C.text, textAlign: "center" }}><h2 style={{ margin: "0 0 6px", fontSize: 17 }}>증거 공격 · 카드 공개</h2><p style={{ ...st.muted, marginBottom: 10 }}>공격 대상이 된 증거 카드가 양쪽 플레이어에게 공개되었습니다. 확인하면 리무브 영역으로 이동합니다.</p><button type="button" onClick={() => openDetails(revealedEvidenceCard)} style={{ width: "min(100%, 230px)", border: 0, padding: 0, background: "transparent" }}>{infoFor(revealedEvidenceCard)?.imageUrl ? <img src={infoFor(revealedEvidenceCard).imageUrl} alt={nameOf(revealedEvidenceCard)} style={{ width: "100%", maxHeight: "48vh", objectFit: "contain" }} /> : <div style={st.faceDown} />}<strong style={{ display: "block", marginTop: 6, fontSize: 12 }}>{nameOf(revealedEvidenceCard)}</strong></button>{pending.target_user_id === userId ? <button type="button" style={{ ...st.button, width: "100%", marginTop: 12, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("resolve_evidence_attack")}>공개 확인 · 리무브로 이동</button> : <p style={{ ...st.muted, marginTop: 10 }}>수비자가 확인한 후 리무브 영역으로 이동합니다.</p>}</section>
      </div>}

      {detailCard && minimizedModal !== "detail" && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setDetailCard(null); }} style={{ position: "fixed", inset: 0, zIndex: game.game_over ? 100300 : 100100, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.83)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "detail")} role="dialog" aria-modal="true" aria-label={`${nameOf(detailCard)} 카드 상세`} style={{ width: "min(100%, 980px)", maxHeight: "94dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(255,255,255,.16)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.65)" }}>
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

      {minimizedModalExists && <button type="button" onClick={() => setMinimizedModal("")} style={{ position: "fixed", zIndex: 100250, left: "50%", bottom: 14, transform: "translateX(-50%)", padding: "10px 16px", borderRadius: 999, border: "1px solid rgba(147,197,253,.65)", color: "#eff6ff", background: "rgba(30,58,95,.97)", boxShadow: "0 8px 28px rgba(0,0,0,.55)", fontSize: 11, fontWeight: 900 }}>접힌 창 복구 · {minimizedModalLabels[minimizedModal] || "창"}</button>}

      {blockedToast && <div role="alert" aria-live="assertive" style={{ position: "fixed", zIndex: 100260, right: 14, bottom: canWinCase ? 78 : 14, width: "min(430px, calc(100vw - 28px))", display: "flex", alignItems: "flex-start", gap: 10, padding: "12px 14px", border: "1px solid #ef4444", borderRadius: 11, background: "rgba(69,10,10,.97)", color: "#fff1f2", boxShadow: "0 12px 32px rgba(0,0,0,.5)" }}><span style={{ display: "grid", placeItems: "center", width: 27, height: 27, flex: "0 0 27px", borderRadius: "50%", background: "#dc2626", color: "white", fontSize: 18, fontWeight: 1000 }}>!</span><span style={{ fontSize: 11, lineHeight: 1.55, fontWeight: 750 }}>{blockedToast}</span><button type="button" onClick={() => setBlockedToast("")} aria-label="안내 닫기" style={{ marginLeft: "auto", border: 0, background: "transparent", color: "#fecaca", fontSize: 15 }}>×</button></div>}

      {game.game_over && <div style={{ position: "fixed", inset: 0, zIndex: 100200, display: "flex", alignItems: "center", justifyContent: "center", padding: 18, background: "rgba(0,0,0,.96)", color: "#f8fafc" }}>
        <section style={{ width: "min(100%, 540px)", padding: "clamp(22px, 5vw, 42px)", textAlign: "center", border: "1px solid rgba(134,239,172,.3)", borderRadius: 18, background: "linear-gradient(160deg,#111827,#05070b)", boxShadow: "0 24px 80px rgba(0,0,0,.7)" }}>
          <div style={{ color: C.green, fontSize: 10, letterSpacing: ".22em", fontWeight: 950 }}>CASE CLOSED</div>
          <h1 style={{ margin: "12px 0 9px", fontSize: "clamp(28px, 7vw, 42px)", fontWeight: 950, color: "#f0fdf4" }}>{winnerName} 승리!</h1>
          <p style={{ margin: "0 0 22px", color: "#a7b4c8", fontSize: 13 }}>턴 {n(game.winner_turn_number, n(game.turn_number))} 소요</p>
          <button type="button" disabled={loadingOpponentDeck} onClick={() => void openOpponentDeckAfterGame()} style={{ width: "100%", padding: "12px 16px", border: "1px solid #22c55e", borderRadius: 10, background: "#166534", color: "white", fontSize: 13, fontWeight: 900, cursor: loadingOpponentDeck ? "wait" : "pointer", opacity: loadingOpponentDeck ? .6 : 1 }}>{loadingOpponentDeck ? "상대 덱을 불러오는 중…" : "상대 덱 보기 →"}</button>
          <p style={{ ...st.muted, marginTop: 12 }}>버튼을 누르면 상대의 덱 구성을 확인할 수 있습니다.</p>
        </section>
      </div>}

      {opponentDeckAfterWin && minimizedModal !== "opponentDeck" && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpponentDeckAfterWin(null); }} style={{ position: "fixed", inset: 0, zIndex: 100220, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.9)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "opponentDeck")} role="dialog" aria-modal="true" aria-label="상대 덱 보기" style={{ width: "min(100%, 1040px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(134,239,172,.3)", borderRadius: 13, background: "#101827", color: C.text }}>
          <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: 14, borderBottom: "1px solid rgba(255,255,255,.1)" }}><div><h2 style={{ margin: 0, fontSize: 18 }}>{opponentDeckAfterWin.opponent_name || "상대"}의 덱</h2><p style={{ ...st.muted, marginTop: 4 }}>게임 종료 후 공개된 상대 덱 · 총 {(opponentDeckAfterWin.cards || []).length}장 및 특수 카드</p></div><button type="button" style={st.button} onClick={() => setOpponentDeckAfterWin(null)}>닫기 ✕</button></header>
          <div style={{ padding: 12, overflowY: "auto" }}>{opponentDeckGroups.map((group) => group.cards.length > 0 && <section key={group.key} style={{ marginBottom: 15 }}><header style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 8, marginBottom: 8, paddingBottom: 6, borderBottom: "1px solid rgba(255,255,255,.1)" }}><h3 style={{ margin: 0, color: group.key === "event" ? C.gold : C.blue, fontSize: 12, fontWeight: 900 }}>{group.label}</h3><span style={st.muted}>{group.cards.length}장 · 코스트 높은 순</span></header><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(95px,1fr))", gap: 7 }}>{group.cards.map((card, index) => <button key={`${card.instance_id || card.key}-${index}`} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 6, border: "1px solid rgba(255,255,255,.1)", borderRadius: 7, background: "#080d16", color: C.text, textAlign: "left" }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 9, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere" }}>{nameOf(card)}</span><span style={{ display: "block", marginTop: 3, color: C.muted, fontSize: 8 }}>코스트 {card.cost ?? infoFor(card)?.cost ?? "-"}</span></button>)}</div></section>)}</div>
        </section>
      </div>}
    </main>
  );
}
