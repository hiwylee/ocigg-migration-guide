import { useCallback, useEffect, useRef, useState } from "react";
import {
  ChevronDown, ChevronRight,
  AlertTriangle, CheckCircle2, XCircle, Clock,
} from "lucide-react";
import api from "../hooks/useApi";
import { cn } from "../lib/utils";
import { VALIDATION_STATUS_BADGE, PRIORITY_BADGE } from "../lib/styles";
import GoNoBadge from "../components/GoNoBadge";
import type { GoNogo } from "../types";

// ── Types ──────────────────────────────────────────────────────────────────

type VStatus = "PASS" | "WARN" | "FAIL" | "PENDING";
type VPriority = "HIGH" | "MEDIUM" | "LOW";

interface ValidationItem {
  id: number;
  domain: string;
  item_no: number;
  item_name: string;
  priority: VPriority;
  status: VStatus;
  area: string | null;
  method: string | null;
  note: string | null;
  assignee: string | null;
  verified_at: string | null;
  verified_by: string | null;
}

interface DomainSummary {
  domain: string;
  total: number;
  pass_count: number;
  warn_count: number;
  fail_count: number;
  pending_count: number;
}

interface SummaryData {
  total: number;
  pass_count: number;
  warn_count: number;
  fail_count: number;
  pending_count: number;
  go_nogo: GoNogo;
  domain_summary: DomainSummary[];
}

type UpdateFields = Partial<Pick<ValidationItem, "status" | "note" | "assignee">>;

// ── Constants ──────────────────────────────────────────────────────────────

const DOMAIN_ORDER = [
  "01_GG_Process",
  "02_Static_Schema",
  "03_Data_Validation",
  "04_Special_Objects",
  "05_Migration_Caution",
];

const TAB_LABELS: Record<string, string> = {
  "01_GG_Process":        "GG 프로세스",
  "02_Static_Schema":     "정적 스키마",
  "03_Data_Validation":   "데이터 검증",
  "04_Special_Objects":   "특수 객체",
  "05_Migration_Caution": "마이그레이션 주의",
};

const STATUS_STYLE = VALIDATION_STATUS_BADGE as Record<VStatus, string>;
const PRIORITY_STYLE = PRIORITY_BADGE as Record<VPriority, string>;

// ── Small components ───────────────────────────────────────────────────────

function PriorityBadge({ priority }: { priority: VPriority }) {
  return (
    <span className={cn(
      "inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold shrink-0",
      PRIORITY_STYLE[priority]
    )}>
      {priority}
    </span>
  );
}

function StatusIcon({ status }: { status: VStatus }) {
  const cls = "w-3.5 h-3.5";
  if (status === "PASS")    return <CheckCircle2 className={cn(cls, "text-emerald-400")} />;
  if (status === "WARN")    return <AlertTriangle className={cn(cls, "text-amber-400")} />;
  if (status === "FAIL")    return <XCircle className={cn(cls, "text-red-400")} />;
  return <Clock className={cn(cls, "text-slate-500")} />;
}

// ── ItemRow ────────────────────────────────────────────────────────────────

interface ItemRowProps {
  item: ValidationItem;
  showDomain?: boolean;
  colSpanTotal: number;
  onUpdate: (id: number, fields: UpdateFields) => Promise<void>;
}

