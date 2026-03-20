import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { RotateCcw, AlertTriangle, Clock, ArrowLeft } from "lucide-react";
import api from "../hooks/useApi";

const RETAIN_DAYS = 14;

function useCountdown(rollbackAt: string | null) {
  const [remaining, setRemaining] = useState<number | null>(null);
  useEffect(() => {
    if (!rollbackAt) return;
    const tick = () => {
      const deadline = new Date(rollbackAt + "Z").getTime() + RETAIN_DAYS * 86400 * 1000;
      setRemaining(Math.max(0, Math.floor((deadline - Date.now()) / 1000)));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [rollbackAt]);
  return remaining;
}

function formatCountdown(secs: number) {
  const d = Math.floor(secs / 86400);
  const h = Math.floor((secs % 86400) / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  return `${d}일 ${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

interface RollbackState {
  rollback_started_at: string | null;
  rollback_reason: string | null;
}

export default function RollbackConsole() {
  const navigate = useNavigate();
  const [state, setState] = useState<RollbackState | null>(null);
  const [reason, setReason] = useState("");
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const remaining = useCountdown(state?.rollback_started_at ?? null);

  useEffect(() => {
    api.get<{ rollback_started_at: string | null; rollback_reason: string | null }>("/cutover/status")
      .then((r) => setState({ rollback_started_at: r.data.rollback_started_at, rollback_reason: r.data.rollback_reason }))
      .finally(() => setLoading(false));
  }, []);

  const startRollback = async () => {
    if (!reason.trim()) return;
    if (!window.confirm("롤백을 시작합니다. 이 작업은 취소할 수 없습니다. 계속하시겠습니까?")) return;
    setSubmitting(true);
    try {
      await api.post("/cutover/rollback", { reason: reason.trim() });
      const r = await api.get<RollbackState>("/cutover/status");
      setState({ rollback_started_at: r.data.rollback_started_at, rollback_reason: r.data.rollback_reason });
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) return <div className="p-6 text-slate-400">로딩 중...</div>;

  return (
    <div className="p-6 space-y-6 max-w-2xl">
      <div className="flex items-center gap-3">
        <button onClick={() => navigate("/cutover")} className="text-slate-400 hover:text-white">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <RotateCcw className="w-6 h-6 text-red-400" />
        <h1 className="text-xl font-bold text-white">롤백 콘솔</h1>
      </div>

      {/* Warning banner */}
      <div className="bg-red-900/30 border border-red-600 rounded-lg p-4 flex gap-3">
        <AlertTriangle className="w-5 h-5 text-red-400 shrink-0 mt-0.5" />
        <div>
          <p className="text-red-300 font-semibold text-sm">롤백 주의사항</p>
          <ul className="text-red-400 text-sm mt-2 space-y-1 list-disc list-inside">
            <li>소스 AWS RDS 인스턴스로 연결을 복원합니다</li>
            <li>타겟 OCI DBCS에 기록된 데이터는 손실될 수 있습니다</li>
            <li>GoldenGate 프로세스를 모두 중지합니다</li>
            <li>모든 애플리케이션 연결을 소스 DB로 전환합니다</li>
          </ul>
        </div>
      </div>

      {state?.rollback_started_at ? (
        // Rollback in progress
        <div className="space-y-6">
          <div className="bg-slate-800 rounded-lg p-5">
            <p className="text-slate-400 text-sm">롤백 시작 시각</p>
            <p className="text-white font-mono text-lg mt-1">
              {state.rollback_started_at.slice(0, 19).replace("T", " ")} UTC
            </p>
          </div>
          <div className="bg-slate-800 rounded-lg p-5">
            <p className="text-slate-400 text-sm">롤백 사유</p>
            <p className="text-white mt-1">{state.rollback_reason}</p>
          </div>
          <div className="bg-slate-800 rounded-lg p-5">
            <div className="flex items-center gap-2 mb-3">
              <Clock className="w-4 h-4 text-amber-400" />
              <p className="text-sm font-medium text-slate-300">
                소스 RDS 인스턴스 유지 기간 ({RETAIN_DAYS}일)
              </p>
            </div>
            {remaining !== null && (
              <p className={`text-3xl font-mono font-bold ${remaining < 86400 ? "text-red-400" : "text-amber-400"}`}>
                {formatCountdown(remaining)}
              </p>
            )}
            <p className="text-slate-500 text-xs mt-2">
              기간 내 소스 RDS 인스턴스를 삭제하지 마십시오
            </p>
          </div>

          <div className="bg-slate-800 rounded-lg p-5 space-y-2">
            <p className="text-sm font-medium text-slate-300 mb-3">롤백 체크리스트</p>
            {ROLLBACK_STEPS.map((s, i) => (
              <div key={i} className="flex items-start gap-3 text-sm text-slate-300">
                <span className="text-slate-500 w-5 text-right shrink-0">{i + 1}.</span>
                <span>{s}</span>
              </div>
            ))}
          </div>
        </div>
      ) : (
        // Rollback form
        <div className="bg-slate-800 rounded-lg p-5 space-y-4">
          <p className="text-sm font-medium text-slate-300">롤백 사유 입력</p>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="롤백을 결정한 사유를 상세히 입력하십시오..."
            rows={4}
            className="w-full bg-slate-700 border border-slate-600 rounded px-3 py-2 text-white text-sm placeholder-slate-500 focus:outline-none focus:border-blue-500 resize-none"
          />
          <button
            onClick={startRollback}
            disabled={!reason.trim() || submitting}
            className="w-full py-3 bg-red-600 hover:bg-red-700 disabled:bg-slate-600 disabled:text-slate-500 text-white rounded-lg font-semibold text-sm transition-colors"
          >
            {submitting ? "처리 중..." : "롤백 시작 확인"}
          </button>
        </div>
      )}
    </div>
  );
}

const ROLLBACK_STEPS = [
  "GoldenGate Extract / Pump / Replicat 중지",
  "애플리케이션 연결 문자열을 소스 RDS로 복원",
  "소스 RDS 보안그룹 인바운드 1521 포트 재오픈",
  "소스 DBMS_JOB BROKEN 해제 (필요 시)",
  "애플리케이션 기동 및 정상 동작 확인",
  "타겟 DBCS 접근 차단 (데이터 불일치 방지)",
  "롤백 완료 보고 및 원인 분석 착수",
];
