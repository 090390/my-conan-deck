import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import MatchStartFlow from "./MatchStartFlow";
import MatchTurnBoard from "./MatchTurnBoard";
import MatchGreetingStep from "./MatchGreetingStep";
import AIBattlePanel from "./AIBattlePanel";

const ACTIVE_ROOM_STORAGE_KEY = "conan-active-private-room-v1";
const COMPLETED_GREETING_ROOM_KEY = "conan-completed-greeting-room-v1";
const AI_ROOM_STORAGE_KEY = "conan-ai-battle-room-v1";

function normalizeCardIdentifier(value) {
  const raw = String(value ?? "").trim().toLocaleUpperCase();
  if (!raw) return "";
  return /^\d+$/.test(raw) ? String(Number(raw)) : raw;
}

function getCopyLimitExemptionId(card, fallbackKey = "") {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const values = [card?.key, card?.databaseId, card?.cardId, card?.cardNum, fallbackKey,
    source?.id, source?.databaseId, source?.database_id, source?.cardId, source?.card_id, source?.cardNum, source?.card_num];
  if (values.some((value) => normalizeCardIdentifier(value) === "627")) return "0627";
  if (values.some((value) => normalizeCardIdentifier(value) === "1039")) return "1039";
  return null;
}

function getEventRuleCode(card, fallbackKey = "") {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const values = [card?.key, card?.databaseId, card?.cardId, card?.cardNum, fallbackKey,
    source?.id, source?.databaseId, source?.database_id, source?.cardId, source?.card_id, source?.cardNum, source?.card_num];
  const normalized = values.map((value) => String(value ?? "").trim().toLocaleUpperCase());
  if (values.some((value) => normalizeCardIdentifier(value) === "1046")) return "culprits_1046";
  if (values.some((value) => normalizeCardIdentifier(value) === "1261")
      || normalized.some((value) => value === "B11098" || value === "B11098P")) return "conan_vs_kid_1261";
  return "";
}

function getCardTraits(card) {
  const values = [card?.traits, card?.category1, card?.category2, card?.category3];
  return [...new Set(values.flatMap((value) => {
    if (Array.isArray(value)) return value.map((item) => String(item ?? "").trim()).filter(Boolean);
    if (value === null || value === undefined || String(value).trim() === "") return [];
    return String(value).split(/[、,，;；|｜]/u).map((item) => item.trim()).filter(Boolean);
  }))];
}

const COLOR_ORDER = ["청", "적", "황", "녹", "흑", "백"];
const COLOR_ALIASES = [
  ["청", ["청", "파랑", "파란색", "파랑색", "푸른색", "青色", "青", "ブルー", "blue"]],
  ["적", ["적", "빨강", "빨간색", "빨강색", "赤色", "赤", "レッド", "red"]],
  ["황", ["황", "노랑", "노란색", "노랑색", "黄色", "黄", "イエロー", "yellow"]],
  ["녹", ["녹", "녹색", "초록", "초록색", "緑色", "緑", "グリーン", "green"]],
  ["흑", ["흑", "검정", "검정색", "검은색", "黒色", "黒", "黑", "ブラック", "black"]],
  ["백", ["백", "흰색", "하양", "하얀색", "白色", "白", "ホワイト", "white"]],
].flatMap(([tag, aliases]) => aliases.map((alias) => ({ tag, alias: alias.toLocaleLowerCase() })))
 .sort((a, b) => b.alias.length - a.alias.length);
function getCardColorKey(card) {
  const raw = card?.color ?? card?.sourceData?.color ?? card?.sourceData?.colour ?? card?.raw?.color ?? "";
  let remaining = String(raw).trim().toLocaleLowerCase()
    .replace(/[【】［］\[\]()（）]/gu, "")
    .replace(/[\s,，、/&＋+・·|｜]/gu, "");
  if (!remaining) return "";
  const tags = [];
  while (remaining) {
    const match = COLOR_ALIASES.find((entry) => remaining.startsWith(entry.alias));
    if (!match) return "";
    tags.push(match.tag);
    remaining = remaining.slice(match.alias.length);
  }
  const unique = new Set(tags);
  return COLOR_ORDER.filter((tag) => unique.has(tag)).join("");
}

