import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

const PAGE_SIZE = 10;
const PREVIEW_LENGTH = 220;
const MAX_POST_LENGTH = 3000;
const MAX_COMMENT_LENGTH = 1500;

function formatDate(value) {
  if (!value) return "일시 미상";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "일시 미상";
  return date.toLocaleString("ko-KR", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
}

function inlineButton(background = "#26384f") {
  return { border: "1px solid rgba(148,163,184,.32)", borderRadius: 7, background, color: "#e8edf7", padding: "8px 11px", fontSize: 12, fontWeight: 750, cursor: "pointer" };
}

const modalBackdrop = { position: "fixed", inset: 0, zIndex: 120000, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(2,6,14,.86)" };
const modalPanel = { width: "min(100%, 760px)", maxHeight: "92dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(148,163,184,.35)", borderRadius: 13, background: "#101827", color: "#e8edf7", boxShadow: "0 22px 65px rgba(0,0,0,.48)" };
const textAreaStyle = { width: "100%", boxSizing: "border-box", resize: "vertical", minHeight: 110, border: "1px solid rgba(148,163,184,.32)", borderRadius: 8, background: "#080d16", color: "#e8edf7", padding: 10, font: "inherit", fontSize: 12, lineHeight: 1.65 };

export default function FeedbackBoard() {
  const [open, setOpen] = useState(false);
  const [body, setBody] = useState("");
  const [posts, setPosts] = useState([]);
  const [commentsByPost, setCommentsByPost] = useState({});
  const [count, setCount] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [selectedPost, setSelectedPost] = useState(null);
  const [adminPassword, setAdminPassword] = useState("");
  const [adminComment, setAdminComment] = useState("");
  const [adminBusy, setAdminBusy] = useState(false);
  const pageCount = Math.max(1, Math.ceil(count / PAGE_SIZE));
  const pageNumbers = useMemo(() => {
    const numbers = new Set([1, pageCount]);
    for (let value = Math.max(1, page - 2); value <= Math.min(pageCount, page + 2); value += 1) numbers.add(value);
    return [...numbers].sort((a, b) => a - b);
  }, [page, pageCount]);

  const loadPosts = useCallback(async () => {
    setLoading(true);
    setError("");
    const from = (page - 1) * PAGE_SIZE;
    const to = from + PAGE_SIZE - 1;
    const { data, error: queryError, count: total } = await supabase
      .from("site_change_suggestions")
      .select("id, body, created_at", { count: "exact" })
      .order("created_at", { ascending: false })
      .range(from, to);
    if (queryError) {
      setError(`수정 제안 목록을 불러오지 못했습니다: ${queryError.message}`);
      setPosts([]);
      setCount(0);
      setCommentsByPost({});
      setLoading(false);
      return;
    }
    const nextPosts = data || [];
    setPosts(nextPosts);
    setCount(total || 0);
    if (nextPosts.length) {
      const { data: commentRows, error: commentError } = await supabase
        .from("site_change_suggestion_comments")
        .select("id, suggestion_id, body, created_at")
        .in("suggestion_id", nextPosts.map((post) => post.id))
        .order("created_at", { ascending: true });
      if (commentError) {
        setError(`관리자 답변을 불러오지 못했습니다: ${commentError.message}`);
      } else {
        const grouped = {};
        for (const comment of commentRows || []) {
          if (!grouped[comment.suggestion_id]) grouped[comment.suggestion_id] = [];
          grouped[comment.suggestion_id].push(comment);
        }
        setCommentsByPost(grouped);
      }
    } else {
      setCommentsByPost({});
    }
    setLoading(false);
  }, [page]);

  useEffect(() => {
    if (!open) return undefined;
    void loadPosts();
    const channel = supabase
      .channel("site-change-suggestions-v7")
      .on("postgres_changes", { event: "*", schema: "public", table: "site_change_suggestions" }, () => void loadPosts())
      .on("postgres_changes", { event: "*", schema: "public", table: "site_change_suggestion_comments" }, () => void loadPosts())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [open, loadPosts]);

  const selectedComments = useMemo(
    () => selectedPost ? commentsByPost[selectedPost.id] || [] : [],
    [selectedPost, commentsByPost],
  );

  const closeSelectedPost = () => {
    setSelectedPost(null);
    setAdminPassword("");
    setAdminComment("");
    setAdminBusy(false);
  };

  const submitPost = async (event) => {
    event.preventDefault();
    const value = body.trim();
    if (!value) { setError("제안 내용을 입력해 주세요."); return; }
    if (value.length > MAX_POST_LENGTH) { setError(`본문은 ${MAX_POST_LENGTH}자 이하로 작성해 주세요.`); return; }
    setSaving(true);
    setError("");
    const { error: insertError } = await supabase.from("site_change_suggestions").insert({ body: value });
    setSaving(false);
    if (insertError) { setError(`게시글을 등록하지 못했습니다: ${insertError.message}`); return; }
    setBody("");
    setPage(1);
    await loadPosts();
  };

  const postAdminComment = async (event) => {
    event.preventDefault();
    if (!selectedPost) return;
    const value = adminComment.trim();
    if (!value) { setError("관리자 댓글을 입력해 주세요."); return; }
    if (!adminPassword.trim()) { setError("관리자 비밀번호를 입력해 주세요."); return; }
    setAdminBusy(true);
    setError("");
    const { error: rpcError } = await supabase.rpc("add_site_change_suggestion_comment", {
      p_suggestion_id: selectedPost.id,
      p_body: value,
      p_admin_password: adminPassword,
    });
    setAdminBusy(false);
    if (rpcError) { setError(`댓글을 등록하지 못했습니다: ${rpcError.message}`); return; }
    setAdminComment("");
    await loadPosts();
  };

  const deletePost = async () => {
    if (!selectedPost) return;
    if (!adminPassword.trim()) { setError("관리자 비밀번호를 입력해 주세요."); return; }
    if (!window.confirm("이 수정 제안 게시글과 댓글을 삭제할까요? 이 작업은 되돌릴 수 없습니다.")) return;
    setAdminBusy(true);
    setError("");
    const { error: rpcError } = await supabase.rpc("delete_site_change_suggestion", {
      p_suggestion_id: selectedPost.id,
      p_admin_password: adminPassword,
    });
    setAdminBusy(false);
    if (rpcError) { setError(`게시글을 삭제하지 못했습니다: ${rpcError.message}`); return; }
    closeSelectedPost();
    if (posts.length === 1 && page > 1) setPage((current) => current - 1);
    await loadPosts();
  };

  return <>
    <button type="button" onClick={() => { setOpen(true); setError(""); }} className="rounded-lg border border-white/10 px-3 py-2 text-xs font-semibold text-slate-300 transition hover:border-rose-400/50 hover:text-white" style={{ border: "1px solid rgba(255,255,255,.1)", borderRadius: 8, background: "transparent", color: "#cbd5e1", padding: "8px 12px", fontSize: 12, fontWeight: 600, cursor: "pointer" }} aria-haspopup="dialog">수정 제안</button>
    {open && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) { setOpen(false); closeSelectedPost(); } }} style={modalBackdrop}>
      <section role="dialog" aria-modal="true" aria-label="수정 제안 게시판" style={modalPanel}>
        <header style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "center", padding: "13px 15px", borderBottom: "1px solid rgba(255,255,255,.1)" }}>
          <div><h2 style={{ margin: 0, fontSize: 17, fontWeight: 900 }}>수정 제안</h2><p style={{ margin: "4px 0 0", color: "#94a3b8", fontSize: 10 }}>익명 제안 게시판 · 새 글이 위에 표시됩니다.</p></div>
          <button type="button" style={inlineButton()} onClick={() => { setOpen(false); closeSelectedPost(); }}>닫기 ✕</button>
        </header>
        <div style={{ padding: 13, overflowY: "auto", display: "grid", gap: 14 }}>
          <form onSubmit={submitPost} style={{ padding: 10, border: "1px solid rgba(148,163,184,.18)", borderRadius: 9, background: "#0b1220" }}>
            <p style={{ margin: "0 0 8px", color: "#cbd5e1", fontSize: 11, lineHeight: 1.6 }}>수정 및 보완이 필요한 사항, 오역, 카드별로 흔히 쓰이는 애칭/별명 제보, 추가로 있었으면 하는 기능 등을 적어 주세요.</p>
            <textarea value={body} onChange={(event) => setBody(event.target.value)} maxLength={MAX_POST_LENGTH} placeholder="수정 제안 내용을 입력해 주세요." style={textAreaStyle} />
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap", marginTop: 7 }}><span style={{ color: "#94a3b8", fontSize: 10 }}>{body.length}/{MAX_POST_LENGTH}자 · 작성자 이름은 표시되지 않습니다.</span><button type="submit" style={inlineButton("#164e63")} disabled={saving}>{saving ? "등록 중…" : "제안 등록"}</button></div>
          </form>

          <section>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8, marginBottom: 7 }}><h3 style={{ margin: 0, fontSize: 13, fontWeight: 900 }}>등록된 제안</h3><span style={{ color: "#94a3b8", fontSize: 10 }}>{count}개</span></div>
            {error && <p role="alert" style={{ margin: "8px 0", padding: 8, borderRadius: 6, border: "1px solid rgba(251,113,133,.35)", color: "#fda4af", fontSize: 11, overflowWrap: "anywhere" }}>{error}</p>}
            {loading && <p style={{ color: "#94a3b8", fontSize: 11 }}>목록을 불러오는 중…</p>}
            {!loading && !posts.length && <p style={{ color: "#94a3b8", fontSize: 11 }}>아직 등록된 제안이 없습니다.</p>}
            <div style={{ display: "grid", gap: 7 }}>
              {posts.map((post) => {
                const preview = post.body.length > PREVIEW_LENGTH ? `${post.body.slice(0, PREVIEW_LENGTH)}…` : post.body;
                const comments = commentsByPost[post.id] || [];
                return <article key={post.id} style={{ padding: 10, border: "1px solid rgba(148,163,184,.17)", borderRadius: 8, background: "#080d16" }}>
                  <div style={{ marginBottom: 5, color: "#94a3b8", fontSize: 9 }}>{formatDate(post.created_at)} · 익명</div>
                  <button type="button" onClick={() => { setSelectedPost(post); setError(""); }} style={{ width: "100%", padding: 0, textAlign: "left", border: 0, background: "transparent", color: "#e8edf7", whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 12, lineHeight: 1.65, cursor: "pointer" }} aria-label="제안 원문 보기">{preview}{post.body.length > PREVIEW_LENGTH && <span style={{ color: "#93c5fd", marginLeft: 5 }}>원문 보기</span>}</button>
                  {comments.length > 0 && <div style={{ marginTop: 8, paddingTop: 7, borderTop: "1px solid rgba(255,255,255,.08)", display: "grid", gap: 6 }}>{comments.slice(-2).map((comment) => <div key={comment.id}><div style={{ color: "#94a3b8", fontSize: 9, marginBottom: 2 }}>관리자 답변 · {formatDate(comment.created_at)}</div><p style={{ margin: 0, color: "#cbd5e1", fontSize: 11, lineHeight: 1.55, whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{comment.body}</p></div>)}</div>}
                </article>;
              })}
            </div>
            {pageCount > 1 && <nav aria-label="수정 제안 페이지" style={{ display: "flex", justifyContent: "center", gap: 5, flexWrap: "wrap", marginTop: 12 }}>{pageNumbers.map((number, index) => <span key={number} style={{ display: "contents" }}>{index > 0 && number - pageNumbers[index - 1] > 1 && <span aria-hidden="true" style={{ alignSelf: "center", color: "#94a3b8", fontSize: 12, padding: "0 3px" }}>…</span>}<button type="button" onClick={() => setPage(number)} aria-current={number === page ? "page" : undefined} style={{ ...inlineButton(number === page ? "#164e63" : "#172033"), minWidth: 35, padding: "7px 9px", borderColor: number === page ? "#67e8f9" : "rgba(148,163,184,.25)" }}>{number}</button></span>)}</nav>}
          </section>
        </div>
      </section>
    </div>}

    {selectedPost && open && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) closeSelectedPost(); }} style={{ ...modalBackdrop, zIndex: 120010, background: "rgba(2,6,14,.78)" }}>
      <section role="dialog" aria-modal="true" aria-label="수정 제안 원문" style={{ ...modalPanel, width: "min(100%, 680px)" }}>
        <header style={{ display: "flex", justifyContent: "space-between", gap: 8, alignItems: "center", padding: "12px 14px", borderBottom: "1px solid rgba(255,255,255,.1)" }}><h2 style={{ margin: 0, fontSize: 15, fontWeight: 900 }}>수정 제안 원문</h2><button type="button" onClick={closeSelectedPost} style={inlineButton()}>닫기 ✕</button></header>
        <div style={{ padding: 13, overflowY: "auto", display: "grid", gap: 12 }}>
          <article style={{ padding: 10, borderRadius: 8, border: "1px solid rgba(148,163,184,.18)", background: "#080d16" }}><div style={{ color: "#94a3b8", fontSize: 9, marginBottom: 6 }}>{formatDate(selectedPost.created_at)} · 익명</div><p style={{ margin: 0, whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 12, lineHeight: 1.75 }}>{selectedPost.body}</p></article>
          <section><h3 style={{ margin: "0 0 8px", fontSize: 12, fontWeight: 900 }}>관리자 답변</h3>{selectedComments.length ? <div style={{ display: "grid", gap: 7 }}>{selectedComments.map((comment) => <article key={comment.id} style={{ padding: 9, borderRadius: 7, border: "1px solid rgba(148,163,184,.16)", background: "#0b1220" }}><div style={{ color: "#94a3b8", fontSize: 9, marginBottom: 4 }}>{formatDate(comment.created_at)}</div><p style={{ margin: 0, fontSize: 11, lineHeight: 1.65, whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{comment.body}</p></article>)}</div> : <p style={{ color: "#94a3b8", fontSize: 11 }}>아직 등록된 관리자 답변이 없습니다.</p>}</section>
          <section style={{ paddingTop: 10, borderTop: "1px solid rgba(255,255,255,.1)" }}><label style={{ display: "block", color: "#cbd5e1", fontSize: 10, marginBottom: 5 }} htmlFor="suggestion-admin-password">관리자 비밀번호</label><input id="suggestion-admin-password" type="password" autoComplete="current-password" value={adminPassword} onChange={(event) => setAdminPassword(event.target.value)} style={{ ...textAreaStyle, minHeight: 0, resize: "none" }} placeholder="관리자 작업 시에만 입력" /><p style={{ margin: "5px 0 9px", color: "#94a3b8", fontSize: 9 }}>댓글 작성과 삭제 권한은 서버에서 비밀번호를 확인합니다. 작성자에게 편집/삭제 권한은 없습니다.</p>
            <form onSubmit={postAdminComment} style={{ display: "grid", gap: 7 }}><textarea value={adminComment} onChange={(event) => setAdminComment(event.target.value)} maxLength={MAX_COMMENT_LENGTH} style={{ ...textAreaStyle, minHeight: 75 }} placeholder="해당 사항 반영 완료 / 반영 불가 / 참고하겠습니다 등" /><div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 7, flexWrap: "wrap" }}><span style={{ color: "#94a3b8", fontSize: 9 }}>{adminComment.length}/{MAX_COMMENT_LENGTH}자</span><div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}><button type="submit" disabled={adminBusy} style={inlineButton("#164e63")}>{adminBusy ? "처리 중…" : "관리자 댓글 등록"}</button><button type="button" disabled={adminBusy} onClick={() => void deletePost()} style={inlineButton("#5b2632")}>게시글 삭제</button></div></div></form>
          </section>
          {error && <p role="alert" style={{ margin: 0, color: "#fda4af", fontSize: 11, overflowWrap: "anywhere" }}>{error}</p>}
        </div>
      </section>
    </div>}
  </>;
}