function ItemRow({ item, showDomain = false, colSpanTotal, onUpdate }: ItemRowProps) {
  const [saving, setSaving] = useState(false);
  const [showNote, setShowNote] = useState(false);
  const [noteVal, setNoteVal] = useState(item.note ?? "");
  const [assigneeVal, setAssigneeVal] = useState(item.assignee ?? "");
  const assigneeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleStatus = async (s: VStatus) => {
    if (s === item.status) return;
    setSaving(true);
    await onUpdate(item.id, { status: s });
    setSaving(false);
  };

  const handleAssigneeChange = (val: string) => {
    setAssigneeVal(val);
    if (assigneeTimer.current) clearTimeout(assigneeTimer.current);
    assigneeTimer.current = setTimeout(() => onUpdate(item.id, { assignee: val }), 800);
  };

  const handleNoteSave = async () => {
    await onUpdate(item.id, { note: noteVal });
    setShowNote(false);
  };

  return (
    <>
      <tr
        className={cn(
          "border-b border-slate-700/40 hover:bg-slate-800/50 transition",
          item.status === "FAIL" && "border-l-2 border-l-red-500",
          item.status === "WARN" && "border-l-2 border-l-amber-500",
        )}
      >
        {/* NO */}
        <td className="px-3 py-2 text-slate-500 text-xs font-mono text-right w-8 align-top pt-3">
          {item.item_no}
        </td>

        {/* Domain badge (HIGH section only) */}
        {showDomain && (
          <td className="px-2 py-2 align-top pt-2.5 w-28">
            <span className="text-[10px] text-slate-400 bg-slate-700 px-1.5 py-0.5 rounded whitespace-nowrap">
              {TAB_LABELS[item.domain] ?? item.domain}
            </span>
          </td>
        )}

        {/* 검증항목 + 검증방법 */}
        <td className="px-3 py-2">
          <div className="flex items-start gap-2">
            <StatusIcon status={item.status} />
            <div className="min-w-0">
              <div className="text-slate-200 text-sm leading-snug">{item.item_name}</div>
              {item.method && (
                <div className="mt-1">
                  <span
                    className="inline-block text-[10px] text-cyan-400 bg-cyan-950/50 border border-cyan-800/40 rounded px-1.5 py-0.5 leading-tight"
                    title={item.method}
                  >
                    {item.method.length > 60 ? item.method.slice(0, 60) + "…" : item.method}
                  </span>
                </div>
              )}
              {item.note && !showNote && (
                <div className="mt-1 text-[11px] text-slate-500 truncate max-w-sm">
                  📝 {item.note}
                </div>
              )}
            </div>
          </div>
        </td>

        {/* 중요도 */}
        <td className="px-2 py-2 align-top pt-2.5 w-16 text-center">
          <PriorityBadge priority={item.priority} />
        </td>

        {/* 담당자 */}
        <td className="px-2 py-2 align-top pt-2 w-24">
          <input
            className="w-full bg-slate-700 border border-slate-600 rounded px-1.5 py-1 text-xs text-slate-200 focus:outline-none focus:border-blue-500"
            placeholder="담당자"
            value={assigneeVal}
            onChange={(e) => handleAssigneeChange(e.target.value)}
          />
        </td>

        {/* 상태 + 메모 */}
        <td className="px-2 py-2 align-top pt-2 w-40">
          <div className="flex items-center gap-1">
            {(["PASS", "WARN", "FAIL", "PENDING"] as VStatus[]).map((s) => (
              <button
                key={s}
                disabled={saving}
                onClick={() => handleStatus(s)}
                className={cn(
                  "px-1.5 py-1 rounded text-[10px] font-semibold transition min-w-[26px] text-center",
                  item.status === s
                    ? STATUS_STYLE[s]
                    : "bg-slate-700 text-slate-400 hover:bg-slate-600"
                )}
              >
                {s === "PENDING" ? "—" : s.charAt(0)}
              </button>
            ))}
            <button
              onClick={() => setShowNote((v) => !v)}
              className="ml-0.5 text-slate-500 hover:text-slate-300 text-sm"
              title="메모"
            >
              {item.note ? "📝" : "✏️"}
            </button>
          </div>
        </td>
      </tr>

      {/* Note editor row */}
      {showNote && (
        <tr className="border-b border-slate-700/40 bg-slate-800/30">
          <td colSpan={colSpanTotal} className="px-6 pb-3 pt-1">
            <div className="flex gap-2 ml-5">
              <textarea
                className="flex-1 bg-slate-700 border border-slate-600 rounded px-2 py-1.5 text-xs text-slate-200 resize-none h-16 focus:outline-none focus:border-blue-500"
                value={noteVal}
                onChange={(e) => setNoteVal(e.target.value)}
                placeholder="메모 입력..."
              />
              <div className="flex flex-col gap-1">
                <button
                  onClick={handleNoteSave}
                  className="px-2 py-1 bg-blue-600 hover:bg-blue-500 text-white text-xs rounded"
                >
                  저장
                </button>
                <button
                  onClick={() => { setShowNote(false); setNoteVal(item.note ?? ""); }}
                  className="px-2 py-1 bg-slate-600 hover:bg-slate-500 text-slate-300 text-xs rounded"
                >
                  취소
                </button>
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}

// ── AreaGroupHeader ────────────────────────────────────────────────────────

function AreaGroupHeader({
  area, count, colSpan,
}: { area: string; count: number; colSpan: number }) {
  return (
    <tr className="bg-slate-800/80">
      <td colSpan={colSpan} className="px-4 py-1.5">
        <div className="flex items-center gap-2">
          <div className="h-px w-3 bg-slate-600" />
          <span className="text-[11px] font-bold text-slate-400 shrink-0">{area}</span>
          <span className="text-[10px] text-slate-600">({count})</span>
          <div className="h-px flex-1 bg-slate-700/50" />
        </div>
      </td>
    </tr>
  );
}

// ── ValidationTable ────────────────────────────────────────────────────────

function ValidationTable({
  items,
  showDomain = false,
  onUpdate,
}: {
  items: ValidationItem[];
  showDomain?: boolean;
  onUpdate: (id: number, fields: UpdateFields) => Promise<void>;
}) {
  if (items.length === 0) {
    return <div className="py-12 text-center text-slate-500 text-sm">항목 없음</div>;
  }

  // Column count for colSpan
  const colCount = showDomain ? 6 : 5;

  // Build area counts
  const areaCount: Record<string, number> = {};
  for (const item of items) {
    const a = item.area || "(기타)";
    areaCount[a] = (areaCount[a] || 0) + 1;
  }

  const rows: React.ReactNode[] = [];
  let lastArea = "__init__";

  for (const item of items) {
    const areaKey = item.area || "(기타)";
    if (areaKey !== lastArea) {
      rows.push(
        <AreaGroupHeader
          key={`hdr-${areaKey}-${item.id}`}
          area={areaKey}
          count={areaCount[areaKey]}
          colSpan={colCount}
        />
      );
      lastArea = areaKey;
    }
    rows.push(
      <ItemRow
        key={item.id}
        item={item}
        showDomain={showDomain}
        colSpanTotal={colCount}
        onUpdate={onUpdate}
      />
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-left">
        <thead>
          <tr className="bg-slate-850 border-b-2 border-slate-700">
            <th className="px-3 py-2 text-[10px] text-slate-500 font-semibold uppercase tracking-wide w-8 text-right">NO</th>
            {showDomain && (
              <th className="px-2 py-2 text-[10px] text-slate-500 font-semibold uppercase tracking-wide w-28">도메인</th>
            )}
            <th className="px-3 py-2 text-[10px] text-slate-500 font-semibold uppercase tracking-wide">
              검증항목 / 검증방법
            </th>
            <th className="px-2 py-2 text-[10px] text-slate-500 font-semibold uppercase tracking-wide w-16 text-center">중요도</th>
            <th className="px-2 py-2 text-[10px] text-slate-500 font-semibold uppercase tracking-wide w-24">담당자</th>
            <th className="px-2 py-2 text-[10px] text-slate-500 font-semibold uppercase tracking-wide w-40">상태</th>
          </tr>
        </thead>
        <tbody>{rows}</tbody>
      </table>
    </div>
  );
}

// ── HighAccordion ──────────────────────────────────────────────────────────

function HighAccordion({
  items,
  onUpdate,
}: {
  items: ValidationItem[];
  onUpdate: (id: number, fields: UpdateFields) => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const fail = items.filter((i) => i.status === "FAIL").length;
  const warn = items.filter((i) => i.status === "WARN").length;
  const pass = items.filter((i) => i.status === "PASS").length;
  const pct = items.length > 0 ? Math.round((pass / items.length) * 100) : 0;

  return (
    <div className={cn(
      "border-2 rounded-lg overflow-hidden",
      fail > 0 ? "border-red-700" : warn > 0 ? "border-amber-700" : "border-slate-700"
    )}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-4 py-3 bg-slate-800/60 hover:bg-slate-700/60 transition"
      >
        <div className="flex items-center gap-3">
          {open
            ? <ChevronDown className="w-4 h-4 text-red-400" />
            : <ChevronRight className="w-4 h-4 text-red-400" />
          }
          <AlertTriangle className="w-4 h-4 text-red-400" />
          <span className="text-sm font-bold text-red-300">HIGH 우선순위 항목</span>
          <span className="text-xs text-slate-500">({items.length}개)</span>
          {fail > 0 && (
            <span className="px-2 py-0.5 bg-red-600 text-white text-xs rounded font-bold">
              FAIL {fail}
            </span>
          )}
          {warn > 0 && (
            <span className="px-2 py-0.5 bg-amber-600 text-white text-xs rounded font-bold">
              WARN {warn}
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs text-slate-400">{pass}/{items.length} PASS</span>
          <div className="w-28 h-1.5 bg-slate-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-emerald-500 rounded-full transition-all"
              style={{ width: `${pct}%` }}
            />
          </div>
        </div>
      </button>

      {open && (
        <div className="bg-slate-900/50">
          <ValidationTable items={items} showDomain onUpdate={onUpdate} />
        </div>
      )}
    </div>
  );
}

// ── DomainTab ──────────────────────────────────────────────────────────────

function DomainTab({
  domain, active, domainItems, onClick,
}: {
  domain: string;
  active: boolean;
  domainItems: ValidationItem[];
  onClick: () => void;
}) {
  const fail = domainItems.filter((i) => i.status === "FAIL").length;
  const warn = domainItems.filter((i) => i.status === "WARN").length;
  const pass = domainItems.filter((i) => i.status === "PASS").length;
  const pct = domainItems.length > 0 ? Math.round((pass / domainItems.length) * 100) : 0;

  return (
    <button
      onClick={onClick}
      className={cn(
        "flex flex-col items-start px-4 py-2.5 border-b-2 text-left transition shrink-0",
        active
          ? "border-blue-500 bg-slate-800 text-white"
          : "border-transparent text-slate-400 hover:text-slate-200 hover:bg-slate-800/50",
      )}
    >
      <div className="flex items-center gap-1.5">
        <span className="text-sm font-semibold">{TAB_LABELS[domain] ?? domain}</span>
        {fail > 0 && (
          <span className="px-1.5 py-0.5 bg-red-600 text-white text-[10px] rounded font-bold">F{fail}</span>
        )}
        {warn > 0 && (
          <span className="px-1.5 py-0.5 bg-amber-600 text-white text-[10px] rounded font-bold">W{warn}</span>
        )}
      </div>
      <div className="flex items-center gap-1.5 mt-0.5">
        <div className="w-16 h-1 bg-slate-700 rounded-full overflow-hidden">
          <div className="h-full bg-emerald-500 rounded-full" style={{ width: `${pct}%` }} />
        </div>
        <span className="text-[10px] text-slate-500">{pass}/{domainItems.length}</span>
      </div>
    </button>
  );
}

// ── StickyProgressBar ──────────────────────────────────────────────────────

function StickyProgressBar({ pass, total }: { pass: number; total: number }) {
  const pct = total > 0 ? Math.round((pass / total) * 100) : 0;
  return (
    <div className="sticky bottom-0 bg-slate-900 border-t border-slate-700 px-6 py-3 z-20">
      <div className="flex items-center gap-4">
        <div className="flex-1 h-2 bg-slate-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-emerald-500 rounded-full transition-all duration-500"
            style={{ width: `${pct}%` }}
          />
        </div>
        <span className="text-sm text-slate-300 whitespace-nowrap">
          <span className="text-white font-bold">{pass}</span>
          <span className="text-slate-500"> / {total} 완료 ({pct}%)</span>
        </span>
      </div>
    </div>
  );
}

// ── Main ───────────────────────────────────────────────────────────────────

export default function Validation() {
  const [items, setItems] = useState<ValidationItem[]>([]);
  const [summary, setSummary] = useState<SummaryData | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState(DOMAIN_ORDER[0]);

  const fetchItems = useCallback(async () => {
    try {
      const res = await api.get<ValidationItem[]>("/validation/items");
      setItems(res.data);
    } catch (err) { console.warn("Validation: failed to load items", err); }
  }, []);

  const fetchSummary = useCallback(async () => {
    try {
      const res = await api.get<SummaryData>("/validation/summary");
      setSummary(res.data);
    } catch (err) { console.warn("Validation: failed to load summary", err); }
  }, []);

  useEffect(() => {
    Promise.all([fetchItems(), fetchSummary()]).finally(() => setLoading(false));
  }, [fetchItems, fetchSummary]);

  const handleUpdate = useCallback(
    async (id: number, fields: UpdateFields) => {
      setItems((prev) => prev.map((item) => item.id === id ? { ...item, ...fields } : item));
      try {
        await api.patch(`/validation/items/${id}`, fields);
        await fetchSummary();
      } catch (err) {
        console.warn("Validation: update failed, reverting", err);
        await fetchItems();
      }
    },
    [fetchItems, fetchSummary],
  );

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64 text-slate-400">
        <span className="animate-pulse">검증 항목 로드 중...</span>
      </div>
    );
  }

  const highItems = items.filter((i) => i.priority === "HIGH");
  const tabItems = items.filter((i) => i.domain === activeTab);
  const goNogo = summary?.go_nogo ?? "PENDING";
  const passCount = summary?.pass_count ?? 0;
  const total = summary?.total ?? items.length;

  return (
    <div className="flex flex-col h-full bg-slate-900 overflow-hidden">
      <div className="flex-1 overflow-y-auto">

        {/* ── Top: Go/No-Go + domain mini cards ── */}
        <div className="px-6 pt-6 pb-4">
          <div className="flex items-center gap-6 mb-5">
            <GoNoBadge goNogo={goNogo} size="lg" showLabel />
            <div>
              <div className="text-3xl font-bold text-white">
                {passCount}
                <span className="text-slate-500 text-xl font-normal"> / {total} 완료</span>
              </div>
              <div className="text-sm text-slate-400 mt-0.5">Phase 6 — 검증 {total}항목</div>
            </div>
          </div>

          {/* Domain mini cards — click to jump to tab */}
          {summary && (
            <div className="grid grid-cols-5 gap-2">
              {summary.domain_summary.map((ds) => {
                const pct = ds.total > 0 ? Math.round((ds.pass_count / ds.total) * 100) : 0;
                return (
                  <button
                    key={ds.domain}
                    onClick={() => setActiveTab(ds.domain)}
                    className={cn(
                      "flex flex-col gap-1.5 p-3 rounded-lg border transition text-left",
                      activeTab === ds.domain
                        ? "bg-slate-700 border-blue-500"
                        : "bg-slate-800 border-slate-700 hover:bg-slate-700",
                    )}
                  >
                    <div className="text-[10px] font-bold text-slate-300 truncate">
                      {TAB_LABELS[ds.domain] ?? ds.domain}
                    </div>
                    <div className="w-full h-1.5 bg-slate-600 rounded-full overflow-hidden">
                      <div className="h-full bg-emerald-500 rounded-full" style={{ width: `${pct}%` }} />
                    </div>
                    <div className="flex flex-wrap gap-1.5 text-[10px]">
                      <span className="text-emerald-400">{ds.pass_count}P</span>
                      {ds.fail_count > 0 && <span className="text-red-400">{ds.fail_count}F</span>}
                      {ds.warn_count > 0 && <span className="text-amber-400">{ds.warn_count}W</span>}
                      <span className="text-slate-500">{ds.pending_count}—</span>
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>

        {/* ── HIGH 우선순위 accordion ── */}
        <div className="px-6 pb-4">
          <HighAccordion items={highItems} onUpdate={handleUpdate} />
        </div>

        {/* ── Tabs + table ── */}
        <div className="px-6 pb-6">
          <div className="flex border-b border-slate-700 overflow-x-auto mb-0">
            {DOMAIN_ORDER.map((d) => (
              <DomainTab
                key={d}
                domain={d}
                active={activeTab === d}
                domainItems={items.filter((i) => i.domain === d)}
                onClick={() => setActiveTab(d)}
              />
            ))}
          </div>
          <ValidationTable items={tabItems} onUpdate={handleUpdate} />
        </div>
      </div>

      <StickyProgressBar pass={passCount} total={total} />
    </div>
  );
}
