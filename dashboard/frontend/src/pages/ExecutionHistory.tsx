import { useCallback, useEffect, useState } from "react";
import { History, ChevronRight, CheckCircle2, XCircle, Clock, RefreshCw } from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";

interface ScriptRun {
  id: number;
  script_path: string;
  risk_level: string;
  started_at: string;
  finished_at: string | null;
  status: string;
  exit_code: number | null;
  log_path: string | null;
  run_by: string | null;
  reason: string | null;
}

const STATUS_STYLE: Record<string, string> = {
  completed: "text-emerald-400",
  running:   "text-blue-400",
  failed:    "text-red-400",
  killed:    "text-amber-400",
};

const RISK_BADGE: Record<string, string> = {
  LOW:      "bg-slate-600 text-slate-300",
  MEDIUM:   "bg-blue-700 text-blue-200",
  HIGH:     "bg-amber-700 text-amber-200",
  CRITICAL: "bg-red-700 text-red-200",
};

export default function ExecutionHistory() {
  const [runs, setRuns] = useState<ScriptRun[]>([]);
  const [selected, setSelected] = useState<ScriptRun | null>(null);
  const [logContent, setLogContent] = useState<string>("");
  const [logLoading, setLogLoading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, string> = { limit: "100" };
      if (statusFilter) params.status = statusFilter;
      const r = await api.get<ScriptRun[]>("/scripts/runs", { params });
      setRuns(r.data);
    } finally {
      setLoading(false);
    }
  }, [statusFilter]);

  useEffect(() => { load(); }, [load]);

  const selectRun = async (run: ScriptRun) => {
    setSelected(run);
    setLogContent("");
    if (!run.log_path) return;
    setLogLoading(true);
    try {
      const r = await api.get<{ content: string }>(`/scripts/runs/${run.id}/log`);
      setLogContent(r.data.content);
    } catch {
      setLogContent("로그 파일을 불러올 수 없습니다.");
    } finally {
      setLogLoading(false);
    }
  };

  function StatusIcon({ status }: { status: string }) {
    if (status === "completed") return <CheckCircle2 className="w-4 h-4 text-emerald-500" />;
    if (status === "failed" || status === "killed") return <XCircle className="w-4 h-4 text-red-500" />;
    return <Clock className="w-4 h-4 text-blue-400" />;
  }

  return (
    <div className="p-6 flex gap-4 h-[calc(100vh-4rem)] max-w-6xl">
      {/* Left: list */}
      <div className="w-80 shrink-0 flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <History className="w-5 h-5 text-blue-400" />
            <h1 className="text-lg font-bold text-white">실행 이력</h1>
          </div>
          <button onClick={load} className="text-slate-400 hover:text-white">
            <RefreshCw className={cn("w-4 h-4", loading && "animate-spin")} />
          </button>
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-white text-sm focus:outline-none focus:border-blue-500 w-full"
        >
          <option value="">전체 상태</option>
          <option value="completed">completed</option>
          <option value="failed">failed</option>
          <option value="running">running</option>
          <option value="killed">killed</option>
        </select>
        <div className="flex-1 overflow-y-auto bg-slate-800 rounded-lg divide-y divide-slate-700/50">
          {runs.length === 0 ? (
            <p className="p-4 text-slate-500 text-sm text-center">실행 이력 없음</p>
          ) : (
            runs.map((run) => (
              <button
                key={run.id}
                onClick={() => selectRun(run)}
                className={cn(
                  "w-full text-left px-4 py-3 hover:bg-slate-700/50 transition-colors",
                  selected?.id === run.id && "bg-blue-600/20 border-r-2 border-blue-500"
                )}
              >
                <div className="flex items-center gap-2">
                  <StatusIcon status={run.status} />
                  <span className={cn("text-xs font-medium", RISK_BADGE[run.risk_level], "px-1.5 py-0.5 rounded")}>
                    {run.risk_level}
                  </span>
                </div>
                <p className="text-white text-xs mt-1.5 truncate font-mono">
                  {run.script_path.split("/").pop()}
                </p>
                <p className="text-slate-500 text-xs mt-0.5">
                  {run.started_at.slice(0, 19).replace("T", " ")}
                </p>
                {run.run_by && <p className="text-slate-600 text-xs">{run.run_by}</p>}
              </button>
            ))
          )}
        </div>
      </div>

      {/* Right: detail */}
      <div className="flex-1 min-w-0 flex flex-col gap-3">
        {selected ? (
          <>
            <div className="bg-slate-800 rounded-lg p-4 space-y-2">
              <div className="flex items-center gap-3 flex-wrap">
                <span className={cn("text-sm font-medium", STATUS_STYLE[selected.status] ?? "text-white")}>
                  {selected.status.toUpperCase()}
                </span>
                {selected.exit_code !== null && (
                  <span className="text-slate-400 text-sm">exit: {selected.exit_code}</span>
                )}
                <span className={cn("px-2 py-0.5 rounded text-xs", RISK_BADGE[selected.risk_level])}>
                  {selected.risk_level}
                </span>
              </div>
              <p className="text-white text-sm font-mono">{selected.script_path}</p>
              <div className="grid grid-cols-2 gap-2 text-xs text-slate-400 mt-2">
                <span>시작: {selected.started_at.slice(0, 19).replace("T", " ")}</span>
                <span>종료: {selected.finished_at?.slice(0, 19).replace("T", " ") ?? "-"}</span>
                <span>실행자: {selected.run_by ?? "-"}</span>
                {selected.reason && <span className="col-span-2">사유: {selected.reason}</span>}
              </div>
            </div>
            <div className="flex-1 bg-slate-900 rounded-lg overflow-hidden flex flex-col">
              <div className="px-4 py-2 border-b border-slate-700 text-xs text-slate-400">
                {selected.log_path ?? "로그 없음"}
              </div>
              <div className="flex-1 overflow-y-auto p-4">
                {logLoading ? (
                  <p className="text-slate-400 text-sm">로딩 중...</p>
                ) : (
                  <pre className="text-xs text-slate-300 font-mono whitespace-pre-wrap break-all">
                    {logContent || "(로그 없음)"}
                  </pre>
                )}
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-slate-500">
            <div className="text-center">
              <ChevronRight className="w-8 h-8 mx-auto mb-2 opacity-30" />
              <p>왼쪽에서 실행 이력을 선택하세요</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
