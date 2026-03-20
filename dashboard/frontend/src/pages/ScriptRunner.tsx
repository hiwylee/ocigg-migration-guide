import { useCallback, useEffect, useState } from "react";
import {
  FileCode,
  Lock,
  AlertTriangle,
  ChevronRight,
  Clock,
  CheckCircle2,
  XCircle,
  Minus,
} from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";
import LogStreamer from "../components/LogStreamer";

// ---------------------------------------------------------------------------
// 타입
// ---------------------------------------------------------------------------

type RiskLevel = "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";

interface LastRun {
  status: string;
  finished_at: string | null;
}

interface Script {
  id: string;
  path: string;
  phase: number;
  risk_level: RiskLevel;
  role: string;
  available: boolean;
  last_run: LastRun | null;
}

// ---------------------------------------------------------------------------
// 상수 / 유틸
// ---------------------------------------------------------------------------

const RISK_BADGE: Record<RiskLevel, string> = {
  LOW:      "bg-slate-600 text-slate-200",
  MEDIUM:   "bg-blue-600 text-blue-100",
  HIGH:     "bg-amber-600 text-amber-100",
  CRITICAL: "bg-red-600 text-red-100",
};

const ROLE_LABEL: Record<string, string> = {
  src_dba:          "소스 DBA",
  tgt_dba:          "타겟 DBA",
  gg_operator:      "GG 담당자",
  migration_leader: "마이그레이션 리더",
};

const PHASE_LABELS: Record<number, string> = {
  0: "P0: 적합성 점검",
  1: "P1: 소스 DB 준비",
  2: "P2: 타겟 DB 준비",
  3: "P3: GoldenGate 구성",
  4: "P4: 초기 데이터 적재",
  5: "P5: 델타 동기화",
  6: "P6: 검증",
  7: "P7: Cut-over",
  8: "P8: 안정화",
};

function shortName(path: string): string {
  return path.split("/").pop() ?? path;
}

