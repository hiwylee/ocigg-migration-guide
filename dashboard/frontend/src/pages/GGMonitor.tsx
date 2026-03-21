import { useEffect, useState, useCallback, useRef } from "react";
import {
  Play,
  Square,
  Zap,
  RefreshCw,
  AlertTriangle,
  Terminal,
  ChevronDown,
} from "lucide-react";
import { cn } from "../lib/utils";
import { STATUS_BADGE } from "../lib/styles";
import { useAuthStore } from "../store/authStore";
import api from "../hooks/useApi";
import LagChart, { type LagPoint } from "../components/LagChart";
import type { GGStatus } from "../types";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ProcessStatus {
  name: string;
  status: GGStatus;
  lag_seconds?: number | null;
  error?: string;
}

interface StatusResponse {
  configured: boolean;
  processes: ProcessStatus[];
}

interface LagHistoryResponse {
  process_name: string;
  lag_seconds: number;
  recorded_at: string;
}

interface LagStableResponse {
  stable: boolean;
  since: string | null;
  hours_elapsed: number;
  threshold_seconds: number;
}

interface DiscardResponse {
  replicat: string;
  count: number;
  configured?: boolean;
}

interface ErrorLogResponse {
  lines: string[];
  count: number;
  configured?: boolean;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const PROCESSES = ["EXT1", "PUMP1", "REP1"] as const;
type ProcessName = typeof PROCESSES[number];

const STATUS_STYLES: Record<GGStatus, { badge: string; dot: string; text: string }> = {
  RUNNING: { badge: STATUS_BADGE.RUNNING, dot: "bg-emerald-400",            text: "text-emerald-400" },
  STOPPED: { badge: STATUS_BADGE.STOPPED, dot: "bg-amber-400",              text: "text-amber-400"   },
  ABEND:   { badge: STATUS_BADGE.ABEND,   dot: "bg-red-400 animate-pulse",  text: "text-red-400"     },
  UNKNOWN: { badge: STATUS_BADGE.UNKNOWN, dot: "bg-slate-500",              text: "text-slate-400"   },
};

const OPERATOR_ROLES = new Set(["gg_operator", "admin", "migration_leader"]);

// ---------------------------------------------------------------------------
// Process Card
// ---------------------------------------------------------------------------

interface ProcessCardProps {
  proc: ProcessStatus;
  canOperate: boolean;
  onAction: (name: string, action: "start" | "stop" | "kill") => Promise<void>;
  actionLoading: string | null;
}

function ProcessCard({ proc, canOperate, onAction, actionLoading }: ProcessCardProps) {
  const style = STATUS_STYLES[proc.status] ?? STATUS_STYLES.UNKNOWN;
  const isLoading = actionLoading === proc.name;

  const lagDisplay =
    proc.lag_seconds != null
      ? `${proc.lag_seconds.toFixed(1)}s`
      : "—";

  return (
    <div
      className={cn(
        "bg-slate-800 rounded-lg border p-4 flex flex-col gap-3",
        proc.status === "ABEND"
          ? "border-red-500/40"
          : "border-slate-700"
      )}
    >
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className={cn("w-2 h-2 rounded-full shrink-0", style.dot)} />
          <span className="text-white font-mono font-semibold text-sm">{proc.name}</span>
        </div>
        <span className={cn("text-xs px-2 py-0.5 rounded font-medium", style.badge)}>
          {proc.status}
        </span>
      </div>

      {/* LAG */}
      <div className="text-center py-1">
        <span
          className={cn(
            "text-3xl font-mono font-bold",
            proc.lag_seconds != null && proc.lag_seconds > 30
              ? "text-red-400"
              : proc.lag_seconds != null && proc.lag_seconds > 15
              ? "text-amber-400"
              : "text-slate-300"
          )}
        >
          {lagDisplay}
        </span>
        <p className="text-xs text-slate-600 mt-0.5">현재 LAG</p>
      </div>

      {/* Action buttons */}
      <div className="flex gap-1.5">
        <button
          onClick={() => onAction(proc.name, "start")}
          disabled={!canOperate || isLoading || proc.status === "RUNNING"}
          title="START"
          className={cn(
            "flex-1 flex items-center justify-center gap-1 text-xs py-1.5 rounded transition font-medium",
            canOperate && proc.status !== "RUNNING"
              ? "bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-400 border border-emerald-600/40"
              : "bg-slate-700/50 text-slate-600 border border-slate-700 cursor-not-allowed"
          )}
        >
          <Play className="w-3 h-3" />
          START
        </button>

        <button
          onClick={() => onAction(proc.name, "stop")}
          disabled={!canOperate || isLoading || proc.status !== "RUNNING"}
          title="STOP"
          className={cn(
            "flex-1 flex items-center justify-center gap-1 text-xs py-1.5 rounded transition font-medium",
            canOperate && proc.status === "RUNNING"
              ? "bg-amber-600/20 hover:bg-amber-600/30 text-amber-400 border border-amber-600/40"
              : "bg-slate-700/50 text-slate-600 border border-slate-700 cursor-not-allowed"
          )}
        >
          <Square className="w-3 h-3" />
          STOP
        </button>

        <button
          onClick={() => onAction(proc.name, "kill")}
          disabled={!canOperate || isLoading}
          title="KILL"
          className={cn(
            "flex-1 flex items-center justify-center gap-1 text-xs py-1.5 rounded transition font-medium",
            canOperate
              ? "bg-red-600/20 hover:bg-red-600/30 text-red-400 border border-red-600/40"
              : "bg-slate-700/50 text-slate-600 border border-slate-700 cursor-not-allowed"
          )}
        >
          <Zap className="w-3 h-3" />
          KILL
        </button>
      </div>

      {isLoading && (
        <p className="text-xs text-slate-500 text-center animate-pulse">처리 중...</p>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Elapsed label
// ---------------------------------------------------------------------------

function elapsedLabel(hoursElapsed: number): string {
  const h = Math.floor(hoursElapsed);
  const m = Math.round((hoursElapsed - h) * 60);
  return `${h}h ${m}m`;
}

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------

export default function GGMonitor() {
  const user = useAuthStore((s) => s.user);
  const canOperate = user ? OPERATOR_ROLES.has(user.role) : false;

  const [configured, setConfigured] = useState<boolean | null>(null);
  const [processes, setProcesses] = useState<ProcessStatus[]>([]);
  const [statusLoading, setStatusLoading] = useState(false);

  const [selectedProcess, setSelectedProcess] = useState<ProcessName>("EXT1");
  const [lagData, setLagData] = useState<Record<ProcessName, LagPoint[]>>({
    EXT1: [], PUMP1: [], REP1: [],
  });
  const [lagLoading, setLagLoading] = useState(false);

  const [stableInfo, setStableInfo] = useState<LagStableResponse | null>(null);

  const [discardCount, setDiscardCount] = useState<number | null>(null);
  const [errorLogLines, setErrorLogLines] = useState<string[]>([]);
  const [logLoading, setLogLoading] = useState(false);

  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  const statusIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lagIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ---- Fetch process status ----
  const fetchStatus = useCallback(async () => {
    setStatusLoading(true);
    try {
      const res = await api.get<StatusResponse>("/gg/status");
      setConfigured(res.data.configured);
      setProcesses(res.data.processes ?? []);
    } catch (err) {
      console.warn("GGMonitor: failed to fetch status", err);
      setConfigured(false);
    } finally {
      setStatusLoading(false);
    }
  }, []);

  // ---- Fetch LAG history for all 3 processes ----
  const fetchLagHistory = useCallback(async () => {
    setLagLoading(true);
    try {
      const results = await Promise.allSettled(
        PROCESSES.map((name) =>
          api
            .get<LagHistoryResponse[]>(`/gg/lag-history`, {
              params: { hours: 24, process: name },
            })
            .then((r) => ({ name, data: r.data }))
        )
      );
      const next: Record<ProcessName, LagPoint[]> = { EXT1: [], PUMP1: [], REP1: [] };
      for (const r of results) {
        if (r.status === "fulfilled") {
          next[r.value.name as ProcessName] = r.value.data;
        }
      }
      setLagData(next);
    } catch (err) {
      console.warn("GGMonitor: failed to fetch lag history", err);
    } finally {
      setLagLoading(false);
    }
  }, []);

  // ---- Fetch stable info ----
  const fetchStable = useCallback(async () => {
    try {
      const res = await api.get<LagStableResponse>("/gg/lag-stable");
      setStableInfo(res.data);
    } catch (err) {
      console.warn("GGMonitor: failed to fetch stable info", err);
    }
  }, []);

  // ---- Fetch discard count ----
  const fetchDiscard = useCallback(async () => {
    try {
      const res = await api.get<DiscardResponse>("/gg/discard-count");
      if (res.data.configured !== false) {
        setDiscardCount(res.data.count);
      }
    } catch (err) {
      console.warn("GGMonitor: failed to fetch discard count", err);
    }
  }, []);

  // ---- Fetch error log ----
  const fetchErrorLog = useCallback(async () => {
    setLogLoading(true);
    try {
      const res = await api.get<ErrorLogResponse>("/gg/error-log", {
        params: { lines: 50 },
      });
      if (res.data.configured !== false) {
        setErrorLogLines(res.data.lines ?? []);
      }
    } catch {
      // ignore
    } finally {
      setLogLoading(false);
    }
  }, []);

  // ---- Process action ----
  async function handleAction(name: string, action: "start" | "stop" | "kill") {
    setActionLoading(name);
    setActionMsg(null);
    try {
      await api.post(`/gg/process/${name}/${action}`);
      setActionMsg(`${name} ${action.toUpperCase()} 요청 완료`);
      await fetchStatus();
    } catch (err: unknown) {
      const msg =
        err && typeof err === "object" && "response" in err
          ? (err as { response?: { data?: { detail?: string } } }).response?.data?.detail ?? "오류"
          : "오류";
      setActionMsg(`오류: ${msg}`);
    } finally {
      setActionLoading(null);
      setTimeout(() => setActionMsg(null), 4000);
    }
  }

  // ---- Init & polling ----
  useEffect(() => {
    fetchStatus();
    fetchLagHistory();
    fetchStable();
    fetchDiscard();
    fetchErrorLog();

    // 프로세스 상태 30초 폴링
    statusIntervalRef.current = setInterval(() => {
      fetchStatus();
      fetchStable();
    }, 30_000);

    // LAG 이력 5분 폴링
    lagIntervalRef.current = setInterval(() => {
      fetchLagHistory();
      fetchDiscard();
    }, 5 * 60_000);

    return () => {
      if (statusIntervalRef.current) clearInterval(statusIntervalRef.current);
      if (lagIntervalRef.current) clearInterval(lagIntervalRef.current);
    };
  }, [fetchStatus, fetchLagHistory, fetchStable, fetchDiscard, fetchErrorLog]);

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  const threshold = stableInfo?.threshold_seconds ?? 30;

  return (
    <div className="space-y-6 max-w-6xl">
      {/* Page header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">GG Monitor</h1>
          <p className="text-slate-400 text-sm">OCI GoldenGate 프로세스 모니터링</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => { fetchStatus(); fetchStable(); }}
            disabled={statusLoading}
            className="flex items-center gap-1.5 text-xs bg-slate-700 hover:bg-slate-600 disabled:opacity-50 text-slate-300 px-3 py-1.5 rounded transition"
          >
            <RefreshCw className={cn("w-3 h-3", statusLoading && "animate-spin")} />
            INFO ALL
          </button>
          <button
            onClick={fetchLagHistory}
            disabled={lagLoading}
            className="flex items-center gap-1.5 text-xs bg-slate-700 hover:bg-slate-600 disabled:opacity-50 text-slate-300 px-3 py-1.5 rounded transition"
          >
            <RefreshCw className={cn("w-3 h-3", lagLoading && "animate-spin")} />
            LAG 새로고침
          </button>
        </div>
      </div>

      {/* GG_ADMIN_URL 미설정 배너 */}
      {configured === false && (
        <div className="flex items-center gap-3 bg-amber-500/10 border border-amber-500/30 rounded-lg px-4 py-3">
          <AlertTriangle className="w-4 h-4 text-amber-400 shrink-0" />
          <p className="text-amber-300 text-sm">
            GoldenGate Admin URL이 설정되지 않았습니다.{" "}
            <span className="font-mono text-amber-400">Config Registry</span>에서{" "}
            <span className="font-mono text-amber-400">GG_ADMIN_URL</span> 설정이 필요합니다.
          </p>
        </div>
      )}

      {/* 액션 메시지 */}
      {actionMsg && (
        <div className={cn(
          "text-xs px-4 py-2 rounded border",
          actionMsg.startsWith("오류")
            ? "bg-red-500/10 border-red-500/30 text-red-400"
            : "bg-emerald-500/10 border-emerald-500/30 text-emerald-400"
        )}>
          {actionMsg}
        </div>
      )}

      {/* ── Section 1: Process Cards ── */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {PROCESSES.map((name) => {
          const proc = processes.find((p) => p.name === name) ?? {
            name,
            status: "UNKNOWN" as GGStatus,
            lag_seconds: null,
          };
          return (
            <ProcessCard
              key={name}
              proc={proc}
              canOperate={canOperate}
              onAction={handleAction}
              actionLoading={actionLoading}
            />
          );
        })}
      </div>

      {/* ── Section 2: LAG 24h Chart ── */}
      <div className="bg-slate-800 rounded-lg border border-slate-700 p-4">
        {/* Chart header with tabs + stable badge */}
        <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
          <div className="flex items-center gap-1">
            {PROCESSES.map((name) => (
              <button
                key={name}
                onClick={() => setSelectedProcess(name)}
                className={cn(
                  "text-xs px-3 py-1 rounded font-mono transition",
                  selectedProcess === name
                    ? "bg-sky-600 text-white"
                    : "bg-slate-700 text-slate-400 hover:bg-slate-600"
                )}
              >
                {name}
              </button>
            ))}
          </div>

          {/* 24h 안정화 배지 */}
          {stableInfo && (
            stableInfo.stable ? (
              <span className="flex items-center gap-1 text-xs bg-emerald-500/20 border border-emerald-500/40 text-emerald-400 px-3 py-1 rounded-full font-medium">
                ✓ 24h 안정화 달성
              </span>
            ) : (
              <span className="flex items-center gap-1 text-xs bg-slate-700 border border-slate-600 text-slate-400 px-3 py-1 rounded-full">
                대기 중 {elapsedLabel(stableInfo.hours_elapsed)}
              </span>
            )
          )}
        </div>

        <LagChart
          data={lagData[selectedProcess]}
          threshold={threshold}
          stableSince={stableInfo?.since ?? null}
          loading={lagLoading && lagData[selectedProcess].length === 0}
        />
      </div>

      {/* ── Section 3: Discard + Error Log ── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Discard */}
        <div className="bg-slate-800 rounded-lg border border-slate-700 p-4">
          <h2 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-4">
            Discard 레코드
          </h2>
          <div className="text-center py-4">
            <span
              className={cn(
                "text-5xl font-mono font-bold",
                discardCount != null && discardCount > 0 ? "text-red-400" : "text-slate-300"
              )}
            >
              {discardCount ?? "—"}
            </span>
            <p className="text-slate-500 text-xs mt-1">건</p>
          </div>
          <button
            onClick={() => fetchDiscard()}
            className="w-full flex items-center justify-center gap-1.5 text-xs bg-slate-700 hover:bg-slate-600 text-slate-300 px-3 py-2 rounded transition mt-2"
          >
            <ChevronDown className="w-3 h-3" />
            VIEW DISCARD
          </button>
        </div>

        {/* Error Log */}
        <div className="bg-slate-800 rounded-lg border border-slate-700 p-4 flex flex-col">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Terminal className="w-4 h-4 text-slate-500" />
              <h2 className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
                GG Error Log
              </h2>
            </div>
            <button
              onClick={fetchErrorLog}
              disabled={logLoading}
              className="flex items-center gap-1 text-xs text-slate-500 hover:text-slate-300 transition"
            >
              <RefreshCw className={cn("w-3 h-3", logLoading && "animate-spin")} />
              새로고침
            </button>
          </div>

          <div className="flex-1 overflow-y-auto max-h-56 bg-slate-900 rounded border border-slate-700 p-2">
            {logLoading ? (
              <p className="text-slate-600 text-xs animate-pulse text-center py-4">
                로딩 중...
              </p>
            ) : errorLogLines.length === 0 ? (
              <p className="text-slate-600 text-xs text-center py-4">
                에러 로그가 없습니다
              </p>
            ) : (
              <div className="space-y-0.5">
                {errorLogLines.map((line, idx) => (
                  <p
                    key={idx}
                    className={cn(
                      "font-mono text-xs leading-5 whitespace-pre-wrap break-all",
                      line.includes("CRITICAL") || line.includes("ABEND")
                        ? "text-red-400"
                        : line.includes("WARN")
                        ? "text-amber-400"
                        : "text-slate-400"
                    )}
                  >
                    {line}
                  </p>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
