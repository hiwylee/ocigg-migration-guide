import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Zap, CheckCircle2, Circle, AlertTriangle, Clock, RotateCcw, Play
} from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";

interface CutoverStep {
  step_id: string;
  title: string;
  completed: boolean;
  completed_by: string | null;
  completed_at: string | null;
}

interface CutoverStatus {
  started_at: string | null;
  rollback_started_at: string | null;
  rollback_reason: string | null;
  steps: CutoverStep[];
}

interface ValidationSummary {
  total: number;
  pass_count: number;
  fail_count: number;
  warn_count: number;
  go_nogo: string;
}

function useElapsed(startedAt: string | null) {
  const [elapsed, setElapsed] = useState(0);
  useEffect(() => {
    if (!startedAt) { setElapsed(0); return; }
    const tick = () => {
      const diff = Math.floor((Date.now() - new Date(startedAt + "Z").getTime()) / 1000);
      setElapsed(Math.max(0, diff));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [startedAt]);
  return elapsed;
}

function formatElapsed(secs: number) {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

export default function CutoverConsole() {
  const navigate = useNavigate();
  const [status, setStatus] = useState<CutoverStatus | null>(null);
  const [validation, setValidation] = useState<ValidationSummary | null>(null);
  const [lagSeconds, setLagSeconds] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);
  const audioRef = useRef<AudioContext | null>(null);

  const elapsed = useElapsed(status?.started_at ?? null);

  const load = useCallback(async () => {
    try {
      const [s, v, gg] = await Promise.all([
        api.get<CutoverStatus>("/cutover/status"),
        api.get<ValidationSummary>("/validation/summary"),
        api.get<{ processes: { name: string; lag_seconds?: number }[] }>("/gg/status").catch(() => null),
      ]);
      setStatus(s.data);
      setValidation(v.data);
      if (gg) {
        const rep = gg.data.processes.find((p) => p.name.startsWith("REP"));
        setLagSeconds(rep?.lag_seconds ?? null);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  // poll when cutover is running
  useEffect(() => {
    if (!status?.started_at || status.rollback_started_at) return;
    const id = setInterval(load, 10000);
    return () => clearInterval(id);
  }, [status, load]);

  // alarm sound at 20/25 min
  useEffect(() => {
    if (!status?.started_at) return;
    const mins = elapsed / 60;
    if (mins >= 25 && !audioRef.current) {
      const ctx = new AudioContext();
      audioRef.current = ctx;
      const osc = ctx.createOscillator();
      osc.frequency.value = 880;
      osc.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.5);
    }
  }, [elapsed, status]);

  const startCutover = async () => {
    if (!window.confirm("Cut-over를 시작합니다. 계속하시겠습니까?")) return;
    setStarting(true);
    try {
      await api.post("/cutover/start");
      await load();
    } finally {
      setStarting(false);
    }
  };

  const completeStep = async (stepId: string) => {
    await api.post(`/cutover/steps/${stepId}/complete`, {});
    await load();
  };

  const undoStep = async (stepId: string) => {
    await api.post(`/cutover/steps/${stepId}/undo`);
    await load();
  };

  if (loading) return <div className="p-6 text-slate-400">로딩 중...</div>;
  if (!status) return <div className="p-6 text-red-400">데이터를 불러올 수 없습니다</div>;

  const highFail = validation ? validation.fail_count > 0 : true;
  const lagOk = lagSeconds !== null && lagSeconds <= 30;
  const canStart = !highFail && lagOk && !status.started_at;

  const mins = elapsed / 60;
  const timerColor = mins >= 25 ? "text-red-400" : mins >= 20 ? "text-amber-400" : "text-emerald-400";
  const completedCount = status.steps.filter((s) => s.completed).length;

  return (
    <div className="p-6 space-y-6 max-w-4xl">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Zap className="w-6 h-6 text-amber-400" />
          <h1 className="text-xl font-bold text-white">Cut-over Console</h1>
        </div>
        {status.started_at && !status.rollback_started_at && (
          <button
            onClick={() => navigate("/rollback")}
            className="flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded text-sm font-medium"
          >
            <RotateCcw className="w-4 h-4" />
            롤백
          </button>
        )}
      </div>

      {/* Rollback notice */}
      {status.rollback_started_at && (
        <div className="bg-red-900/40 border border-red-600 rounded-lg p-4">
          <p className="text-red-300 font-semibold">롤백 진행 중</p>
          <p className="text-red-400 text-sm mt-1">사유: {status.rollback_reason}</p>
        </div>
      )}

      {/* Start conditions */}
      {!status.started_at && (
        <div className="bg-slate-800 rounded-lg p-5 space-y-3">
          <p className="text-sm font-medium text-slate-300 mb-3">Cut-over 시작 조건</p>
          <Condition ok={!highFail} label={`Validation HIGH 항목 전체 PASS (FAIL: ${validation?.fail_count ?? "?"}건)`} />
          <Condition ok={lagOk} label={`GG REP LAG ≤ 30초 (현재: ${lagSeconds !== null ? lagSeconds + "초" : "미확인"})`} />
          <button
            onClick={startCutover}
            disabled={!canStart || starting}
            className={cn(
              "mt-4 w-full flex items-center justify-center gap-2 py-3 rounded-lg font-semibold text-sm transition-colors",
              canStart
                ? "bg-amber-500 hover:bg-amber-600 text-white cursor-pointer"
                : "bg-slate-700 text-slate-500 cursor-not-allowed"
            )}
          >
            <Play className="w-4 h-4" />
            {starting ? "시작 중..." : "Cut-over 시작"}
          </button>
        </div>
      )}

      {/* Timer */}
      {status.started_at && !status.rollback_started_at && (
        <div className="bg-slate-800 rounded-lg p-5 flex items-center justify-between">
          <div>
            <p className="text-slate-400 text-sm">경과 시간</p>
            <p className={cn("text-4xl font-mono font-bold mt-1", timerColor)}>
              {formatElapsed(elapsed)}
            </p>
            {mins >= 20 && <p className="text-amber-400 text-xs mt-1">⚠ 목표 시간 20분 초과</p>}
            {mins >= 25 && <p className="text-red-400 text-xs">🚨 최대 시간 25분 초과</p>}
          </div>
          <div className="text-right">
            <p className="text-slate-400 text-sm">완료 단계</p>
            <p className="text-2xl font-bold text-white mt-1">{completedCount} / {status.steps.length}</p>
          </div>
        </div>
      )}

      {/* Steps */}
      <div className="bg-slate-800 rounded-lg overflow-hidden">
        <div className="px-5 py-3 border-b border-slate-700">
          <p className="text-sm font-medium text-slate-300">실행 체크리스트</p>
        </div>
        <ul className="divide-y divide-slate-700/50">
          {status.steps.map((step, idx) => (
            <li key={step.step_id} className="px-5 py-3 flex items-center gap-4">
              <span className="text-slate-500 text-xs w-5 text-right shrink-0">{idx + 1}</span>
              {step.completed
                ? <CheckCircle2 className="w-5 h-5 text-emerald-500 shrink-0" />
                : <Circle className="w-5 h-5 text-slate-600 shrink-0" />}
              <div className="flex-1 min-w-0">
                <p className={cn("text-sm", step.completed ? "text-slate-400 line-through" : "text-white")}>
                  {step.title}
                </p>
                {step.completed && step.completed_by && (
                  <p className="text-xs text-slate-500 mt-0.5">
                    {step.completed_by} · {step.completed_at?.slice(0, 19).replace("T", " ")}
                  </p>
                )}
              </div>
              {status.started_at && !status.rollback_started_at && (
                <div className="flex gap-2 shrink-0">
                  {!step.completed ? (
                    <button
                      onClick={() => completeStep(step.step_id)}
                      className="px-3 py-1 bg-emerald-600 hover:bg-emerald-700 text-white text-xs rounded"
                    >
                      완료
                    </button>
                  ) : (
                    <button
                      onClick={() => undoStep(step.step_id)}
                      className="px-3 py-1 bg-slate-600 hover:bg-slate-500 text-white text-xs rounded"
                    >
                      취소
                    </button>
                  )}
                </div>
              )}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function Condition({ ok, label }: { ok: boolean; label: string }) {
  return (
    <div className="flex items-center gap-3">
      {ok
        ? <CheckCircle2 className="w-5 h-5 text-emerald-500 shrink-0" />
        : <AlertTriangle className="w-5 h-5 text-amber-500 shrink-0" />}
      <span className={cn("text-sm", ok ? "text-emerald-300" : "text-slate-300")}>{label}</span>
    </div>
  );
}
