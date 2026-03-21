import { useCallback, useEffect, useRef, useState } from "react";
import { Copy, Square, CheckCircle2, XCircle, Loader2, Wifi } from "lucide-react";
import { cn } from "../lib/utils";
import api from "../hooks/useApi";

// ---------------------------------------------------------------------------
// 타입
// ---------------------------------------------------------------------------

export interface LogStreamerProps {
  scriptId: string;
  wsUrl: string;
  payload: object;
  onComplete: (exitCode: number) => void;
  onError: (msg: string) => void;
  autoScroll?: boolean;
}

type RunStatus = "connecting" | "running" | "success" | "failed" | "killed";

interface LogLine {
  type: "stdout" | "stderr" | "system";
  text: string;
}

// ---------------------------------------------------------------------------
// 파싱 헬퍼
// ---------------------------------------------------------------------------

const MAX_LINES = 5000;

function parseLine(raw: string): LogLine {
  if (raw.startsWith("[STDOUT] ")) return { type: "stdout", text: raw.slice(9) };
  if (raw.startsWith("[STDERR] ")) return { type: "stderr", text: raw.slice(9) };
  return { type: "system", text: raw.startsWith("[SYSTEM] ") ? raw.slice(9) : raw };
}

function lineClass(type: LogLine["type"]): string {
  if (type === "stdout") return "text-green-400";
  if (type === "stderr") return "text-red-400";
  return "text-slate-400";
}

// ---------------------------------------------------------------------------
// 컴포넌트
// ---------------------------------------------------------------------------

export default function LogStreamer({
  scriptId,
  wsUrl,
  payload,
  onComplete,
  onError,
  autoScroll = true,
}: LogStreamerProps) {
  const [lines, setLines] = useState<LogLine[]>([]);
  const [status, setStatus] = useState<RunStatus>("connecting");
  const [exitCode, setExitCode] = useState<number | null>(null);
  const bottomRef = useRef<HTMLDivElement | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  // 로그 추가 (5000줄 제한)
  const appendLine = useCallback((raw: string) => {
    const parsed = parseLine(raw);
    setLines((prev) => {
      const next = [...prev, parsed];
      return next.length > MAX_LINES ? next.slice(next.length - MAX_LINES) : next;
    });
  }, []);

  // 완료 메시지에서 exit_code 파싱
  const parseExitCode = (text: string): number => {
    const m = text.match(/exit_code=(-?\d+)/);
    return m ? parseInt(m[1], 10) : -1;
  };

  useEffect(() => {
    // token은 authStore에서 직접 가져오기
    const { useAuthStore } = require("../store/authStore");
    const token: string | null = useAuthStore.getState().token;

    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setStatus("running");
      // Send token as first message to avoid exposing JWT in server logs via URL.
      ws.send(JSON.stringify({ token: token ?? "", ...payload }));
    };

    ws.onmessage = (ev: MessageEvent) => {
      const raw: string = ev.data as string;
      appendLine(raw);

      // 완료 판별
      if (raw.startsWith("[SYSTEM] 실행 완료")) {
        const code = parseExitCode(raw);
        setExitCode(code);
        setStatus(raw.includes("status=success") ? "success" : raw.includes("status=killed") ? "killed" : "failed");
        onComplete(code);
      } else if (raw.startsWith("[SYSTEM] 오류") || raw.startsWith("[SYSTEM] 인증 실패")) {
        setStatus("failed");
        onError(raw);
      }
    };

    ws.onerror = () => {
      appendLine("[SYSTEM] WebSocket 연결 오류");
      setStatus("failed");
      onError("WebSocket 연결 오류");
    };

    ws.onclose = (ev) => {
      wsRef.current = null;
      if (status === "running" || status === "connecting") {
        appendLine(`[SYSTEM] 연결 종료 (code=${ev.code})`);
        setStatus("failed");
        onError(`WebSocket 연결 종료 (code=${ev.code})`);
      }
    };

    return () => {
      ws.close();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wsUrl]);

  // 자동 스크롤
  useEffect(() => {
    if (autoScroll && bottomRef.current) {
      bottomRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [lines, autoScroll]);

  // 강제 종료
  async function handleKill() {
    try {
      await api.post(`/scripts/${scriptId}/kill`);
      setStatus("killed");
      appendLine("[SYSTEM] 강제 종료 요청 전송됨");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      appendLine(`[SYSTEM] 강제 종료 실패: ${msg}`);
    }
  }

  // 로그 복사
  async function handleCopy() {
    const text = lines.map((l) => l.text).join("\n");
    await navigator.clipboard.writeText(text);
  }

  // 상태 아이콘/배지
  const StatusBadge = () => {
    if (status === "connecting")
      return (
        <span className="flex items-center gap-1 text-amber-400 text-xs">
          <Wifi className="w-3.5 h-3.5 animate-pulse" /> 연결 중
        </span>
      );
    if (status === "running")
      return (
        <span className="flex items-center gap-1 text-blue-400 text-xs">
          <Loader2 className="w-3.5 h-3.5 animate-spin" /> 실행 중
        </span>
      );
    if (status === "success")
      return (
        <span className="flex items-center gap-1 text-emerald-400 text-xs">
          <CheckCircle2 className="w-3.5 h-3.5" /> 완료 (exit_code={exitCode})
        </span>
      );
    if (status === "killed")
      return (
        <span className="flex items-center gap-1 text-amber-400 text-xs">
          <Square className="w-3.5 h-3.5" /> 강제 종료
        </span>
      );
    return (
      <span className="flex items-center gap-1 text-red-400 text-xs">
        <XCircle className="w-3.5 h-3.5" /> 실패 (exit_code={exitCode ?? "?"})
      </span>
    );
  };

  const isRunning = status === "connecting" || status === "running";

  return (
    <div className="flex flex-col gap-2">
      {/* 툴바 */}
      <div className="flex items-center justify-between">
        <StatusBadge />
        <div className="flex items-center gap-2">
          <button
            onClick={handleKill}
            disabled={!isRunning}
            className={cn(
              "flex items-center gap-1 text-xs px-2 py-1 rounded transition",
              isRunning
                ? "bg-red-700 hover:bg-red-600 text-white"
                : "bg-slate-700 text-slate-500 cursor-not-allowed opacity-50"
            )}
          >
            <Square className="w-3 h-3" />
            강제 종료
          </button>
          <button
            onClick={handleCopy}
            className="flex items-center gap-1 text-xs px-2 py-1 rounded bg-slate-700 hover:bg-slate-600 text-slate-300 transition"
          >
            <Copy className="w-3 h-3" />
            로그 복사
          </button>
        </div>
      </div>

      {/* 터미널 영역 */}
      <div className="bg-slate-950 border border-slate-700 rounded-lg p-3 font-mono text-xs overflow-y-auto h-72 leading-5">
        {lines.length === 0 ? (
          <span className="text-slate-600">출력 대기 중...</span>
        ) : (
          lines.map((l, i) => (
            <div key={i} className={cn("whitespace-pre-wrap break-all", lineClass(l.type))}>
              {l.text}
            </div>
          ))
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
