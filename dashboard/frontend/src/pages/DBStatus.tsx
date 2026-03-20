import { useEffect, useState, useCallback } from "react";
import {
  Database,
  RefreshCw,
  CheckCircle2,
  XCircle,
  AlertTriangle,
} from "lucide-react";
import { cn } from "../lib/utils";
import api from "../hooks/useApi";

// ─── Types ───────────────────────────────────────────────────────────────────

interface ParamRow {
  param: string;
  source_value: string | null;
  target_value: string | null;
  match: boolean;
}

interface SessionCount {
  source: number | null;
  target: number | null;
  recorded_at: string;
}

interface SchemaDiffRow {
  object_type: string;
  source_count: number | null;
  target_count: number | null;
  diff: number | null;
}

type ConnStatus = "ok" | "error" | "checking" | "unknown";

// ─── Connection status deduction ─────────────────────────────────────────────

function deriveConnStatus(params: ParamRow[], side: "source" | "target"): ConnStatus {
  if (params.length === 0) return "unknown";
  const valField = side === "source" ? "source_value" : "target_value";
  const hasError = params.every((p) => p[valField] === "연결 오류" || p[valField] === null);
  const hasAny = params.some((p) => p[valField] !== null && p[valField] !== "연결 오류");
  if (hasAny) return "ok";
  if (hasError) return "error";
  return "unknown";
}

// ─── Subcomponents ────────────────────────────────────────────────────────────

function ConnectionCard({
  label,
  host,
  status,
  checkedAt,
}: {
  label: string;
  host: string;
  status: ConnStatus;
  checkedAt: string;
}) {
  const statusConfig: Record<ConnStatus, { color: string; bg: string; icon: React.ReactNode; text: string }> = {
    ok: {
      color: "text-emerald-400",
      bg: "bg-emerald-500/10 border-emerald-500/30",
      icon: <CheckCircle2 className="w-4 h-4 text-emerald-400" />,
      text: "연결됨",
    },
    error: {
      color: "text-red-400",
      bg: "bg-red-500/10 border-red-500/30",
      icon: <XCircle className="w-4 h-4 text-red-400" />,
      text: "연결 오류",
    },
    checking: {
      color: "text-amber-400",
      bg: "bg-amber-500/10 border-amber-500/30",
      icon: <div className="w-4 h-4 border-2 border-amber-400 border-t-transparent rounded-full animate-spin" />,
      text: "확인 중",
    },
    unknown: {
      color: "text-slate-400",
      bg: "bg-slate-700/50 border-slate-600",
      icon: <Database className="w-4 h-4 text-slate-400" />,
      text: "미확인",
    },
  };

  const cfg = statusConfig[status];

  return (
    <div className={cn("flex-1 rounded-lg border p-4", cfg.bg)}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-slate-300 font-medium text-sm">{label}</span>
        <div className="flex items-center gap-1.5">
          {cfg.icon}
          <span className={cn("text-xs font-medium", cfg.color)}>{cfg.text}</span>
        </div>
      </div>
      <p className="text-slate-400 text-xs font-mono truncate">{host || "미설정"}</p>
      {checkedAt && (
        <p className="text-slate-600 text-xs mt-1">
          확인: {new Date(checkedAt).toLocaleString("ko-KR")}
        </p>
      )}
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-slate-300 font-medium text-sm mb-3">{children}</h2>
  );
}

// ─── Main Component ───────────────────────────────────────────────────────────