function formatDate(iso: string | null | undefined): string {
  if (!iso) return "";
  try {
    return new Date(iso).toLocaleString("ko-KR", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return iso;
  }
}

// ---------------------------------------------------------------------------
// 서브 컴포넌트: 마지막 실행 결과 배지
// ---------------------------------------------------------------------------

function LastRunBadge({ lastRun }: { lastRun: LastRun | null }) {
  if (!lastRun) {
    return (
      <span className="flex items-center gap-0.5 text-xs text-slate-500">
        <Minus className="w-3 h-3" /> 미실행
      </span>
    );
  }
  const { status } = lastRun;
  if (status === "success")
    return (
      <span className="flex items-center gap-0.5 text-xs text-emerald-400">
        <CheckCircle2 className="w-3 h-3" /> PASS
      </span>
    );
  if (status === "running")
    return (
      <span className="flex items-center gap-0.5 text-xs text-blue-400">
        <Clock className="w-3 h-3 animate-pulse" /> 실행 중
      </span>
    );
  if (status === "killed")
    return (
      <span className="flex items-center gap-0.5 text-xs text-amber-400">
        <AlertTriangle className="w-3 h-3" /> 종료됨
      </span>
    );
  return (
    <span className="flex items-center gap-0.5 text-xs text-red-400">
      <XCircle className="w-3 h-3" /> FAIL
    </span>
  );
}

// ---------------------------------------------------------------------------
// 서브 컴포넌트: 스크립트 카드
// ---------------------------------------------------------------------------

interface ScriptCardProps {
  script: Script;
  selected: boolean;
  locked: boolean;
  onClick: () => void;
}

function ScriptCard({ script, selected, locked, onClick }: ScriptCardProps) {
  return (
    <button
      onClick={onClick}
      disabled={locked && !selected}
      className={cn(
        "w-full text-left px-3 py-2.5 rounded-lg border transition-all",
        selected
          ? "bg-slate-700 border-blue-500"
          : "bg-slate-800 border-slate-700 hover:border-slate-500",
        !script.available && "opacity-50",
        locked && !selected && "cursor-not-allowed opacity-40"
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <FileCode className="w-3.5 h-3.5 text-slate-400 shrink-0" />
          <span
            className={cn(
              "text-xs font-mono truncate",
              selected ? "text-white" : "text-slate-300"
            )}
          >
            {shortName(script.path)}
          </span>
        </div>
        <span
          className={cn(
            "shrink-0 text-[10px] font-semibold px-1.5 py-0.5 rounded uppercase tracking-wide",
            RISK_BADGE[script.risk_level]
          )}
        >
          {script.risk_level}
        </span>
      </div>

      <div className="mt-1.5 flex items-center justify-between gap-2">
        <LastRunBadge lastRun={script.last_run} />
        {script.last_run?.finished_at && (
          <span className="text-[10px] text-slate-600 shrink-0">
            {formatDate(script.last_run.finished_at)}
          </span>
        )}
        {!script.available && (
          <span className="text-[10px] text-red-500 shrink-0">파일 없음</span>
        )}
      </div>
    </button>
  );
}

// ---------------------------------------------------------------------------
// 메인 컴포넌트
// ---------------------------------------------------------------------------

export default function ScriptRunner() {
  // 데이터
  const [scripts, setScripts] = useState<Script[]>([]);
  const [loading, setLoading] = useState(true);
  const [currentPhase, setCurrentPhase] = useState<number>(0);

  // 필터
  const [filterPhase, setFilterPhase] = useState<string>("");
  const [filterRole, setFilterRole] = useState<string>("");
  const [filterRisk, setFilterRisk] = useState<string>("");

  // 선택/실행 상태
  const [selected, setSelected] = useState<Script | null>(null);
  const [reason, setReason] = useState("");
  const [confirmToken, setConfirmToken] = useState("");
  const [isRunning, setIsRunning] = useState(false);
  const [showLog, setShowLog] = useState(false);
  const [wsKey, setWsKey] = useState(0); // LogStreamer 재마운트용

  // ---------------------------------------------------------------------------
  // 데이터 로드
  // ---------------------------------------------------------------------------

  const loadScripts = useCallback(async () => {
    try {
      const params: Record<string, string> = {};
      if (filterPhase) params.phase = filterPhase;
      if (filterRole) params.role = filterRole;
      if (filterRisk) params.risk = filterRisk;

      const res = await api.get<Script[]>("/scripts", { params });
      setScripts(res.data);
    } catch {
      // ignore
    } finally {
      setLoading(false);
    }
  }, [filterPhase, filterRole, filterRisk]);

  const loadCurrentPhase = useCallback(async () => {
    try {
      const res = await api.get<Array<{ key: string; value: string }>>("/config");
      const cp =
        parseInt(
          res.data.find((e) => e.key === "CURRENT_PHASE")?.value ?? "0"
        ) || 0;
      setCurrentPhase(cp);
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    loadCurrentPhase();
  }, [loadCurrentPhase]);

  useEffect(() => {
    setLoading(true);
    loadScripts();
  }, [loadScripts]);

  // ---------------------------------------------------------------------------
  // 필터 결과
  // ---------------------------------------------------------------------------

  const currentPhaseScripts = scripts.filter(
    (s) => s.phase === currentPhase && !filterPhase
  );
  const otherScripts = scripts.filter(
    (s) => filterPhase || s.phase !== currentPhase
  );

  // ---------------------------------------------------------------------------
  // 실행 핸들러
  // ---------------------------------------------------------------------------

  function handleRun() {
    if (!selected) return;
    setShowLog(true);
    setIsRunning(true);
    setWsKey((k) => k + 1);
  }

  function handleComplete(exitCode: number) {
    setIsRunning(false);
    // 목록 갱신 (마지막 실행 결과 반영)
    setTimeout(() => loadScripts(), 500);
    // 실패 시에도 표시 유지
    if (exitCode !== 0) {
      // 로그는 유지
    }
  }

  function handleError(msg: string) {
    setIsRunning(false);
    console.error("Script error:", msg);
  }

  function handleSelectScript(script: Script) {
    if (isRunning) return;
    setSelected(script);
    setReason("");
    setConfirmToken("");
    setShowLog(false);
  }

  // ---------------------------------------------------------------------------
  // WS URL
  // ---------------------------------------------------------------------------

  const wsUrl = selected
    ? `ws://${window.location.host}/api/scripts/${selected.id}/run`
    : "";

  const wsPayload = {
    reason,
    confirm_token: confirmToken,
  };

  // ---------------------------------------------------------------------------
  // 실행 버튼 활성화 조건
  // ---------------------------------------------------------------------------

  function canRun(): boolean {
    if (!selected || !selected.available || isRunning) return false;
    if (
      (selected.risk_level === "HIGH" || selected.risk_level === "CRITICAL") &&
      !reason.trim()
    )
      return false;
    if (selected.risk_level === "CRITICAL" && !confirmToken.trim()) return false;
    return true;
  }

  // ---------------------------------------------------------------------------
  // 렌더
  // ---------------------------------------------------------------------------

  return (
    <div className="h-full flex flex-col gap-4 max-w-7xl">
      {/* 헤더 */}
      <div>
        <h1 className="text-xl font-bold text-white">Script Runner</h1>
        <p className="text-slate-400 text-sm">
          마이그레이션 단계별 스크립트 실행 및 로그 스트리밍
        </p>
      </div>

      {/* 메인 2열 레이아웃 */}
      <div className="flex gap-4 flex-1 min-h-0">
        {/* ------------------------------------------------------------------ */}
        {/* 좌측: 스크립트 목록 (40%)                                          */}
        {/* ------------------------------------------------------------------ */}
        <div className="w-[40%] flex flex-col gap-3 min-h-0">
          {/* 필터 */}
          <div className="bg-slate-800 border border-slate-700 rounded-lg p-3 space-y-2 shrink-0">
            <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
              필터
            </p>
            <div className="grid grid-cols-3 gap-2">
              {/* Phase 필터 */}
              <select
                value={filterPhase}
                onChange={(e) => setFilterPhase(e.target.value)}
                className="text-xs bg-slate-700 border border-slate-600 text-slate-200 rounded px-2 py-1 focus:outline-none focus:border-blue-500"
              >
                <option value="">전체 Phase</option>
                {Object.entries(PHASE_LABELS).map(([no, label]) => (
                  <option key={no} value={no}>
                    {label}
                  </option>
                ))}
              </select>

              {/* Role 필터 */}
              <select
                value={filterRole}
                onChange={(e) => setFilterRole(e.target.value)}
                className="text-xs bg-slate-700 border border-slate-600 text-slate-200 rounded px-2 py-1 focus:outline-none focus:border-blue-500"
              >
                <option value="">전체 역할</option>
                {Object.entries(ROLE_LABEL).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>

              {/* Risk 필터 */}
              <select
                value={filterRisk}
                onChange={(e) => setFilterRisk(e.target.value)}
                className="text-xs bg-slate-700 border border-slate-600 text-slate-200 rounded px-2 py-1 focus:outline-none focus:border-blue-500"
              >
                <option value="">전체 Risk</option>
                <option value="LOW">LOW</option>
                <option value="MEDIUM">MEDIUM</option>
                <option value="HIGH">HIGH</option>
                <option value="CRITICAL">CRITICAL</option>
              </select>
            </div>
          </div>

          {/* 스크립트 목록 */}
          <div className="flex-1 overflow-y-auto space-y-3 pr-1">
            {loading ? (
              <div className="text-center text-slate-500 text-sm py-8">
                로딩 중...
              </div>
            ) : (
              <>
                {/* 현재 Phase 섹션 (필터 없을 때만) */}
                {!filterPhase && currentPhaseScripts.length > 0 && (
                  <div>
                    <div className="flex items-center gap-2 mb-2">
                      <ChevronRight className="w-3.5 h-3.5 text-amber-400" />
                      <p className="text-xs font-semibold text-amber-400 uppercase tracking-wider">
                        지금 실행할 스크립트 — {PHASE_LABELS[currentPhase]}
                      </p>
                    </div>
                    <div className="space-y-1.5 pl-1 border-l-2 border-amber-500/30">
                      {currentPhaseScripts.map((s) => (
                        <ScriptCard
                          key={s.id}
                          script={s}
                          selected={selected?.id === s.id}
                          locked={isRunning}
                          onClick={() => handleSelectScript(s)}
                        />
                      ))}
                    </div>
                  </div>
                )}

                {/* 나머지 스크립트 */}
                {otherScripts.length > 0 && (
                  <div>
                    {!filterPhase && currentPhaseScripts.length > 0 && (
                      <p className="text-xs text-slate-500 uppercase tracking-wider mb-2 ml-1">
                        기타 스크립트
                      </p>
                    )}
                    <div className="space-y-1.5">
                      {otherScripts.map((s) => (
                        <ScriptCard
                          key={s.id}
                          script={s}
                          selected={selected?.id === s.id}
                          locked={isRunning}
                          onClick={() => handleSelectScript(s)}
                        />
                      ))}
                    </div>
                  </div>
                )}

                {scripts.length === 0 && (
                  <div className="text-center text-slate-500 text-sm py-8">
                    조건에 맞는 스크립트가 없습니다
                  </div>
                )}
              </>
            )}
          </div>
        </div>

        {/* ------------------------------------------------------------------ */}
        {/* 우측: 실행 패널 (60%)                                              */}
        {/* ------------------------------------------------------------------ */}
        <div className="flex-1 min-h-0 flex flex-col gap-3">
          {!selected ? (
            <div className="flex-1 flex items-center justify-center bg-slate-800 border border-slate-700 rounded-lg">
              <div className="text-center text-slate-500">
                <FileCode className="w-10 h-10 mx-auto mb-3 opacity-30" />
                <p className="text-sm">좌측에서 스크립트를 선택하세요</p>
              </div>
            </div>
          ) : (
            <>
              {/* 스크립트 정보 */}
              <div className="bg-slate-800 border border-slate-700 rounded-lg p-4 shrink-0">
                <div className="flex items-start justify-between gap-2 mb-3">
                  <div className="min-w-0">
                    <p className="text-xs text-slate-400 mb-0.5">선택된 스크립트</p>
                    <p className="text-sm font-mono text-white break-all">{selected.path}</p>
                  </div>
                  {isRunning && (
                    <div className="shrink-0 flex items-center gap-1 text-xs text-amber-400 bg-amber-500/10 border border-amber-500/30 px-2 py-1 rounded">
                      <Lock className="w-3 h-3" /> 실행 중
                    </div>
                  )}
                </div>

                <div className="grid grid-cols-3 gap-3">
                  <div>
                    <p className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">
                      Phase
                    </p>
                    <p className="text-xs text-slate-300">
                      {PHASE_LABELS[selected.phase] ?? `P${selected.phase}`}
                    </p>
                  </div>
                  <div>
                    <p className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">
                      Risk
                    </p>
                    <span
                      className={cn(
                        "text-[10px] font-semibold px-1.5 py-0.5 rounded uppercase",
                        RISK_BADGE[selected.risk_level]
                      )}
                    >
                      {selected.risk_level}
                    </span>
                  </div>
                  <div>
                    <p className="text-[10px] text-slate-500 uppercase tracking-wider mb-1">
                      담당 역할
                    </p>
                    <p className="text-xs text-slate-300">
                      {ROLE_LABEL[selected.role] ?? selected.role}
                    </p>
                  </div>
                </div>

                {!selected.available && (
                  <div className="mt-3 flex items-center gap-1.5 text-xs text-red-400 bg-red-500/10 border border-red-500/20 rounded px-2 py-1.5">
                    <AlertTriangle className="w-3.5 h-3.5 shrink-0" />
                    스크립트 파일이 서버에 존재하지 않습니다
                  </div>
                )}
              </div>

              {/* 실행 설정 */}
              <div className="bg-slate-800 border border-slate-700 rounded-lg p-4 shrink-0 space-y-3">
                {/* HIGH / CRITICAL: 실행 사유 */}
                {(selected.risk_level === "HIGH" ||
                  selected.risk_level === "CRITICAL") && (
                  <div>
                    <label className="block text-xs text-slate-400 mb-1">
                      실행 사유{" "}
                      <span className="text-red-400">*</span>
                      <span className="text-slate-500 ml-1">
                        (HIGH 이상 필수)
                      </span>
                    </label>
                    <textarea
                      rows={2}
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                      disabled={isRunning}
                      placeholder="실행 사유를 입력하세요..."
                      className="w-full text-xs bg-slate-700 border border-slate-600 text-slate-200 rounded px-2 py-1.5 resize-none focus:outline-none focus:border-blue-500 disabled:opacity-50 placeholder-slate-500"
                    />
                  </div>
                )}

                {/* CRITICAL: 승인 코드 */}
                {selected.risk_level === "CRITICAL" && (
                  <div>
                    <label className="block text-xs text-slate-400 mb-1">
                      Cut-over 승인 코드{" "}
                      <span className="text-red-400">*</span>
                    </label>
                    <input
                      type="password"
                      value={confirmToken}
                      onChange={(e) => setConfirmToken(e.target.value)}
                      disabled={isRunning}
                      placeholder="승인 코드를 입력하세요"
                      className="w-full text-xs bg-slate-700 border border-slate-600 text-slate-200 rounded px-2 py-1.5 focus:outline-none focus:border-red-500 disabled:opacity-50 placeholder-slate-500"
                    />
                  </div>
                )}

                {/* 실행 버튼 */}
                <button
                  onClick={handleRun}
                  disabled={!canRun()}
                  className={cn(
                    "w-full text-sm font-semibold py-2 rounded transition",
                    canRun()
                      ? selected.risk_level === "CRITICAL"
                        ? "bg-red-700 hover:bg-red-600 text-white"
                        : selected.risk_level === "HIGH"
                        ? "bg-amber-700 hover:bg-amber-600 text-white"
                        : "bg-blue-700 hover:bg-blue-600 text-white"
                      : "bg-slate-700 text-slate-500 cursor-not-allowed"
                  )}
                >
                  {isRunning ? "실행 중..." : "실행"}
                </button>
              </div>

              {/* 로그 스트리머 */}
              {showLog && (
                <div className="flex-1 min-h-0 bg-slate-800 border border-slate-700 rounded-lg p-4 flex flex-col gap-2 overflow-hidden">
                  <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider shrink-0">
                    실행 로그
                  </p>
                  <div className="flex-1 min-h-0">
                    <LogStreamer
                      key={wsKey}
                      scriptId={selected.id}
                      wsUrl={wsUrl}
                      payload={wsPayload}
                      onComplete={handleComplete}
                      onError={handleError}
                      autoScroll
                    />
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