export default function RoomLobby({ deck = {}, partnerId = "", eventId = "", cards = [], onGameFieldChange }) {
  const [inviteCodeInput, setInviteCodeInput] = useState("");
  const [room, setRoom] = useState(null);
  const [isAIBattle, setIsAIBattle] = useState(false);
  const [players, setPlayers] = useState([]);
  const [showTermsModal, setShowTermsModal] = useState(false);
  const [greetingFinished, setGreetingFinished] = useState(false);
  const [userId, setUserId] = useState("");
  const [readyDeckSignature, setReadyDeckSignature] = useState("");
  const [matchPhase, setMatchPhase] = useState("waiting");
  const [canLeaveBeforeMulligan, setCanLeaveBeforeMulligan] = useState(true);
  const [showFieldOnly, setShowFieldOnly] = useState(true);
  const [nicknameDraft, setNicknameDraft] = useState("");
  const [nicknameDirty, setNicknameDirty] = useState(false);
  const [savingNickname, setSavingNickname] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let active = true;
    let savedRoom = null;
    try {
      savedRoom = JSON.parse(localStorage.getItem(ACTIVE_ROOM_STORAGE_KEY) || "null");
    } catch {
      localStorage.removeItem(ACTIVE_ROOM_STORAGE_KEY);
    }
    if (!savedRoom?.id || !savedRoom?.inviteCode) return undefined;

    async function restoreRoom() {
      try {
        const restoredAiBattle = localStorage.getItem(AI_ROOM_STORAGE_KEY) === savedRoom.id;
        const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
        if (sessionError) throw sessionError;
        let session = sessionData?.session;
        if (!session) {
          const { data, error: signInError } = await supabase.auth.signInAnonymously();
          if (signInError) throw signInError;
          session = data?.session;
        }
        if (!session?.user?.id) throw new Error("로그인 세션을 복원하지 못했습니다.");
        const { data: member, error: memberError } = await supabase
          .from("room_players")
          .select("room_id")
          .eq("room_id", savedRoom.id)
          .eq("user_id", session.user.id)
          .maybeSingle();
        if (memberError) throw memberError;
        if (!member) {
          localStorage.removeItem(ACTIVE_ROOM_STORAGE_KEY);
          return;
        }
        const { data: state, error: stateError } = await supabase.rpc("get_private_match_state", {
          p_room_id: savedRoom.id,
        });
        if (stateError) throw stateError;
        const phase = state?.phase || "waiting";
        const phaseToken = String(phase).toLocaleLowerCase();
        let finishedMatch = Boolean(state?.game_over)
          || ["finished", "complete", "completed", "ended", "game_over"].includes(phaseToken);

        // Match state often keeps its phase as "playing" and records completion separately.
        if (!finishedMatch && phase === "playing") {
          const { data: turnState, error: turnStateError } = await supabase.rpc("get_private_turn_state_v2", {
            p_room_id: savedRoom.id,
          });
          if (turnStateError) throw turnStateError;
          finishedMatch = turnState?.game_over === true;
        }

        // Finished matches are not resumable rooms. Clear stale cache so refresh returns to create/join.
        if (finishedMatch) {
          localStorage.removeItem(ACTIVE_ROOM_STORAGE_KEY);
          localStorage.removeItem(COMPLETED_GREETING_ROOM_KEY);
      localStorage.removeItem(AI_ROOM_STORAGE_KEY);
          if (active) {
            setRoom(null);
            setPlayers([]);
            setMatchPhase("waiting");
            setGreetingFinished(false);
            setShowFieldOnly(true);
            setNotice("이전 게임이 종료되어 새 대전을 시작할 수 있습니다. 새 방을 만들거나 초대 코드로 입장해 주세요.");
          }
          return;
        }

        if (!active) return;
        setUserId(session.user.id);
        setIsAIBattle(restoredAiBattle);
        setInviteCodeInput(String(savedRoom.inviteCode).toUpperCase());
        setRoom(savedRoom);
        setMatchPhase(phase);
        setCanLeaveBeforeMulligan(phase === "waiting" || (String(phase).toLocaleLowerCase() === "mulligan" && state?.seat1_mulligan_done !== true && state?.seat2_mulligan_done !== true));
        setGreetingFinished(localStorage.getItem(COMPLETED_GREETING_ROOM_KEY) === savedRoom.id);
      } catch (err) {
        if (active) setNotice(err?.message || "이전 방 정보를 복원하지 못했습니다. 연결 상태를 확인해 주세요.");
      }
    }
    void restoreRoom();
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (room?.id && room?.inviteCode) {
      localStorage.setItem(ACTIVE_ROOM_STORAGE_KEY, JSON.stringify(room));
    }
  }, [room?.id, room?.inviteCode]);

  async function ensureSignedIn() {
    const {
      data: { session },
      error: sessionError,
    } = await supabase.auth.getSession();

    if (sessionError) throw sessionError;
    if (session) {
      setUserId(session.user.id);
      return session;
    }

    const { data, error: signInError } = await supabase.auth.signInAnonymously();
    if (signInError) throw signInError;
    if (!data.session) throw new Error("로그인 세션을 만들지 못했습니다.");

    setUserId(data.session.user.id);
    return data.session;
  }

  async function loadPlayers(roomId) {
    const { data, error: queryError } = await supabase
      .from("room_players")
      .select("user_id, seat, joined_at, is_ready, temporary_nickname")
      .eq("room_id", roomId)
      .order("seat");

    if (queryError) throw queryError;
    setPlayers(data ?? []);
  }

  async function createRoom() {
    setLoading(true);
    setError("");
    setNotice("");

    try {
      await ensureSignedIn();
      const { data, error: rpcError } = await supabase.rpc("create_private_room");
      if (rpcError) throw rpcError;

      const result = Array.isArray(data) ? data[0] : data;
      if (!result?.out_room_id || !result?.out_invite_code) {
        throw new Error("방 생성 결과를 확인할 수 없습니다.");
      }

      localStorage.removeItem(COMPLETED_GREETING_ROOM_KEY);
      localStorage.removeItem(AI_ROOM_STORAGE_KEY);
      setIsAIBattle(false);
      setRoom({ id: result.out_room_id, inviteCode: result.out_invite_code });
      setGreetingFinished(false);
      setNotice("방이 생성되었습니다. 친구에게 초대 코드를 전달해 주세요.");
    } catch (err) {
      setError(err?.message || "방을 만들지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  async function joinRoom() {
    const code = inviteCodeInput.trim().toUpperCase();
    if (!code) {
      setError("친구에게 받은 초대 코드를 입력해 주세요.");
      return;
    }

    setLoading(true);
    setError("");
    setNotice("");

    try {
      await ensureSignedIn();
      const { data, error: rpcError } = await supabase.rpc("join_private_room", {
        p_invite_code: code,
      });
      if (rpcError) throw rpcError;

      const result = Array.isArray(data) ? data[0] : data;
      if (!result?.out_room_id) throw new Error("입장 결과를 확인할 수 없습니다.");

      localStorage.removeItem(COMPLETED_GREETING_ROOM_KEY);
      localStorage.removeItem(AI_ROOM_STORAGE_KEY);
      setIsAIBattle(false);
      setRoom({ id: result.out_room_id, inviteCode: code });
      setGreetingFinished(false);
      setNotice("방에 입장했습니다.");
    } catch (err) {
      setError(err?.message || "방에 입장하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!room?.id) return undefined;

    let active = true;
    const load = async () => {
      try {
        const { data, error: queryError } = await supabase
          .from("room_players")
          .select("user_id, seat, joined_at, is_ready, temporary_nickname")
          .eq("room_id", room.id)
          .order("seat");
        if (queryError) throw queryError;
        if (active) setPlayers(data ?? []);
      } catch (err) {
        if (active) setError(err?.message || "플레이어 목록을 불러오지 못했습니다.");
      }
    };

    void load();
    const channel = supabase
      .channel(`room-players-${room.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "room_players",
          filter: `room_id=eq.${room.id}`,
        },
        () => void load()
      )
      .subscribe((status) => {
        if (active && (status === "CHANNEL_ERROR" || status === "TIMED_OUT")) {
          setError("실시간 연결에 문제가 발생했습니다. 새로고침 후 다시 확인해 주세요.");
        }
      });

    return () => {
      active = false;
      void supabase.removeChannel(channel);
    };
  }, [room?.id]);

  async function copyInviteCode() {
    try {
      await navigator.clipboard.writeText(room.inviteCode);
      setNotice("초대 코드를 복사했습니다.");
    } catch {
      setNotice("초대 코드를 직접 선택한 뒤 복사해 주세요.");
    }
  }

  const deckTotal = Object.values(deck || {}).reduce(
    (sum, value) => sum + Math.max(0, Math.floor(Number(value) || 0)),
    0
  );
  const cardsByKey = new Map(cards.map((card) => [String(card.key), card]));
  const partnerCard = cardsByKey.get(String(partnerId));
  const eventCard = cardsByKey.get(String(eventId));
  const partnerType = `${partnerCard?.type || ""} ${partnerCard?.originalType || ""} ${partnerCard?.roleText || ""}`;
  const eventType = `${eventCard?.type || ""} ${eventCard?.originalType || ""} ${eventCard?.roleText || ""}`;
  const partnerLooksValid = Boolean(partnerCard) && (/パートナー|파트너/i.test(partnerType) || /^P\d+/i.test(partnerCard?.cardId || ""));
  const eventLooksValid = Boolean(eventCard) && /事件|사건|event/i.test(eventType);
  const allDeckKeysExist = Object.keys(deck || {}).every((key) => cardsByKey.has(String(key)));
  const canReady = deckTotal === 40 && partnerLooksValid && eventLooksValid && allDeckKeysExist;
  const myPlayer = players.find((player) => player.user_id === userId);
  const bothReady = players.length === 2 && players.every((player) => player.is_ready === true);
  const handleMatchPhaseChange = useCallback((phase, canLeave = phase === "waiting") => {
    setMatchPhase(phase);
    setCanLeaveBeforeMulligan(Boolean(canLeave));
  }, []);
  const completeGreeting = useCallback(() => {
    setGreetingFinished(true);
    if (room?.id) localStorage.setItem(COMPLETED_GREETING_ROOM_KEY, room.id);
  }, [room?.id]);
  const returnToRoomLobby = useCallback(() => {
    localStorage.removeItem(ACTIVE_ROOM_STORAGE_KEY);
    localStorage.removeItem(COMPLETED_GREETING_ROOM_KEY);
      localStorage.removeItem(AI_ROOM_STORAGE_KEY);
    setRoom(null);
    setIsAIBattle(false);
    setPlayers([]);
    setReadyDeckSignature("");
    setMatchPhase("waiting");
    setCanLeaveBeforeMulligan(true);
    setGreetingFinished(false);
    setShowFieldOnly(true);
    setShowTermsModal(false);
    setError("");
    setNotice("이전 게임을 닫았습니다. 새 방을 만들거나 초대 코드로 입장해 주세요.");
  }, []);

  async function handleAIBattleStarted({ roomId, inviteCode, userId: aiHumanUserId, aiDeckName, aiDeckComposer, initialAiMessage }) {
    localStorage.setItem(AI_ROOM_STORAGE_KEY, roomId);
    localStorage.removeItem(COMPLETED_GREETING_ROOM_KEY);
    setIsAIBattle(true);
    setUserId(aiHumanUserId || userId);
    setReadyDeckSignature(deckSignature);
    setInviteCodeInput(String(inviteCode || "").toUpperCase());
    setRoom({ id: roomId, inviteCode });
    setPlayers([]);
    setMatchPhase("mulligan");
    setCanLeaveBeforeMulligan(true);
    setGreetingFinished(false);
    setShowFieldOnly(true);
    await loadPlayers(roomId);
    const deckInfo = aiDeckName
      ? `AI 탐정이 공개 덱 저장소에서 ‘${aiDeckName}’ 덱${aiDeckComposer ? `(편성자: ${aiDeckComposer})` : ""}을 선택했습니다.`
      : "AI 대전용 방을 만들었습니다.";
    setNotice([deckInfo, initialAiMessage].filter(Boolean).join(" "));
  }

  async function leaveRoom() {
    if (!room?.id || loading || !canLeaveBeforeMulligan) return;
    if (!window.confirm("현재 입장한 대전 대기실에서 나가 로비로 돌아가시겠습니까?")) return;
    setLoading(true);
    setError("");
    setNotice("");
    try {
      await ensureSignedIn();
      const { error: rpcError } = await supabase.rpc("leave_private_room_before_mulligan_v1", {
        p_room_id: room.id,
      });
      if (rpcError) throw rpcError;

      localStorage.removeItem(ACTIVE_ROOM_STORAGE_KEY);
      localStorage.removeItem(COMPLETED_GREETING_ROOM_KEY);
      localStorage.removeItem(AI_ROOM_STORAGE_KEY);
      setIsAIBattle(false);
      setRoom(null);
      setPlayers([]);
      setReadyDeckSignature("");
      setMatchPhase("waiting");
      setGreetingFinished(false);
      setShowFieldOnly(true);
      setShowTermsModal(false);
      setNotice("대기실에서 나왔습니다. 새 방을 만들거나 초대 코드로 다시 입장할 수 있습니다.");
    } catch (err) {
      setError(err?.message || "대기실에서 나가지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!nicknameDirty && myPlayer) setNicknameDraft(myPlayer.temporary_nickname || "");
  }, [myPlayer?.temporary_nickname, nicknameDirty, userId]);

  useEffect(() => {
    onGameFieldChange?.(Boolean(room?.id && matchPhase === "playing" && showFieldOnly));
  }, [room?.id, matchPhase, showFieldOnly, onGameFieldChange]);

  async function saveTemporaryNickname() {
    if (!room?.id || savingNickname) return;
    setSavingNickname(true); setError(""); setNotice("");
    try {
      await ensureSignedIn();
      const { error: rpcError } = await supabase.rpc("set_private_room_nickname", {
        p_room_id: room.id,
        p_nickname: nicknameDraft.trim(),
      });
      if (rpcError) throw rpcError;
      setNicknameDirty(false);
      await loadPlayers(room.id);
      setNotice(nicknameDraft.trim() ? "이번 방에서 사용할 임시 닉네임을 저장했습니다." : "임시 닉네임을 삭제했습니다. 기본 플레이어 이름을 사용합니다.");
    } catch (err) {
      setError(err?.message || "임시 닉네임을 저장하지 못했습니다.");
    } finally { setSavingNickname(false); }
  }
  const deckSignature = JSON.stringify({
    deck: Object.entries(deck || {}).sort(([a], [b]) => a.localeCompare(b)),
    partnerId,
    eventId,
  });

  // 모의전 탭을 벗어나 덱을 편집해도 방은 유지됩니다. 준비 완료 후 구성이 바뀌면
  // 서버의 준비 상태도 자동으로 취소해 이전 덱으로 준비 완료가 남지 않게 합니다.
  useEffect(() => {
    if (!room?.id || myPlayer?.is_ready !== true || readyDeckSignature === deckSignature) return undefined;

    let active = true;
    async function cancelOutdatedReady() {
      try {
        const { error: rpcError } = await supabase.rpc("unready_private_room", {
          p_room_id: room.id,
        });
        if (rpcError) throw rpcError;

        const { data, error: queryError } = await supabase
          .from("room_players")
          .select("user_id, seat, joined_at, is_ready, temporary_nickname")
          .eq("room_id", room.id)
          .order("seat");
        if (queryError) throw queryError;
        if (active) {
          setPlayers(data ?? []);
          setNotice("덱 구성이 변경되어 준비가 취소되었습니다. 수정한 덱으로 다시 준비해 주세요.");
        }
      } catch (err) {
        if (active) setError(err?.message || "덱 변경 후 준비 상태를 갱신하지 못했습니다.");
      }
    }

    void cancelOutdatedReady();
    return () => { active = false; };
  }, [room?.id, myPlayer?.is_ready, readyDeckSignature, deckSignature]);

  function makePrivateDeckPayload() {
    const eventCard = cardsByKey.get(String(eventId));
    const eventColorKey = getCardColorKey(eventCard);
    return Object.entries(deck || {})
      .map(([key, rawCount]) => {
        const count = Math.floor(Number(rawCount) || 0);
        if (count <= 0) return null;
        const card = cardsByKey.get(String(key));
        const identity = String(
          card?.cardId ?? card?.sourceData?.card_id ?? card?.databaseId ?? card?.key ?? key
        ).trim().toLocaleUpperCase();
        const typeText = `${card?.type || ""} ${card?.originalType || ""} ${card?.roleText || ""}`;
        let cardType = "other";
        if (/イベント|이벤트|(?:^|\s)event(?:\s|$)/iu.test(typeText)) cardType = "event";
        else if (/キャラ|character|캐릭터/iu.test(typeText)) cardType = "character";
        const cutInText = String(card?.cutInEffect || "").trim();
        const cutInMatch = cutInText.normalize("NFKC").match(/AP\s*\+\s*(\d{1,5})/iu);
        const cutInBonus = cutInMatch ? Math.max(0, Number(cutInMatch[1]) || 0) : 0;
        const misleadSource = [...(card?.keywordTags || []), card?.ability || "", card?.originalAbility || ""].join(" ");
        const misleadMatch = misleadSource.match(/[【〚［\[]\s*(?:미스리드|ミスリード)\s*([0-9０-９]+)\s*[】〛］\]]/iu)
          || misleadSource.match(/[【〚［\[]\s*(?:미스리드|ミスリード)\s*[】〛］\]]\s*([0-9０-９]+)/iu)
          || misleadSource.match(/(?:미스리드|ミスリード)\s*([0-9０-９]+)/iu);
        const misleadValue = misleadMatch
          ? Math.max(0, Number(String(misleadMatch[1]).replace(/[０-９]/gu, (digit) => String.fromCharCode(digit.charCodeAt(0) - 0xFEE0))) || 0)
          : 0;
        return {
          key: String(key), count, limit_key: identity, card_type: cardType,
          name: String(card?.name || card?.originalName || card?.cardId || key),
          color: String(card?.color ?? card?.sourceData?.color ?? card?.raw?.color ?? ""),
          color_key: getCardColorKey(card),
          event_color_key: eventColorKey,
          copy_limit_exemption_id: getCopyLimitExemptionId(card, key),
          card_id: String(card?.cardId || card?.sourceData?.card_id || ""),
          card_num: String(card?.cardNum || card?.sourceData?.card_num || ""),
          database_id: String(card?.databaseId || card?.sourceData?.database_id || key),
          traits: getCardTraits(card),
          category1: String(card?.category1 || ""),
          category2: String(card?.category2 || ""),
          category3: String(card?.category3 || ""),
          rarity: String(card?.rarity || card?.sourceData?.rarity || ""),
          cost: Math.max(0, Number(card?.cost) || 0),
          ap: Math.max(0, Number(card?.ap ?? card?.sourceData?.ap ?? card?.sourceData?.AP) || 0),
          lp: Math.max(0, Number(card?.lp ?? card?.sourceData?.lp ?? card?.sourceData?.LP) || 0),
          cut_in_bonus: cutInBonus,
          cut_in_effect: cutInText,
          mislead_value: misleadValue,
        };
      })
      .filter(Boolean);
  }

  async function markReady() {
    if (!room?.id || !canReady || loading) return;
    setLoading(true);
    setError("");
    setNotice("");

    try {
      await ensureSignedIn();
      const { error: rpcError } = await supabase.rpc("submit_private_room_deck", {
        p_room_id: room.id,
        p_main_deck: makePrivateDeckPayload(),
        p_partner_key: partnerId,
        p_event_key: eventId,
        p_event_rule_code: getEventRuleCode(cardsByKey.get(String(eventId)), eventId),
      });
      if (rpcError) throw rpcError;
      setReadyDeckSignature(deckSignature);
      await loadPlayers(room.id);
      setNotice("덱은 비공개로 저장되었으며, 준비 완료 상태로 표시되었습니다.");
    } catch (err) {
      setError(err?.message || "덱을 제출하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  async function cancelReady() {
    if (!room?.id || loading) return;
    setLoading(true);
    setError("");
    setNotice("");

    try {
      const { error: rpcError } = await supabase.rpc("unready_private_room", {
        p_room_id: room.id,
      });
      if (rpcError) throw rpcError;
      await loadPlayers(room.id);
      setNotice("준비가 취소되었습니다. 덱을 변경한 뒤 다시 준비할 수 있습니다.");
    } catch (err) {
      setError(err?.message || "준비를 취소하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  if (room?.id && matchPhase === "playing" && showFieldOnly) {
    return greetingFinished
      ? <MatchTurnBoard roomId={room.id} userId={userId} cards={cards} inviteCode={room.inviteCode} isAIBattle={isAIBattle} onLeaveField={() => setShowFieldOnly(false)} onReturnToLobby={returnToRoomLobby} />
      : <MatchGreetingStep roomId={room.id} userId={userId} players={players} isAIBattle={isAIBattle} onComplete={completeGreeting} />;
  }

  const panelStyle = {
    boxSizing: "border-box",
    width: "100%",
    maxWidth: 820,
    margin: "8px auto 24px",
    padding: 22,
    border: "1px solid rgba(255,255,255,.10)",
    borderRadius: 16,
    background: "#101827",
    color: "#e8edf7",
    boxShadow: "0 12px 36px rgba(0,0,0,.16)",
  };
  const buttonStyle = {
    border: "1px solid rgba(255,255,255,.12)",
    borderRadius: 9,
    padding: "10px 14px",
    background: "#263d63",
    color: "#fff",
    cursor: loading ? "wait" : "pointer",
    fontSize: 13,
    fontWeight: 700,
    opacity: loading ? 0.65 : 1,
  };
  const inputStyle = {
    boxSizing: "border-box",
    width: "100%",
    padding: 12,
    border: "1px solid rgba(255,255,255,.14)",
    borderRadius: 8,
    fontSize: 15,
    color: "#e8edf7",
    background: "#090f1b",
  };

  return (
    <>
    <section style={panelStyle}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
        <div>
          <p style={{ margin: "0 0 5px", color: "#fb7185", fontSize: 10, fontWeight: 800, letterSpacing: ".18em" }}>PRIVATE MATCH</p>
          <h2 style={{ margin: 0, fontSize: 22, fontWeight: 850 }}>비공개 대전 방</h2>
          <p style={{ color: "#9aa8bd", marginTop: 7, fontSize: 13 }}>친구와 2인 비공개 방에서 각자 준비한 덱을 사용하여 모의전을 진행합니다.</p>
        </div>
        {room && <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <span style={{ padding: "5px 9px", border: "1px solid rgba(134,239,172,.22)", borderRadius: 7, color: "#86efac", background: "rgba(34,197,94,.08)", fontSize: 11, fontWeight: 750 }}>대기실 입장 중</span>
          {canLeaveBeforeMulligan && <button type="button" style={{ ...buttonStyle, padding: "5px 9px", borderRadius: 7, background: "#7f1d1d", borderColor: "rgba(251,113,133,.7)", fontSize: 11, fontWeight: 750, boxShadow: "0 0 0 1px rgba(251,113,133,.10)" }} disabled={loading} onClick={() => void leaveRoom()}>{loading ? "나가는 중…" : "대기실 나가기"}</button>}
        </div>}
      </div>

      {room && matchPhase === "playing" && !showFieldOnly && <div style={{ marginTop: 14, padding: 12, borderRadius: 10, border: "1px solid rgba(147,197,253,.24)", background: "rgba(30,58,95,.2)", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap" }}><div><strong style={{ display: "block", fontSize: 13, color: "#dbeafe" }}>대전 진행 중</strong><span style={{ display: "block", marginTop: 3, color: "#9aa8bd", fontSize: 11 }}>필드 화면이 접혀 있습니다. 버튼을 눌러 게임 필드 전체 화면으로 돌아갈 수 있습니다.</span></div><button type="button" style={buttonStyle} onClick={() => setShowFieldOnly(true)}>게임 필드 전체 화면으로 돌아가기</button></div>}

      {!room ? (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(230px, 1fr))", gap: 16, marginTop: 20 }}>
          <div style={{ border: "1px solid rgba(255,255,255,.08)", borderRadius: 12, padding: 16, background: "#0b1220" }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 14 }}>새 방 만들기</h3>
            <p style={{ margin: "0 0 14px", color: "#8998ae", fontSize: 12 }}>방을 만든 뒤 초대 코드를 친구에게 전달해 주세요.</p>
            <button type="button" style={buttonStyle} disabled={loading} onClick={createRoom}>{loading ? "처리 중..." : "새 방 만들기"}</button>
          </div>
          <div style={{ border: "1px solid rgba(255,255,255,.08)", borderRadius: 12, padding: 16, background: "#0b1220" }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 14 }}>초대 코드로 입장</h3>
            <label htmlFor="room-invite-code" style={{ display: "block", marginBottom: 7, color: "#aab5c8", fontSize: 12 }}>친구의 초대 코드</label>
            <input id="room-invite-code" style={inputStyle} value={inviteCodeInput} onChange={(event) => setInviteCodeInput(event.target.value.toUpperCase())} placeholder="초대 코드 입력" maxLength={10} autoComplete="off" />
            <button type="button" style={{ ...buttonStyle, marginTop: 10 }} disabled={loading} onClick={joinRoom}>{loading ? "입장 중..." : "코드로 입장"}</button>
          </div>
        </div>
      ) : (
        <>
          <div style={{ marginTop: 20, padding: 16, border: "1px solid rgba(255,255,255,.08)", borderRadius: 12, background: "#0b1220" }}>
            <div style={{ color: "#8998ae", fontSize: 12 }}>친구에게 전달할 초대 코드</div>
            <div style={{ fontSize: 28, fontWeight: 850, letterSpacing: 3, margin: "5px 0 12px", overflowWrap: "anywhere" }}>{room.inviteCode}</div>
            <button type="button" style={buttonStyle} onClick={copyInviteCode}>초대 코드 복사</button>
          </div>

          <div style={{ marginTop: 16, padding: 14, border: "1px solid rgba(255,255,255,.08)", borderRadius: 10, background: "#0b1220" }}>
            <h3 style={{ margin: "0 0 6px", fontSize: 13 }}>이번 방에서 표시할 이름</h3>
            <p style={{ margin: "0 0 9px", color: "#8998ae", fontSize: 11, lineHeight: 1.6 }}>선택 사항입니다. 비워 둘 시 플레이어 1/2로 표시됩니다. 이 이름은 이 방에만 저장되며 게임이 끝나면 자동으로 삭제됩니다.</p>
            <div style={{ display: "flex", gap: 7, flexWrap: "wrap" }}>
              <input value={nicknameDraft} onChange={(event) => { setNicknameDraft(event.target.value); setNicknameDirty(true); }} maxLength={16} placeholder={`기본 이름: 플레이어 ${myPlayer?.seat || "?"}`} aria-label="이번 방 임시 닉네임" style={{ ...inputStyle, flex: "1 1 220px", minWidth: 0 }} />
              <button type="button" style={{ ...buttonStyle, background: "#374151" }} disabled={savingNickname || loading} onClick={() => void saveTemporaryNickname()}>{savingNickname ? "저장 중…" : "닉네임 저장"}</button>
            </div>
          </div>

          <div style={{ marginTop: 22 }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 15 }}>대기실</h3>
            {[1, 2].map((seat) => {
              const player = players.find((item) => item.seat === seat);
              return (
                <div key={seat} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, padding: "13px 2px", borderBottom: "1px solid rgba(255,255,255,.08)" }}>
                  <span style={{ color: "#dbe4f1", fontSize: 13 }}>{player?.temporary_nickname || `플레이어 ${seat}`}{player?.user_id === userId ? " · 나" : ""}</span>
                  <strong style={{ color: !player ? "#7d8ba0" : player.is_ready ? "#86efac" : "#fcd34d", fontSize: 12 }}>{!player ? "입장 대기 중" : player.is_ready ? "준비 완료" : "덱 선택 중"}</strong>
                </div>
              );
            })}
          </div>

          <div style={{ marginTop: 18, padding: 16, border: "1px solid rgba(255,255,255,.08)", borderRadius: 12, background: "#0b1220" }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 14 }}>내 덱 준비</h3>
            <p style={{ margin: "0 0 10px", color: "#aab5c8", fontSize: 12 }}>메인 덱 {deckTotal}/40장 · 파트너 {partnerLooksValid ? "선택됨" : "미선택"} · 사건 {eventLooksValid ? "선택됨" : "미선택"}</p>
            {!canReady && <p style={{ margin: "0 0 12px", color: "#fda4af", fontSize: 12, lineHeight: 1.6 }}>준비하려면 메인 덱을 정확히 40장으로 맞추고, 파트너 카드와 사건 카드를 각각 1장씩 선택해 주세요. 덱 편집은 위의 ‘내 덱 구성’ 탭에서 할 수 있습니다.</p>}
            {myPlayer?.is_ready ? (
              <button type="button" style={{ ...buttonStyle, background: "#4b2637" }} disabled={loading} onClick={cancelReady}>{loading ? "처리 중..." : "준비 취소 · 덱 수정하기"}</button>
            ) : (
              <button type="button" style={{ ...buttonStyle, background: canReady ? "#166534" : "#263040", opacity: !canReady || loading ? 0.55 : 1 }} disabled={!canReady || loading} onClick={() => setShowTermsModal(true)}>{loading ? "저장 중..." : "덱을 비공개로 제출하고 준비 완료"}</button>
            )}
            <p style={{ margin: "10px 0 0", color: "#74839a", fontSize: 11, lineHeight: 1.6 }}>상대에게는 준비 여부만 표시됩니다. 카드별 덱 목록은 별도의 비공개 테이블에 저장됩니다.</p>
          </div>

          {bothReady && <MatchStartFlow roomId={room.id} userId={userId} players={players} cards={cards} inviteCode={room.inviteCode} isAIBattle={isAIBattle} onPhaseChange={handleMatchPhaseChange} onReturnToLobby={returnToRoomLobby} />}
        </>
      )}

      {showTermsModal && room && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowTermsModal(false); }} style={{ position: "fixed", inset: 0, zIndex: 100500, display: "flex", alignItems: "center", justifyContent: "center", padding: 16, background: "rgba(0,0,0,.88)", backdropFilter: "blur(5px)" }}>
        <section role="dialog" aria-modal="true" aria-label="사이트 이용 안내" style={{ width: "min(100%, 620px)", maxHeight: "90dvh", overflowY: "auto", padding: 22, border: "1px solid rgba(147,197,253,.35)", borderRadius: 14, background: "#101827", color: "#e8edf7", boxShadow: "0 24px 70px rgba(0,0,0,.7)" }}>
          <h2 style={{ margin: 0, fontSize: 18, fontWeight: 900 }}>시작 전 안내</h2>
          <div style={{ marginTop: 12, color: "#cbd5e1", fontSize: 12, lineHeight: 1.9, whiteSpace: "pre-line" }}>{[
            "본 사이트는 개인 사용 목적의 비영리 웹사이트로, AI 바이브코딩을 이용해 만들어졌습니다.",
            "카드 데이터 및 이미지를 영리적으로 사용하거나 구현해 둔 모의전 페이지의 기능으로 수익을 낼 생각은 전혀 없으며, 만일 개인적 사용이라는 취지에 부합하지 않는 사용 사례가 발견될 경우 사이트를 즉시 폐쇄하거나 지인제로 전환할 예정입니다.",
            "부디 물의를 일으키지 않을 범위 내에서만 사용해 주세요.",
            "",
            "이상의 안내를 모두 확인하셨다면 확인 버튼을 눌러 다음으로 진행해 주세요."
          ].join("\n")}</div>
          <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 18 }}>
            <button type="button" style={{ ...buttonStyle, background: "#374151" }} disabled={loading} onClick={() => setShowTermsModal(false)}>취소</button>
            <button type="button" style={{ ...buttonStyle, background: "#166534" }} disabled={loading} onClick={() => { setShowTermsModal(false); void markReady(); }}>확인 · 제출하고 준비 완료</button>
          </div>
        </section>
      </div>}
      {notice && <p role="status" style={{ color: "#86efac", marginTop: 16, fontSize: 13 }}>{notice}</p>}
      {error && <p role="alert" style={{ color: "#fda4af", marginTop: 16, fontSize: 13, overflowWrap: "anywhere" }}>오류: {error}</p>}
    </section>
    {!room && <AIBattlePanel deck={deck} partnerId={partnerId} eventId={eventId} cards={cards} ensureSignedIn={ensureSignedIn} onStarted={handleAIBattleStarted} />}
    </>
  );
}
