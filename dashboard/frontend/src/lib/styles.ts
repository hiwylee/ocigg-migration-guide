// Centralised Tailwind badge/style constants shared across pages.

// GoldenGate process status (RUNNING / STOPPED / ABEND / UNKNOWN)
export const STATUS_BADGE: Record<string, string> = {
  RUNNING: "bg-emerald-500/20 border border-emerald-500/40 text-emerald-400",
  STOPPED: "bg-amber-500/20 border border-amber-500/40 text-amber-400",
  ABEND:   "bg-red-500/20 border border-red-500/40 text-red-400",
  UNKNOWN: "bg-slate-700 border border-slate-600 text-slate-400",
};

// Validation item status (PASS / WARN / FAIL / PENDING)
export const VALIDATION_STATUS_BADGE: Record<string, string> = {
  PASS:    "bg-emerald-600 text-white",
  WARN:    "bg-amber-500 text-white",
  FAIL:    "bg-red-600 text-white",
  PENDING: "bg-slate-600 text-slate-300",
};

// Validation item priority (HIGH / MEDIUM / LOW)
export const PRIORITY_BADGE: Record<string, string> = {
  HIGH:   "bg-red-600 text-white",
  MEDIUM: "bg-amber-600 text-white",
  LOW:    "bg-slate-600 text-slate-300",
};

// Connection / healthcheck status (ok / error / not_configured / checking)
export const CONN_BADGE: Record<string, string> = {
  ok:             "bg-emerald-500/20 text-emerald-400 border border-emerald-500/40",
  error:          "bg-red-500/20 text-red-400 border border-red-500/40",
  not_configured: "bg-slate-700 text-slate-400 border border-slate-600",
  checking:       "bg-amber-500/20 text-amber-400 border border-amber-500/40",
};

export const CONN_LABEL: Record<string, string> = {
  ok:             "연결됨",
  error:          "오류",
  not_configured: "미설정",
  checking:       "확인 중",
};
