import { useEffect, useState } from "react";
import {
  CheckCircle2,
  Circle,
  Clock,
  AlertCircle,
  RefreshCw,
} from "lucide-react";
import api from "../hooks/useApi";
import type { PhaseStatus, HealthResult, GoNogo } from "../types";
import { cn } from "../lib/utils";

interface PhaseRow {
  phase_no: number;
  label: string;
  period: string;
  status: PhaseStatus;
}

const PHASE_META = [
  { label: "P0: 적합성 & 환경 점검",          period: "D-14~D-7"  },
  { label: "P1: 소스 DB 준비 (AWS RDS)",       period: "D-7~D-5"   },
  { label: "P2: 타겟 DB 준비 (OCI DBCS)",      period: "D-7~D-5"   },
  { label: "P3: OCI GoldenGate 구성",          period: "D-5~D-3"   },
  { label: "P4: 초기 데이터 적재",              period: "D-3~D-1"   },
  { label: "P5: 델타 동기화",                   period: "D-1~D-Day" },
  { label: "P6: 검증 (136항목)",               period: "D-1~D-Day" },
  { label: "P7: Cut-over",                     period: "D-Day"     },
  { label: "P8: 마이그레이션 후 안정화",        period: "D+1~D+7"   },
];

function PhaseIcon({ status }: { status: PhaseStatus }) {
  if (status === "completed")  return <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />;
  if (status === "in_progress") return <Clock        className="w-4 h-4 text-amber-400 shrink-0 animate-pulse" />;
  if (status === "failed")     return <AlertCircle  className="w-4 h-4 text-red-400 shrink-0" />;
  return <Circle className="w-4 h-4 text-slate-600 shrink-0" />;
}

const CONN_BADGE: Record<string, string> = {
  ok:             "bg-emerald-500/20 text-emerald-400 border border-emerald-500/40",
  error:          "bg-red-500/20 text-red-400 border border-red-500/40",
  not_configured: "bg-slate-700 text-slate-400 border border-slate-600",
  checking:       "bg-amber-500/20 text-amber-400 border border-amber-500/40",
};
const CONN_LABEL: Record<string, string> = {
  ok:             "연결됨",
  error:          "오류",
  not_configured: "미설정",
  checking:       "확인 중",
};

const GONOGO_STYLE: Record<GoNogo, string> = {
  GO:             "text-emerald-400",
  CONDITIONAL_GO: "text-amber-400",
  NO_GO:          "text-red-400",
  PENDING:        "text-slate-400",
};

