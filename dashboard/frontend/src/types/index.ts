export type Role =
  | "admin"
  | "migration_leader"
  | "src_dba"
  | "tgt_dba"
  | "gg_operator"
  | "viewer";

export interface User {
  username: string;
  role: Role;
}

export type PhaseStatus = "pending" | "in_progress" | "completed" | "failed";

export interface Phase {
  phase_no: number;
  phase_name: string;
  status: PhaseStatus;
  started_at?: string;
  completed_at?: string;
  completed_by?: string;
}

export interface ConfigEntry {
  key: string;
  value: string | null;
  locked: boolean;
  changed_by: string | null;
  changed_at: string | null;
}

export type ConnStatus = "ok" | "error" | "not_configured" | "checking";

export interface HealthResult {
  source_db:  { status: ConnStatus; detail?: string; dsn?: string };
  target_db:  { status: ConnStatus; detail?: string; dsn?: string };
  goldengate: { status: ConnStatus; detail?: string; http_status?: number };
}

export type GGStatus = "RUNNING" | "STOPPED" | "ABEND" | "UNKNOWN";

export interface GGProcessStatus {
  name: string;
  status: GGStatus;
  lag_seconds?: number;
}

export type GoNogo = "GO" | "CONDITIONAL_GO" | "NO_GO" | "PENDING";

export interface ValidationSummary {
  total:         number;
  pass_count:    number;
  warn_count:    number;
  fail_count:    number;
  pending_count: number;
  go_nogo:       GoNogo;
}
