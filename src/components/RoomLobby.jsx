import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import MatchStartFlow from "./MatchStartFlow";
import MatchTurnBoard from "./MatchTurnBoard";

export default function RoomLobby({ deck = {}, partnerId = "", eventId = "", cards = [], onGameFieldChange }) {
  const [inviteCodeInput, setInviteCodeInput] = useState("");
  const [room, setRoom] = useState(null);
  const [players, setPlayers] = useState([]);
  const [userId, setUserId] = useState("");
  const [readyDeckSignature, setReadyDeckSignature] = useState("");
  const [matchPhase, setMatchPhase] = useState("waiting");
  const [showFieldOnly, setShowFieldOnly] = useState(true);
  const [nicknameDraft, setNicknameDraft] = useState("");
  const [nicknameDirty, setNicknameDirty] = useState(false);
  const [savingNickname, setSavingNickname] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

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

      setRoom({ id: result.out_room_id, inviteCode: result.out_invite_code });
      setNotice("방을 만들었어! 친구에게 초대 코드를 보내 줘.");
    } catch (err) {
      setError(err?.message || "방을 만들지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  async function joinRoom() {
    const code = inviteCodeInput.trim().toUpperCase();
    if (!code) {
      setError("친구에게 받은 초대 코드를 입력해 줘.");
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

      setRoom({ id: result.out_room_id, inviteCode: code });
      setNotice("방에 입장했어!");
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
          setError("실시간 연결에 문제가 있어. 새로고침 후 다시 확인해 줘.");
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
      setNotice("초대 코드를 복사했어!");
    } catch {
      setNotice("초대 코드를 직접 선택해서 복사해 줘.");
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
  const handleMatchPhaseChange = useCallback((phase) => setMatchPhase(phase), []);

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
      setNotice(nicknameDraft.trim() ? "이번 방에서 사용할 임시 닉네임을 저장했어." : "임시 닉네임을 지웠어. 기본 플레이어 이름을 사용해.");
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
          setNotice("덱 구성이 바뀌어서 준비를 취소했어. 수정한 덱으로 다시 준비해 줘.");
        }
      } catch (err) {
        if (active) setError(err?.message || "덱 변경 후 준비 상태를 갱신하지 못했습니다.");
      }
    }

    void cancelOutdatedReady();
    return () => { active = false; };
  }, [room?.id, myPlayer?.is_ready, readyDeckSignature, deckSignature]);

  function makePrivateDeckPayload() {
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
        const cutInText = String(card?.cutInEffect || "");
        const cutInBonus = /2000/u.test(cutInText) ? 2000 : /1000/u.test(cutInText) ? 1000 : 0;
        return {
          key: String(key), count, limit_key: identity, card_type: cardType,
          cost: Math.max(0, Number(card?.cost) || 0),
          ap: Math.max(0, Number(card?.ap ?? card?.sourceData?.ap ?? card?.sourceData?.AP) || 0),
          lp: Math.max(0, Number(card?.lp ?? card?.sourceData?.lp ?? card?.sourceData?.LP) || 0),
          cut_in_bonus: cutInBonus,
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
      });
      if (rpcError) throw rpcError;
      setReadyDeckSignature(deckSignature);
      await loadPlayers(room.id);
      setNotice("덱은 비공개로 저장됐고, 준비 완료로 표시했어.");
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
      setNotice("준비를 취소했어. 덱을 바꾼 뒤 다시 준비할 수 있어.");
    } catch (err) {
      setError(err?.message || "준비를 취소하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  if (room?.id && matchPhase === "playing" && showFieldOnly) {
    return <MatchTurnBoard roomId={room.id} userId={userId} cards={cards} onLeaveField={() => setShowFieldOnly(false)} />;
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
    <section style={panelStyle}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
        <div>
          <p style={{ margin: "0 0 5px", color: "#fb7185", fontSize: 10, fontWeight: 800, letterSpacing: ".18em" }}>PRIVATE MATCH</p>
          <h2 style={{ margin: 0, fontSize: 22, fontWeight: 850 }}>비공개 대전 방</h2>
          <p style={{ color: "#9aa8bd", marginTop: 7, fontSize: 13 }}>친구와 방을 만들고, 각자 덱을 준비해 봐. 덱 목록은 상대에게 공개되지 않아.</p>
        </div>
        {room && <span style={{ padding: "5px 9px", border: "1px solid rgba(134,239,172,.22)", borderRadius: 7, color: "#86efac", background: "rgba(34,197,94,.08)", fontSize: 11, fontWeight: 750 }}>대기실 입장 중</span>}
      </div>

      {!room ? (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(230px, 1fr))", gap: 16, marginTop: 20 }}>
          <div style={{ border: "1px solid rgba(255,255,255,.08)", borderRadius: 12, padding: 16, background: "#0b1220" }}>
            <h3 style={{ margin: "0 0 8px", fontSize: 14 }}>새 방 만들기</h3>
            <p style={{ margin: "0 0 14px", color: "#8998ae", fontSize: 12 }}>방을 만든 뒤 초대 코드를 친구에게 보내 줘.</p>
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
            <p style={{ margin: "0 0 9px", color: "#8998ae", fontSize: 11, lineHeight: 1.6 }}>선택 사항이야. 비워 두면 플레이어 1/2로 보여. 이 이름은 이 방에만 저장되고 게임이 끝나면 자동으로 지워져.</p>
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
            {!canReady && <p style={{ margin: "0 0 12px", color: "#fda4af", fontSize: 12, lineHeight: 1.6 }}>준비하려면 메인 덱을 정확히 40장으로 맞추고, 파트너 카드와 사건 카드를 각각 1장씩 선택해 줘. 덱 편집은 위의 ‘내 덱 구성’ 탭에서 할 수 있어.</p>}
            {myPlayer?.is_ready ? (
              <button type="button" style={{ ...buttonStyle, background: "#4b2637" }} disabled={loading} onClick={cancelReady}>{loading ? "처리 중..." : "준비 취소 · 덱 수정하기"}</button>
            ) : (
              <button type="button" style={{ ...buttonStyle, background: canReady ? "#166534" : "#263040", opacity: !canReady || loading ? 0.55 : 1 }} disabled={!canReady || loading} onClick={markReady}>{loading ? "저장 중..." : "덱을 비공개로 제출하고 준비 완료"}</button>
            )}
            <p style={{ margin: "10px 0 0", color: "#74839a", fontSize: 11, lineHeight: 1.6 }}>상대에게는 준비 여부만 표시돼. 카드별 덱 목록은 별도 비공개 테이블에 저장돼.</p>
          </div>

          {bothReady && <MatchStartFlow roomId={room.id} userId={userId} players={players} cards={cards} onPhaseChange={handleMatchPhaseChange} />}
        </>
      )}

      {notice && <p role="status" style={{ color: "#86efac", marginTop: 16, fontSize: 13 }}>{notice}</p>}
      {error && <p role="alert" style={{ color: "#fda4af", marginTop: 16, fontSize: 13, overflowWrap: "anywhere" }}>오류: {error}</p>}
    </section>
  );
}