export default function DBStatus() {
  const [params, setParams] = useState<ParamRow[]>([]);
  const [sessions, setSessions] = useState<SessionCount | null>(null);
  const [schemaDiff, setSchemaDiff] = useState<SchemaDiffRow[]>([]);
  const [paramsLoading, setParamsLoading] = useState(false);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [schemaLoading, setSchemaLoading] = useState(false);
  const [lastChecked, setLastChecked] = useState<string>("");

  const mismatchCount = params.filter((p) => !p.match).length;

  const fetchParams = useCallback(async () => {
    setParamsLoading(true);
    try {
      const res = await api.get<ParamRow[]>("/db/compare");
      setParams(res.data);
      setLastChecked(new Date().toISOString());
    } catch {
      // keep previous state
    } finally {
      setParamsLoading(false);
    }
  }, []);

  const fetchSessions = useCallback(async () => {
    setSessionsLoading(true);
    try {
      const res = await api.get<SessionCount>("/db/session-count");
      setSessions(res.data);
    } catch {
      // keep previous state
    } finally {
      setSessionsLoading(false);
    }
  }, []);

  const fetchSchema = useCallback(async () => {
    setSchemaLoading(true);
    try {
      const res = await api.get<SchemaDiffRow[]>("/db/schema-diff");
      setSchemaDiff(res.data);
    } catch {
      // keep previous state
    } finally {
      setSchemaLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchParams();
    fetchSessions();
    fetchSchema();
  }, [fetchParams, fetchSessions, fetchSchema]);

  const srcStatus = deriveConnStatus(params, "source");
  const tgtStatus = deriveConnStatus(params, "target");

  return (
    <div className="space-y-5">
      {/* 제목 */}
      <div className="flex items-center gap-3">
        <Database className="w-5 h-5 text-blue-400" />
        <h1 className="text-white font-semibold text-lg">DB Status</h1>
        {mismatchCount > 0 && (
          <span className="flex items-center gap-1 px-2 py-0.5 bg-red-500/20 text-red-400 border border-red-500/40 rounded-full text-xs font-semibold">
            <AlertTriangle className="w-3 h-3" />
            {mismatchCount}개 불일치
          </span>
        )}
      </div>

      {/* 연결 상태 카드 */}
      <div className="flex gap-4">
        <ConnectionCard
          label="Source (AWS RDS Oracle SE)"
          host={import.meta.env.VITE_SRC_HOST || ""}
          status={paramsLoading ? "checking" : srcStatus}
          checkedAt={lastChecked}
        />
        <ConnectionCard
          label="Target (OCI DBCS Oracle SE)"
          host={import.meta.env.VITE_TGT_HOST || ""}
          status={paramsLoading ? "checking" : tgtStatus}
          checkedAt={lastChecked}
        />
      </div>

      {/* 파라미터 비교 테이블 */}
      <div className="bg-slate-800 border border-slate-700 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <SectionTitle>파라미터 비교</SectionTitle>
          <button
            onClick={fetchParams}
            disabled={paramsLoading}
            className="flex items-center gap-1.5 text-xs text-slate-400 hover:text-white bg-slate-700 hover:bg-slate-600 px-2.5 py-1 rounded transition-colors disabled:opacity-50"
          >
            <RefreshCw className={cn("w-3 h-3", paramsLoading && "animate-spin")} />
            새로고침
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="border-b border-slate-700">
                <th className="text-left text-slate-400 font-medium px-3 py-2 text-xs">파라미터</th>
                <th className="text-left text-slate-400 font-medium px-3 py-2 text-xs">Source 값</th>
                <th className="text-left text-slate-400 font-medium px-3 py-2 text-xs">Target 값</th>
                <th className="text-center text-slate-400 font-medium px-3 py-2 text-xs">일치</th>
              </tr>
            </thead>
            <tbody>
              {params.length === 0 && paramsLoading ? (
                <tr>
                  <td colSpan={4} className="text-center text-slate-500 py-8 text-xs">
                    <div className="flex items-center justify-center gap-2">
                      <div className="w-4 h-4 border-2 border-slate-500 border-t-blue-400 rounded-full animate-spin" />
                      조회 중...
                    </div>
                  </td>
                </tr>
              ) : (
                params.map((row) => (
                  <tr
                    key={row.param}
                    className={cn(
                      "border-b border-slate-700/50 hover:bg-slate-700/30 transition-colors",
                      !row.match && "bg-red-500/5"
                    )}
                  >
                    <td className="px-3 py-2 font-mono text-xs text-slate-300">
                      {row.param}
                    </td>
                    <td
                      className={cn(
                        "px-3 py-2 font-mono text-xs",
                        row.source_value === "연결 오류"
                          ? "text-red-400"
                          : "text-slate-200"
                      )}
                    >
                      {row.source_value ?? "—"}
                    </td>
                    <td
                      className={cn(
                        "px-3 py-2 font-mono text-xs",
                        row.target_value === "연결 오류"
                          ? "text-red-400"
                          : "text-slate-200"
                      )}
                    >
                      {row.target_value ?? "—"}
                    </td>
                    <td className="px-3 py-2 text-center">
                      {row.match ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-400 mx-auto" />
                      ) : (
                        <XCircle className="w-4 h-4 text-red-400 mx-auto" />
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* 하단 2열 */}
      <div className="flex gap-4">
        {/* Schema Diff */}
        <div className="flex-1 bg-slate-800 border border-slate-700 rounded-lg p-4">
          <div className="flex items-center justify-between mb-3">
            <SectionTitle>Schema Diff</SectionTitle>
            <button
              onClick={fetchSchema}
              disabled={schemaLoading}
              className="flex items-center gap-1.5 text-xs text-slate-400 hover:text-white bg-slate-700 hover:bg-slate-600 px-2.5 py-1 rounded transition-colors disabled:opacity-50"
            >
              <RefreshCw className={cn("w-3 h-3", schemaLoading && "animate-spin")} />
              새로고침
            </button>
          </div>
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="border-b border-slate-700">
                <th className="text-left text-slate-400 font-medium px-2 py-2 text-xs">오브젝트</th>
                <th className="text-right text-slate-400 font-medium px-2 py-2 text-xs">Source</th>
                <th className="text-right text-slate-400 font-medium px-2 py-2 text-xs">Target</th>
                <th className="text-right text-slate-400 font-medium px-2 py-2 text-xs">차이</th>
              </tr>
            </thead>
            <tbody>
              {schemaDiff.length === 0 && schemaLoading ? (
                <tr>
                  <td colSpan={4} className="text-center text-slate-500 py-6 text-xs">
                    <div className="flex items-center justify-center gap-2">
                      <div className="w-4 h-4 border-2 border-slate-500 border-t-blue-400 rounded-full animate-spin" />
                      조회 중...
                    </div>
                  </td>
                </tr>
              ) : (
                schemaDiff.map((row) => {
                  const hasDiff = row.diff !== null && row.diff !== 0;
                  return (
                    <tr
                      key={row.object_type}
                      className={cn(
                        "border-b border-slate-700/50 hover:bg-slate-700/30 transition-colors",
                        hasDiff && "bg-red-500/5"
                      )}
                    >
                      <td className="px-2 py-2 text-xs text-slate-300 font-mono">
                        {row.object_type}
                      </td>
                      <td className="px-2 py-2 text-xs text-right text-slate-200">
                        {row.source_count ?? "—"}
                      </td>
                      <td className="px-2 py-2 text-xs text-right text-slate-200">
                        {row.target_count ?? "—"}
                      </td>
                      <td
                        className={cn(
                          "px-2 py-2 text-xs text-right font-semibold",
                          row.diff === null
                            ? "text-slate-500"
                            : row.diff === 0
                            ? "text-emerald-400"
                            : "text-red-400"
                        )}
                      >
                        {row.diff !== null
                          ? row.diff > 0
                            ? `+${row.diff}`
                            : row.diff
                          : "—"}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {/* 활성 세션 */}
        <div className="w-64 bg-slate-800 border border-slate-700 rounded-lg p-4 flex flex-col">
          <div className="flex items-center justify-between mb-3 shrink-0">
            <SectionTitle>활성 세션</SectionTitle>
            <button
              onClick={fetchSessions}
              disabled={sessionsLoading}
              className="flex items-center gap-1.5 text-xs text-slate-400 hover:text-white bg-slate-700 hover:bg-slate-600 px-2.5 py-1 rounded transition-colors disabled:opacity-50"
            >
              <RefreshCw className={cn("w-3 h-3", sessionsLoading && "animate-spin")} />
              새로고침
            </button>
          </div>

          <div className="flex-1 flex flex-col gap-4 justify-center">
            {/* Source */}
            <div className="text-center p-4 bg-slate-900 rounded-lg border border-slate-700">
              <p className="text-slate-500 text-xs mb-1">Source (RDS)</p>
              {sessionsLoading ? (
                <div className="w-6 h-6 border-2 border-slate-500 border-t-blue-400 rounded-full animate-spin mx-auto" />
              ) : (
                <p
                  className={cn(
                    "text-4xl font-bold",
                    sessions?.source === null ? "text-slate-500" : "text-white"
                  )}
                >
                  {sessions?.source ?? "—"}
                </p>
              )}
            </div>

            {/* Target */}
            <div className="text-center p-4 bg-slate-900 rounded-lg border border-slate-700">
              <p className="text-slate-500 text-xs mb-1">Target (DBCS)</p>
              {sessionsLoading ? (
                <div className="w-6 h-6 border-2 border-slate-500 border-t-blue-400 rounded-full animate-spin mx-auto" />
              ) : (
                <p
                  className={cn(
                    "text-4xl font-bold",
                    sessions?.target === null ? "text-slate-500" : "text-white"
                  )}
                >
                  {sessions?.target ?? "—"}
                </p>
              )}
            </div>
          </div>

          {sessions?.recorded_at && (
            <p className="text-slate-600 text-xs text-center mt-2 shrink-0">
              {new Date(sessions.recorded_at).toLocaleString("ko-KR")}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
