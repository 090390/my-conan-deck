import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";

const C = {
  bg: "#080d17", panel: "#101827", panel2: "#0b1220", border: "rgba(148,163,184,.22)",
  text: "#e8edf7", muted: "#94a3b8", blue: "#93c5fd", red: "#fda4af", green: "#86efac", gold: "#fcd34d",
};
const HAND_TO_PARTNER_LABEL = "파트너로";

function n(value, fallback = 0) {
  const valueNumber = Number(value);
  return Number.isFinite(valueNumber) ? valueNumber : fallback;
}
function normalizeEffectQuotes(value) {
  return String(value ?? "").replace(/[“”]/gu, (quote) => quote === "“" ? "「" : "」");
}
function countDelta(current, previous) {
  const delta = Number(current || 0) - Number(previous ?? current ?? 0);
  return delta === 0 ? "±0" : `${delta > 0 ? "+" : ""}${delta}`;
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

const TRAIT_TRANSLATIONS = new Map([
  ["怪盗", "괴도"], ["高校生", "고등학생"], ["マジシャン", "마술사"],
  ["探偵", "탐정"], ["小学生", "초등학생"], ["警察", "경찰"], ["刑事", "형사"],
  ["公安", "공안"], ["FBI", "FBI"], ["黒ずくめの組織", "검은 조직"],
  ["犯人", "범인"], ["怪盗団", "괴도단"], ["高校", "고등학생"],
]);
const JAPANESE_TRAIT_CHARS = /[\u3040-\u30ff\u3400-\u9fff]/u;
function traitTokens(value) {
  const values = Array.isArray(value) ? value : [value];
  return values.flatMap((entry) => typeof entry === "string" ? entry.split(/[|｜,，、/／·・]+/u) : [])
    .map((token) => token.trim())
    .filter(Boolean)
    .map((token) => TRAIT_TRANSLATIONS.get(token) || TRAIT_TRANSLATIONS.get(token.toLocaleUpperCase()) || token)
    .filter((token) => !JAPANESE_TRAIT_CHARS.test(token));
}
function normalizeCardTraits(card) {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const inputs = [
    card?.traitsKo, card?.traits_ko, card?.traits, card?.trait, card?.characteristics, card?.characteristic,
    card?.category1Ko, card?.category2Ko, card?.category3Ko,
    source?.traitsKo, source?.traits_ko, source?.traits, source?.trait, source?.characteristics, source?.characteristic,
    source?.category1Ko, source?.category2Ko, source?.category3Ko,
    card?.category1, card?.category_1, card?.category2, card?.category_2, card?.category3, card?.category_3,
    source?.category1, source?.category_1, source?.category2, source?.category_2, source?.category3, source?.category_3,
  ];
  const results = [];
  for (const token of inputs.flatMap(traitTokens)) if (!results.includes(token)) results.push(token);
  return results;
}
function cardDisguiseEffect(card) {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : card?.raw && typeof card.raw === "object" ? card.raw : {};
  return String(
    card?.disguiseEffect || card?.disguise_effect || card?.disguise || card?.henso || card?.hensoEffect ||
    card?.gameSystemEffects?.disguise || card?.gameSystemEffects?.henso ||
    source?.disguiseEffect || source?.disguise_effect || source?.disguise || source?.henso || source?.hensoEffect || ""
  ).trim();
}

function normalizeRuleCardId(value) {
  const raw = String(value ?? "").trim().toLocaleUpperCase();
  if (!raw) return "";
  return /^\d+$/.test(raw) ? String(Number(raw)) : raw;
}

function cardHasRuleId(card, targetId) {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const target = normalizeRuleCardId(targetId);
  return [card?.key, card?.databaseId, card?.cardId, card?.cardNum, card?.id,
    source?.id, source?.databaseId, source?.database_id, source?.cardId, source?.card_id, source?.cardNum, source?.card_num]
    .some((value) => normalizeRuleCardId(value) === target);
}

function cardHasCulpritTrait(card) {
  const values = Array.isArray(card?.traits) ? card.traits : card?.traits == null ? [] : [card.traits];
  return values.some((value) => {
    const token = String(value ?? "").normalize("NFKC").replace(/\s+/gu, "").toLocaleLowerCase();
    return token === "범인" || (token.includes("특징") && token.includes("범인"));
  });
}

export default function MatchTurnBoard({ roomId, userId, cards = [], inviteCode = "", isAIBattle = false, onLeaveField = null, onReturnToLobby = null }) {
  const [game, setGame] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [selectedNextHint, setSelectedNextHint] = useState("");
  const [localBaseCardPlayLocked, setLocalBaseCardPlayLocked] = useState(false);
  const [selectedAttacker, setSelectedAttacker] = useState("");
  const [allowActiveTargetsByCard, setAllowActiveTargetsByCard] = useState({});
  const [allowFreshlyPlayedByCard, setAllowFreshlyPlayedByCard] = useState({});
  const [showRemoveArea, setShowRemoveArea] = useState(false);
  const [detailCard, setDetailCard] = useState(null);
  const [peekOrderIds, setPeekOrderIds] = useState([]);
  const [selectedPeekInstanceId, setSelectedPeekInstanceId] = useState("");
  const [dismissedSharedPeekSignature, setDismissedSharedPeekSignature] = useState("");
  const [blockedToast, setBlockedToast] = useState("");
  const [minimizedModal, setMinimizedModal] = useState("");
  const [opponentDeckAfterWin, setOpponentDeckAfterWin] = useState(null);
  const [loadingOpponentDeck, setLoadingOpponentDeck] = useState(false);
  const [showHandRevealSelector, setShowHandRevealSelector] = useState(false);
  const [selectedHandRevealIds, setSelectedHandRevealIds] = useState([]);
  const [cardEffectActivations, setCardEffectActivations] = useState([]);
  const [cardEffectOptions, setCardEffectOptions] = useState([]);
  const [cardEffectSelectedIds, setCardEffectSelectedIds] = useState([]);
  const [setCardModal, setSetCardModal] = useState(null);
  const [handZoneChoice, setHandZoneChoice] = useState(null);
  const [handEvidenceChoice, setHandEvidenceChoice] = useState(null);
  const [showPlayHistory, setShowPlayHistory] = useState(false);
  const [playHistory, setPlayHistory] = useState([]);
  const [playHistoryZoneSnapshots, setPlayHistoryZoneSnapshots] = useState([]);
  const [loadingPlayHistory, setLoadingPlayHistory] = useState(false);
  const [actionLog, setActionLog] = useState([]);
  const [showActionLog, setShowActionLog] = useState(false);
  const [loadingActionLog, setLoadingActionLog] = useState(false);
  const [actionLogError, setActionLogError] = useState("");
  const [aiStatusMessage, setAiStatusMessage] = useState("");
  const [aiIsWaiting, setAiIsWaiting] = useState(false);
  const aiStepBusyRef = useRef(false);
  const aiMountedRef = useRef(false);

  useEffect(() => {
    aiMountedRef.current = true;
    return () => { aiMountedRef.current = false; };
  }, []);

  useEffect(() => {
    setLocalBaseCardPlayLocked(false);
  }, [roomId, game?.current_turn_user_id, game?.turn_number]);

  const myPeekSignature = useMemo(() => {
    const peek = game?.my_deck_peek;
    return peek?.source_user_id ? `${peek.source_user_id}:${(peek.cards || []).map((card) => card.instance_id).join("|")}` : "";
  }, [game?.my_deck_peek]);
  const sharedPeekSignature = useMemo(() => (game?.shared_deck_peek_cards || []).map((entry) => `${entry.source_user_id}:${entry.card?.instance_id}:${Boolean(entry.returned)}`).join("|"), [game?.shared_deck_peek_cards]);

  useEffect(() => {
    setSelectedPeekInstanceId("");
    if (!myPeekSignature) setPeekOrderIds([]);
    else setPeekOrderIds(myPeekSignature.split(":").slice(1).join(":").split("|").filter(Boolean));
  }, [myPeekSignature]);

  useEffect(() => {
    if (!sharedPeekSignature) setDismissedSharedPeekSignature("");
  }, [sharedPeekSignature]);

  const cardsByKey = useMemo(() => new Map(cards.map((card) => [String(card.key), {
    ...card,
    traits: normalizeCardTraits(card),
    ability: normalizeEffectQuotes(card.ability),
    originalAbility: normalizeEffectQuotes(card.originalAbility),
    hiramekiEffect: normalizeEffectQuotes(card.hiramekiEffect),
    cutInEffect: normalizeEffectQuotes(card.cutInEffect),
    disguiseEffect: normalizeEffectQuotes(cardDisguiseEffect(card)),
  }])), [cards]);

  const refreshActionLog = useCallback(async () => {
    if (!roomId) return;
    setLoadingActionLog(true);
    try {
      const { data, error: rpcError } = await supabase.rpc("get_private_match_action_log_v1", { p_room_id: roomId });
      if (rpcError) throw rpcError;
      const entries = Array.isArray(data) ? data : Array.isArray(data?.logs) ? data.logs : [];
      setActionLog([...entries].sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()));
      setActionLogError("");
    } catch (err) {
      setActionLogError(err?.message || "게임 행동 로그를 불러오지 못했습니다. Supabase의 202610200002 행동 로그 복구 마이그레이션 적용 여부를 확인해 주세요.");
    } finally {
      setLoadingActionLog(false);
    }
  }, [roomId]);

  useEffect(() => {
    if (!roomId || !game) return;
    void refreshActionLog();
  }, [roomId, game, refreshActionLog]);

  async function openActionLog() {
    setShowActionLog(true);
    await refreshActionLog();
  }

  async function beginTurnAndPlaceFiles() {
    const started = await runAction("begin_turn");
    if (!started) return;
    await runAction("place_files");
  }

  async function copyRoomInviteCode() {
    if (!inviteCode) return;
    try {
      await navigator.clipboard.writeText(inviteCode);
      setNotice("초대 코드를 복사했습니다.");
    } catch {
      window.prompt("이 초대 코드를 직접 복사해 주세요.", inviteCode);
    }
  }

  async function endTurnWithPartnerCheck() {
    if (canPartnerDeduce && !window.confirm("현재 파트너 추리가 가능합니다. 파트너 추리를 하지 않고 턴을 종료하시겠습니까?")) return;
    await runAction("end_turn");
  }

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
    return data && typeof data === "object" ? data : null;
  }, [roomId, userId]);

  useEffect(() => {
    const isMutualCancellation = Boolean(
      game?.game_over &&
      !game?.winner_user_id &&
      String(game?.last_action_label || "").startsWith("모의전 취소 완료:")
    );
    if (isMutualCancellation) onReturnToLobby?.();
  }, [game?.game_over, game?.winner_user_id, game?.last_action_label, onReturnToLobby]);

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

  useEffect(() => {
    if (!isAIBattle || !roomId || !game || game.game_over || aiStepBusyRef.current) return;

    const needsAiAction = (state) => {
      if (!state || state.game_over) return false;
      const boards = Array.isArray(state.boards) ? state.boards : [];
      const aiBoard = boards.find((board) => board.user_id !== userId);
      if (!aiBoard) return false;
      const pendingAction = state.pending_action || null;
      const aiMustRespond = Boolean(pendingAction && (
        pendingAction.target_user_id === aiBoard.user_id
        || pendingAction.next_responder_user_id === aiBoard.user_id
        || (pendingAction.type === "culprits_crime_reveal" && pendingAction.initiator_user_id === aiBoard.user_id)
        || (pendingAction.type === "evidence_attack_reveal" && pendingAction.attacker_user_id === aiBoard.user_id)
        || pendingAction.chooser_user_id === aiBoard.user_id
      ));
      return state.current_turn_user_id === aiBoard.user_id || aiMustRespond;
    };
    if (!needsAiAction(game)) return;

    aiStepBusyRef.current = true;
    (async () => {
      let state = game;
      let consecutiveBusyResponses = 0;
      try {
        // Keep ownership of the AI sequence while realtime updates refresh game state.
        // Each iteration executes at most one server action, then fetches authoritative state.
        for (let stepIndex = 0; stepIndex < 40 && aiMountedRef.current; stepIndex += 1) {
          if (!needsAiAction(state)) break;

          setAiIsWaiting(true);
          await new Promise((resolve) => window.setTimeout(resolve, 2500));
          if (!aiMountedRef.current) break;

          const { data, error: aiError } = await supabase.functions.invoke("ai-battle", {
            body: { action: "step", room_id: roomId },
          });
          if (aiError) throw aiError;
          if (!aiMountedRef.current) break;

          if (data?.busy) {
            consecutiveBusyResponses += 1;
            if (consecutiveBusyResponses >= 10) {
              setAiStatusMessage("AI 탐정: 다른 처리와 겹쳐 대기 중입니다. 잠시 후 상태 새로고침을 눌러 주세요.");
              break;
            }
            await new Promise((resolve) => window.setTimeout(resolve, 500));
            state = await refresh();
            continue;
          }
          consecutiveBusyResponses = 0;

          if (typeof data?.message === "string" && data.message.trim()) {
            setAiStatusMessage(data.message.trim());
          }
          if (data?.blocked_action) {
            setError(data.message || "AI의 행동이 규칙 검사에서 거부되었습니다. 진행 상태를 확인해 주세요.");
            break;
          }
          if (!Array.isArray(data?.actions) || data.actions.length === 0) {
            // No action means the current state is awaiting the human or a manual choice.
            state = await refresh();
            break;
          }

          setError("");
          state = await refresh();
          // The next loop iteration waits 2.5 seconds before making the next decision.
        }
      } catch (err) {
        if (aiMountedRef.current) {
          const message = err?.message || "AI의 다음 행동을 처리하지 못했습니다.";
          setAiStatusMessage(`AI 탐정: ${message}`);
          setError(message);
        }
      } finally {
        aiStepBusyRef.current = false;
        if (aiMountedRef.current) setAiIsWaiting(false);
      }
    })();
  }, [
    isAIBattle, roomId, userId, game?.boards, game?.state_version, game?.current_turn_user_id,
    game?.turn_number, game?.turn_step, game?.pending_action, game?.game_over, refresh,
  ]);

  const runAction = useCallback(async (action, payload = {}) => {
    if (loading) return false;
    setLoading(true); setError(""); setNotice("");
    try {
      const { data, error: rpcError } = action === "refresh_deck"
        ? await supabase.rpc("refresh_private_deck_v1", { p_room_id: roomId })
        : action === "cancel_next_hint"
          ? await supabase.rpc("cancel_private_next_hint_v2", { p_room_id: roomId })
          : action === "move_evidence_to_deck_top"
          ? await supabase.rpc("move_private_evidence_to_deck_top_v1", {
              p_room_id: roomId,
              p_owner_user_id: payload.owner_user_id,
              p_instance_id: payload.instance_id,
            })
          : action === "move_field_mr_to_partner"
            ? await supabase.rpc("move_private_field_mr_to_partner_v2", {
                p_room_id: roomId,
                p_owner_user_id: payload.owner_user_id,
                p_instance_id: payload.instance_id,
                p_card_rarity: payload.rarity,
              })
            : action === "move_stacked_card_to_hand"
              ? await supabase.rpc("move_private_stacked_card_to_hand_v1", {
                  p_room_id: roomId,
                  p_host_owner_user_id: payload.host_owner_user_id,
                  p_host_instance_id: payload.host_instance_id,
                  p_stacked_instance_id: payload.stacked_instance_id,
                })
              : action === "move_stacked_card_to_remove"
                ? await supabase.rpc("move_private_stacked_card_to_remove_v1", {
                    p_room_id: roomId,
                    p_host_owner_user_id: payload.host_owner_user_id,
                    p_host_instance_id: payload.host_instance_id,
                    p_stacked_instance_id: payload.stacked_instance_id,
                  })
                : action === "adjust_character_ap"
              ? await supabase.rpc("adjust_private_character_ap_v1", {
                  p_room_id: roomId,
                  p_owner_user_id: payload.owner_user_id,
                  p_instance_id: payload.instance_id,
                  p_delta: payload.delta,
                })
              : action === "move_mr_partner_card"
                ? await supabase.rpc("move_private_mr_partner_to_zone_v1", {
                    p_room_id: roomId,
                    p_owner_user_id: payload.owner_user_id,
                    p_instance_id: payload.instance_id,
                    p_destination: payload.destination,
                  })
                : await supabase.rpc("perform_private_turn_action_v2", {
                    p_room_id: roomId, p_action: action, p_payload: payload,
                  });
      if (rpcError) throw rpcError;
      let updatedGame = data && typeof data === "object" ? data : null;
      const oldBoards = Array.isArray(game?.boards) ? game.boards : [];
      let newBoards = Array.isArray(updatedGame?.boards) ? updatedGame.boards : [];
      if (updatedGame) {
        const departedAttachments = oldBoards.some((oldBoard) => {
          const nextBoard = newBoards.find((board) => board.user_id === oldBoard.user_id);
          const nextIds = new Set((nextBoard?.field_cards || []).map((card) => String(card.instance_id)));
          return (oldBoard.field_cards || []).some((card) =>
            card.instance_id &&
            !nextIds.has(String(card.instance_id)) &&
            ((Array.isArray(card.set_cards) && card.set_cards.length > 0) ||
             (Array.isArray(card.stacked_cards) && card.stacked_cards.length > 0))
          );
        });
        if (departedAttachments) {
          // Deferred DB triggers split attachments after the action transaction commits.
          const { data: freshState, error: refreshError } = await supabase.rpc("get_private_turn_state_v2", { p_room_id: roomId });
          if (!refreshError && freshState && typeof freshState === "object") {
            updatedGame = freshState;
            newBoards = Array.isArray(updatedGame?.boards) ? updatedGame.boards : [];
          }
        }
        const departedMrs = [];
        const enteredMrs = [];
        for (const oldBoard of oldBoards) {
          const newBoard = newBoards.find((board) => board.user_id === oldBoard.user_id);
          const oldFieldIds = new Set((oldBoard?.field_cards || []).map((card) => String(card.instance_id)));
          const newFieldIds = new Set((newBoard?.field_cards || []).map((card) => String(card.instance_id)));
          for (const card of oldBoard.field_cards || []) {
            const rarity = String(card.rarity || card.rarity_code || card.rarityCode || card.sourceData?.rarity || card.raw?.rarity || cardsByKey.get(String(card.key))?.rarity || "").trim().toUpperCase();
            if (["MR", "MRP"].includes(rarity) && card.instance_id && !newFieldIds.has(String(card.instance_id))) {
              // The server helper requires rarity on the card object; pass the resolved, normalized rarity.
              departedMrs.push({ owner_user_id: oldBoard.user_id, card: { ...card, rarity } });
            }
          }
          for (const card of newBoard?.field_cards || []) {
            const rarity = String(card.rarity || cardsByKey.get(String(card.key))?.rarity || "").toUpperCase();
            if (["MR", "MRP"].includes(rarity) && card.instance_id && !oldFieldIds.has(String(card.instance_id))) {
              enteredMrs.push({ owner_user_id: oldBoard.user_id, card });
            }
          }
        }
        // The new MR enters the field first: any older MR already in the MR partner area
        // is then moved to Remove. After that, any MR that left the field is stored there.
        for (const entry of enteredMrs) {
          try {
            const { data: recovered, error: recoveryError } = await supabase.rpc("remove_replaced_mr_partner_on_new_mr_v2", {
              p_room_id: roomId,
              p_owner_user_id: entry.owner_user_id,
              p_new_field_mr_instance_id: String(entry.card.instance_id),
            });
            if (recoveryError) throw recoveryError;
            if (recovered && typeof recovered === "object") updatedGame = recovered;
          } catch (recoveryError) {
            setError(recoveryError?.message || "새 MR 등장 시 기존 MR 파트너를 리무브로 이동하지 못했습니다.");
          }
        }
        for (const departure of departedMrs) {
          try {
            const { data: recovered, error: recoveryError } = await supabase.rpc("auto_store_departed_mr_partner_v2", {
              p_room_id: roomId,
              p_owner_user_id: departure.owner_user_id,
              p_card: departure.card,
            });
            if (recoveryError) throw recoveryError;
            if (recovered && typeof recovered === "object") updatedGame = recovered;
          } catch (recoveryError) {
            setError(recoveryError?.message || "현장을 떠난 MR 카드를 MR 파트너 에이리어로 이동하지 못했습니다.");
          }
        }
      }
      setGame(updatedGame);
      if (action === "begin_turn") setLocalBaseCardPlayLocked(false);
      if (action === "play_character" || action === "play_event") setLocalBaseCardPlayLocked(true);
      setNotice(action === "refresh_deck"
        ? "리프레시를 완료했습니다. 리무브 에이리어의 카드를 셔플해 덱으로 되돌렸고, 상대에게 증거 1장을 추가했습니다."
        : updatedGame?.last_action_label || data?.last_action_label || "행동을 반영했습니다.");
      if (action === "next_hint") setSelectedNextHint("");
      if (["declare_contact", "attack_character", "attack_evidence", "guard_with_character", "decline_guard", "guard_contact_with_character", "decline_contact_guard", "contact_use_cutin", "contact_pass_cutin"].includes(action)) setSelectedAttacker("");
      if ((action === "move_field_card" || action === "move_hand_card") && (payload.owner_user_id || userId) === userId) setDetailCard(null);
      return true;
    } catch (err) {
      const message = err?.message || "행동을 처리하지 못했습니다.";
      setError(message);
      showBlockedReason(message);
      return false;
    } finally { setLoading(false); }
  }, [roomId, userId, loading, game, cardsByKey]);

  const voteToCancelMatch = useCallback(async () => {
    if (!roomId || loading || game?.game_over) return;
    const votes = Array.isArray(game?.cancel_requested_by) ? game.cancel_requested_by : [];
    if (votes.length > 0) return;
    setLoading(true);
    setError("");
    setNotice("");
    try {
      if (isAIBattle) {
        // AI는 응답을 기다릴 필요가 없으므로, 요청 등록 직후 서버에서 즉시 종료 처리합니다.
        const { error: voteError } = await supabase.rpc("vote_private_match_cancel_v1", { p_room_id: roomId });
        if (voteError) throw voteError;
        const { data: cancelData, error: cancelError } = await supabase.functions.invoke("ai-battle", {
          body: { action: "cancel", room_id: roomId },
        });
        if (cancelError) throw cancelError;
        if (cancelData?.error) throw new Error(cancelData.error);
        const { data: updatedGame, error: stateError } = await supabase.rpc("get_private_turn_state_v2", { p_room_id: roomId });
        if (stateError) throw stateError;
        if (updatedGame && typeof updatedGame === "object") setGame(updatedGame);
        setNotice("AI 대전을 중도 종료했습니다. 게임이 즉시 종료되었습니다.");
        return;
      }
      const { data, error: rpcError } = await supabase.rpc("vote_private_match_cancel_v1", { p_room_id: roomId });
      if (rpcError) throw rpcError;
      if (data && typeof data === "object") setGame(data);
    } catch (err) {
      const message = err?.message || "중도 종료를 처리하지 못했습니다.";
      setError(message);
      showBlockedReason(message);
    } finally {
      setLoading(false);
    }
  }, [roomId, loading, game?.game_over, game?.cancel_requested_by, isAIBattle]);

  const respondToCancelMatch = useCallback(async (accept) => {
    if (!roomId || loading || game?.game_over) return;
    const votes = Array.isArray(game?.cancel_requested_by) ? game.cancel_requested_by : [];
    if (votes.length !== 1 || votes[0] === userId) return;
    setLoading(true);
    setError("");
    setNotice("");
    try {
      const { data, error: rpcError } = await supabase.rpc("respond_private_match_cancel_v1", {
        p_room_id: roomId,
        p_accept: Boolean(accept),
      });
      if (rpcError) throw rpcError;
      if (data && typeof data === "object") setGame(data);
      if (!accept) setNotice("중도 종료 제안이 거절되었습니다. 게임을 계속 진행할 수 있습니다.");
    } catch (err) {
      const message = err?.message || "중도 종료 응답을 처리하지 못했습니다.";
      setError(message);
      showBlockedReason(message);
    } finally {
      setLoading(false);
    }
  }, [roomId, userId, loading, game?.game_over, game?.cancel_requested_by]);



  const boards = Array.isArray(game?.boards) ? game.boards : [];
  const myBoard = boards.find((board) => board.user_id === userId);
  const myFieldCharacterCount = (myBoard?.field_cards || []).filter((card) => String(card?.card_type || "").trim().toLowerCase() === "character").length;
  const opponentBoard = boards.find((board) => board.user_id !== userId);
  const currentTurnBoard = boards.find((board) => board.user_id === game?.current_turn_user_id);
  const myHand = Array.isArray(game?.my_hand) ? game.my_hand : [];
  const sharedHandReveal = game?.shared_hand_reveal && Array.isArray(game.shared_hand_reveal.cards) ? game.shared_hand_reveal : null;
  const sharedHandRevealSignature = sharedHandReveal ? `${sharedHandReveal.source_user_id || ""}:${sharedHandReveal.cards.map((card) => card.instance_id).join("|")}` : "";
  useEffect(() => {
    if (sharedHandRevealSignature) setMinimizedModal((current) => current === "handReveal" ? "" : current);
  }, [sharedHandRevealSignature]);
  const myRemoveCards = Array.isArray(game?.my_remove_cards) ? game.my_remove_cards : [];
  const myFileCards = Array.isArray(game?.my_file_cards) ? game.my_file_cards : [];
  const opponentRemoveCards = Array.isArray(game?.opponent_remove_cards) ? game.opponent_remove_cards : [];
  const pending = game?.pending_action || null;

  useEffect(() => {
    let cancelled = false;
    const pendingType = game?.pending_action?.type || "";
    const chooserId = game?.pending_action?.chooser_user_id || "";
    setCardEffectSelectedIds([]);
    const loadEffectState = async () => {
      if (!roomId || !userId || game?.game_over) {
        if (!cancelled) {
          setCardEffectActivations([]);
          setCardEffectOptions([]);
        }
        return;
      }
      if (!pendingType) {
        const { data, error } = await supabase.rpc("get_private_card_effect_activations_v1", { p_room_id: roomId });
        if (!cancelled) setCardEffectActivations(!error && Array.isArray(data?.activations) ? data.activations : []);
        if (!cancelled) setCardEffectOptions([]);
        return;
      }
      setCardEffectActivations([]);
      if (["card_effect_selection", "card_effect_order"].includes(pendingType) && chooserId === userId) {
        const { data, error } = await supabase.rpc("get_private_card_effect_options_v1", { p_room_id: roomId });
        if (!cancelled) setCardEffectOptions(!error && Array.isArray(data?.options) ? data.options : []);
      } else if (!cancelled) {
        setCardEffectOptions([]);
      }
    };
    void loadEffectState();
    return () => { cancelled = true; };
  }, [
    roomId, userId, game?.state_version, game?.game_over,
    game?.pending_action?.type, game?.pending_action?.chooser_user_id,
    game?.pending_action?.effect_id, game?.pending_action?.source_instance_id,
  ]);
  const culpritRevealPending = pending?.type === "culprits_crime_reveal" ? pending : null;
  const culpritRevealCards = Array.isArray(culpritRevealPending?.revealed_evidence_cards) ? culpritRevealPending.revealed_evidence_cards : [];
  const culpritTraitCount = culpritRevealCards.filter(cardHasCulpritTrait).length;
  const culpritAcknowledgedIds = Array.isArray(culpritRevealPending?.acknowledged_user_ids) ? culpritRevealPending.acknowledged_user_ids : [];
  const myCulpritRevealAcknowledged = culpritAcknowledgedIds.includes(userId);
  const pendingIsForMe = pending?.target_user_id === userId;
  const isContactGuardPending = pending?.type === "character_contact_guard";
  const isContactPending = pending?.type === "character_contact";
  const isMisleadPending = pending?.type === "mislead_response";
  const isMyTurn = game?.current_turn_user_id === userId;
  const canStartMyTurn = isMyTurn && game?.turn_step === "begin" && !game?.game_over && !pending;
  const myRole = game?.first_player_user_id === userId ? "선공" : "후공";
  const fileTarget = n(myBoard?.files_to_place);
  const filesPlaced = n(myBoard?.files_placed_this_turn);
  const costLimit = n(myBoard?.file_count) + (myBoard?.partner_assist_used ? 1 : 0);
  const canActMain = isMyTurn && game?.turn_step === "main" && !game?.game_over && !pending && !myBoard?.next_hint_pending && (!game?.deck_peek_locked || Boolean(game?.my_deck_peek));
  const canPartnerDeduce = canActMain && !myBoard?.partner_rested && !myBoard?.partner_assist_used && Boolean(myBoard?.partner_key);
  const canPartnerAssist = canActMain && !myBoard?.partner_rested && !myBoard?.partner_assist_used && !myBoard?.next_hint_pending;

  // A guard selection starts (or updates) character_contact. The next responder can change
  // without changing the pending type, so include the guarded target and cut-in flags in the
  // dependency list; each responder must see the choice window instead of inheriting a minimized one.
  useEffect(() => {
    if (pending?.type === "character_contact") {
      setMinimizedModal((current) => current === "contact" ? "" : current);
    }
  }, [
    pending?.type,
    pending?.target_instance_id,
    pending?.next_responder_user_id,
    pending?.attacker_cut_in_used,
    pending?.target_cut_in_used,
    pending?.attacker_cut_in_passed,
    pending?.target_cut_in_passed,
  ]);

  useEffect(() => {
    if (!isMyTurn || game?.turn_step !== "main" || game?.game_over) {
      setAllowActiveTargetsByCard({});
      setAllowFreshlyPlayedByCard({});
    }
  }, [game?.current_turn_user_id, game?.turn_number, game?.turn_step, game?.game_over, isMyTurn]);
  const myEventCard = myBoard ? cardsByKey.get(String(myBoard.event_key)) : null;
  const opponentEventCard = opponentBoard ? cardsByKey.get(String(opponentBoard.event_key)) : null;

  const st = {
    root: { position: "fixed", inset: 0, boxSizing: "border-box", width: "100vw", height: "100dvh", overflowY: "auto", zIndex: 90000, padding: "clamp(10px, 2vw, 22px)", paddingBottom: "calc(92px + env(safe-area-inset-bottom))", background: C.bg, color: C.text, fontFamily: 'Inter, Pretendard, "Noto Sans KR", sans-serif' },
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
  async function openPlayHistory() {
    if (loadingPlayHistory) return;
    setLoadingPlayHistory(true);
    try {
      const { data: historyData, error: historyError } = await supabase.rpc("get_private_match_play_history", { p_room_id: roomId });
      if (historyError) throw historyError;
      // Keep existing play history usable while the zone-snapshot migration is pending.
      let zoneData = [];
      try {
        const { data, error: zoneError } = await supabase.rpc("get_private_match_turn_zone_snapshots_v1", { p_room_id: roomId });
        if (!zoneError) zoneData = Array.isArray(data) ? data : [];
      } catch {
        zoneData = [];
      }
      setPlayHistory(Array.isArray(historyData) ? historyData : Array.isArray(historyData?.history) ? historyData.history : []);
      setPlayHistoryZoneSnapshots(zoneData);
      setShowPlayHistory(true);
    } catch (err) {
      showBlockedReason(err?.message || "플레이 기록을 불러오지 못했습니다.");
    } finally { setLoadingPlayHistory(false); }
  }
  function openSetCardModal(hostCard, hostOwnerId, mode = "set", source = "hand") {
    setSetCardModal({ hostCard, hostOwnerId, mode, source, faceUp: false });
  }
  function selectSetSourceCard(card) {
    if (!setCardModal) return;
    const { hostCard, hostOwnerId, mode, source, faceUp } = setCardModal;
    if (mode === "stack") {
      void runAction("stack_remove_under_field", { host_instance_id: hostCard.instance_id, host_owner_user_id: hostOwnerId, source_instance_id: card.instance_id, face_up: true });
    } else {
      void runAction("set_card_to_field", { host_instance_id: hostCard.instance_id, host_owner_user_id: hostOwnerId, source, source_instance_id: card.instance_id, face_up: faceUp });
    }
    setSetCardModal(null);
  }
  function promptApBonus(card, ownerId) {
    const raw = window.prompt(`${nameOf(card)}에 이번 턴 동안 추가할 AP 수치 (숫자)`, "1");
    if (raw === null) return;
    const amount = Math.floor(Number(raw));
    if (!Number.isInteger(amount) || amount < 1 || amount > 10000) {
      window.alert("1~10000 사이의 정수를 입력해 주세요.");
      return;
    }
    void runAction("add_ap_bonus", { instance_id: card.instance_id, owner_user_id: ownerId, amount });
  }

  function promptApPenalty(card, ownerId) {
    const raw = window.prompt(`${nameOf(card)}의 AP에서 감소시킬 수치 (숫자)`, "1");
    if (raw === null) return;
    const amount = Math.floor(Number(raw));
    if (!Number.isInteger(amount) || amount < 1 || amount > 10000) {
      window.alert("1~10000 사이의 정수를 입력해 주세요.");
      return;
    }
    void runAction("adjust_character_ap", { instance_id: card.instance_id, owner_user_id: ownerId, delta: -amount });
  }
  function invokePromptDraw() {
    const count = promptCount("몇 장 드로우할까요?", 1, 20);
    if (count !== null) void runAction("draw_cards", { count });
  }

  function openHandZoneChoice(card, zone) {
    setHandZoneChoice({ card, zone });
  }
  function applyHandZoneChoice(destination) {
    if (!handZoneChoice?.card) return;
    const card = handZoneChoice.card;
    setHandZoneChoice(null);
    void runAction("move_hand_card", { instance_id: card.instance_id, destination });
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
    if (count !== null) void runAction("investigate", { instance_id: instance.instance_id, evidence_count: count, allow_newly_played: Boolean(allowFreshlyPlayedByCard[instance.instance_id]) });
  }
  function moveField(card, ownerId, destination) {
    const cardRarity = String(card?.rarity || card?.rarity_code || card?.rarityCode || card?.sourceData?.rarity || card?.raw?.rarity || cardsByKey.get(String(card?.key))?.rarity || "").trim().toUpperCase();
    if (destination === "remove" && ["MR", "MRP"].includes(cardRarity)) {
      if (!window.confirm(`${nameOf(card)}는 MR/MRP 카드이므로 리무브로 보내지 않고 MR 파트너 에이리어로 이동합니다. 계속할까요?`)) return;
      void runAction("move_field_mr_to_partner", { instance_id: card.instance_id, owner_user_id: ownerId, rarity: cardRarity });
      return;
    }
    const labels = { hand: "소유자의 손패", deck: "소유자의 덱 아래", remove: "리무브 에이리어" };
    if (!window.confirm(`${nameOf(card)} 카드를 ${labels[destination]}로 이동할까요? 효과 처리를 위한 수동 이동입니다.`)) return;
    void runAction("move_field_card", { instance_id: card.instance_id, owner_user_id: ownerId, destination, rarity: cardRarity });
  }

  function moveMrPartnerCard(card, ownerId, destination) {
    const labels = { hand: "소유자의 손패", deck: "소유자의 덱 맨 아래", remove: "리무브 에이리어" };
    if (!window.confirm(`MR 파트너 ${nameOf(card)} 카드를 ${labels[destination]}로 직접 이동할까요?`)) return;
    void runAction("move_mr_partner_card", { instance_id: card.instance_id, owner_user_id: ownerId, destination });
  }
  async function restCharacterManually(instance, ownerId) {
    if (instance?.status === "stunned") {
      const activated = await runAction("activate_character", { instance_id: instance.instance_id, owner_user_id: ownerId });
      if (!activated) return;
    }
    await runAction("rest_character_manual", { instance_id: instance.instance_id, owner_user_id: ownerId });
  }

  function CardArt({ instance, compact = false, rested = false, status: statusProp = "", onClick = null, faceDown = false }) {
    const info = infoFor(instance);
    const cardStatus = statusProp === "stunned" || instance?.status === "stunned"
      ? "stunned"
      : (rested || instance?.rested ? "rested" : (statusProp || instance?.status || "active"));
    const transform = cardStatus === "stunned" ? "rotate(180deg)" : cardStatus === "rested" || rested || instance?.rested ? "rotate(90deg)" : "none";
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
    const allowFreshForCard = Boolean(allowFreshlyPlayedByCard[instance.instance_id]);
    const notReadyYet = Boolean(instance.summoned_this_turn) && !allowFreshForCard;
    const canOfferContact = Boolean(selectedAttacker) && !mine && !isEvent && canActMain;
    const canManage = !game?.game_over && !pending;
    const ownerLabel = ownerId === userId ? "내" : "상대";
    return (
      <article key={instance.instance_id} style={{ minWidth: 0, width: "100%", border: `1px solid ${canOfferContact ? "#fb7185" : "rgba(148,163,184,.16)"}`, borderRadius: 7, padding: 4, background: "#080d16" }}>
        {mine && !isEvent && <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 4, margin: "0 1px 4px" }}>
          <label title="액티브 상태 대상 공격 가능" style={{ display: "flex", alignItems: "center", gap: 3, color: "#93c5fd", cursor: "pointer", fontSize: 8, lineHeight: 1.2 }}>
            <input type="checkbox" aria-label="액티브 상태 대상 공격 가능" title="액티브 상태 대상 공격 가능" checked={Boolean(allowActiveTargetsByCard[instance.instance_id])} disabled={!canActMain} onChange={(event) => setAllowActiveTargetsByCard((current) => ({ ...current, [instance.instance_id]: event.target.checked }))} style={{ width: 12, height: 12, margin: 0, accentColor: "#3b82f6" }} />
            <span>액티브 대상</span>
          </label>
          <label title="등장한 턴부터 바로 행동 가능" style={{ display: "flex", alignItems: "center", gap: 3, color: "#fcd34d", cursor: "pointer", fontSize: 8, lineHeight: 1.2 }}>
            <input type="checkbox" aria-label="등장한 턴부터 바로 행동 가능" title="등장한 턴부터 바로 행동 가능" checked={allowFreshForCard} disabled={!canActMain} onChange={(event) => setAllowFreshlyPlayedByCard((current) => ({ ...current, [instance.instance_id]: event.target.checked }))} style={{ width: 12, height: 12, margin: 0, accentColor: "#eab308" }} />
            <span>즉시 행동</span>
          </label>
        </div>}
        <button type="button" onClick={() => openDetails(instance)} title={`${nameOf(instance)} 상세 정보`} style={{ display: "block", width: "100%", border: 0, background: "transparent", color: C.text, padding: 0 }}>
          <div style={{ position: "relative", overflow: "hidden", aspectRatio: "3 / 4", display: "grid", placeItems: "center", background: "#0c1422", borderRadius: 5 }}>
            <CardArt instance={instance} rested={rested} status={cardStatus} />
            <span style={{ position: "absolute", left: 3, top: 3, padding: "2px 3px", borderRadius: 4, background: cardStatus === "stunned" ? "rgba(126,34,206,.95)" : cardStatus === "rested" || rested ? "rgba(190,24,93,.94)" : "rgba(22,101,52,.9)", color: "white", fontSize: 7, fontWeight: 900 }}>{cardStatus === "stunned" ? "스턴" : cardStatus === "rested" || rested ? "슬립" : "액티브"}</span>
            {["MR", "MRP"].includes(String(instance.rarity || "").toUpperCase()) && <span style={{ position: "absolute", right: 3, bottom: 3, padding: "2px 3px", borderRadius: 4, background: "#a16207", color: "white", fontSize: 7, fontWeight: 900 }}>MR</span>}
            {isEvent && <span style={{ position: "absolute", right: 3, top: 3, padding: "2px 3px", borderRadius: 4, background: "rgba(3,105,161,.92)", color: "white", fontSize: 7, fontWeight: 900 }}>이벤트</span>}
          </div>
        </button>
        <div style={{ marginTop: 4, fontSize: 9, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere" }}>{nameOf(instance)}</div>
        <div style={{ marginTop: 2, color: C.muted, fontSize: 8 }}>AP {n(instance.ap) + n(instance.ap_bonus)} · 레벨 {instance.cost ?? "-"}</div>
        {eventResolving && mine && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, background: "#075985" }} disabled={loading} onClick={() => void runAction("finish_event", { instance_id: instance.instance_id })}>효과 처리 완료 → 리무브</button>}
        {canOfferContact && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, borderColor: "#fb7185", color: C.red }} disabled={loading} onClick={() => {
          if (cardStatus === "active" && !allowActiveTargetsByCard[selectedAttacker]) { showBlockedReason("액티브 상태의 캐릭터는 기본적으로 공격 대상으로 지정할 수 없습니다. 공격자로 선택한 카드의 파란 체크박스를 활성화해 주세요."); return; }
          void runAction("declare_contact", { attacker_instance_id: selectedAttacker, target_user_id: ownerId, target_instance_id: instance.instance_id, allow_active_target: Boolean(allowActiveTargetsByCard[selectedAttacker]), allow_newly_played: Boolean(allowFreshlyPlayedByCard[selectedAttacker]) });
        }}>컨택 시작</button>}
        {mine && !isEvent && canActMain && <div style={{ display: "grid", gap: 4, marginTop: 5 }}>
          <button type="button" style={{ ...st.smallButton, opacity: cardStatus !== "active" || notReadyYet ? .72 : 1 }} disabled={loading} title={cardStatus !== "active" ? "슬립/스턴 상태에서는 추리할 수 없습니다." : notReadyYet ? "이번 턴에 등장한 카드는 기본적으로 행동할 수 없습니다." : ""} onClick={() => { if (cardStatus !== "active") { showBlockedReason("슬립/스턴 상태의 캐릭터는 추리할 수 없습니다."); return; } if (notReadyYet) { showBlockedReason("등장 후 1턴이 지나지 않아 행동할 수 없습니다. 효과 예외 옵션을 활성화해 주세요."); return; } invokeInvestigate(instance); }}>추리</button>
          <button type="button" style={{ ...st.smallButton, opacity: cardStatus !== "active" || notReadyYet ? .72 : 1, borderColor: selectedAttacker === instance.instance_id ? "#fb7185" : "rgba(255,255,255,.13)" }} disabled={loading} onClick={() => { if (cardStatus !== "active") { showBlockedReason("슬립/스턴 상태의 캐릭터는 공격자로 지정할 수 없습니다."); return; } if (notReadyYet) { showBlockedReason("등장 후 1턴이 지나지 않아 공격자로 선택할 수 없습니다. 효과 예외 옵션을 활성화해 주세요."); return; } setSelectedAttacker((current) => current === instance.instance_id ? "" : instance.instance_id); }}>{selectedAttacker === instance.instance_id ? "공격자 선택 해제" : "공격자로 선택"}</button>
          <button type="button" style={{ ...st.smallButton, opacity: cardStatus !== "active" || notReadyYet ? .72 : 1 }} disabled={loading} onClick={() => { if (cardStatus !== "active") { showBlockedReason("슬립/스턴 상태의 캐릭터는 공격할 수 없습니다."); return; } if (notReadyYet && !allowFreshForCard) { showBlockedReason("등장 후 1턴이 지나지 않아 공격할 수 없습니다. 이 카드의 노란 체크박스를 활성화해 주세요."); return; } if (!opponentBoard?.evidence_count) { showBlockedReason("상대 증거 에이리어에 공격할 증거가 없습니다."); return; } void runAction("attack_evidence", { attacker_instance_id: instance.instance_id, target_user_id: opponentBoard?.user_id, allow_newly_played: allowFreshForCard }); }}>상대 증거 공격</button>
        </div>}
        {canManage && <>
          <details style={{ marginTop: 5 }}><summary style={{ cursor: "pointer", fontSize: 8, color: "#8796ac" }}>효과 처리</summary><div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 4, marginTop: 5 }}>
            {!isEvent && (cardStatus === "active" || cardStatus === "stunned") && <button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${nameOf(instance)} 카드를 슬립 상태로 만들까요?`)) void restCharacterManually(instance, ownerId); }}>슬립</button>}
            {!isEvent && (cardStatus === "active" || cardStatus === "rested") && <button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${nameOf(instance)} 카드를 스턴 상태로 만들까요?`)) void runAction("stun_character", { instance_id: instance.instance_id, owner_user_id: ownerId }); }}>스턴</button>}
            {!isEvent && (cardStatus === "rested" || cardStatus === "stunned") && <button type="button" style={st.smallButton} disabled={loading} onClick={() => void runAction("activate_character", { instance_id: instance.instance_id, owner_user_id: ownerId })}>액티브</button>}
            {String(instance?.card_type || "").trim().toLowerCase() === "character" && <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 4 }}>
              <button type="button" style={st.smallButton} disabled={loading} onClick={() => promptApBonus(instance, ownerId)}>AP +N</button>
              <button type="button" style={st.smallButton} disabled={loading} onClick={() => promptApPenalty(instance, ownerId)}>AP −N</button>
            </div>}
          </div></details>
          <details style={{ marginTop: 5 }}><summary style={{ cursor: "pointer", fontSize: 8, color: "#8796ac" }}>카드 이동</summary><div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 4, marginTop: 5 }}>
            <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "hand")}>손패로</button>
            <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "deck")}>덱 아래로</button>
            <button type="button" style={st.smallButton} disabled={loading} onClick={() => moveField(instance, ownerId, "remove")}>리무브 에이리어로</button>
            <button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${nameOf(instance)} 카드를 앞면 공개 상태로 증거 에이리어 맨 위에 이동할까요?`)) void runAction("move_field_card", { instance_id: instance.instance_id, owner_user_id: ownerId, destination: "evidence_top" }); }}>증거 에이리어로</button>
          </div></details>
        </>}
        {Array.isArray(instance.set_cards) && instance.set_cards.length > 0 && <div style={{ marginTop: 6, padding: 5, border: "1px dashed rgba(252,211,77,.38)", borderRadius: 6, background: "rgba(120,83,10,.08)" }}><div style={{ color: C.gold, fontSize: 8, fontWeight: 900, marginBottom: 4 }}>세트 카드 · 현장 장수 제한에서 제외</div><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(42px,1fr))", gap: 4 }}>{instance.set_cards.map((setCard) => <div key={setCard.instance_id} style={{ minWidth: 0 }}><button type="button" title={nameOf(setCard)} onClick={() => (setCard.face_up || setCard.set_owner_user_id === userId) ? openDetails(setCard) : showBlockedReason("상대의 뒷면 세트 카드는 앞면으로 공개된 뒤 상세 정보를 확인할 수 있습니다.")} style={{ width: "100%", padding: 2, border: "1px solid rgba(255,255,255,.12)", borderRadius: 4, background: "#080d16" }}>{setCard.face_up && infoFor(setCard)?.imageUrl ? <img src={infoFor(setCard).imageUrl} alt={nameOf(setCard)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}</button>{!setCard.face_up && canManualEffect && <button type="button" style={{ ...st.smallButton, width: "100%", fontSize: 7, padding: 2, marginTop: 2 }} disabled={loading} onClick={() => void runAction("reveal_set_card", { host_instance_id: instance.instance_id, host_owner_user_id: ownerId, set_instance_id: setCard.instance_id })}>뒤집기</button>}{canManualEffect && mine && <button type="button" style={{ ...st.smallButton, width: "100%", fontSize: 7, padding: 2, marginTop: 2 }} disabled={loading} onClick={() => void runAction("move_set_card_to_hand", { host_instance_id: instance.instance_id, host_owner_user_id: ownerId, set_instance_id: setCard.instance_id })}>손패로 가져오기</button>}</div>)}</div></div>}
        {Array.isArray(instance.stacked_cards) && instance.stacked_cards.length > 0 && <div style={{ marginTop: 5, padding: 5, border: "1px dashed rgba(147,197,253,.28)", borderRadius: 6 }}><div style={{ color: C.blue, fontSize: 8, fontWeight: 900, marginBottom: 4 }}>아래에 겹친 카드</div><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(64px,1fr))", gap: 4 }}>{instance.stacked_cards.map((stackCard) => <div key={stackCard.instance_id} style={{ minWidth: 0 }}><button type="button" title={nameOf(stackCard)} onClick={() => stackCard.face_up ? openDetails(stackCard) : showBlockedReason("뒷면으로 겹쳐 둔 카드는 공개된 뒤 상세 정보를 확인할 수 있습니다.")} style={{ width: "100%", minWidth: 0, padding: 2, border: "1px solid rgba(255,255,255,.12)", borderRadius: 4, background: "#080d16" }}>{stackCard.face_up && infoFor(stackCard)?.imageUrl ? <img src={infoFor(stackCard).imageUrl} alt={nameOf(stackCard)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}</button>{canManualEffect && String(stackCard.set_owner_user_id || "") === String(userId) && <div style={{ display: "grid", gap: 2, marginTop: 2 }}><button type="button" style={{ ...st.smallButton, width: "100%", fontSize: 7, padding: 2 }} disabled={loading} onClick={() => void runAction("move_stacked_card_to_hand", { host_instance_id: instance.instance_id, host_owner_user_id: ownerId, stacked_instance_id: stackCard.instance_id })}>손패로 가져오기</button><button type="button" style={{ ...st.smallButton, width: "100%", fontSize: 7, padding: 2 }} disabled={loading} onClick={() => { if (window.confirm(nameOf(stackCard) + " 카드를 리무브 에이리어로 보낼까요?")) void runAction("move_stacked_card_to_remove", { host_instance_id: instance.instance_id, host_owner_user_id: ownerId, stacked_instance_id: stackCard.instance_id }); }}>리무브로 보내기</button></div>}</div>)}</div></div>}
        {canManualEffect && mine && <details style={{ marginTop: 5 }}><summary style={{ cursor: "pointer", fontSize: 8, color: "#8796ac" }}>세트 · 카드 겹치기</summary><div style={{ display: "grid", gap: 4, marginTop: 5 }}><button type="button" style={st.smallButton} disabled={loading || (!myHand.length && !myRemoveCards.length && !n(game?.my_deck_count))} onClick={() => openSetCardModal(instance, ownerId, "set", "choose")}>세트</button><button type="button" style={st.smallButton} disabled={loading || !myRemoveCards.length} onClick={() => openSetCardModal(instance, ownerId, "stack", "remove")}>겹치기</button></div></details>}
      </article>
    );
  }

  if (!game) return <main style={st.root}><div style={st.panel}>게임 필드를 불러오는 중…{error && <p style={{ color: C.red }}>{error}</p>}</div></main>;

  const solutionFileThreshold = game.first_player_user_id === userId ? 7 : 6;
  const currentEventKey = String(myBoard?.event_key || myEventCard?.key || "").trim().toLocaleUpperCase();
  const hasConanVsKidCase = cardHasRuleId(myEventCard || { key: myBoard?.event_key }, "1261")
    || currentEventKey === "B11098" || currentEventKey === "B11098P"
    || /(?:^|[^0-9])11098(?:[^0-9]|$)/u.test(currentEventKey);
  const winEvidenceThreshold = solutionFileThreshold + (hasConanVsKidCase ? 1 : 0);
  const roleText = game.first_player_user_id === userId ? "선공" : "후공";
  const currentTurnRole = game.current_turn_user_id === userId ? "내 턴" : "상대 턴";
  const canManualEffect = !game.game_over && !pending && !myBoard?.next_hint_pending && (!game.deck_peek_locked || Boolean(game.my_deck_peek));
  // Next Hint only blocks ending the turn; deck actions remain available while the required character is pending.
  const canUseDeckActions = !game.game_over && !pending && (!game.deck_peek_locked || Boolean(game.my_deck_peek));
  const canTransitionSolution = canActMain && myBoard?.case_phase === "incident" && n(myBoard?.file_count) >= solutionFileThreshold
    && !myBoard?.partner_rested && !myBoard?.partner_assist_used && !myBoard?.next_hint_used && !myBoard?.next_hint_pending;
  const hasCulpritsCrimeCase = cardHasRuleId(myEventCard || { key: myBoard?.event_key }, "1046");
  const hasEvidenceErasureCase = ["0614", "0615", "0722", "0723", "0724", "0725", "0398"]
    .some((ruleId) => cardHasRuleId(myEventCard || { key: myBoard?.event_key }, ruleId));
  const canWinCase = canActMain && myBoard?.case_phase === "solution" && !hasCulpritsCrimeCase && n(myBoard?.evidence_count) >= winEvidenceThreshold
    && !myBoard?.partner_rested && !myBoard?.partner_assist_used;
  const canDeclareCulpritsCrime = canActMain && myBoard?.case_phase === "solution" && hasCulpritsCrimeCase && n(myBoard?.evidence_count) >= 8
    && !myBoard?.partner_rested && !myBoard?.partner_assist_used;
  const activeSharedPeekCards = Array.isArray(game.shared_deck_peek_cards) ? game.shared_deck_peek_cards : [];
  // Define the current private peek before checking which cards have been selected for sharing.
  // Keeping this declaration order matters: const values are in the temporal dead zone until initialized.
  const ownPeek = game.my_deck_peek || null;
  const ownPeekCards = Array.isArray(ownPeek?.cards) ? ownPeek.cards : [];
  const allOwnPeekCardsShared = ownPeekCards.length > 0 && ownPeekCards.every((card) => (ownPeek?.shared_instance_ids || []).includes(card.instance_id));
  const fileRemovalPending = pending?.type === "file_remove_reveal";
  const deckRemovalPending = pending?.type === "deck_remove_reveal" || fileRemovalPending;
  const deckRemovalCards = Array.isArray(pending?.cards) ? pending.cards : [];
  const deckRemovalAcknowledged = Array.isArray(pending?.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
  const opponentDeckCardGroup = (card) => {
    const instanceId = String(card?.instance_id || "");
    // The configured incident/case card is returned by the RPC with an event-like type,
    // but it is not part of the normal event-card section.
    if (instanceId.startsWith("after-game-partner-") || instanceId.startsWith("after-game-event-")) return "special";
    const type = String(card?.card_type || infoFor(card)?.type || infoFor(card)?.originalType || infoFor(card)?.roleText || "").toLowerCase();
    if (/partner|パートナー|파트너/.test(type) || /^p\d+/i.test(String(card?.key || ""))) return "special";
    if (/case|incident|사건 카드|事件カード/.test(type) && !/event|イベント|이벤트/.test(type)) return "special";
    if (/event|イベント|이벤트/.test(type)) return "event";
    return "character";
  };
  const opponentDeckCards = [...(opponentDeckAfterWin?.cards || [])].sort((a, b) => {
    const groupOrder = { special: 0, character: 1, event: 2 };
    const groupDiff = groupOrder[opponentDeckCardGroup(a)] - groupOrder[opponentDeckCardGroup(b)];
    return groupDiff || n(b?.cost ?? infoFor(b)?.cost, -1) - n(a?.cost ?? infoFor(a)?.cost, -1) || nameOf(a).localeCompare(nameOf(b), "ko");
  });
  const opponentDeckGroups = [
    { key: "special", label: "파트너 · 사건 카드", cards: opponentDeckCards.filter((card) => opponentDeckCardGroup(card) === "special") },
    { key: "character", label: "캐릭터 카드", cards: opponentDeckCards.filter((card) => opponentDeckCardGroup(card) === "character") },
    { key: "event", label: "이벤트 카드", cards: opponentDeckCards.filter((card) => opponentDeckCardGroup(card) === "event") },
  ];
  const ownPeekOrder = peekOrderIds.map((id) => ownPeekCards.find((card) => card.instance_id === id)).filter(Boolean);
  const canSelectNextHintCard = isMyTurn && game?.turn_step === "main" && !game?.game_over && !pending && Boolean(myBoard?.next_hint_pending);
  const canPlayEventDuringNextHint = canSelectNextHintCard && (!game?.deck_peek_locked || Boolean(game?.my_deck_peek));
  const isManualEvidenceRemovePending = pending?.type === "evidence_remove_reveal";
  const revealedEvidenceCard = pending?.type === "evidence_attack_reveal" || isManualEvidenceRemovePending ? pending.revealed_evidence_card : null;
  const evidenceRemoveAcknowledgedIds = Array.isArray(pending?.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
  const myEvidenceRemoveAcknowledged = evidenceRemoveAcknowledgedIds.includes(userId);
  const winnerBoard = boards.find((board) => board.user_id === game?.winner_user_id);
  const winnerName = game?.winner_display_name || winnerBoard?.display_name || "플레이어";
  const minimizedModalLabels = { remove: "리무브 에이리어", peek: "덱 위 카드 살펴보기", sharedPeek: "상대가 공개한 카드", handReveal: "상대 손패 공개 확인", contact: "컨택 · 컷인 선택", evidence: "증거 카드 공개", detail: "카드 상세 정보", opponentDeck: "상대 덱 보기", deckRemove: "덱 위 카드 리무브 확인" };
  const minimizedModalExists = Boolean(
    (minimizedModal === "remove" && showRemoveArea) ||
    (minimizedModal === "peek" && ownPeek) ||
    (minimizedModal === "sharedPeek" && activeSharedPeekCards.length > 0) ||
    (minimizedModal === "handReveal" && Boolean(sharedHandReveal)) ||
    (minimizedModal === "contact" && (isContactPending || isContactGuardPending)) ||
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
        .mock-sticky-status { position: sticky; top: calc(-1 * clamp(10px, 2vw, 22px)); z-index: 1000; margin-top: calc(-1 * clamp(10px, 2vw, 22px)); margin-left: calc(-1 * clamp(10px, 2vw, 22px)); margin-right: calc(-1 * clamp(10px, 2vw, 22px)); padding: calc(clamp(10px, 2vw, 22px) + 4px) clamp(10px, 2vw, 22px) 0; background: #080d17; backdrop-filter: blur(12px); border-bottom: 1px solid rgba(148,163,184,.18); box-shadow: 0 8px 20px rgba(0,0,0,.16); }
        .mock-sticky-status::before { content: ""; position: absolute; top: calc(-1 * clamp(10px, 2vw, 22px)); left: 0; right: 0; height: calc(clamp(10px, 2vw, 22px) + 4px); background: #080d17; pointer-events: none; z-index: 0; }
        .mock-board-grid { display:grid; grid-template-columns:minmax(145px,1.05fr) minmax(0,7fr) minmax(145px,1.05fr); grid-template-rows:auto auto auto; gap:10px; align-items:stretch; }
        .mock-zone-case {grid-column:1;grid-row:1;} .mock-zone-center {grid-column:2;grid-row:1 / span 2;} .mock-zone-deck {grid-column:3;grid-row:1;}
        .mock-zone-evidence {grid-column:1;grid-row:2 / span 1;} .mock-zone-remove {grid-column:3;grid-row:2 / span 1;} .mock-zone-files {grid-column:1 / span 3;grid-row:3;}
        .mock-file-row {display:flex;align-items:center;gap:8px;min-width:0;padding:7px;background:#070c14;border:1px solid rgba(255,255,255,.07);border-radius:6px;}
        .mock-file-card-strip {display:flex;align-items:center;gap:3px;min-width:0;flex:1;overflow-x:auto;padding:4px 2px;}
        .mock-file-card {position:relative;flex:0 0 34px;width:34px;height:30px;display:grid;place-items:center;padding:0;border:0;border-radius:4px;background:transparent;cursor:pointer;}
        .mock-file-card:before {content:"";width:22px;height:30px;display:block;border:1px solid #b7c3da;border-radius:4px;background:repeating-linear-gradient(135deg,#1b2a49,#1b2a49 4px,#24395f 4px,#24395f 8px);transform:rotate(90deg);box-shadow:inset 0 0 0 2px rgba(255,255,255,.06);}
        .mock-file-card.is-face-up:before {display:none;}
        .mock-file-card-front {position:absolute;width:22px;height:30px;object-fit:cover;transform:rotate(90deg);border:1px solid #b7c3da;border-radius:3px;pointer-events:none;}
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
          {inviteCode && <button type="button" style={{ ...st.button, background: "#164e63", borderColor: "rgba(103,232,249,.3)" }} onClick={() => void copyRoomInviteCode()}>초대 코드 {inviteCode} · 복사</button>}
          <button type="button" style={st.button} disabled={loading} onClick={() => void refresh()}>상태 새로고침</button>
          <button type="button" style={{ ...st.button, background: "#7f2935", borderColor: "rgba(248,113,113,.5)", opacity: loading || game?.game_over || (Array.isArray(game?.cancel_requested_by) && game.cancel_requested_by.length > 0) ? .65 : 1 }} disabled={loading || game?.game_over || (Array.isArray(game?.cancel_requested_by) && game.cancel_requested_by.length > 0)} onClick={() => void voteToCancelMatch()}>중도 종료</button>
          {onLeaveField && <button type="button" style={{ ...st.button, background: "#273244" }} onClick={onLeaveField}>전체 화면 해제</button>}
        </div>
      </header>

      {Array.isArray(game?.cancel_requested_by) && game.cancel_requested_by.length > 0 && !game?.game_over && <div role="presentation" style={{ position: "fixed", inset: 0, zIndex: 100700, display: "flex", justifyContent: "center", alignItems: "center", padding: 16, background: "rgba(2,6,15,.86)", backdropFilter: "blur(7px)" }}>
        <section role="dialog" aria-modal="true" aria-labelledby="match-cancel-title" style={{ width: "min(100%, 430px)", padding: 20, borderRadius: 14, border: "1px solid rgba(248,113,113,.5)", background: "#111a2a", color: C.text, boxShadow: "0 28px 90px rgba(0,0,0,.75)" }}>
          <div style={{ color: "#fca5a5", fontSize: 9, fontWeight: 900, letterSpacing: ".16em" }}>MATCH PAUSED</div>
          <h2 id="match-cancel-title" style={{ margin: "5px 0 9px", fontSize: 19, fontWeight: 900 }}>모의전 중도 종료</h2>
          {game.cancel_requested_by[0] === userId
            ? <><p style={{ ...st.muted, fontSize: 12, lineHeight: 1.7 }}>중도 종료를 제안했습니다. 상대가 응답할 때까지 양쪽의 게임 진행이 일시 중지됩니다.</p><div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 14, padding: 10, borderRadius: 8, background: "rgba(248,113,113,.08)", color: "#fecaca", fontSize: 11 }}><span style={{ width: 7, height: 7, borderRadius: 99, background: "#f87171" }} />상대 플레이어의 [동의] 또는 [거절] 응답을 기다리는 중입니다.</div></>
            : <><p style={{ ...st.muted, fontSize: 12, lineHeight: 1.7 }}>상대가 모의전을 중도 종료하자고 제안했습니다. 동의하면 두 사람 모두 모의전 로비로 돌아갑니다. 거절하면 현재 게임을 계속합니다.</p><div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginTop: 16 }}><button type="button" disabled={loading} onClick={() => void respondToCancelMatch(true)} style={{ ...st.button, background: "#166534", borderColor: "rgba(134,239,172,.35)", padding: "11px 12px" }}>동의</button><button type="button" disabled={loading} onClick={() => void respondToCancelMatch(false)} style={{ ...st.button, background: "#374151", padding: "11px 12px" }}>거절</button></div></>}
        </section>
      </div>}

      {isAIBattle && aiStatusMessage && <section aria-live="polite" aria-atomic="true" style={{ marginBottom: 10, padding: "11px 12px", border: "1px solid rgba(56,189,248,.3)", borderRadius: 8, background: "linear-gradient(120deg,rgba(8,47,73,.55),rgba(15,23,42,.75))", color: "#e0f2fe" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, marginBottom: 4 }}>
          <strong style={{ fontSize: 11, color: "#7dd3fc", letterSpacing: ".04em" }}>AI 탐정 · 행동 선언</strong>
          {aiIsWaiting && <span style={{ fontSize: 9, color: "#94a3b8" }}>다음 판단을 준비하고 있습니다…</span>}
        </div>
        <p style={{ margin: 0, fontSize: 12, lineHeight: 1.7 }}>{aiStatusMessage}</p>
      </section>}
      {(error || notice) && <div role={error ? "alert" : "status"} style={{ marginBottom: 10, padding: 9, borderRadius: 6, border: `1px solid ${error ? "rgba(253,164,175,.3)" : "rgba(134,239,172,.24)"}`, color: error ? C.red : C.green, background: error ? "rgba(190,24,93,.07)" : "rgba(22,101,52,.07)", fontSize: 11 }}>{error || notice}</div>}
      {game.last_action_label && <div style={{ display: "grid", gap: 4, marginBottom: 10 }}>
        <button type="button" onClick={() => void openActionLog()} style={{ ...st.muted, textAlign: "left", padding: "7px 9px", border: "1px solid rgba(148,163,184,.24)", borderRadius: 5, background: "rgba(71,85,105,.22)", color: C.text, cursor: "pointer" }} title="눌러서 전체 게임 행동 로그를 최신순으로 확인">
          전체 게임 행동 내역: {actionLog[0]?.action_label || game.last_action_label}
        </button>
      </div>}
      </div>

      {pending?.type === "evidence_attack" && <div style={{ position: "fixed", inset: 0, zIndex: 100140, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label="증거 공격 가드 선택" style={{ width: "min(100%, 620px)", maxHeight: "90dvh", overflowY: "auto", ...st.panel, borderColor: "rgba(252,211,77,.55)", boxShadow: "0 24px 70px rgba(0,0,0,.72)" }}>
          <h2 style={{ ...st.zoneTitle, color: C.gold, fontSize: 16 }}>증거 공격 · 가드 선택</h2>
          {pendingIsForMe ? <>
            <p style={{ ...st.muted, marginBottom: 12, fontSize: 11 }}>상대가 내 증거 에이리어를 공격했습니다. 액티브 캐릭터로 가드할 수 있습니다. 가드하면 공격자와 가드 캐릭터의 컷인 사용 여부를 정한 뒤 AP를 비교하며, 가드하지 않으면 증거 공개로 진행합니다.</p>
            <div style={{ display: "grid", gap: 7 }}>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(112px,1fr))", gap: 8 }}>{(myBoard?.field_cards || []).filter((card) => !card.rested && card.card_type !== "event" && (card.status || "active") === "active").map((card) => <button key={card.instance_id} type="button" style={{ ...st.smallButton, textAlign: "left", padding: 7 }} disabled={loading} onClick={() => void runAction("guard_with_character", { instance_id: card.instance_id })}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ display: "block", width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<strong style={{ display: "block", marginTop: 4, fontSize: 10 }}>{nameOf(card)}</strong><span style={{ display: "block", fontSize: 9, color: C.muted, marginTop: 3 }}>AP {n(card.ap)+n(card.ap_bonus)} · 가드 선택</span></button>)}</div>
              <button type="button" style={{ ...st.button, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("decline_guard")}>가드하지 않기</button>
            </div>
          </> : <p style={{ ...st.muted, fontSize: 11 }}>상대가 가드 여부를 선택하고 있습니다. 가드하면 컷인 선택 후 공격자와 가드 캐릭터의 AP를 비교합니다. 가드하지 않으면 다음 창에서 공격 대상 증거가 공개됩니다.</p>}
        </section>
      </div>}

      {isMisleadPending && <section style={{ ...st.panel, marginBottom: 10, borderColor: "rgba(232,121,249,.45)" }}>
        <h2 style={{ ...st.zoneTitle, color: "#e879f9" }}>미스리드 응답</h2>
        <p style={{ ...st.muted, marginBottom: 8 }}>상대가 추리를 선언하여 증거 {n(pending.evidence_count)}장을 획득하려고 합니다. 미스리드를 사용하면 획득 수를 지정한 만큼 줄일 수 있습니다.</p>
        {pending.target_user_id === userId ? <>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 7 }}>
            {(myBoard?.field_cards || []).filter((card) => n(card.mislead_value) > 0 && !card.rested && (card.status || "active") === "active" && (!card.summoned_this_turn || Boolean(allowFreshlyPlayedByCard[card.instance_id]))).map((card) => <button key={card.instance_id} type="button" style={{ ...st.button, background: "#581c87" }} disabled={loading} onClick={() => void runAction("resolve_mislead", { instance_id: card.instance_id, allow_newly_played: Boolean(allowFreshlyPlayedByCard[card.instance_id]) })}>{nameOf(card)} · 미스리드 {n(card.mislead_value)}</button>)}
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
          {canTransitionSolution && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7, background: "#7f1d1d", borderColor: "#fb7185" }} disabled={loading} onClick={() => { if (window.confirm("해결편으로 전환 시 파트너는 자동으로 어시스트되며, 사건 효과가 있을 경우 수동 처리해야 합니다.")) void runAction("declare_solution"); }}>해결편 전환</button>}
          {canDeclareCulpritsCrime ? <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7, background: "#7f1d1d", borderColor: "#ef4444" }} disabled={loading} onClick={() => { if (window.confirm("본인 덱 전체를 리무브하고 모든 증거를 앞면으로 공개합니다. 증거가 8장 이상이면 승리합니다. 선언하시겠습니까?")) void runAction("culprits_crime"); }}>범인들의 범행</button> : canWinCase && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 7, background: hasEvidenceErasureCase ? "#050505" : "#166534", borderColor: hasEvidenceErasureCase ? "#000000" : "#166534", color: "#ffffff" }} disabled={loading} onClick={() => void runAction("solve_case")}>{hasEvidenceErasureCase ? "증거 인멸" : "사건 해결 선언"}</button>}
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
                if (!board || !board.partner_key || board.partner_assist_used) return null;
                const partner = cardsByKey.get(String(board.partner_key));
                return <div key={board.user_id} style={{ display: "grid", gridTemplateColumns: "minmax(55px,90px) minmax(0,1fr)", gap: 8, alignItems: "center", padding: 6, border: "1px solid rgba(255,255,255,.09)", borderRadius: 6, background: "#080d16" }}>
                  {partner?.imageUrl ? <button type="button" onClick={() => openDetails({ key: board.partner_key, instance_id: `partner-${board.user_id}` })} style={{ width: "100%", height: 122, overflow: "hidden", display: "grid", placeItems: "center", border: 0, background: "transparent", padding: 0 }}><img src={partner.imageUrl} alt={partner.name} style={board.partner_rested ? { width: 68, height: 90, objectFit: "contain", transform: "rotate(90deg)", transformOrigin: "center" } : { width: "100%", height: 122, objectFit: "contain" }} /></button> : <div style={st.faceDown} />}
                  <div style={{ minWidth: 0 }}><div style={{ color: C.muted, fontSize: 8, marginBottom: 3 }}>{board.display_name || (mine ? "내 파트너" : "상대 파트너")}</div><div style={{ fontSize: 10, fontWeight: 850, overflowWrap: "anywhere" }}>{partner?.name || board.partner_key}</div><div style={{ color: board.partner_rested ? C.red : C.green, fontSize: 9, marginTop: 4 }}>{board.partner_rested ? "슬립" : "액티브"}</div>
                    {mine && !board.partner_rested && <div style={{ display: "grid", gap: 4, marginTop: 6 }}><button type="button" style={st.smallButton} disabled={loading || !canActMain || board.partner_assist_used || board.next_hint_pending} onClick={() => void runAction("partner_assist")}>어시스트 · 레벨 +1</button><button type="button" style={st.smallButton} disabled={loading || !canActMain || board.partner_assist_used || board.next_hint_pending} onClick={() => invokeInvestigate(null, true)}>파트너 추리 · 증거 1장</button><button type="button" style={st.smallButton} disabled={loading || !canActMain || board.partner_assist_used || board.next_hint_pending} onClick={() => void runAction("rest_partner_manual")}>슬립</button></div>}
                  </div>
                </div>;
              })}
            </div>
          </div>

          <div style={{ border: "1px solid rgba(148,163,184,.25)", borderRadius: 7, padding: 8, background: "rgba(100,116,139,.06)" }}>
            <h3 style={{ ...st.zoneTitle, textAlign: "center", marginBottom: 7 }}>MR 파트너 에이리어</h3>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 8 }}>
              {[{ board: opponentBoard, mine: false }, { board: myBoard, mine: true }].map(({ board, mine }) => {
                if (!board) return null;
                const rawPartnerCard = board.partner_mr_card || null;
                const rawRarity = String(rawPartnerCard?.rarity || infoFor(rawPartnerCard)?.rarity || "").toUpperCase();
                const mr = rawPartnerCard && ["MR", "MRP"].includes(rawRarity) ? rawPartnerCard : null;
                const legacyNonMr = rawPartnerCard && !["MR", "MRP"].includes(rawRarity) ? [rawPartnerCard] : [];
                const nonMrCards = [...(Array.isArray(board.partner_non_mr_cards) ? board.partner_non_mr_cards : []), ...legacyNonMr];
                return <div key={board.user_id} style={{ minWidth: 0, display: "grid", gap: 7, alignContent: "start" }}>
                  <div style={{ padding: 6, border: "1px solid rgba(255,255,255,.08)", borderRadius: 6, background: "#080d16" }}>
                    <div style={{ color: C.muted, fontSize: 8, marginBottom: 4 }}>{mine ? "내 MR" : "상대 MR"}</div>
                    {mr ? <div style={{ display: "grid", gridTemplateColumns: !game.game_over && !pending ? "minmax(48px, .72fr) minmax(0, 1.28fr)" : "minmax(0, 1fr)", alignItems: "center", gap: 7 }}>
                      <div style={{ minWidth: 0 }}>
                        <button type="button" onClick={() => openDetails(mr)} style={{ display: "block", width: "100%", padding: 0, border: 0, background: "transparent" }}>{infoFor(mr)?.imageUrl ? <img src={infoFor(mr).imageUrl} alt={nameOf(mr)} style={{ display: "block", width: "100%", maxHeight: 94, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}</button>
                        <div style={{ fontSize: 8, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere", textAlign: "center", marginTop: 4 }}>{nameOf(mr)}</div>
                      </div>
                      {!game.game_over && !pending && <div style={{ display: "grid", gap: 4, minWidth: 0 }}>
                        <button type="button" style={{ ...st.smallButton, width: "100%", padding: "5px 2px", fontSize: 8 }} disabled={loading} onClick={() => moveMrPartnerCard(mr, board.user_id, "hand")}>손패로</button>
                        <button type="button" style={{ ...st.smallButton, width: "100%", padding: "5px 2px", fontSize: 8 }} disabled={loading} onClick={() => moveMrPartnerCard(mr, board.user_id, "deck")}>덱 아래로</button>
                        <button type="button" style={{ ...st.smallButton, width: "100%", padding: "5px 2px", fontSize: 8 }} disabled={loading} onClick={() => moveMrPartnerCard(mr, board.user_id, "remove")}>리무브 에이리어로</button>
                      </div>}
                    </div> : <div style={{ minHeight: 55, display: "grid", placeItems: "center", color: C.muted, fontSize: 9 }}>없음</div>}
                  </div>
                  <div style={{ padding: 6, border: "1px solid rgba(255,255,255,.08)", borderRadius: 6, background: "#080d16" }}>
                    <div style={{ color: C.muted, fontSize: 8, marginBottom: 5 }}>MR 외 카드 · {nonMrCards.length}장</div>
                    {nonMrCards.length ? <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(58px,1fr))", gap: 5 }}>{nonMrCards.map((card) => <div key={card.instance_id} style={{ minWidth: 0 }}>
                      <button type="button" onClick={() => openDetails(card)} title={nameOf(card)} style={{ width: "100%", padding: 2, border: "1px solid rgba(255,255,255,.1)", borderRadius: 4, background: "#101827", color: C.text }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ display: "block", width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", fontSize: 7, lineHeight: 1.2, marginTop: 3, overflowWrap: "anywhere" }}>{nameOf(card)}</span></button>
                      {!game.game_over && !pending && <div style={{ display: "grid", gap: 3, marginTop: 3 }}><button type="button" style={{ ...st.smallButton, padding: "3px 2px", fontSize: 8 }} disabled={loading} onClick={() => moveField(card, board.user_id, "hand")}>손패로</button><button type="button" style={{ ...st.smallButton, padding: "3px 2px", fontSize: 8 }} disabled={loading} onClick={() => moveField(card, board.user_id, "remove")}>리무브로</button></div>}
                    </div>)}</div> : <div style={{ minHeight: 35, display: "grid", placeItems: "center", color: C.muted, fontSize: 9 }}>없음</div>}
                  </div>
                </div>;
              })}
            </div>
          </div>

          <div style={{ padding: 9, borderRadius: 7, border: "1px solid rgba(148,163,184,.13)", background: "#090f1b" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: 8, marginBottom: 8 }}><strong style={{ color: C.muted, fontSize: 10 }}>내 현장</strong><span style={st.muted}>{myBoard?.field_cards?.length || 0}장 · {isMyTurn ? "내 턴" : "상대 턴"}</span></div>
            <div className="mock-field-row">
              {(myBoard?.field_cards || []).map((card) => <ZoneCard key={card.instance_id} instance={card} rested={Boolean(card.rested)} ownerId={userId} mine eventResolving={Boolean(card.resolving)} />)}
              {!myBoard?.field_cards?.length && <p style={st.muted}>아직 현장에 등장한 카드가 없습니다.</p>}
            </div>
          </div>
          {cardEffectActivations.length > 0 && <div style={{ marginTop: 8, padding: 9, border: "1px solid rgba(96,165,250,.2)", borderRadius: 7, background: "#0a1425" }}>
            <strong style={{ display: "block", marginBottom: 7, fontSize: 10, color: C.blue }}>발동 가능한 카드 능력</strong>
            <div style={{ display: "grid", gap: 6 }}>
              {cardEffectActivations.map((ability) => {
                const source = (myBoard?.field_cards || []).find((card) => String(card.instance_id) === String(ability.source_instance_id));
                return <div key={ability.effect_id + ":" + ability.source_instance_id} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, padding: 6, borderRadius: 6, background: "#111e32" }}>
                  <div style={{ minWidth: 0 }}>
                    <strong style={{ display: "block", fontSize: 10, overflowWrap: "anywhere" }}>{source ? nameOf(source) : ability.source_name || "카드"}</strong>
                    <span style={{ display: "block", fontSize: 9, color: C.muted }}>{ability.label || "능력 발동"}</span>
                  </div>
                  <button type="button" style={{ ...st.smallButton, flexShrink: 0 }} disabled={loading || !isMyTurn || Boolean(pending)} onClick={() => void runAction("activate_card_effect", { source_instance_id: ability.source_instance_id, effect_id: ability.effect_id })}>발동</button>
                </div>;
              })}
            </div>
          </div>
        </div>

        <div className="mock-zone-deck" style={st.panel}>
          <h2 style={st.zoneTitle}>덱</h2>
          <div style={st.faceDown} />
          <div style={{ marginTop: 7, fontSize: 11, textAlign: "center", fontWeight: 850 }}>내 덱 {game.my_deck_count ?? "-"}장</div>
          <div style={{ marginTop: 3, fontSize: 10, textAlign: "center", color: C.muted }}>상대 덱 {opponentBoard?.deck_count ?? "-"}장</div>
          <p style={{ ...st.muted, textAlign: "center", marginTop: 4 }}>{game.deck_peek_waiting_for_ack && !game.my_deck_peek ? (activeSharedPeekCards.length > 0 ? "공개된 덱 카드를 확인해 주세요" : "상대가 공개된 카드를 확인할 때까지 대기합니다") : game.deck_peek_in_progress && !game.my_deck_peek ? "상대가 덱을 살펴보고 있습니다" : "카드 순서는 기본적으로 비공개입니다"}</p>
          {canUseDeckActions && <div style={{ display: "grid", gap: 5, marginTop: 8 }}>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading || Boolean(game.deck_peek_locked)} onClick={() => void runAction("shuffle_deck")}>내 덱 전체 셔플</button>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading || n(game.my_deck_count) < 1 || Boolean(game.deck_peek_locked)} onClick={() => invokeDeckPeek(userId, n(game.my_deck_count))}>N장 보기</button>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading || n(game.my_deck_count) < 1 || Boolean(game.deck_peek_locked) || Boolean(pending)} onClick={invokeRemoveTopDeck}>N장 리무브</button>
            <button type="button" style={{ ...st.smallButton, width: "100%" }} disabled={loading} onClick={invokePromptDraw}>N장 드로우</button>
            {n(game.my_deck_count) === 0 && <button type="button" style={{ ...st.smallButton, width: "100%", background: "#263b56", borderColor: "rgba(147,197,253,.48)", color: "#eaf2ff", fontWeight: 900 }} disabled={loading || Boolean(pending) || Boolean(game.deck_peek_locked)} onClick={() => void runAction("refresh_deck")}>리프레시</button>}
          </div>}
        </div>

        <div className="mock-zone-evidence" style={st.panel}>
          <h2 style={st.zoneTitle}>증거 에이리어</h2>
          <div style={{ ...st.counts, gridTemplateColumns: "repeat(2,minmax(0,1fr))" }}><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>내 증거</div><div style={{ fontSize: 22, fontWeight: 900 }}>{myBoard?.evidence_count ?? 0}</div></div><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>상대 증거</div><div style={{ fontSize: 22, fontWeight: 900 }}>{opponentBoard?.evidence_count ?? 0}</div></div></div>
          <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 8 }} disabled={loading || n(game?.my_deck_count) < 1 || Boolean(pending) || Boolean(game?.deck_peek_locked)} onClick={() => void runAction("gain_evidence_from_deck")}>덱에서 증거 획득</button>
          {[{ board: opponentBoard, mine: false }, { board: myBoard, mine: true }].map(({ board, mine }) => {
            const publicCards = Array.isArray(board?.evidence_public_cards) ? board.evidence_public_cards : [];
            const privateEvidenceCards = mine && Array.isArray(board?.evidence_private_cards) ? board.evidence_private_cards : null;
            const hiddenCount = privateEvidenceCards ? privateEvidenceCards.filter((card) => !Boolean(card.face_up)).length : Math.max(0, n(board?.evidence_count) - publicCards.length);
            return <div key={`evidence-${mine ? "mine" : "opponent"}`} style={{ marginTop: 8, padding: 6, border: "1px solid rgba(255,255,255,.07)", borderRadius: 6, background: "#080d16" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 6, marginBottom: 7 }}><span style={{ fontSize: 9, color: C.muted, fontWeight: 800 }}>{mine ? "내 증거" : "상대 증거"} · 뒷면 {hiddenCount}장 / 앞면 {publicCards.length}장</span><span style={{ fontSize: 8, color: "#6b7b94" }}>{mine ? "카드를 위에서 아래로 표시합니다." : "공개 카드만 표시됩니다."}</span></div>
              <div style={{ display: "grid", gap: 6, marginTop: 4 }}>
                {Array.from({ length: privateEvidenceCards ? 0 : Math.min(12, hiddenCount) }, (_, i) => <div key={`hidden-${i}`} style={{ display: "grid", gridTemplateColumns: "68px minmax(0,1fr)", gap: 6, alignItems: "center", padding: "4px 0", borderBottom: "1px solid rgba(255,255,255,.05)" }}>
                  <div style={{ width: 64, height: 48, flex: "0 0 64px" }}><div style={{ ...st.faceDown, width: 64, height: 48, aspectRatio: "auto" }} /></div>
                  <span style={{ minWidth: 0, color: C.muted, fontSize: 8 }}>비공개 증거</span>
                </div>)}
                {(privateEvidenceCards || publicCards).map((card) => <div key={card.instance_id} style={{ display: "grid", gridTemplateColumns: "68px minmax(0,1fr)", gap: 6, alignItems: "center", padding: "4px 0", borderBottom: "1px solid rgba(255,255,255,.05)" }}>
                  <button type="button" onClick={() => { if (card.face_up) openDetails(card); }} title={card.face_up ? `${nameOf(card)} · 앞면 증거 · 클릭하여 상세 보기` : "비공개 증거"} aria-label={card.face_up ? `${nameOf(card)} 상세 보기` : "비공개 증거"} style={{ width: 64, height: 48, minWidth: 64, padding: 2, overflow: "hidden", border: "1px solid rgba(148,163,184,.35)", borderRadius: 5, background: "#111827", color: C.text, display: "grid", placeItems: "center" }}>
                    {Boolean(card.face_up) && infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt="" style={{ display: "block", width: 44, height: 58, objectFit: "contain", transform: "rotate(90deg)" }} /> : <div style={{ width: 58, height: 44, ...st.faceDown, aspectRatio: "auto" }} />}
                  </button>
                  {canManualEffect ? <div style={{ minWidth: 0, display: "grid", gap: 3, alignContent: "center" }}>
                    <button type="button" style={{ ...st.smallButton, width: "100%", padding: "3px 2px", fontSize: 7, whiteSpace: "nowrap", borderColor: "rgba(147,197,253,.3)" }} disabled={loading} title="소유자의 덱 맨 위로 이동합니다. 비공개 증거도 이동할 수 있습니다." onClick={() => { if (window.confirm(`${card.face_up ? `${nameOf(card)} 공개 증거` : "비공개 증거"}를 소유자의 덱 맨 위로 이동할까요?`)) void runAction("move_evidence_to_deck_top", { instance_id: card.instance_id, owner_user_id: board.user_id }); }}>덱 위로</button>
                    <button type="button" style={{ ...st.smallButton, width: "100%", padding: "3px 2px", fontSize: 7, whiteSpace: "nowrap" }} disabled={loading} title="공개 증거를 소유자의 덱 맨 아래로 이동합니다." onClick={() => { if (window.confirm(`${card.face_up ? `${nameOf(card)} 공개 증거` : "비공개 증거"}를 소유자의 덱 맨 아래로 이동할까요?`)) void runAction("move_evidence_to_deck_bottom", { instance_id: card.instance_id, owner_user_id: board.user_id }); }}>덱 밑으로</button>
                    <button type="button" style={{ ...st.smallButton, width: "100%", padding: "3px 2px", fontSize: 7, whiteSpace: "nowrap" }} disabled={loading} title="공개 증거를 소유자의 리무브 에이리어로 이동합니다." onClick={() => { if (window.confirm(`${card.face_up ? `${nameOf(card)} 공개 증거` : "비공개 증거"}를 소유자의 리무브 에이리어로 이동할까요?`)) void runAction("move_evidence_to_remove", { instance_id: card.instance_id, owner_user_id: board.user_id }); }}>리무브로</button>
                    {mine && <button type="button" style={{ ...st.smallButton, width: "100%", padding: "3px 2px", fontSize: 7, whiteSpace: "nowrap", borderColor: "rgba(134,239,172,.35)" }} disabled={loading} title="내 공개 증거를 손패로 이동합니다." onClick={() => { if (window.confirm(`${card.face_up ? `${nameOf(card)} 공개 증거` : "비공개 증거"}를 내 손패로 이동할까요?`)) void runAction("move_evidence_to_hand", { instance_id: card.instance_id, owner_user_id: board.user_id }); }}>손패로</button>}
                  </div> : <span style={{ color: C.muted, fontSize: 8 }}>효과 처리 불가</span>}
                </div>)}
              </div>
              {mine && canManualEffect && n(board?.evidence_count) > 0 && <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 8, paddingTop: 7, borderTop: "1px solid rgba(255,255,255,.06)" }}><button type="button" style={{ ...st.smallButton, minWidth: 104, background: "#263d63" }} disabled={loading} onClick={() => invokeExposeEvidence(board.user_id, n(board.evidence_count), "내 증거")}>위 N장 공개</button></div>}
            </div>;
          })}
        </div>

        <div className="mock-zone-remove" style={st.panel}>
          <h2 style={st.zoneTitle}>리무브 에이리어</h2>
          <div style={{ ...st.counts, gridTemplateColumns: "repeat(2,minmax(0,1fr))" }}><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>내 리무브</div><div style={{ fontSize: 22, fontWeight: 900 }}>{myBoard?.remove_count ?? 0}</div></div><div style={st.countCell}><div style={{ fontSize: 10, color: C.muted }}>상대 리무브</div><div style={{ fontSize: 22, fontWeight: 900 }}>{opponentBoard?.remove_count ?? 0}</div></div></div>
          <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 8 }} onClick={() => setShowRemoveArea(true)}>리무브 에이리어 보기</button>
        </div>

        <div className="mock-zone-files" style={st.panel}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}><h2 style={{ ...st.zoneTitle, marginBottom: 0 }}>파일 에이리어</h2><strong style={{ fontSize: 11 }}>내 파일 {myBoard?.file_count ?? 0}장 · 상대 파일 {opponentBoard?.file_count ?? 0}장</strong></div><div style={{ display: "flex", flexWrap: "wrap", gap: 5, marginTop: 7 }}><button type="button" style={st.smallButton} disabled={loading || !myFileCards.length || Boolean(pending)} onClick={() => void runAction("take_top_file_to_hand")}>파일 맨 위 카드를 손패로</button><button type="button" style={st.smallButton} disabled={loading || !myFileCards.length || Boolean(pending)} onClick={() => void runAction("reveal_top_file")}>파일 맨 위 카드 공개</button><button type="button" style={st.smallButton} disabled={loading || !myFileCards.length || Boolean(pending)} onClick={() => void runAction("remove_top_file")}>파일 맨 위 카드 리무브</button></div>
          <p style={{ ...st.muted, marginTop: 6 }}>파일 카드는 가로로 배치됩니다. 내 파일 중 공개된 카드는 앞면 이미지가 표시됩니다. 넥스트 힌트 사용 시 내 파일의 가장 최근 카드를 회수합니다.</p>
          <div style={{ display: "grid", gap: 6, marginTop: 8 }}>
            <div className="mock-file-row"><strong style={{ color: C.muted, fontSize: 9, flex: "0 0 72px" }}>상대 파일 · {n(opponentBoard?.file_count)}장</strong><div className="mock-file-card-strip" aria-label="상대 파일 카드">{Array.from({ length: Math.min(40, n(opponentBoard?.file_count)) }, (_, i) => <div key={i} className="mock-file-card" title="뒷면 파일 카드" />)}{!n(opponentBoard?.file_count) && <span style={{ color: C.muted, fontSize: 9 }}>파일 없음</span>}</div></div>
            <div className="mock-file-row"><strong style={{ color: C.muted, fontSize: 9, flex: "0 0 72px" }}>내 파일 · {n(myBoard?.file_count)}장</strong><div className="mock-file-card-strip" aria-label="내 파일 카드">{myFileCards.slice(-40).map((card) => { const faceUp = Boolean(card.face_up); const imageUrl = faceUp ? infoFor(card)?.imageUrl : null; return faceUp ? <button key={card.instance_id} type="button" className="mock-file-card is-face-up" title={`${nameOf(card)} · 공개 파일 · 클릭하여 상세 보기`} aria-label={`${nameOf(card)} 공개 파일 상세 보기`} onClick={() => openDetails(card)}>{imageUrl ? <img className="mock-file-card-front" src={imageUrl} alt="" /> : <span style={{ width: 28, height: 20, border: "1px solid #b7c3da", borderRadius: 3, background: "#101827" }} />}</button> : <div key={card.instance_id} className="mock-file-card" title="뒷면 파일 카드" />; })}{!n(myBoard?.file_count) && <span style={{ color: C.muted, fontSize: 9 }}>파일 없음</span>}</div>
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

      {!game.game_over && isMyTurn && <div aria-label="턴 액션">
        {(game.turn_step === "begin" || game.turn_step === "file" || (game.turn_step === "main" && (canSelectNextHintCard || (canActMain && myBoard?.base_action_done && n(myBoard?.file_count) > 0)))) && <div style={{ position: "fixed", left: 14, bottom: "calc(14px + env(safe-area-inset-bottom))", zIndex: 99960, width: "min(220px, calc(50vw - 24px))", pointerEvents: "auto" }}>
          {game.turn_step === "begin" && <button type="button" style={{ ...st.button, width: "100%", padding: "11px 8px", fontSize: 11, background: "#1d4ed8", borderColor: "#60a5fa" }} disabled={loading || pending} onClick={() => void beginTurnAndPlaceFiles()}>내 턴 시작</button>}
          {game.turn_step === "file" && <button type="button" style={{ ...st.button, width: "100%", padding: "11px 8px", fontSize: 11 }} disabled={loading || pending} onClick={() => void runAction("place_files")}>파일 {Math.max(0, fileTarget - filesPlaced)}장 배치</button>}
          {game.turn_step === "main" && canSelectNextHintCard && <button type="button" style={{ ...st.button, width: "100%", padding: "11px 8px", fontSize: 10, background: "#7f1d1d", borderColor: "#fb7185" }} disabled={loading || pending} title="넥스트 힌트로 가져온 캐릭터를 아직 등장시키지 못해 막힌 경우의 응급 복구입니다." onClick={() => {
            const confirmed = window.confirm("넥스트 힌트의 캐릭터 등장 의무를 강제로 해제합니다. 파일에서 가져온 카드는 손패에 남고, 이미 진행한 다른 행동은 되돌리지 않습니다. 응급 복구용 기능입니다. 진행할까요?");
            if (confirmed) void runAction("cancel_next_hint");
          }}>넥스트 힌트 취소 · 응급 복구</button>}
          {game.turn_step === "main" && !canSelectNextHintCard && canActMain && myBoard?.base_action_done && n(myBoard?.file_count) > 0 && <button type="button" style={{ ...st.button, width: "100%", padding: "11px 8px", fontSize: 11, background: "#164e63", borderColor: "#22d3ee" }} disabled={loading} onClick={() => void runAction("next_hint_take_file")}>넥스트 힌트</button>}
        </div>}
        {game.turn_step === "main" && <div style={{ position: "fixed", right: 14, bottom: "calc(14px + env(safe-area-inset-bottom))", zIndex: 99960, width: "min(220px, calc(50vw - 24px))", pointerEvents: "auto" }}>
          <button type="button" style={{ ...st.button, width: "100%", padding: "11px 8px", fontSize: 11, background: myBoard?.next_hint_pending ? "#3f1d2a" : "#4b2637", borderColor: myBoard?.next_hint_pending ? "#fb7185" : "rgba(248,113,113,.65)" }} disabled={loading || pending || Boolean(myBoard?.next_hint_pending)} title={myBoard?.next_hint_pending ? "넥스트 힌트로 가져온 카드 중 캐릭터 1장을 먼저 등장시켜야 합니다." : ""} onClick={() => void endTurnWithPartnerCheck()}>턴 종료{myBoard?.next_hint_pending ? " · 캐릭터 등장 필요" : ""}</button>
        </div>}
      </div>}

      <section style={{ ...st.panel, marginTop: 10 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap" }}><h2 style={{ ...st.zoneTitle, marginBottom: 0 }}>내 손패 · {myHand.length}장</h2><div style={{ display: "flex", alignItems: "center", justifyContent: "flex-end", flexWrap: "wrap", gap: 7 }}><span style={{ padding: "5px 8px", borderRadius: 7, border: "1px solid rgba(134,239,172,.25)", background: "rgba(22,101,52,.12)", color: C.green, fontSize: 10, fontWeight: 850 }}>레벨 {costLimit} 이하의 카드까지 현장 등장 가능 · 파일 {n(myBoard?.file_count)}장{myBoard?.partner_assist_used ? " + 파트너 어시스트 1" : ""}</span><button type="button" style={{ ...st.smallButton, background: canPartnerAssist ? "#d97706" : st.smallButton.background, color: canPartnerAssist ? "#fff7ed" : st.smallButton.color, borderColor: canPartnerAssist ? "#fbbf24" : st.smallButton.border, boxShadow: canPartnerAssist ? "0 0 0 2px rgba(251,191,36,.18), 0 0 16px rgba(245,158,11,.18)" : "none" }} disabled={loading || !canPartnerAssist} onClick={() => void runAction("partner_assist")}>어시스트</button><button type="button" style={st.smallButton} disabled={loading || !myHand.length || !canManualEffect} onClick={() => { setSelectedHandRevealIds([]); setShowHandRevealSelector(true); }}>손패 카드 공개</button><span style={st.muted}>카드 이미지를 선택하면 상세 설명을 확인할 수 있습니다.</span></div></div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(104px,1fr))", gap: 7, marginTop: 9 }}>
          {myHand.map((card) => {
            const info = infoFor(card);
            const cardPlayLocked = Boolean(localBaseCardPlayLocked || myBoard?.base_card_played_this_turn || myBoard?.character_played_this_turn);
            const normalPlay = canActMain && card.card_type === "character" && !cardPlayLocked && n(card.cost) <= costLimit;
            const eventPlayCostLimit = costLimit + (myBoard?.next_hint_pending ? 1 : 0);
            const normalEventPlay = (canActMain || canPlayEventDuringNextHint) && card.card_type === "event" && (!cardPlayLocked || Boolean(myBoard?.next_hint_pending)) && n(card.cost) <= eventPlayCostLimit;
            const nextSelected = selectedNextHint === card.instance_id;
            return <article key={card.instance_id} style={{ minWidth: 0, padding: 6, border: `1px solid ${nextSelected ? "#fb7185" : "rgba(148,163,184,.15)"}`, borderRadius: 7, background: "#080d16" }}>
              <button type="button" onClick={() => openDetails(card)} style={{ display: "block", width: "100%", border: 0, background: "transparent", color: C.text, padding: 0 }}><CardArt instance={card} /><div style={{ fontSize: 10, fontWeight: 800, lineHeight: 1.35, marginTop: 5, textAlign: "left", overflowWrap: "anywhere" }}>{info?.name || card.key}</div></button>
              <div style={{ fontSize: 9, color: C.muted, marginTop: 3 }}>레벨 {card.cost ?? "-"} · AP {card.ap ?? "-"}</div>
              {(canActMain || canSelectNextHintCard) && card.card_type === "character" && <div style={{ display: "grid", gap: 4, marginTop: 6 }}>
                {canActMain && !myBoard?.next_hint_pending && <button type="button" style={{ ...st.smallButton, opacity: !normalPlay || myFieldCharacterCount >= 5 ? .55 : 1, filter: !normalPlay || myFieldCharacterCount >= 5 ? "grayscale(1)" : "none" }} disabled={loading || !normalPlay || myFieldCharacterCount >= 5} onClick={() => {
                  if (n(card.cost) > costLimit) { showBlockedReason(`필요 레벨을 충족하지 않아 사용할 수 없습니다. 현재 레벨 상한은 ${costLimit}입니다.`); return; }
                  if (myBoard?.base_card_played_this_turn || myBoard?.character_played_this_turn) { showBlockedReason("이번 턴의 기본 카드 사용을 이미 완료했습니다. 추가 카드를 내려면 넥스트 힌트를 사용해 주세요."); return; }
                  if (myFieldCharacterCount >= 5) { showBlockedReason("현장에 캐릭터 카드가 이미 5장 있습니다. 먼저 현장 카드를 이동해 주세요."); return; }
                  void runAction("play_character", { instance_id: card.instance_id });
                }}>기본 등장</button>}
                {canSelectNextHintCard && <button type="button" style={{ ...st.smallButton, borderColor: "#fb7185", color: C.red, opacity: n(card.cost) > (costLimit + 1) ? .72 : 1 }} disabled={loading} onClick={() => {
                  const nextCostLimit = n(myBoard?.file_count) + 1 + (myBoard?.partner_assist_used ? 1 : 0);
                  if (n(card.cost) > nextCostLimit) { showBlockedReason(`필요 레벨을 충족하지 않아 넥스트 힌트로 등장할 수 없습니다. 선언 전 기준 레벨 상한은 ${nextCostLimit}입니다.`); return; }
                  void runAction("next_hint", { instance_id: card.instance_id });
                }}>이 카드로 넥스트 힌트 등장</button>}
              </div>}
              {(canActMain || canPlayEventDuringNextHint) && card.card_type === "event" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 6, background: normalEventPlay ? "#075985" : "#263244", borderColor: normalEventPlay ? "rgba(56,189,248,.45)" : "rgba(148,163,184,.18)", color: normalEventPlay ? "#e0f2fe" : "#94a3b8", opacity: normalEventPlay ? 1 : .55, filter: normalEventPlay ? "none" : "grayscale(1)" }} disabled={loading || !normalEventPlay} onClick={() => {
                if (n(card.cost) > eventPlayCostLimit) { showBlockedReason(`필요 레벨을 충족하지 않아 이벤트를 사용할 수 없습니다. 현재 레벨 상한은 ${eventPlayCostLimit}입니다.`); return; }
                if (myBoard?.base_card_played_this_turn && !myBoard?.next_hint_pending) { showBlockedReason("이번 턴의 기본 카드 사용을 이미 완료했습니다. 추가 카드를 내려면 넥스트 힌트를 사용해 주세요."); return; }
                void runAction("play_event", { instance_id: card.instance_id });
              }}>현장에 이벤트 사용</button>}
              {canManualEffect && card.card_type === "character" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, background: "#3b2f5c" }} disabled={loading} onClick={() => { if (myFieldCharacterCount >= 5) { showBlockedReason("현장에 캐릭터 카드가 이미 5장 있습니다. 먼저 현장 카드를 이동해 주세요."); return; } void runAction("extra_play_character", { instance_id: card.instance_id, effect_override: true }); }}>효과로 추가 등장<br />(제한 무시)</button>}
              {canManualEffect && card.card_type === "event" && <button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, background: "#3b2f5c" }} disabled={loading} onClick={() => void runAction("extra_play_event", { instance_id: card.instance_id, effect_override: true })}>효과로 추가 사용<br />(제한 무시)</button>}
              {canManualEffect && <div style={{ display: "grid", gap: 4, marginTop: 5 }}><button type="button" style={st.smallButton} disabled={loading} onClick={() => { if (window.confirm(`${info?.name || card.key}를 리무브 에이리어로 옮길까요?`)) void runAction("move_hand_card", { instance_id: card.instance_id, destination: "remove" }); }}>리무브</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => openHandZoneChoice(card, "deck")}>덱으로</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => openHandZoneChoice(card, "file")}>파일로</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => setHandEvidenceChoice(card)}>증거로</button><button type="button" style={st.smallButton} disabled={loading} onClick={() => void runAction("move_card_to_mr_partner", { source: "hand", instance_id: card.instance_id })} aria-label={HAND_TO_PARTNER_LABEL}>{HAND_TO_PARTNER_LABEL}</button></div>}
            </article>;
          })}
          {!myHand.length && <p style={st.muted}>손패가 비어 있습니다.</p>}
        </div>
      </section>

      {(canWinCase || canDeclareCulpritsCrime) && <div style={{ position: "fixed", zIndex: 99980, right: 14, bottom: "calc(82px + env(safe-area-inset-bottom))", maxWidth: "min(390px, calc(100vw - 28px))", display: "flex", alignItems: "center", gap: 9, padding: "10px 13px", border: `1px solid ${canDeclareCulpritsCrime ? "#ef4444" : "#22c55e"}`, borderRadius: 10, color: "#f0fdf4", background: canDeclareCulpritsCrime ? "rgba(127,29,29,.97)" : "rgba(20,83,45,.97)", boxShadow: "0 8px 30px rgba(20,83,45,.35)", pointerEvents: "none" }}><span style={{ display: "grid", placeItems: "center", width: 27, height: 27, flex: "0 0 27px", borderRadius: "50%", background: canDeclareCulpritsCrime ? "#dc2626" : "#16a34a", color: "white", fontSize: 20, fontWeight: 1000 }}>!</span><strong style={{ fontSize: 11, lineHeight: 1.45 }}>{canDeclareCulpritsCrime ? "범인들의 범행을 선언할 수 있습니다" : hasEvidenceErasureCase ? "지금부터 증거 인멸이 가능합니다" : "사건 해결 선언이 가능합니다"}</strong></div>}
      {canTransitionSolution && <div style={{ position: "fixed", zIndex: 99980, left: 14, bottom: "calc(82px + env(safe-area-inset-bottom))", maxWidth: "min(390px, calc(100vw - 28px))", display: "flex", alignItems: "center", gap: 9, padding: "10px 13px", border: "1px solid #ef4444", borderRadius: 10, color: "#fff1f2", background: "rgba(127,29,29,.96)", boxShadow: "0 8px 30px rgba(127,29,29,.35)", pointerEvents: "none" }}><span style={{ display: "grid", placeItems: "center", width: 27, height: 27, flex: "0 0 27px", borderRadius: "50%", background: "#ef4444", color: "white", fontSize: 20, fontWeight: 1000 }}>!</span><strong style={{ fontSize: 11, lineHeight: 1.45 }}>지금부터 해결편으로 전환할 수 있습니다</strong></div>}
      {canStartMyTurn && <div role="status" aria-live="polite" style={{ position: "fixed", inset: 0, zIndex: 100120, padding: 18, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.68)", backdropFilter: "blur(5px)" }}><section role="dialog" aria-modal="true" aria-label="내 턴 시작 안내" style={{ width: "min(100%, 660px)", padding: "clamp(16px, 3vw, 28px)", border: "1px solid rgba(147,197,253,.65)", borderRadius: 16, textAlign: "center", color: C.text, background: "linear-gradient(160deg,#16243a,#080d17)", boxShadow: "0 24px 80px rgba(0,0,0,.72)" }}><div style={{ color: C.blue, fontSize: 10, fontWeight: 900, letterSpacing: ".18em" }}>YOUR TURN</div><h2 style={{ margin: "8px 0", fontSize: "clamp(23px, 5vw, 30px)", fontWeight: 950 }}>내 턴을 시작할 수 있습니다!</h2><p style={{ ...st.muted, fontSize: 11, lineHeight: 1.5, margin: "0 0 18px", textWrap: "balance" }}>턴 시작 시 캐릭터 액티브화 → 손패 1장 드로우 → 파일 배치가 차례로 진행됩니다.</p><button type="button" style={{ ...st.button, width: "100%", padding: "13px 16px", fontSize: 13, background: "#1d4ed8", borderColor: "#60a5fa" }} disabled={loading || Boolean(pending)} onClick={() => void beginTurnAndPlaceFiles()}>내 턴 시작 · 액티브화 · 손패 드로우 및 파일 배치</button></section></div>}

      {setCardModal && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSetCardModal(null); }} style={{ position: "fixed", inset: 0, zIndex: 100180, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.88)" }}><section role="dialog" aria-modal="true" aria-label="카드 세트 또는 겹치기" style={{ width: "min(100%, 780px)", maxHeight: "90dvh", overflowY: "auto", padding: 14, border: "1px solid rgba(148,163,184,.24)", borderRadius: 12, background: "#111a2a", color: C.text }}><header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}><h2 style={{ margin: 0, fontSize: 16 }}>{setCardModal.mode === "stack" ? "겹치기" : "세트"}</h2><button type="button" style={st.button} onClick={() => setSetCardModal(null)}>닫기</button></header><p style={{ ...st.muted, marginTop: 6 }}>대상 카드: {nameOf(setCardModal.hostCard)} · 겹친 카드는 현장 5장 제한에 포함되지 않습니다.</p>{setCardModal.mode === "set" && <><div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", margin: "10px 0" }}><label style={{ fontSize: 11, display: "flex", gap: 6, alignItems: "center" }}><input type="radio" name="set-face" checked={!setCardModal.faceUp} onChange={() => setSetCardModal((old) => ({ ...old, faceUp: false }))}/>뒷면으로 세트</label><label style={{ fontSize: 11, display: "flex", gap: 6, alignItems: "center" }}><input type="radio" name="set-face" checked={setCardModal.faceUp} onChange={() => setSetCardModal((old) => ({ ...old, faceUp: true }))}/>앞면으로 세트</label></div>{setCardModal.source === "choose" && <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(140px,1fr))", gap: 7, marginBottom: 10 }}><button type="button" style={st.button} disabled={loading || !myHand.length} onClick={() => setSetCardModal((old) => ({ ...old, source: "hand" }))}>손패에서 가져오기</button><button type="button" style={st.button} disabled={loading || !myRemoveCards.length} onClick={() => setSetCardModal((old) => ({ ...old, source: "remove" }))}>리무브 에이리어에서 가져오기</button><button type="button" style={st.button} disabled={loading || !n(game?.my_deck_count)} onClick={() => setSetCardModal((old) => ({ ...old, source: "deck_top" }))}>덱 위에서 가져오기</button></div>}{setCardModal.source === "deck_top" ? <button type="button" style={st.button} disabled={loading || !n(game?.my_deck_count)} onClick={() => { const { hostCard, hostOwnerId, faceUp } = setCardModal; setSetCardModal(null); void runAction("set_card_to_field", { host_instance_id: hostCard.instance_id, host_owner_user_id: hostOwnerId, source: "deck_top", face_up: faceUp }); }}>세트</button> : (setCardModal.source === "hand" || setCardModal.source === "remove") && <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(100px,1fr))", gap: 7 }}>{(setCardModal.source === "hand" ? myHand : myRemoveCards).filter((card) => card.card_type === "character" || card.card_type === "event" || /event|イベント|이벤트/i.test(`${infoFor(card)?.type || ""} ${infoFor(card)?.originalType || ""} ${infoFor(card)?.roleText || ""}`)).map((card) => <button key={card.instance_id} type="button" style={st.smallButton} disabled={loading} onClick={() => selectSetSourceCard(card)}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4 }}>{nameOf(card)}</span></button>)}{!(setCardModal.source === "hand" ? myHand : myRemoveCards).some((card) => card.card_type === "character" || card.card_type === "event" || /event|イベント|이벤트/i.test(`${infoFor(card)?.type || ""} ${infoFor(card)?.originalType || ""} ${infoFor(card)?.roleText || ""}`)) && <p style={st.muted}>이 에이리어에 세트할 수 있는 카드가 없습니다.</p>}</div>}</>}{setCardModal.mode === "stack" && <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(100px,1fr))", gap: 7, marginTop: 10 }}>{myRemoveCards.map((card) => <button key={card.instance_id} type="button" style={st.smallButton} disabled={loading} onClick={() => selectSetSourceCard(card)}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4 }}>{nameOf(card)}</span></button>)}</div>}</section></div>}

      {handEvidenceChoice && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setHandEvidenceChoice(null); }} style={{ position: "fixed", inset: 0, zIndex: 100175, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.86)", backdropFilter: "blur(4px)" }}><section role="dialog" aria-modal="true" aria-label="증거 카드 공개 방식 선택" style={{ width: "min(100%, 440px)", padding: 15, border: "1px solid rgba(252,211,77,.45)", borderRadius: 12, background: "#111a2a", color: C.text }}><h2 style={{ margin: 0, fontSize: 16 }}>증거 에이리어로 이동</h2><p style={{ ...st.muted, marginTop: 7, fontSize: 11 }}>{nameOf(handEvidenceChoice)}를 증거 에이리어에 앞면 또는 뒷면으로 놓습니다.</p><div style={{ display: "grid", gap: 7, marginTop: 12 }}><button type="button" style={{ ...st.button, background: "#854d0e" }} disabled={loading} onClick={() => { const card = handEvidenceChoice; setHandEvidenceChoice(null); void runAction("move_hand_card_to_evidence", { instance_id: card.instance_id, face_up: true }); }}>앞면으로 증거에 놓기</button><button type="button" style={st.button} disabled={loading} onClick={() => { const card = handEvidenceChoice; setHandEvidenceChoice(null); void runAction("move_hand_card_to_evidence", { instance_id: card.instance_id, face_up: false }); }}>뒷면으로 증거에 놓기</button><button type="button" style={st.smallButton} onClick={() => setHandEvidenceChoice(null)}>취소</button></div></section></div>}
      {handZoneChoice && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setHandZoneChoice(null); }} style={{ position: "fixed", inset: 0, zIndex: 100170, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.84)" }}><section role="dialog" aria-modal="true" aria-label={handZoneChoice.zone === "deck" ? "덱 이동 위치 선택" : "파일 이동 위치 선택"} style={{ width: "min(100%, 440px)", padding: 15, border: "1px solid rgba(148,163,184,.24)", borderRadius: 12, background: "#111a2a", color: C.text }}><h2 style={{ margin: 0, fontSize: 16 }}>{handZoneChoice.zone === "deck" ? "덱으로" : "파일로"}</h2><p style={{ ...st.muted, marginTop: 7, fontSize: 11 }}>{nameOf(handZoneChoice.card)}를 {handZoneChoice.zone === "deck" ? "덱의 어느 쪽에 둘지 선택해 주세요." : "파일 에이리어에 배치합니다. 파일로 이동한 카드는 앞면으로 놓이는 것이 기본 규칙입니다."}</p><div style={{ display: "grid", gap: 7, marginTop: 12 }}>{handZoneChoice.zone === "deck" ? <><button type="button" style={st.button} disabled={loading} onClick={() => applyHandZoneChoice("deck_top")}>덱 맨 위로</button><button type="button" style={st.button} disabled={loading} onClick={() => applyHandZoneChoice("deck")}>덱 맨 아래로</button></> : <><button type="button" style={st.button} disabled={loading} onClick={() => applyHandZoneChoice("file_top")}>파일 맨 위로</button><button type="button" style={st.button} disabled={loading} onClick={() => applyHandZoneChoice("file_bottom")}>파일 맨 아래로</button></>}<button type="button" style={st.smallButton} onClick={() => setHandZoneChoice(null)}>취소</button></div></section></div>}

      {showRemoveArea && minimizedModal !== "remove" && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowRemoveArea(false); }} style={{ position: "fixed", inset: 0, zIndex: 100000, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.84)", backdropFilter: "blur(4px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "remove")} role="dialog" aria-modal="true" aria-label="리무브 에이리어 목록" style={{ width: "min(100%, 920px)", maxHeight: "92dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(148,163,184,.24)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 12, borderBottom: "1px solid rgba(255,255,255,.09)" }}><div><h2 style={{ margin: 0, fontSize: 17 }}>리무브 에이리어</h2><p style={{ ...st.muted, marginTop: 4 }}>내 리무브 {myRemoveCards.length}장 · 상대 리무브 {opponentRemoveCards.length}장</p></div><button type="button" style={st.button} onClick={() => setShowRemoveArea(false)}>닫기 ✕</button></header>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 10, padding: 12, overflowY: "auto" }}>{[{ label: "내 리무브", cards: myRemoveCards }, { label: "상대 리무브", cards: opponentRemoveCards }].map((pile) => <div key={pile.label} style={{ minWidth: 0, padding: 8, border: "1px solid rgba(255,255,255,.08)", borderRadius: 8, background: "#080d16" }}><h3 style={{ margin: "0 0 8px", fontSize: 11, color: C.blue }}>{pile.label} · {pile.cards.length}장</h3><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(86px,1fr))", gap: 6 }}>{pile.cards.map((card) => {
                return <article key={card.instance_id} style={{ border: "1px solid rgba(255,255,255,.1)", boxShadow: "none", borderRadius: 6, padding: 5, background: "#101827", color: C.text, minWidth: 0 }}>
                  <button type="button" onClick={() => openDetails(card)} style={{ width: "100%", border: 0, padding: 0, background: "transparent", color: C.text }}>
                    {infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}
                    <div style={{ fontSize: 9, lineHeight: 1.3, overflowWrap: "anywhere", marginTop: 4 }}>{nameOf(card)}</div>
                  </button>
                  {pile.label === "내 리무브" && !game.game_over && !pending && <div style={{ display: "grid", gap: 3, marginTop: 5 }}>
                    <button type="button" style={st.smallButton} disabled={loading} onClick={() => void runAction("move_remove_card_to_hand", { instance_id: card.instance_id })}>손패로 가져오기</button>
                    <button type="button" style={st.smallButton} disabled={loading || myFieldCharacterCount >= 5} onClick={() => void runAction("play_remove_character", { instance_id: card.instance_id })}>현장에 등장</button>
                    <button type="button" style={st.smallButton} disabled={loading || Boolean(myBoard?.partner_mr_card)} onClick={() => void runAction("move_card_to_mr_partner", { source: "remove", instance_id: card.instance_id })}>파트너로</button>
                  </div>}
                </article>;
              })}</div>{!pile.cards.length && <p style={st.muted}>비어 있습니다.</p>}</div>)}</div>
        </section>
      </div>}

      {deckRemovalPending && <div style={{ position: "fixed", inset: 0, zIndex: 100180, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.91)", backdropFilter: "blur(7px)" }}>
        <section role="dialog" aria-modal="true" aria-label={fileRemovalPending ? "파일 맨 위 카드 리무브 공개 확인" : "덱 위 카드 리무브 공개 확인"} style={{ width: "min(100%, 860px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(253,164,175,.55)", borderRadius: 14, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.75)" }}>
          <header style={{ padding: 14, borderBottom: "1px solid rgba(255,255,255,.09)" }}><h2 style={{ margin: 0, color: C.red, fontSize: 18 }}>{fileRemovalPending ? "파일 맨 위 카드 공개 · 리무브 확인" : "덱 위 카드 공개 · 리무브 확인"}</h2><p style={{ ...st.muted, marginTop: 5, fontSize: 11 }}>{fileRemovalPending ? "파일에서 이동할 카드" : "덱에서 이동할 카드"} {deckRemovalCards.length}장을 양쪽 플레이어가 확인합니다. 두 사람 모두 확인하면 해당 카드가 리무브 에이리어로 이동합니다.</p></header>
          <div style={{ padding: 12, overflowY: "auto" }}><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(100px,1fr))", gap: 8 }}>{deckRemovalCards.map((card, index) => <button key={`${card.instance_id || card.key}-${index}`} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 6, border: "1px solid rgba(253,164,175,.25)", borderRadius: 7, background: "#080d16", color: C.text, textAlign: "left" }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 9, fontWeight: 800, overflowWrap: "anywhere" }}>{nameOf(card)}</span><span style={{ display: "block", marginTop: 3, color: C.muted, fontSize: 8 }}>레벨 {card.cost ?? infoFor(card)?.cost ?? "-"}</span></button>)}</div>
          </div>
          <footer style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap", padding: 12, borderTop: "1px solid rgba(255,255,255,.09)" }}><span style={st.muted}>확인 완료 {deckRemovalAcknowledged.length}/2명</span>{deckRemovalAcknowledged.includes(userId) ? <button type="button" style={{ ...st.button, background: "#374151" }} disabled>{"확인 완료 · 상대 확인 대기"}</button> : <button type="button" style={{ ...st.button, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction(fileRemovalPending ? "acknowledge_file_remove" : "acknowledge_deck_remove")}>카드 확인 완료</button>}</footer>
        </section>
      </div>}

      {showHandRevealSelector && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowHandRevealSelector(false); }} style={{ position: "fixed", inset: 0, zIndex: 100040, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label="손패 공개 카드 선택" style={{ width: "min(100%, 900px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(252,211,77,.55)", borderRadius: 13, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.75)" }}>
          <header style={{ padding: 14, borderBottom: "1px solid rgba(255,255,255,.09)" }}><h2 style={{ margin: 0, fontSize: 18 }}>상대에게 공개할 손패 선택</h2><p style={{ ...st.muted, marginTop: 6, fontSize: 11 }}>손패에서 공개할 카드만 선택합니다. 선택한 카드는 이동하지 않으며, 상대가 확인 버튼을 누르면 공개 창이 닫힙니다.</p><div style={{ display: "flex", alignItems: "center", gap: 7, flexWrap: "wrap", marginTop: 9 }}><span style={{ color: C.gold, fontWeight: 850, fontSize: 11 }}>선택 {selectedHandRevealIds.length}장 / 손패 {myHand.length}장</span><button type="button" style={st.smallButton} disabled={loading || !myHand.length} onClick={() => setSelectedHandRevealIds(selectedHandRevealIds.length === myHand.length ? [] : myHand.map((card) => card.instance_id))}>{selectedHandRevealIds.length === myHand.length ? "전체 선택 해제" : "손패 전체 선택"}</button><button type="button" style={st.smallButton} disabled={loading || !selectedHandRevealIds.length} onClick={() => setSelectedHandRevealIds([])}>선택 해제</button></div></header>
          <div style={{ padding: 12, overflowY: "auto", display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(112px,1fr))", gap: 8 }}>
            {myHand.map((card) => { const info = infoFor(card); const selected = selectedHandRevealIds.includes(card.instance_id); return <button key={card.instance_id} type="button" aria-pressed={selected} onClick={() => setSelectedHandRevealIds((ids) => selected ? ids.filter((id) => id !== card.instance_id) : [...ids, card.instance_id])} style={{ minWidth: 0, padding: 7, textAlign: "left", border: `2px solid ${selected ? C.gold : "rgba(255,255,255,.12)"}`, borderRadius: 8, background: selected ? "rgba(120,83,10,.25)" : "#080d16", color: C.text, cursor: "pointer" }}><CardArt instance={card} /><strong style={{ display: "block", marginTop: 5, fontSize: 10, lineHeight: 1.35, overflowWrap: "anywhere" }}>{selected ? "✓ " : ""}{info?.name || card.key}</strong><span style={{ display: "block", color: C.muted, fontSize: 9, marginTop: 3 }}>레벨 {card.cost ?? "-"} · AP {card.ap ?? "-"}</span></button>; })}
            {!myHand.length && <p style={st.muted}>공개할 손패가 없습니다.</p>}
          </div>
          <footer style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", padding: 12, borderTop: "1px solid rgba(255,255,255,.09)" }}><button type="button" style={st.button} disabled={loading} onClick={() => setShowHandRevealSelector(false)}>취소</button><button type="button" style={{ ...st.button, background: "#854d0e", borderColor: "rgba(252,211,77,.55)" }} disabled={loading || !selectedHandRevealIds.length} onClick={async () => { await runAction("reveal_hand_cards", { instance_ids: selectedHandRevealIds }); setShowHandRevealSelector(false); setSelectedHandRevealIds([]); }}>선택한 {selectedHandRevealIds.length}장 상대에게 잠시 공개</button></footer>
        </section>
      </div>}

      {sharedHandReveal && !game.game_over && minimizedModal !== "handReveal" && <div style={{ position: "fixed", inset: 0, zIndex: 100060, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.88)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "handReveal")} role="dialog" aria-modal="true" aria-label="상대가 공개한 손패" style={{ width: "min(100%, 850px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(252,211,77,.7)", borderRadius: 13, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.8)" }}>
          <header style={{ padding: 14, borderBottom: "1px solid rgba(255,255,255,.1)" }}><h2 style={{ margin: 0, fontSize: 18 }}>{sharedHandReveal.source_display_name || "상대"}님이 손패를 공개했습니다</h2><p style={{ ...st.muted, marginTop: 6, fontSize: 11 }}>상대가 선택한 손패 {sharedHandReveal.cards.length}장입니다. 카드는 손패에 그대로 남아 있습니다.</p></header>
          <div style={{ padding: 12, overflowY: "auto", display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(125px,1fr))", gap: 9 }}>{sharedHandReveal.cards.map((card) => { const info = infoFor(card); return <button key={card.instance_id} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 8, border: "1px solid rgba(252,211,77,.32)", borderRadius: 8, background: "#080d16", color: C.text, textAlign: "left" }}><CardArt instance={card} /><strong style={{ display: "block", marginTop: 5, fontSize: 10, lineHeight: 1.35, overflowWrap: "anywhere" }}>{info?.name || card.key}</strong><span style={{ display: "block", color: C.muted, fontSize: 9, marginTop: 3 }}>레벨 {card.cost ?? "-"} · AP {card.ap ?? "-"}</span></button>; })}</div>
          <footer style={{ display: "flex", justifyContent: "flex-end", padding: 12, borderTop: "1px solid rgba(255,255,255,.09)" }}><button type="button" style={{ ...st.button, background: "#854d0e", borderColor: "rgba(252,211,77,.55)" }} disabled={loading} onClick={() => void runAction("acknowledge_hand_reveal")}>확인하고 공개 창 닫기</button></footer>
        </section>
      </div>}

      {ownPeek && minimizedModal !== "peek" && <div style={{ position: "fixed", inset: 0, zIndex: 100010, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.82)", backdropFilter: "blur(4px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "peek")} role="dialog" aria-modal="true" aria-label="덱 위 카드 살펴보기" style={{ width: "min(100%, 980px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(147,197,253,.3)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <header style={{ padding: 13, borderBottom: "1px solid rgba(255,255,255,.09)" }}><h2 style={{ margin: 0, fontSize: 16 }}>덱 위 카드 살펴보기</h2><p style={{ ...st.muted, marginTop: 5 }}>{ownPeek.source_user_id === userId ? "내 덱" : `${ownPeek.source_display_name || "상대"}의 덱`} 위에서 꺼낸 {ownPeekCards.length}장 · 이 창은 본인에게만 표시됩니다. 위에서 아래 순서가 덱 맨 위부터의 순서입니다.</p></header>
          <div style={{ padding: 12, overflowY: "auto", display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(115px,1fr))", gap: 8 }}>
            {ownPeekOrder.map((card, index) => {
              const shared = (ownPeek.shared_instance_ids || []).includes(card.instance_id);
              const selected = selectedPeekInstanceId === card.instance_id;
              return <article key={card.instance_id} style={{ padding: 7, border: `1px solid ${selected ? "#60a5fa" : shared ? "rgba(252,211,77,.8)" : "rgba(255,255,255,.12)"}`, boxShadow: selected ? "0 0 0 2px rgba(96,165,250,.16)" : "none", borderRadius: 8, background: "#080d16", minWidth: 0 }}>
                <button type="button" onClick={() => openDetails(card)} style={{ display: "block", width: "100%", padding: 0, border: 0, background: "transparent", color: C.text }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", maxHeight: 220, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<div style={{ marginTop: 4, textAlign: "left", fontSize: 10, fontWeight: 800, overflowWrap: "anywhere" }}>{index + 1}. {nameOf(card)}</div></button>
                <div style={{ display: "flex", gap: 4, marginTop: 7 }}><button type="button" style={st.smallButton} disabled={loading || index === 0} onClick={() => setPeekOrderIds((ids) => { const next = [...ids]; [next[index - 1], next[index]] = [next[index], next[index - 1]]; return next; })}>↑ 위</button><button type="button" style={st.smallButton} disabled={loading || index === ownPeekOrder.length - 1} onClick={() => setPeekOrderIds((ids) => { const next = [...ids]; [next[index], next[index + 1]] = [next[index + 1], next[index]]; return next; })}>↓ 아래</button></div>
                {ownPeek.source_user_id === userId && <><button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 5, borderColor: shared ? "rgba(252,211,77,.8)" : selected ? "#60a5fa" : "rgba(255,255,255,.13)", color: shared ? "#fde68a" : selected ? "#bfdbfe" : st.smallButton.color }} disabled={loading} onClick={() => {
                  if (shared) {
                    setSelectedPeekInstanceId("");
                    void runAction("share_deck_peek_card", { instance_id: card.instance_id });
                    return;
                  }
                  setSelectedPeekInstanceId((current) => current === card.instance_id ? "" : card.instance_id);
                }}>{shared ? "공개 지정 취소" : selected ? "공개할 카드로 선택됨" : "공개할 카드로 선택"}</button><button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 4, color: C.green, borderColor: "rgba(134,239,172,.25)" }} disabled={loading || shared} title={shared ? "먼저 위의 공개 지정 취소를 눌러 주세요." : "선택한 카드를 내 손패로 가져옵니다."} onClick={() => void runAction("take_deck_peek_card", { instance_id: card.instance_id })}>이 카드를 손패로 가져오기</button><button type="button" style={{ ...st.smallButton, width: "100%", marginTop: 4, background: "rgba(127,29,29,.32)", color: C.red, borderColor: "rgba(248,113,113,.4)" }} disabled={loading || shared} title={shared ? "먼저 위의 공개 지정 취소를 눌러 주세요." : "선택한 카드를 즉시 리무브 에이리어로 이동합니다."} onClick={() => void runAction("remove_deck_peek_card", { instance_id: card.instance_id })}>이 카드를 리무브하기</button></>}
              </article>;
            })}
          </div>
          <footer style={{ display: "flex", gap: 7, justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", padding: 12, borderTop: "1px solid rgba(255,255,255,.09)" }}><div style={{ display: "flex", gap: 7, flexWrap: "wrap", justifyContent: "flex-start" }}>{ownPeek.source_user_id === userId && <button type="button" style={{ ...st.button, background: "#263d63" }} disabled={loading || !selectedPeekInstanceId || !ownPeekCards.some((card) => card.instance_id === selectedPeekInstanceId)} onClick={() => void runAction("share_deck_peek_card", { instance_id: selectedPeekInstanceId })}>{(ownPeek.shared_instance_ids || []).includes(selectedPeekInstanceId) ? "선택한 카드 공개 선택 취소" : "선택한 카드 공개"}</button>}</div><div style={{ display: "flex", gap: 7, flexWrap: "wrap", justifyContent: "flex-end" }}><button type="button" style={{ ...st.button, background: "#164e63" }} disabled={loading || ownPeekOrder.length !== ownPeekCards.length} onClick={() => void runAction("return_deck_peek", { destination: "top", instance_order: peekOrderIds })}>원래 순서로 덱 위에 되돌리기</button><button type="button" style={st.button} disabled={loading || ownPeekOrder.length !== ownPeekCards.length} onClick={() => void runAction("return_deck_peek", { destination: "bottom", instance_order: peekOrderIds })}>지정 순서로 덱 아래에 넣기</button></div></footer>
        </section>
      </div>}

      {activeSharedPeekCards.length > 0 && dismissedSharedPeekSignature !== sharedPeekSignature && minimizedModal !== "sharedPeek" && <div style={{ position: "fixed", inset: 0, zIndex: 100015, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.8)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "sharedPeek")} role="dialog" aria-modal="true" aria-label="기존 덱 공개 확인" style={{ width: "min(100%, 760px)", maxHeight: "90dvh", overflowY: "auto", padding: 13, border: "1px solid rgba(252,211,77,.55)", borderRadius: 12, background: "#111a2a", color: C.text }}><h2 style={{ margin: "0 0 5px", fontSize: 16 }}>공개된 덱 카드 확인</h2><p style={{ ...st.muted, marginBottom: 10 }}>카드 내용을 확인한 뒤 확인 버튼을 누르면 공개 창이 닫힙니다. 덱을 살펴본 플레이어는 별도로 카드를 덱에 되돌립니다.</p><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(110px,1fr))", gap: 8 }}>{activeSharedPeekCards.map((entry) => <button key={`${entry.source_user_id}-${entry.card?.instance_id}`} type="button" onClick={() => openDetails(entry.card)} style={{ padding: 7, border: "1px solid rgba(252,211,77,.3)", borderRadius: 7, background: "#080d16", color: C.text }}>{infoFor(entry.card)?.imageUrl ? <img src={infoFor(entry.card).imageUrl} alt={nameOf(entry.card)} style={{ width: "100%", maxHeight: 210, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 10, fontWeight: 800, overflowWrap: "anywhere" }}>{nameOf(entry.card)}</span><span style={{ display: "block", fontSize: 8, color: C.gold }}>{entry.source_display_name || "상대 덱"}</span></button>)}</div><div style={{ display: "flex", justifyContent: "flex-end", marginTop: 11 }}><button type="button" style={st.button} disabled={loading} onClick={() => void runAction("acknowledge_shared_deck_peek")}>확인하고 공개 종료</button></div></section>
      </div>}

      {culpritRevealPending && <div style={{ position: "fixed", inset: 0, zIndex: 100220, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.9)", backdropFilter: "blur(6px)" }}>
        <section role="dialog" aria-modal="true" aria-label="범인들의 범행 증거 확인" style={{ width: "min(100%, 900px)", maxHeight: "92dvh", overflowY: "auto", padding: 15, border: "1px solid rgba(248,113,113,.72)", borderRadius: 14, background: "#111a2a", color: C.text, boxShadow: "0 24px 75px rgba(0,0,0,.75)" }}>
          <div style={{ color: "#f87171", fontSize: 10, letterSpacing: ".14em", fontWeight: 900 }}>CULPRITS' CRIME · EVIDENCE CHECK</div>
          <h2 style={{ margin: "5px 0 7px", fontSize: 20 }}>범인들의 범행 · 증거 확인</h2>
          <p style={{ ...st.muted, fontSize: 11, lineHeight: 1.65, marginBottom: 12 }}>선언한 플레이어의 증거 카드가 모두 앞면으로 공개되었습니다. 두 플레이어가 카드의 특징을 확인해 주세요. <b>특징 [범인]</b> 카드만 승리 조건에 포함됩니다.</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(3,minmax(0,1fr))", gap: 8, marginBottom: 12 }}>
            <div style={{ padding: 10, borderRadius: 8, background: "#080d16", border: "1px solid rgba(255,255,255,.09)" }}><div style={{ color: C.muted, fontSize: 9 }}>공개된 증거</div><strong style={{ display: "block", fontSize: 19, marginTop: 3 }}>{culpritRevealCards.length}장</strong></div>
            <div style={{ padding: 10, borderRadius: 8, background: "#080d16", border: "1px solid rgba(255,255,255,.09)" }}><div style={{ color: C.muted, fontSize: 9 }}>특징 [범인]</div><strong style={{ display: "block", fontSize: 19, marginTop: 3, color: culpritTraitCount >= 8 ? "#86efac" : "#fca5a5" }}>{culpritTraitCount} / 8장</strong></div>
            <div style={{ padding: 10, borderRadius: 8, background: "#080d16", border: "1px solid rgba(255,255,255,.09)" }}><div style={{ color: C.muted, fontSize: 9 }}>확인 완료</div><strong style={{ display: "block", fontSize: 19, marginTop: 3 }}>{culpritAcknowledgedIds.length} / {boards.length || 2}명</strong></div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(92px,1fr))", gap: 7 }}>
            {culpritRevealCards.map((card, index) => {
              const hasTrait = cardHasCulpritTrait(card);
              return <button key={card.instance_id || index} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 6, textAlign: "left", border: `1px solid ${hasTrait ? "rgba(74,222,128,.65)" : "rgba(255,255,255,.1)"}`, borderRadius: 7, background: hasTrait ? "rgba(20,83,45,.22)" : "#080d16", color: C.text }}>
                {infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}
                <span style={{ display: "block", marginTop: 5, fontSize: 9, fontWeight: 800, lineHeight: 1.4, overflowWrap: "anywhere" }}>{nameOf(card)}</span>
                <span style={{ display: "block", marginTop: 4, fontSize: 8, fontWeight: 900, color: hasTrait ? "#86efac" : C.muted }}>{hasTrait ? "✓ 특징 [범인]" : "특징 [범인] 없음"}</span>
              </button>;
            })}
          </div>
          <div style={{ marginTop: 12, padding: 10, borderRadius: 8, background: "rgba(127,29,29,.16)", border: "1px solid rgba(248,113,113,.22)", fontSize: 10, lineHeight: 1.6 }}>
            {culpritAcknowledgedIds.length < (boards.length || 2) ? "두 플레이어가 각각 확인해야 승리 조건 판정을 완료합니다." : "양쪽 플레이어가 확인했습니다. 서버가 특징 [범인] 카드 수를 다시 계산합니다."}
          </div>
          <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 12 }}>
            <button type="button" style={st.button} disabled={loading || myCulpritRevealAcknowledged} onClick={() => void runAction("acknowledge_culprits_crime")}>{myCulpritRevealAcknowledged ? "확인 완료 · 상대 확인 대기" : "카드 특징을 확인했습니다"}</button>
          </div>
        </section>
      </div>}


      {pending && String(pending.type || "").startsWith("card_effect_") && <div role="presentation" style={{ position: "fixed", inset: 0, zIndex: 100210, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label="카드 효과 처리" style={{ width: "min(100%, 850px)", maxHeight: "90dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(96,165,250,.45)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.75)" }}>
          <header style={{ padding: 14, borderBottom: "1px solid rgba(255,255,255,.09)" }}>
            <h2 style={{ margin: 0, fontSize: 17 }}>카드 효과 처리</h2>
            <p style={{ ...st.muted, marginTop: 7 }}>{pending.prompt || "카드 효과의 다음 절차를 진행해 주세요."}</p>
            {pending.chooser_user_id && pending.chooser_user_id !== userId && <p style={{ color: C.gold, fontSize: 11, margin: "8px 0 0" }}>상대 플레이어의 선택을 기다리는 중입니다.</p>}
          </header>
          <div style={{ padding: 12, overflowY: "auto", minHeight: 0 }}>
            {pending.type === "card_effect_selection" && pending.chooser_user_id === userId && <>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(108px,1fr))", gap: 8 }}>
                {cardEffectOptions.map((option) => {
                  const card = option.card || option;
                  const id = String(option.instance_id || card.instance_id || "");
                  const selected = cardEffectSelectedIds.includes(id);
                  return <button key={id} type="button" aria-pressed={selected} onClick={() => setCardEffectSelectedIds((ids) => selected ? ids.filter((v) => v !== id) : (ids.length < Number(pending.max || 1) ? [...ids, id] : ids))} style={{ minWidth: 0, padding: 7, border: `2px solid ${selected ? C.gold : "rgba(255,255,255,.12)"}`, borderRadius: 8, background: selected ? "rgba(120,83,10,.25)" : "#080d16", color: C.text, textAlign: "left" }}>
                    <CardArt instance={card} />
                    <strong style={{ display: "block", marginTop: 5, fontSize: 10, lineHeight: 1.35, overflowWrap: "anywhere" }}>{selected ? "✓ " : ""}{nameOf(card)}</strong>
                    <span style={{ display: "block", fontSize: 9, color: C.muted, marginTop: 3 }}>레벨 {card.cost ?? infoFor(card)?.cost ?? "-"} · AP {card.ap ?? "-"}</span>
                  </button>;
                })}
                {!cardEffectOptions.length && <p style={st.muted}>조건에 맞는 선택 대상이 없습니다.</p>}
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
                <span style={{ fontSize: 10, color: C.muted }}>선택 {cardEffectSelectedIds.length}장 · 최대 {pending.max}장</span>
                <button type="button" style={st.button} disabled={loading || cardEffectSelectedIds.length < Number(pending.min || 0) || cardEffectSelectedIds.length > Number(pending.max || 1)} onClick={() => void runAction("card_effect_continue", { selected_instance_ids: cardEffectSelectedIds })}>선택 완료</button>
              </div>
            </>}
            {pending.type === "card_effect_order" && pending.chooser_user_id === userId && <>
              <p style={{ ...st.muted, marginBottom: 8 }}>아래 카드를 클릭하여 덱 아래에 놓을 순서를 정하세요. 선택한 순서가 위에서부터 적용됩니다.</p>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(100px,1fr))", gap: 8 }}>
                {cardEffectOptions.map((option) => {
                  const card = option.card || option;
                  const id = String(option.instance_id || card.instance_id || "");
                  const order = cardEffectSelectedIds.indexOf(id);
                  return <button key={id} type="button" onClick={() => setCardEffectSelectedIds((ids) => order >= 0 ? ids.filter((v) => v !== id) : [...ids, id])} style={{ minWidth: 0, padding: 7, border: `2px solid ${order >= 0 ? C.gold : "rgba(255,255,255,.12)"}`, borderRadius: 8, background: order >= 0 ? "rgba(120,83,10,.25)" : "#080d16", color: C.text, textAlign: "left" }}>
                    {order >= 0 && <span style={{ display: "inline-flex", padding: "2px 5px", marginBottom: 4, borderRadius: 4, background: C.gold, color: "#111", fontSize: 9, fontWeight: 900 }}>{order + 1}번째</span>}
                    <CardArt instance={card} />
                    <strong style={{ display: "block", marginTop: 5, fontSize: 10, overflowWrap: "anywhere" }}>{nameOf(card)}</strong>
                  </button>;
                })}
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
                <span style={{ fontSize: 10, color: C.muted }}>순서 지정 {cardEffectSelectedIds.length} / {cardEffectOptions.length}장</span>
                <button type="button" style={st.button} disabled={loading || cardEffectSelectedIds.length !== cardEffectOptions.length} onClick={() => void runAction("card_effect_continue", { selected_instance_ids: cardEffectSelectedIds })}>순서 확정</button>
              </div>
            </>}
            {pending.type === "card_effect_reveal_ack" && <>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(112px,1fr))", gap: 8 }}>
                {(pending.revealed_cards || []).map((card) => <button key={card.instance_id || card.key} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 7, border: "1px solid rgba(252,211,77,.28)", borderRadius: 8, background: "#080d16", color: C.text, textAlign: "left" }}><CardArt instance={card} /><strong style={{ display: "block", marginTop: 5, fontSize: 10 }}>{nameOf(card)}</strong></button>)}
              </div>
              {pending.chooser_user_id === userId ? <button type="button" style={{ ...st.button, width: "100%", marginTop: 12 }} disabled={loading} onClick={() => void runAction("card_effect_continue", { decision: "acknowledge" })}>확인 완료</button> : <p style={{ ...st.muted, marginTop: 12 }}>공개된 카드를 확인하고 있습니다.</p>}
            </>}
            {pending.type === "card_effect_reveal_sequence" && <>
              {pending.revealed_card && <div style={{ width: "min(100%,220px)", margin: "0 auto", padding: 10, border: "1px solid rgba(252,211,77,.28)", borderRadius: 8, background: "#080d16" }}><CardArt instance={pending.revealed_card} /><strong style={{ display: "block", marginTop: 6, fontSize: 11, textAlign: "center" }}>{nameOf(pending.revealed_card)}</strong><p style={{ ...st.muted, textAlign: "center", marginTop: 5 }}>지금까지 공개 {pending.revealed_count || 1}장</p></div>}
              {pending.chooser_user_id === userId ? <button type="button" style={{ ...st.button, width: "100%", marginTop: 12 }} disabled={loading} onClick={() => void runAction("card_effect_continue", { decision: "acknowledge" })}>다음 카드 공개</button> : <p style={{ ...st.muted, marginTop: 12 }}>카드 공개 진행 중입니다.</p>}
            </>}
            {pending.type === "card_effect_reaction" && <>
              {pending.chooser_user_id === userId ? <div style={{ display: "flex", gap: 8, flexWrap: "wrap", justifyContent: "flex-end", marginTop: 8 }}>
                {(pending.choices || []).map((choice) => <button key={choice} type="button" style={st.button} disabled={loading} onClick={() => void runAction("card_effect_continue", { choice })}>{choice === "activate" ? "발동" : choice === "pass" ? "사용하지 않음" : choice}</button>)}
              </div> : <p style={{ ...st.muted, marginTop: 12 }}>반응 선택을 기다리는 중입니다.</p>}
            </>}
          </div>
        </section>
      </div>}

      {isContactGuardPending && minimizedModal !== "contact" && <div style={{ position: "fixed", inset: 0, zIndex: 100025, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.88)", backdropFilter: "blur(5px)" }}><section onDoubleClick={(event) => minimizeOnDoubleClick(event, "contact")} role="dialog" aria-modal="true" aria-label="컨택 가드 선택" style={{ width: "min(100%, 760px)", maxHeight: "90dvh", overflowY: "auto", padding: 15, border: "1px solid rgba(252,211,77,.6)", borderRadius: 12, background: "#111a2a", color: C.text }}><h2 style={{ margin: "0 0 7px", fontSize: 18 }}>컨택 공격 · 가드 지정</h2><p style={{ ...st.muted, marginBottom: 10 }}>{pending.target_user_id === userId ? "공격을 받을 캐릭터 대신 액티브 캐릭터로 가드할 수 있습니다. 가드한 캐릭터는 컨택 대결에서 패배하면 리무브되고, 승리하면 슬립 상태로 남습니다." : "상대가 공격 가드를 선택하고 있습니다."}</p>{pending.target_user_id === userId ? <><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(110px,1fr))", gap: 7 }}>{(myBoard?.field_cards || []).filter((card) => card.card_type === "character" && card.instance_id !== pending.target_instance_id && !card.rested && (card.status || "active") === "active").map((card) => <button key={card.instance_id} type="button" style={{ ...st.smallButton, padding: 7 }} disabled={loading} onClick={() => void runAction("guard_contact_with_character", { instance_id: card.instance_id })}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4 }}>{nameOf(card)}<br/>AP {n(card.ap)+n(card.ap_bonus)}</span></button>)}</div><button type="button" style={{ ...st.button, width: "100%", marginTop: 10 }} disabled={loading} onClick={() => void runAction("decline_contact_guard")}>가드하지 않고 진행</button></> : <p style={{ marginTop: 10, color: C.gold, fontSize: 11 }}>수비자의 선택을 기다리는 중입니다.</p>}</section></div>}

      {isContactPending && minimizedModal !== "contact" && <div style={{ position: "fixed", inset: 0, zIndex: 100030, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "contact")} role="dialog" aria-modal="true" aria-label="컨택 및 컷인 선택" style={{ width: "min(100%, 700px)", maxHeight: "90dvh", overflowY: "auto", padding: 15, border: "1px solid rgba(251,113,133,.6)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <div style={{ color: C.red, fontSize: 9, letterSpacing: ".15em", fontWeight: 900 }}>CONTACT</div><h2 style={{ margin: "4px 0 7px", fontSize: 18 }}>컨택 발생 · 컷인 선택</h2><p style={{ ...st.muted, marginBottom: 10 }}>{pending.guarded_evidence_attack ? "증거 공격을 가드했습니다. 증거 카드는 유지되고, 공격자와 가드 캐릭터의 컷인 선택 후 AP를 비교합니다." : pending.disguise_replaced_target || pending.disguise_replaced_attacker ? "변장으로 컨택 참가 캐릭터가 교체되었습니다. 교체된 카드는 덱 맨 아래로 이동하고, 새 캐릭터는 슬립 상태입니다." : "컨택 시점의 AP가 낮은 플레이어부터 컷인 선택을 진행합니다. AP가 같으면 수비자가 먼저입니다."} 각 플레이어는 자신의 순서에 컷인 사용, 변장 사용, 또는 패스 중 하나를 선택합니다. 두 플레이어의 선택이 끝나면 최종 AP를 비교합니다.</p>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 9 }}>
            {[{ title: "공격자", board: contactAttackerBoard, card: contactAttackerCard, ap: n(pending.attacker_ap) + n(pending.attacker_bonus) }, { title: "수비자", board: contactTargetBoard, card: contactTargetCard, ap: n(pending.target_ap) + n(pending.target_bonus) }].map((entry) => <div key={entry.title} style={{ padding: 8, border: "1px solid rgba(255,255,255,.1)", borderRadius: 8, background: "#080d16", minWidth: 0 }}><div style={{ fontSize: 9, color: C.muted }}>{entry.title} · {entry.board?.display_name || "플레이어"}</div>{entry.card && <button type="button" onClick={() => openDetails(entry.card)} style={{ display: "block", width: "100%", padding: 0, marginTop: 6, border: 0, background: "transparent", color: C.text }}>{infoFor(entry.card)?.imageUrl ? <img src={infoFor(entry.card).imageUrl} alt={nameOf(entry.card)} style={{ width: "100%", maxHeight: 175, aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", fontSize: 10, marginTop: 5, overflowWrap: "anywhere" }}>{nameOf(entry.card)}</span></button>}<strong style={{ display: "block", marginTop: 8, fontSize: 16 }}>AP {entry.ap}</strong></div>)}
          </div>
          {pending.next_responder_user_id === userId ? <><p style={{ fontSize: 11, color: C.gold, margin: "12px 0 7px" }}>{userId === pending.target_user_id ? "현재 순서: 수비자 · 컷인 사용 여부를 선택해 주세요." : "현재 순서: 공격자 · 컷인 사용 여부를 선택해 주세요."}</p><div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 6, marginBottom: 8, padding: 8, border: "1px solid rgba(96,165,250,.28)", borderRadius: 8, background: "rgba(30,58,95,.22)" }}><span style={{ fontSize: 10, color: "#bfdbfe", fontWeight: 800, marginRight: 3 }}>컨택 AP 수동 조정 · 컷인과 별도</span><button type="button" style={{ ...st.smallButton, background: "#1d4ed8" }} disabled={loading} onClick={() => { const raw = window.prompt("본인 컨택 카드에 더할 AP를 입력하세요. (예: 1000)", "1000"); if (raw === null) return; const amount = Math.abs(Number(String(raw).replace(/[,，\s]/gu, ""))); if (!Number.isSafeInteger(amount) || amount < 1 || amount > 100000) { setError("AP 변화량은 1~100000 사이의 정수로 입력해 주세요."); return; } void runAction("contact_adjust_ap", { amount }); }}>AP +N</button><button type="button" style={{ ...st.smallButton, background: "#374151" }} disabled={loading} onClick={() => { const raw = window.prompt("본인 컨택 카드에서 뺄 AP를 입력하세요. (예: 1000)", "1000"); if (raw === null) return; const amount = Math.abs(Number(String(raw).replace(/[,，\s]/gu, ""))); if (!Number.isSafeInteger(amount) || amount < 1 || amount > 100000) { setError("AP 변화량은 1~100000 사이의 정수로 입력해 주세요."); return; } void runAction("contact_adjust_ap", { amount: -amount }); }}>AP −N</button></div><div style={{ display: "grid", gap: 6 }}>{myHand.filter((card) => n(card.cut_in_bonus) > 0 || Boolean(String(infoFor(card)?.cutInEffect || card.cut_in_effect || "").trim())).map((card) => {
            const effectText = String(infoFor(card)?.cutInEffect || card.cut_in_effect || "").trim();
            const cardInfo = infoFor(card);
            const isCulpritScalingCutIn = cardHasRuleId({ ...cardInfo, ...card }, "0627");
            const culpritCardCount = isCulpritScalingCutIn ? myRemoveCards.filter((removedCard) => {
              const removedInfo = infoFor(removedCard);
              const names = [removedInfo?.name, removedInfo?.originalName, removedCard?.name, removedCard?.nameKo, removedCard?.name_ko, removedCard?.originalName]
                .map((value) => String(value ?? "").normalize("NFKC").replace(/\\s+/gu, "").toLocaleLowerCase());
              return names.some((name) => name === "범인" || name === "犯人");
            }).length : 0;
            const bonus = isCulpritScalingCutIn ? (culpritCardCount + 1) * 2000 : n(card.cut_in_bonus);
            return <button key={card.instance_id} type="button" style={{ ...st.button, background: "#164e63", textAlign: "left" }} disabled={loading} onClick={() => void runAction("contact_use_cutin", { instance_id: card.instance_id })}>
              <strong style={{ display: "block", marginBottom: 4 }}>{nameOf(card)} · {bonus > 0 ? `AP +${bonus}` : "AP 증가 없음"}</strong>
              <span style={{ display: "block", whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 10, lineHeight: 1.5 }}>{effectText || "컷인 효과 문구를 확인할 수 없습니다."}</span>
            </button>;
          })}</div>{myHand.some((card) => card.card_type === "character" && Boolean(infoFor(card)?.disguiseEffect || infoFor(card)?.hensoEffect || card.disguise_effect || card.disguiseEffect || card.hensoEffect || card.henso)) && <div style={{ marginTop: 10, paddingTop: 10, borderTop: "1px solid rgba(252,211,77,.2)" }}><h3 style={{ margin: "0 0 5px", color: C.gold, fontSize: 12 }}>변장 사용 · 컷인 대신 선택</h3><p style={{ ...st.muted, marginBottom: 8 }}>손패의 변장 캐릭터를 선택하면 현재 자신의 컨택 캐릭터와 교체됩니다. 기존 캐릭터는 덱 맨 아래로 이동하며, 새 캐릭터는 슬립 상태로 등장합니다.</p><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(108px,1fr))", gap: 7 }}>{myHand.filter((card) => card.card_type === "character" && Boolean(infoFor(card)?.disguiseEffect || infoFor(card)?.hensoEffect || card.disguise_effect || card.disguiseEffect || card.hensoEffect || card.henso)).map((card) => { const info = infoFor(card); const effect = String(info?.disguiseEffect || info?.hensoEffect || card.disguise_effect || card.disguiseEffect || card.hensoEffect || card.henso || "").trim(); return <button key={card.instance_id} type="button" style={{ ...st.smallButton, padding: 7, borderColor: "rgba(252,211,77,.45)", textAlign: "left" }} disabled={loading} onClick={() => void runAction("contact_use_disguise", { instance_id: card.instance_id, disguise_effect: effect })}>{info?.imageUrl ? <img src={info.imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 10 }}>{nameOf(card)}</span><span style={{ display: "block", marginTop: 3, color: C.gold, fontSize: 9, whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{effect || "변장"}</span></button>; })}</div></div>}{myHand.every((card) => n(card.cut_in_bonus) <= 0 && !String(infoFor(card)?.cutInEffect || card.cut_in_effect || "").trim()) && <p style={{ ...st.muted, marginTop: 6 }}>컷인 카드가 없어도 변장 또는 패스를 선택할 수 있습니다.</p>}<button type="button" style={{ ...st.button, background: "#273244", width: "100%", marginTop: 8 }} disabled={loading} onClick={() => void runAction("contact_pass_cutin")}>{userId === pending.target_user_id
  ? ((pending.attacker_cut_in_used || pending.attacker_cut_in_passed) ? "컷인/변장 없이 최종 AP 비교" : "컷인/변장 없이 공격자에게 넘기기")
  : ((pending.target_cut_in_used || pending.target_cut_in_passed) ? "컷인/변장 없이 최종 AP 비교" : "컷인/변장 없이 수비자에게 넘기기")}</button></> : <p style={{ margin: "12px 0 0", fontSize: 11, color: C.muted }}>{pending.next_responder_user_id === pending.target_user_id ? "수비자가 컷인 사용 여부를 선택하고 있습니다." : "공격자가 컷인 사용 여부를 선택하고 있습니다."}</p>}
        </section>
      </div>}

      {revealedEvidenceCard && minimizedModal !== "evidence" && <div style={{ position: "fixed", inset: 0, zIndex: 100030, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "evidence")} role="dialog" aria-modal="true" aria-label="공개된 증거 카드" style={{ width: "min(100%, 460px)", maxHeight: "90dvh", overflowY: "auto", padding: 15, border: "1px solid rgba(252,211,77,.55)", borderRadius: 12, background: "#111a2a", color: C.text, textAlign: "center" }}>
          <h2 style={{ margin: "0 0 6px", fontSize: 17 }}>{isManualEvidenceRemovePending ? "증거 리무브 · 카드 공개" : "증거 공격 · 카드 공개"}</h2>
          <p style={{ ...st.muted, marginBottom: 10 }}>{isManualEvidenceRemovePending ? "리무브로 보내는 증거 카드가 양쪽 플레이어에게 공개되었습니다. 두 사람 모두 확인하면 리무브 에이리어로 이동합니다." : "공격 대상이 된 증거 카드가 양쪽 플레이어에게 공개되었습니다. 수비자가 확인하면 리무브 에이리어로 이동합니다."}</p>
          {Boolean(revealedEvidenceCard.hirameki_achieved && infoFor(revealedEvidenceCard)?.hiramekiEffect) && <div style={{ width: "min(100%, 230px)", boxSizing: "border-box", margin: "0 auto 10px", padding: "6px 8px", borderRadius: 6, background: "#9d174d", border: "1px solid #f472b6", color: "#fff", fontSize: 10, fontWeight: 850 }}>❗ 히라메키 달성</div>}
          <button type="button" onClick={() => openDetails(revealedEvidenceCard)} style={{ width: "min(100%, 230px)", border: 0, padding: 0, background: "transparent" }}>{infoFor(revealedEvidenceCard)?.imageUrl ? <img src={infoFor(revealedEvidenceCard).imageUrl} alt={nameOf(revealedEvidenceCard)} style={{ width: "100%", maxHeight: "48vh", objectFit: "contain" }} /> : <div style={st.faceDown} />}<strong style={{ display: "block", marginTop: 6, fontSize: 12 }}>{nameOf(revealedEvidenceCard)}</strong></button>
          {isManualEvidenceRemovePending
            ? (myEvidenceRemoveAcknowledged
              ? <button type="button" style={{ ...st.button, width: "100%", marginTop: 12, background: "#374151" }} disabled>확인 완료 · 상대 확인 대기 ({evidenceRemoveAcknowledgedIds.length}/2)</button>
              : <button type="button" style={{ ...st.button, width: "100%", marginTop: 12, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("acknowledge_evidence_remove")}>카드 확인 완료 ({evidenceRemoveAcknowledgedIds.length}/2)</button>)
            : (pending.target_user_id === userId
              ? <button type="button" style={{ ...st.button, width: "100%", marginTop: 12, background: "#7f1d1d" }} disabled={loading} onClick={() => void runAction("resolve_evidence_attack")}>공개 확인 · 리무브로 이동</button>
              : <p style={{ ...st.muted, marginTop: 10 }}>수비자가 확인한 후 리무브 에이리어로 이동합니다.</p>)}
        </section>
      </div>}

      {detailCard && minimizedModal !== "detail" && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setDetailCard(null); }} style={{ position: "fixed", inset: 0, zIndex: 100400, padding: 12, display: "flex", justifyContent: "center", alignItems: "center", background: "rgba(0,0,0,.83)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "detail")} role="dialog" aria-modal="true" aria-label={`${nameOf(detailCard)} 카드 상세`} style={{ width: "min(100%, 980px)", maxHeight: "94dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(255,255,255,.16)", borderRadius: 12, background: "#111a2a", color: C.text, boxShadow: "0 24px 70px rgba(0,0,0,.65)" }}>
          <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 12, borderBottom: "1px solid rgba(255,255,255,.09)" }}><div><div style={{ color: C.red, fontSize: 9, letterSpacing: ".14em", fontWeight: 900 }}>CARD DETAIL</div><h2 style={{ margin: "3px 0 0", fontSize: 18, fontWeight: 900 }}>{nameOf(detailCard)}</h2></div><button type="button" style={st.button} onClick={() => setDetailCard(null)}>닫기 ✕</button></header>
          <div className="mock-card-modal-layout">
            <div>{infoFor(detailCard)?.imageUrl && <img src={infoFor(detailCard).imageUrl} alt={nameOf(detailCard)} style={{ width: "100%", maxHeight: "58vh", objectFit: "contain", background: "#080d16", borderRadius: 8 }} />}</div>
            <div style={{ minWidth: 0, display: "grid", gap: 9, alignContent: "start" }}>
              <dl style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 6, margin: 0 }}>{[["종류", infoFor(detailCard)?.type], ["색상", infoFor(detailCard)?.color], ["레어도", infoFor(detailCard)?.rarity], ["레벨", detailCard.cost ?? infoFor(detailCard)?.cost], ["AP", detailCard.ap ?? infoFor(detailCard)?.ap], ["LP", detailCard.lp ?? infoFor(detailCard)?.lp], ["수록 제품", infoFor(detailCard)?.set]].map(([label, value]) => <div key={label} style={{ padding: 8, borderRadius: 6, background: "#080d16", border: "1px solid rgba(255,255,255,.07)" }}><dt style={{ color: C.muted, fontSize: 9 }}>{label}</dt><dd style={{ margin: "3px 0 0", fontSize: 11, fontWeight: 750, overflowWrap: "anywhere" }}>{value ?? "-"}</dd></div>)}</dl>
              {(infoFor(detailCard)?.traits?.length > 0) && <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>특징</h3><p style={{ margin: 0, fontSize: 11, lineHeight: 1.6 }}>{infoFor(detailCard).traits.join(" · ")}</p></div>}
              {(infoFor(detailCard)?.keywordTags?.length > 0) && <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>특수 태그</h3><p style={{ margin: 0, fontSize: 11, lineHeight: 1.6 }}>{infoFor(detailCard).keywordTags.join(" · ")}</p></div>}
              {(infoFor(detailCard)?.hiramekiEffect || infoFor(detailCard)?.cutInEffect || infoFor(detailCard)?.disguiseEffect) && <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>게임 시스템 효과</h3>{infoFor(detailCard)?.hiramekiEffect && <p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.65, margin: "4px 0" }}><b style={{ color: C.muted }}>히라메키</b>　{infoFor(detailCard).hiramekiEffect}</p>}{infoFor(detailCard)?.cutInEffect && <p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.65, margin: "4px 0" }}><b style={{ color: C.muted }}>컷인</b>　{infoFor(detailCard).cutInEffect}</p>}{infoFor(detailCard)?.disguiseEffect && <p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.65, margin: "4px 0" }}><b style={{ color: C.muted }}>변장</b>　{infoFor(detailCard).disguiseEffect}</p>}</div>}
              <div style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><h3 style={{ fontSize: 11, margin: "0 0 5px", color: C.blue }}>카드 효과</h3><p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.75, margin: 0 }}>{infoFor(detailCard)?.ability || "효과 텍스트 없음"}</p></div>
              {infoFor(detailCard)?.originalAbility && <details style={{ padding: 9, background: "#080d16", borderRadius: 6 }}><summary style={{ cursor: "pointer", fontSize: 11 }}>일본어 원문 보기</summary><p style={{ whiteSpace: "pre-wrap", fontSize: 11, lineHeight: 1.7 }}>{infoFor(detailCard).originalAbility}</p></details>}
            </div>
          </div>
        </section>
      </div>}

      {minimizedModalExists && <button type="button" onClick={() => setMinimizedModal("")} style={{ position: "fixed", zIndex: 100250, left: "50%", bottom: 14, transform: "translateX(-50%)", padding: "10px 16px", borderRadius: 999, border: "1px solid rgba(147,197,253,.65)", color: "#eff6ff", background: "rgba(30,58,95,.97)", boxShadow: "0 8px 28px rgba(0,0,0,.55)", fontSize: 11, fontWeight: 900 }}>접힌 창 복구 · {minimizedModalLabels[minimizedModal] || "창"}</button>}

      {blockedToast && <div role="alert" aria-live="assertive" style={{ position: "fixed", zIndex: 100260, right: 14, bottom: "calc(82px + env(safe-area-inset-bottom))", width: "min(430px, calc(100vw - 28px))", display: "flex", alignItems: "flex-start", gap: 10, padding: "12px 14px", border: "1px solid #ef4444", borderRadius: 11, background: "rgba(69,10,10,.97)", color: "#fff1f2", boxShadow: "0 12px 32px rgba(0,0,0,.5)" }}><span style={{ display: "grid", placeItems: "center", width: 27, height: 27, flex: "0 0 27px", borderRadius: "50%", background: "#dc2626", color: "white", fontSize: 18, fontWeight: 1000 }}>!</span><span style={{ fontSize: 11, lineHeight: 1.55, fontWeight: 750 }}>{blockedToast}</span><button type="button" onClick={() => setBlockedToast("")} aria-label="안내 닫기" style={{ marginLeft: "auto", border: 0, background: "transparent", color: "#fecaca", fontSize: 15 }}>×</button></div>}

      {game.game_over && <div style={{ position: "fixed", inset: 0, zIndex: 100200, display: "flex", alignItems: "center", justifyContent: "center", padding: 18, background: "rgba(0,0,0,.96)", color: "#f8fafc" }}>
        <section style={{ width: "min(100%, 540px)", padding: "clamp(22px, 5vw, 42px)", textAlign: "center", border: "1px solid rgba(134,239,172,.3)", borderRadius: 18, background: "linear-gradient(160deg,#111827,#05070b)", boxShadow: "0 24px 80px rgba(0,0,0,.7)" }}>
          <div style={{ color: C.green, fontSize: 10, letterSpacing: ".22em", fontWeight: 950 }}>CASE CLOSED</div>
          <h1 style={{ margin: "12px 0 9px", fontSize: "clamp(28px, 7vw, 42px)", fontWeight: 950, color: "#f0fdf4" }}>{winnerName} 승리!</h1>
          <p style={{ margin: "0 0 22px", color: "#a7b4c8", fontSize: 13 }}>턴 {n(game.winner_turn_number, n(game.turn_number))} 소요</p>
          <button type="button" disabled={loadingOpponentDeck} onClick={() => void openOpponentDeckAfterGame()} style={{ width: "100%", padding: "12px 16px", border: "1px solid #22c55e", borderRadius: 10, background: "#166534", color: "white", fontSize: 13, fontWeight: 900, cursor: loadingOpponentDeck ? "wait" : "pointer", opacity: loadingOpponentDeck ? .6 : 1 }}>{loadingOpponentDeck ? "상대 덱을 불러오는 중…" : "상대 덱 보기 →"}</button>
          <button type="button" disabled={loadingPlayHistory} onClick={() => void openPlayHistory()} style={{ width: "100%", padding: "11px 16px", marginTop: 8, border: "1px solid rgba(147,197,253,.45)", borderRadius: 10, background: "#17243a", color: "#dbeafe", fontSize: 12, fontWeight: 850 }}>{loadingPlayHistory ? "플레이 기록을 불러오는 중…" : "플레이 기록 보기 →"}</button>
          {onReturnToLobby && <button type="button" onClick={onReturnToLobby} style={{ width: "100%", padding: "12px 16px", marginTop: 10, border: "1px solid rgba(248,113,113,.32)", borderRadius: 10, background: "#7f2935", color: "#f8fafc", fontSize: 12, fontWeight: 900 }}>경기 종료 · 새 대전 준비하기</button>}
          <p style={{ ...st.muted, marginTop: 12 }}>상대 덱과 이번 게임의 턴별 기록을 확인할 수 있습니다. 새 대전을 준비하면 이 방의 캐시가 정리됩니다.</p>
        </section>
      </div>}


      {showActionLog && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowActionLog(false); }} style={{ position: "fixed", inset: 0, zIndex: 100250, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.9)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label="전체 게임 행동 로그" style={{ width: "min(100%, 760px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(147,197,253,.35)", borderRadius: 12, background: "#101827", color: C.text }}>
          <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, padding: 12, borderBottom: "1px solid rgba(255,255,255,.1)" }}>
            <div><h2 style={{ margin: 0, fontSize: 16, fontWeight: 900 }}>전체 게임 행동 로그</h2><p style={{ ...st.muted, marginTop: 4 }}>가장 최근 행동부터 과거 순서로 표시됩니다. 아래로 스크롤해 이전 기록을 확인하세요.</p></div>
            <button type="button" style={st.button} disabled={loadingActionLog} onClick={() => void refreshActionLog()}>{loadingActionLog ? "새로고침 중…" : "새로고침"}</button>
            <button type="button" style={st.smallButton} onClick={() => setShowActionLog(false)}>닫기 ✕</button>
          </header>
          <div style={{ padding: 10, overflowY: "auto", display: "grid", gap: 6 }}>
            {!actionLog.length && <p style={st.muted}>{loadingActionLog ? "기록을 불러오는 중…" : "저장된 행동 로그가 없습니다."}</p>}
            {actionLogError && <p role="alert" style={{ color: C.red, fontSize: 10, lineHeight: 1.6 }}>{actionLogError}</p>}
            {actionLog.map((entry, index) => <article key={entry.id || (String(entry.created_at) + "-" + index)} style={{ display: "grid", gridTemplateColumns: "minmax(96px,auto) minmax(0,1fr)", gap: 10, alignItems: "start", padding: "9px 10px", border: "1px solid rgba(255,255,255,.08)", borderRadius: 7, background: index === 0 ? "rgba(30,58,95,.3)" : "#080d16" }}>
              <div><div style={{ color: C.gold, fontSize: 10, fontWeight: 850 }}>턴 {entry.turn_number ?? "-"}</div><div style={{ marginTop: 3, color: C.muted, fontSize: 9 }}>{entry.created_at ? new Date(entry.created_at).toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit", second: "2-digit" }) : "시간 미상"}</div></div>
              <div><div style={{ color: entry.actor_user_id === userId ? C.green : C.blue, fontSize: 9, fontWeight: 800, marginBottom: 3 }}>{entry.actor_user_id === userId ? "나" : (entry.actor_display_name || "플레이어")}{entry.actor_seat ? " · 좌석 " + entry.actor_seat : ""}</div><div style={{ overflowWrap: "anywhere", fontSize: 11, lineHeight: 1.6 }}>{entry.action_label}</div></div>
            </article>)}
          </div>
        </section>
      </div>}

      {showPlayHistory && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowPlayHistory(false); }} style={{ position: "fixed", inset: 0, zIndex: 100230, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.92)" }}><section role="dialog" aria-modal="true" aria-label="플레이 기록" style={{ width: "min(100%, 1100px)", maxHeight: "94dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(147,197,253,.35)", borderRadius: 12, background: "#101827", color: C.text }}><header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, padding: 12, borderBottom: "1px solid rgba(255,255,255,.1)" }}><div><h2 style={{ margin: 0, fontSize: 17, fontWeight: 900 }}>플레이 기록</h2><p style={{ ...st.muted, marginTop: 4 }}>선공은 왼쪽, 후공은 오른쪽으로 표시됩니다.</p></div><button type="button" style={st.button} onClick={() => setShowPlayHistory(false)}>닫기 ✕</button></header><div style={{ padding: 10, overflowY: "auto", display: "grid", gap: 9 }}>{playHistory.length === 0 && <p style={st.muted}>저장된 플레이 기록이 없습니다.</p>}{playHistory.map((entry, entryIndex) => { const snap = entry.snapshot || {}; const sides = Array.isArray(snap.players) ? snap.players : []; const firstId = snap.first_player_user_id || game.first_player_user_id; const orderedSides = [...sides].sort((a,b) => a.user_id === firstId ? -1 : b.user_id === firstId ? 1 : 0); const previousSides = playHistory[entryIndex - 1]?.snapshot?.players || []; const zoneRows = playHistoryZoneSnapshots.filter((zone) => Number(zone.turn_number) === Number(entry.turn_number)); const turnUserId = snap.current_turn_user_id || snap.turn_user_id || snap.active_player_user_id || null; const zoneForSide = (side) => { const rows = zoneRows.filter((zone) => zone.player_user_id === side.user_id); const exact = turnUserId ? rows.filter((zone) => zone.turn_user_id === turnUserId) : rows; const choices = exact.length ? exact : rows; choices.sort((a,b) => new Date(a.captured_at).getTime() - new Date(b.captured_at).getTime()); return choices[choices.length - 1] || null; }; const deltaFor = (side, key) => countDelta(side[key], previousSides.find((item) => item.user_id === side.user_id)?.[key]); return <article key={entry.id} style={{ border: "1px solid rgba(255,255,255,.1)", borderRadius: 8, padding: 9, background: "#080d16" }}><div style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", marginBottom: 7 }}><strong style={{ fontSize: 11, color: C.gold }}>턴 {entry.turn_number}</strong><span style={{ fontSize: 9, color: C.muted }}>{new Date(entry.created_at).toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit", second: "2-digit" })}</span></div><div style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 7 }}>{orderedSides.map((side, index) => <div key={side.user_id} style={{ minWidth: 0, padding: 7, border: "1px solid rgba(255,255,255,.08)", borderRadius: 7, background: "#101827" }}><strong style={{ display: "block", fontSize: 9, color: index === 0 ? C.blue : C.gold, marginBottom: 4 }}>{index === 0 ? "선공" : "후공"} · {side.display_name || "플레이어"}</strong><div style={{ fontSize: 8, color: C.muted, lineHeight: 1.5 }}>현재: 덱 {side.deck_count ?? 0} · 손패 {side.hand_count ?? 0} · 파일 {side.file_count ?? 0} · 증거 {side.evidence_count ?? 0} · 리무브 {side.remove_count ?? 0}</div><div style={{ fontSize: 8, color: C.green, lineHeight: 1.5, marginTop: 2 }}>변화: 덱 {deltaFor(side,"deck_count")} / 손패 {deltaFor(side,"hand_count")} / 파일 {deltaFor(side,"file_count")} / 증거 {deltaFor(side,"evidence_count")} / 리무브 {deltaFor(side,"remove_count")}</div><div style={{ marginTop: 6 }}><b style={{ fontSize: 8, color: C.blue }}>현장</b><div style={{ display: "flex", flexWrap: "wrap", gap: 3, marginTop: 3 }}>{(zoneForSide(side)?.field_cards || side.field_cards || []).map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} title={`${nameOf(card)} 상세 보기`} style={{ ...st.smallButton, display: "flex", flexDirection: "column", alignItems: "center", gap: 3, width: 62, maxWidth: "100%", whiteSpace: "normal", fontSize: 7, padding: 4 }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ display: "block", width: 40, maxWidth: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={{ ...st.faceDown, width: 40 }} />}<span style={{ display: "block", overflowWrap: "anywhere", textAlign: "center", lineHeight: 1.2 }}>{nameOf(card)}{card.rested ? " · 슬립" : ""}</span></button>)}{!(zoneForSide(side)?.field_cards || side.field_cards || []).length && <span style={{ fontSize: 8, color: C.muted }}>없음</span>}</div></div><div style={{ marginTop: 6 }}><b style={{ fontSize: 8, color: C.gold }}>손패 목록</b><div style={{ display: "flex", flexWrap: "wrap", gap: 3, marginTop: 3 }}>{(zoneForSide(side)?.hand_cards || side.hand_cards || []).map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} title={`${nameOf(card)} 상세 보기`} style={{ ...st.smallButton, display: "flex", flexDirection: "column", alignItems: "center", gap: 3, width: 62, maxWidth: "100%", whiteSpace: "normal", fontSize: 7, padding: 4 }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ display: "block", width: 40, maxWidth: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={{ ...st.faceDown, width: 40 }} />}<span style={{ display: "block", overflowWrap: "anywhere", textAlign: "center", lineHeight: 1.2 }}>{nameOf(card)}</span></button>)}{!(zoneForSide(side)?.hand_cards || side.hand_cards || []).length && <span style={{ fontSize: 8, color: C.muted }}>없음</span>}</div></div>
<div style={{ marginTop: 6 }}><b style={{ fontSize: 8, color: "#a78bfa" }}>증거 에이리어 목록</b><div style={{ display: "flex", flexWrap: "wrap", gap: 3, marginTop: 3 }}>{(zoneForSide(side)?.evidence_cards || side.evidence_cards || []).map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} title={`${nameOf(card)} 상세 보기`} style={{ ...st.smallButton, display: "flex", flexDirection: "column", alignItems: "center", gap: 3, width: 62, maxWidth: "100%", whiteSpace: "normal", fontSize: 7, padding: 4 }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ display: "block", width: 40, maxWidth: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={{ ...st.faceDown, width: 40 }} />}<span style={{ display: "block", overflowWrap: "anywhere", textAlign: "center", lineHeight: 1.2 }}>{nameOf(card)}</span></button>)}{!(zoneForSide(side)?.evidence_cards || side.evidence_cards || []).length && <span style={{ fontSize: 8, color: C.muted }}>없음</span>}</div></div>
<div style={{ marginTop: 6 }}><b style={{ fontSize: 8, color: "#93c5fd" }}>파일 에이리어 목록</b><div style={{ display: "flex", flexWrap: "wrap", gap: 3, marginTop: 3 }}>{(zoneForSide(side)?.file_cards || side.file_cards || []).map((card) => <button key={card.instance_id} type="button" onClick={() => openDetails(card)} title={`${nameOf(card)} 상세 보기`} style={{ ...st.smallButton, display: "flex", flexDirection: "column", alignItems: "center", gap: 3, width: 62, maxWidth: "100%", whiteSpace: "normal", fontSize: 7, padding: 4 }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ display: "block", width: 40, maxWidth: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={{ ...st.faceDown, width: 40 }} />}<span style={{ display: "block", overflowWrap: "anywhere", textAlign: "center", lineHeight: 1.2 }}>{nameOf(card)}</span></button>)}{!(zoneForSide(side)?.file_cards || side.file_cards || []).length && <span style={{ fontSize: 8, color: C.muted }}>없음</span>}</div></div></div>)}</div></article>; })}</div></section></div>}

      {opponentDeckAfterWin && minimizedModal !== "opponentDeck" && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpponentDeckAfterWin(null); }} style={{ position: "fixed", inset: 0, zIndex: 100220, display: "flex", alignItems: "center", justifyContent: "center", padding: 12, background: "rgba(0,0,0,.9)", backdropFilter: "blur(5px)" }}>
        <section onDoubleClick={(event) => minimizeOnDoubleClick(event, "opponentDeck")} role="dialog" aria-modal="true" aria-label="상대 덱 보기" style={{ width: "min(100%, 1040px)", maxHeight: "92dvh", display: "flex", flexDirection: "column", overflow: "hidden", border: "1px solid rgba(134,239,172,.3)", borderRadius: 13, background: "#101827", color: C.text }}>
          <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: 14, borderBottom: "1px solid rgba(255,255,255,.1)" }}><div><h2 style={{ margin: 0, fontSize: 18, fontWeight: 900 }}>{opponentDeckAfterWin.opponent_name || "상대"}의 덱</h2><p style={{ ...st.muted, marginTop: 4 }}>게임 종료 후 공개된 상대 덱 · 총 {(opponentDeckAfterWin.cards || []).length}장 및 특수 카드</p></div><button type="button" style={st.button} onClick={() => setOpponentDeckAfterWin(null)}>닫기 ✕</button></header>
          <div style={{ padding: 12, overflowY: "auto" }}>{opponentDeckGroups.map((group) => group.cards.length > 0 && <section key={group.key} style={{ marginBottom: 15 }}><header style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 8, marginBottom: 8, paddingBottom: 6, borderBottom: "1px solid rgba(255,255,255,.1)" }}><h3 style={{ margin: 0, color: group.key === "event" ? C.gold : C.blue, fontSize: 12, fontWeight: 900 }}>{group.label}</h3><span style={st.muted}>{group.cards.length}장 · 레벨 높은 순</span></header><div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(95px,1fr))", gap: 7 }}>{group.cards.map((card, index) => <button key={`${card.instance_id || card.key}-${index}`} type="button" onClick={() => openDetails(card)} style={{ minWidth: 0, padding: 6, border: "1px solid rgba(255,255,255,.1)", borderRadius: 7, background: "#080d16", color: C.text, textAlign: "left" }}>{infoFor(card)?.imageUrl ? <img src={infoFor(card).imageUrl} alt={nameOf(card)} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} /> : <div style={st.faceDown} />}<span style={{ display: "block", marginTop: 4, fontSize: 9, fontWeight: 800, lineHeight: 1.3, overflowWrap: "anywhere" }}>{nameOf(card)}</span><span style={{ display: "block", marginTop: 3, color: C.muted, fontSize: 8 }}>레벨 {card.cost ?? infoFor(card)?.cost ?? "-"}</span></button>)}</div></section>)}</div>
        </section>
      </div>}
    </main>
  );
}