export default function Overview() {
  const [phases, setPhases] = useState<PhaseRow[]>([]);
  const [health, setHealth] = useState<Partial<HealthResult>>({});
  const [healthLoading, setHealthLoading] = useState(false);
  const [valSummary] = useState({ total: 136, pass: 0, warn: 0, fail: 0 });
  const [goNogo] = useState<GoNogo>("PENDING");

  useEffect(() => {
    api
      .get<Array<{ key: string; value: string }>>("/config")
      .then((res) => {
        const cp =
          parseInt(
            res.data.find((e) => e.key === "CURRENT_PHASE")?.value ?? "0"
          ) || 0;
        setPhases(
          PHASE_META.map((m, i) => ({
            phase_no: i,
            label: m.label,
            period: m.period,
            status:
              i < cp ? "completed" : i === cp ? "in_progress" : "pending",
          }))
        );
      })
      .catch(() => {
        setPhases(
          PHASE_META.map((m, i) => ({
            phase_no: i,
            label: m.label,
            period: m.period,
            status: "pending",
          }))
        );
      });
  }, []);

  async function runHealthcheck() {
    setHealthLoading(true);
    try {
      const res = await api.post<HealthResult>("/config/healthcheck");
      setHealth(res.data);
    } catch {
      // ignore
    } finally {
      setHealthLoading(false);
    }
  }

  const passPct = Math.round((valSummary.pass / valSummary.total) * 100);

  return (
    <div className="space-y-6 max-w-5xl">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">Overview</h1>
          <p className="text-slate-400 text-sm">마이그레이션 전체 현황</p>
        </div>
        <span className={cn("text-sm font-bold tracking-wider", GONOGO_STYLE[goNogo])}>
          ▶ {goNogo === "CONDITIONAL_GO" ? "CONDITIONAL GO" : goNogo}
        </span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Phase Timeline */}
        <div className="lg:col-span-2 bg-slate-800 rounded-lg border border-slate-700 p-4">
          <h2 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">
            Phase 진행 현황
          </h2>
          <div className="space-y-1">
            {phases.map((p) => (
              <div
                key={p.phase_no}
                className={cn(
                  "flex items-center gap-3 px-2 py-1.5 rounded",
                  p.status === "in_progress" &&
                    "bg-amber-500/10 border border-amber-500/20"
                )}
              >
                <PhaseIcon status={p.status} />
                <span
                  className={cn(
                    "flex-1 text-sm",
                    p.status === "completed"  && "text-slate-500 line-through",
                    p.status === "in_progress" && "text-amber-300 font-medium",
                    p.status === "pending"    && "text-slate-300",
                    p.status === "failed"     && "text-red-400"
                  )}
                >
                  {p.label}
                </span>
                <span className="text-xs text-slate-600 shrink-0">{p.period}</span>
              </div>
            ))}
          </div>
        </div>

        {/* 우측 패널 */}
        <div className="space-y-4">
          {/* DB 연결 상태 */}
          <div className="bg-slate-800 rounded-lg border border-slate-700 p-4">
            <h2 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">
              DB 연결 상태
            </h2>
            <div className="space-y-2">
              {(
                [
                  ["source_db",  "Source (RDS)"],
                  ["target_db",  "Target (DBCS)"],
                  ["goldengate", "GoldenGate"],
                ] as const
              ).map(([key, label]) => {
                const s = (health as Record<string, { status: string }>)[key]?.status ?? "—";
                return (
                  <div key={key} className="flex items-center justify-between">
                    <span className="text-xs text-slate-400">{label}</span>
                    <span
                      className={cn(
                        "text-xs px-2 py-0.5 rounded",
                        CONN_BADGE[s] ?? CONN_BADGE.error
                      )}
                    >
                      {CONN_LABEL[s] ?? s}
                    </span>
                  </div>
                );
              })}
            </div>
            <button
              onClick={runHealthcheck}
              disabled={healthLoading}
              className="mt-3 w-full flex items-center justify-center gap-1.5 text-xs bg-slate-700 hover:bg-slate-600 disabled:opacity-50 text-slate-300 px-3 py-1.5 rounded transition"
            >
              <RefreshCw className={cn("w-3 h-3", healthLoading && "animate-spin")} />
              헬스체크 실행
            </button>
          </div>

          {/* Validation 진행률 */}
          <div className="bg-slate-800 rounded-lg border border-slate-700 p-4">
            <h2 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">
              Validation 진행률
            </h2>
            <div className="text-center mb-2">
              <span className="text-3xl font-bold text-white">{valSummary.pass}</span>
              <span className="text-slate-500 text-sm"> / {valSummary.total}</span>
            </div>
            <div className="w-full bg-slate-700 rounded-full h-2 mb-3 overflow-hidden">
              <div
                className="bg-emerald-500 h-2 rounded-full transition-all duration-500"
                style={{ width: `${passPct}%` }}
              />
            </div>
            <div className="grid grid-cols-3 gap-1 text-center">
              {[
                ["PASS", valSummary.pass, "text-emerald-400 bg-emerald-500/10"],
                ["WARN", valSummary.warn, "text-amber-400 bg-amber-500/10"],
                ["FAIL", valSummary.fail, "text-red-400 bg-red-500/10"],
              ].map(([lbl, val, cls]) => (
                <div key={lbl as string} className={cn("rounded p-1.5", cls as string)}>
                  <div className="text-sm font-bold">{val}</div>
                  <div className="text-xs text-slate-500">{lbl}</div>
                </div>
              ))}
            </div>
          </div>

          {/* GG LAG */}
          <div className="bg-slate-800 rounded-lg border border-slate-700 p-4">
            <h2 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">
              GG LAG (현재)
            </h2>
            <div className="text-center py-2">
              <span className="text-4xl font-mono font-bold text-slate-400">--</span>
              <span className="text-slate-500 text-sm ml-1">초</span>
            </div>
            <div className="mt-2 flex items-center gap-1 text-xs text-slate-500">
              <div className="flex-1 h-px bg-slate-700" />
              <span className="text-red-500">임계 30초</span>
              <div className="flex-1 h-px bg-red-900" />
            </div>
            <p className="text-xs text-slate-600 text-center mt-2">
              GG Monitor에서 실시간 확인
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
