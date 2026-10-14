
import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

export default function RoomLobby() {
  const [inviteCodeInput, setInviteCodeInput] = useState("");
  const [room, setRoom] = useState(null);
  const [players, setPlayers] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  // 기존 익명 세션이 있으면 재사용하고, 없으면 새로 만든다.
  async function ensureSignedIn() {
    const {
      data: { session },
      error: sessionError,
    } = await supabase.auth.getSession();

    if (sessionError) throw sessionError;
    if (session) return session;

    const { data, error: signInError } =
      await supabase.auth.signInAnonymously();

    if (signInError) throw signInError;
    if (!data.session) {
      throw new Error("로그인 세션을 만들지 못했습니다.");
    }

    return data.session;
  }

  // 내 방에서 현재 입장한 플레이어 목록을 조회한다.
  const refreshPlayers = useCallback(async (roomId) => {
    const { data, error: queryError } = await supabase
      .from("room_players")
      .select("user_id, seat, joined_at")
      .eq("room_id", roomId)
      .order("seat");

    if (queryError) throw queryError;

    setPlayers(data ?? []);
  }, []);

  // 방을 만들 때 실행한다.
  async function createRoom() {
    setLoading(true);
    setError("");
    setNotice("");

    try {
      await ensureSignedIn();

      const { data, error: rpcError } =
        await supabase.rpc("create_private_room");

      if (rpcError) throw rpcError;

      const result = Array.isArray(data) ? data[0] : data;

      if (!result?.out_room_id || !result?.out_invite_code) {
        throw new Error("방 생성 결과를 확인할 수 없습니다.");
      }

      setRoom({
        id: result.out_room_id,
        inviteCode: result.out_invite_code,
      });

      setNotice("방을 만들었어! 친구에게 초대 코드를 보내 줘.");
    } catch (err) {
      setError(err.message || "방을 만들지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  // 초대 코드로 입장할 때 실행한다.
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

      const { data, error: rpcError } = await supabase.rpc(
        "join_private_room",
        { p_invite_code: code }
      );

      if (rpcError) throw rpcError;

      const result = Array.isArray(data) ? data[0] : data;

      if (!result?.out_room_id) {
        throw new Error("입장 결과를 확인할 수 없습니다.");
      }

      setRoom({
        id: result.out_room_id,
        inviteCode: code,
      });

      setNotice("방에 입장했어!");
    } catch (err) {
      setError(err.message || "방에 입장하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  // 방에 들어간 뒤 플레이어 목록을 읽고 실시간 변경을 구독한다.
  useEffect(() => {
    if (!room?.id) return;

    let active = true;

    async function loadPlayers() {
      try {
        const { data, error: queryError } = await supabase
          .from("room_players")
          .select("user_id, seat, joined_at")
          .eq("room_id", room.id)
          .order("seat");

        if (queryError) throw queryError;

        if (active) setPlayers(data ?? []);
      } catch (err) {
        if (active) {
          setError(err.message || "플레이어 목록을 불러오지 못했습니다.");
        }
      }
    }

    void loadPlayers();

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
        () => {
          void loadPlayers();
        }
      )
      .subscribe((status) => {
        if (
          active &&
          (status === "CHANNEL_ERROR" || status === "TIMED_OUT")
        ) {
          setError(
            "실시간 연결에 문제가 있어. 새로고침 후 다시 확인해 줘."
          );
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

  const cardStyle = {
    border: "1px solid #d7dce2",
    borderRadius: 12,
    padding: 20,
    maxWidth: 520,
    margin: "24px auto",
    background: "#ffffff",
    color: "#20242a",
  };

  const buttonStyle = {
    border: 0,
    borderRadius: 8,
    padding: "11px 16px",
    background: "#263d63",
    color: "#ffffff",
    cursor: loading ? "wait" : "pointer",
    fontSize: 15,
  };

  const inputStyle = {
    boxSizing: "border-box",
    width: "100%",
    padding: 12,
    border: "1px solid #c8ced8",
    borderRadius: 8,
    fontSize: 16,
  };

  return (
    <section style={cardStyle}>
      <h2 style={{ marginTop: 0 }}>비공개 대전 방</h2>
      <p style={{ color: "#5d6572" }}>
        친구와 방을 만들고 초대 코드로 입장해 봐.
      </p>

      {!room ? (
        <>
          <button
            type="button"
            style={buttonStyle}
            disabled={loading}
            onClick={createRoom}
          >
            {loading ? "처리 중..." : "새 방 만들기"}
          </button>

          <hr
            style={{
              border: 0,
              borderTop: "1px solid #e1e5ea",
              margin: "24px 0",
            }}
          />

          <label
            htmlFor="room-invite-code"
            style={{ display: "block", marginBottom: 8 }}
          >
            친구의 초대 코드
          </label>

          <input
            id="room-invite-code"
            style={inputStyle}
            value={inviteCodeInput}
            onChange={(event) =>
              setInviteCodeInput(event.target.value.toUpperCase())
            }
            placeholder="초대 코드 입력"
            maxLength={10}
            autoComplete="off"
          />

          <button
            type="button"
            style={{ ...buttonStyle, marginTop: 10 }}
            disabled={loading}
            onClick={joinRoom}
          >
            {loading ? "입장 중..." : "코드로 입장"}
          </button>
        </>
      ) : (
        <>
          <div
            style={{
              background: "#f2f5fa",
              borderRadius: 10,
              padding: 16,
              margin: "20px 0",
            }}
          >
            <div style={{ color: "#5d6572", fontSize: 13 }}>
              친구에게 전달할 초대 코드
            </div>

            <div
              style={{
                fontSize: 28,
                fontWeight: 700,
                letterSpacing: 3,
                margin: "8px 0 12px",
                overflowWrap: "anywhere",
              }}
            >
              {room.inviteCode}
            </div>

            <button
              type="button"
              style={buttonStyle}
              onClick={copyInviteCode}
            >
              초대 코드 복사
            </button>
          </div>

          <h3>대기실</h3>

          {[1, 2].map((seat) => {
            const player = players.find((item) => item.seat === seat);

            return (
              <div
                key={seat}
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  padding: "12px 0",
                  borderBottom: "1px solid #e1e5ea",
                }}
              >
                <span>플레이어 {seat}</span>
                <strong>{player ? "입장 완료" : "대기 중"}</strong>
              </div>
            );
          })}

          <p style={{ color: "#5d6572", fontSize: 13 }}>
            현재는 방 입장 기능을 확인하는 단계야. 덱 선택과 게임 시작은
            다음 단계에서 연결할 예정이야.
          </p>
        </>
      )}

      {notice && (
        <p role="status" style={{ color: "#167445", marginTop: 16 }}>
          {notice}
        </p>
      )}

      {error && (
        <p role="alert" style={{ color: "#b42318", marginTop: 16 }}>
          오류: {error}
        </p>
      )}
    </section>
  );
}
