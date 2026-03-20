import { useEffect, useState, useCallback, useRef } from "react";
import { marked } from "marked";
import {
  BookOpen,
  CheckCircle2,
  Circle,
  Copy,
  Check,
  AlertTriangle,
  ChevronDown,
  RotateCcw,
} from "lucide-react";
import { cn } from "../lib/utils";
import api from "../hooks/useApi";

// ─── Types ───────────────────────────────────────────────────────────────────

interface RunbookFile {
  filename: string;
  title: string;
  phase: number | null;
}

interface Step {
  step_id: string;
  title: string;
  index: number;
  completed: boolean;
  completed_by: string | null;
  completed_at: string | null;
}

interface WarningItem {
  text: string;
}

// ─── Markdown renderer setup ─────────────────────────────────────────────────

const renderer = new marked.Renderer();

renderer.heading = ({ text, depth }: { text: string; depth: number }) => {
  const slug = text
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  if (depth === 2) {
    return `<h2 id="step-${slug}" class="md-h2 text-blue-400 text-lg font-semibold mt-8 mb-3 pb-2 border-b border-slate-700">${text}</h2>`;
  }
  if (depth === 3) {
    return `<h3 class="md-h3 text-slate-300 font-medium mt-5 mb-2">${text}</h3>`;
  }
  return `<h${depth} class="text-slate-200 font-semibold mt-4 mb-2">${text}</h${depth}>`;
};

renderer.code = ({ text, lang }: { text: string; lang?: string }) => {
  const langClass = lang ? ` language-${lang}` : "";
  const escapedText = text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
  return `<pre class="md-pre bg-slate-900 border border-slate-600 rounded p-3 font-mono text-sm overflow-x-auto my-3 relative group" data-code="${encodeURIComponent(text)}"><code class="text-green-400${langClass}">${escapedText}</code></pre>`;
};

renderer.codespan = ({ text }: { text: string }) => {
  return `<code class="bg-slate-700 text-green-400 font-mono px-1.5 py-0.5 rounded text-sm">${text}</code>`;
};

renderer.table = ({
  header,
  rows,
}: {
  header: string;
  rows: string[];
}) => {
  return `<div class="overflow-x-auto my-4"><table class="w-full text-sm border-collapse border border-slate-600"><thead class="bg-slate-800">${header}</thead><tbody>${rows.join("")}</tbody></table></div>`;
};

renderer.tablerow = ({ text }: { text: string }) => {
  return `<tr class="border-b border-slate-700 hover:bg-slate-800/50">${text}</tr>`;
};

renderer.tablecell = ({
  text,
  tokens,
  header,
  align,
}: {
  text: string;
  tokens?: unknown;
  header: boolean;
  align: string | null;
}) => {
  const tag = header ? "th" : "td";
  const alignClass = align
    ? align === "center"
      ? " text-center"
      : align === "right"
      ? " text-right"
      : ""
    : "";
  const baseClass = header
    ? "text-slate-400 font-medium px-3 py-2 border-b border-slate-600"
    : "text-slate-300 px-3 py-2";
  return `<${tag} class="${baseClass}${alignClass}">${text}</${tag}>`;
};

renderer.paragraph = ({ text }: { text: string }) => {
  return `<p class="text-slate-300 my-2 leading-relaxed">${text}</p>`;
};

renderer.list = ({ items, ordered }: { items: string; ordered: boolean }) => {
  const tag = ordered ? "ol" : "ul";
  const listClass = ordered
    ? "list-decimal list-inside space-y-1 my-2 text-slate-300"
    : "list-disc list-inside space-y-1 my-2 text-slate-300";
  return `<${tag} class="${listClass}">${items}</${tag}>`;
};

renderer.listitem = ({ text }: { text: string }) => {
  return `<li class="text-slate-300 pl-2">${text}</li>`;
};

renderer.blockquote = ({ text }: { text: string }) => {
  return `<blockquote class="border-l-4 border-amber-500 pl-4 py-1 my-3 text-amber-300 bg-amber-500/5 rounded-r">${text}</blockquote>`;
};

marked.use({ renderer, async: false });

// ─── CopyButton ───────────────────────────────────────────────────────────────

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  const handleCopy = () => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };
  return (
    <button
      onClick={handleCopy}
      className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity bg-slate-700 hover:bg-slate-600 text-slate-300 px-2 py-1 rounded text-xs flex items-center gap-1"
    >
      {copied ? <Check className="w-3 h-3 text-emerald-400" /> : <Copy className="w-3 h-3" />}
      {copied ? "복사됨" : "복사"}
    </button>
  );
}

// ─── Main Component ───────────────────────────────────────────────────────────

export default function RunbookViewer() {
  const [files, setFiles] = useState<RunbookFile[]>([]);
  const [selectedFile, setSelectedFile] = useState<string>("");
  const [content, setContent] = useState<string>("");
  const [steps, setSteps] = useState<Step[]>([]);
  const [warnings, setWarnings] = useState<WarningItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  // 파일 목록 로드
  useEffect(() => {
    api.get<RunbookFile[]>("/runbook/files").then((res) => {
      setFiles(res.data);
      if (res.data.length > 0) {
        setSelectedFile(res.data[0].filename);
      }
    });
  }, []);

  // 파일 내용 + step + warning 로드
  const loadFile = useCallback(async (filename: string) => {
    if (!filename) return;
    setLoading(true);
    try {
      const [contentRes, stepsRes, warningsRes] = await Promise.all([
        api.get<string>(`/runbook/${filename}`),
        api.get<Step[]>(`/runbook/${filename}/steps`),
        api.get<WarningItem[]>(`/runbook/${filename}/warnings`),
      ]);
      setContent(contentRes.data);
      setSteps(stepsRes.data);
      setWarnings(warningsRes.data);
    } catch {
      setContent("# 파일을 불러올 수 없습니다");
      setSteps([]);
      setWarnings([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (selectedFile) {
      loadFile(selectedFile);
    }
  }, [selectedFile, loadFile]);

  // 마크다운 렌더 후 Copy 버튼 삽입
  useEffect(() => {
    if (!contentRef.current) return;
    const pres = contentRef.current.querySelectorAll("pre.md-pre");
    pres.forEach((pre) => {
      if (pre.querySelector(".copy-btn")) return;
      const encoded = pre.getAttribute("data-code") || "";
      const code = decodeURIComponent(encoded);
      const btn = document.createElement("button");
      btn.className =
        "copy-btn absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity bg-slate-700 hover:bg-slate-600 text-slate-300 px-2 py-1 rounded text-xs flex items-center gap-1";
      btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/></svg> 복사`;
      btn.onclick = () => {
        navigator.clipboard.writeText(code).then(() => {
          btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg> 복사됨`;
          setTimeout(() => {
            btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/></svg> 복사`;
          }, 2000);
        });
      };
      (pre as HTMLElement).style.position = "relative";
      pre.appendChild(btn);
    });
  }, [content]);

  const handleComplete = async (step: Step) => {
    setActionLoading(step.step_id);
    try {
      const res = await api.post<Step>(
        `/runbook/${selectedFile}/steps/${step.step_id}/complete`,
        {}
      );
      setSteps((prev) =>
        prev.map((s) => (s.step_id === step.step_id ? res.data : s))
      );
    } finally {
      setActionLoading(null);
    }
  };

  const handleUndo = async (step: Step) => {
    setActionLoading(step.step_id);
    try {
      const res = await api.post<Step>(
        `/runbook/${selectedFile}/steps/${step.step_id}/undo`,
        {}
      );
      setSteps((prev) =>
        prev.map((s) => (s.step_id === step.step_id ? res.data : s))
      );
    } finally {
      setActionLoading(null);
    }
  };

  const completedCount = steps.filter((s) => s.completed).length;
  const progress = steps.length > 0 ? (completedCount / steps.length) * 100 : 0;

  // 마크다운 + Step 버튼 오버레이 렌더링
  const renderContentWithStepButtons = () => {
    const html = marked.parse(content) as string;

    // h2 태그에 step 버튼을 삽입하기 위해 DOM 파싱 후 처리
    return (
      <div className="relative">
        {steps.map((step) => {
          const isLoading = actionLoading === step.step_id;
          return (
            <div
              key={step.step_id}
              id={`stepbtn-${step.step_id}`}
              className="hidden"
            >
              {step.completed ? (
                <button
                  onClick={() => handleUndo(step)}
                  disabled={isLoading}
                  className="inline-flex items-center gap-1 text-xs bg-slate-700 hover:bg-slate-600 text-slate-400 px-2 py-0.5 rounded ml-2"
                >
                  <RotateCcw className="w-3 h-3" /> 취소
                </button>
              ) : (
                <button
                  onClick={() => handleComplete(step)}
                  disabled={isLoading}
                  className="inline-flex items-center gap-1 text-xs bg-blue-600/30 hover:bg-blue-600/50 text-blue-300 px-2 py-0.5 rounded ml-2"
                >
                  <CheckCircle2 className="w-3 h-3" /> 완료
                </button>
              )}
            </div>
          );
        })}
        <div
          ref={contentRef}
          className="markdown-content"
          dangerouslySetInnerHTML={{ __html: html }}
        />
      </div>
    );
  };

  // Step 목록 패널용 렌더링 (사이드바)
  const StepListOverlay = () => (
    <div className="space-y-1">
      {steps.map((step) => {
        const isLoading = actionLoading === step.step_id;
        return (
          <div
            key={step.step_id}
            className={cn(
              "flex items-center gap-2 px-2 py-1.5 rounded text-xs group",
              step.completed
                ? "bg-emerald-500/10 text-slate-500"
                : "hover:bg-slate-700/50 text-slate-300"
            )}
          >
            {step.completed ? (
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
            ) : (
              <Circle className="w-3.5 h-3.5 text-slate-600 shrink-0" />
            )}
            <span
              className={cn(
                "flex-1 truncate",
                step.completed && "line-through opacity-60"
              )}
              title={step.title}
            >
              {step.title}
            </span>
            {step.completed ? (
              <button
                onClick={() => handleUndo(step)}
                disabled={isLoading}
                className="opacity-0 group-hover:opacity-100 text-slate-500 hover:text-slate-300 transition-opacity"
                title="취소"
              >
                <RotateCcw className="w-3 h-3" />
              </button>
            ) : (
              <button
                onClick={() => handleComplete(step)}
                disabled={isLoading}
                className="opacity-0 group-hover:opacity-100 text-blue-400 hover:text-blue-300 transition-opacity"
                title="완료 처리"
              >
                <CheckCircle2 className="w-3 h-3" />
              </button>
            )}
          </div>
        );
      })}
    </div>
  );

  const selectedFileMeta = files.find((f) => f.filename === selectedFile);

  return (
    <div className="flex gap-4 h-full overflow-hidden">
      {/* ── 좌: 마크다운 뷰어 (70%) ── */}
      <div className="flex-[7] flex flex-col overflow-hidden">
        {/* 파일 선택 헤더 */}
        <div className="flex items-center gap-3 mb-4 shrink-0">
          <BookOpen className="w-5 h-5 text-blue-400" />
          <h1 className="text-white font-semibold text-lg">Runbook Viewer</h1>
          <div className="relative ml-auto">
            <select
              value={selectedFile}
              onChange={(e) => setSelectedFile(e.target.value)}
              className="appearance-none bg-slate-800 border border-slate-600 text-slate-200 text-sm rounded px-3 py-1.5 pr-8 focus:outline-none focus:border-blue-500 cursor-pointer"
            >
              {files.map((f) => (
                <option key={f.filename} value={f.filename}>
                  {f.title}
                </option>
              ))}
            </select>
            <ChevronDown className="w-4 h-4 text-slate-400 absolute right-2 top-1/2 -translate-y-1/2 pointer-events-none" />
          </div>
        </div>

        {/* 마크다운 본문 */}
        <div className="flex-1 overflow-auto bg-slate-800 border border-slate-700 rounded-lg p-6">
          {loading ? (
            <div className="flex items-center justify-center h-32 text-slate-400">
              <div className="w-5 h-5 border-2 border-slate-400 border-t-blue-400 rounded-full animate-spin mr-2" />
              불러오는 중...
            </div>
          ) : (
            <>
              {selectedFileMeta && (
                <div className="mb-4 pb-3 border-b border-slate-700">
                  <p className="text-slate-400 text-sm">
                    {selectedFileMeta.filename}
                    {selectedFileMeta.phase !== null && (
                      <span className="ml-2 px-2 py-0.5 bg-blue-500/20 text-blue-400 rounded text-xs">
                        Phase {selectedFileMeta.phase}
                      </span>
                    )}
                  </p>
                </div>
              )}
              {renderContentWithStepButtons()}
            </>
          )}
        </div>
      </div>

      {/* ── 우: 고정 패널 (30%) ── */}
      <div className="flex-[3] flex flex-col gap-4 overflow-hidden">
        {/* 진행 현황 */}
        <div className="bg-slate-800 border border-slate-700 rounded-lg p-4 shrink-0">
          <h2 className="text-slate-300 font-medium text-sm mb-3">진행 현황</h2>
          <div className="flex items-baseline gap-1 mb-2">
            <span className="text-2xl font-bold text-white">{completedCount}</span>
            <span className="text-slate-400 text-sm">/ {steps.length} Steps</span>
          </div>
          <div className="w-full bg-slate-700 rounded-full h-2 overflow-hidden">
            <div
              className="h-2 bg-blue-500 rounded-full transition-all duration-500"
              style={{ width: `${progress}%` }}
            />
          </div>
          <p className="text-slate-500 text-xs mt-1.5 text-right">
            {progress.toFixed(0)}% 완료
          </p>

          {/* Step 체크리스트 */}
          <div className="mt-3 border-t border-slate-700 pt-3 max-h-48 overflow-y-auto">
            <StepListOverlay />
          </div>
        </div>

        {/* 주의사항 */}
        <div className="bg-slate-800 border border-slate-700 rounded-lg p-4 flex-1 overflow-hidden flex flex-col">
          <div className="flex items-center gap-2 mb-3 shrink-0">
            <AlertTriangle className="w-4 h-4 text-amber-400" />
            <h2 className="text-slate-300 font-medium text-sm">주의사항</h2>
            <span className="ml-auto text-xs text-slate-500">{warnings.length}건</span>
          </div>
          {warnings.length === 0 ? (
            <p className="text-slate-500 text-xs">주의 항목이 없습니다.</p>
          ) : (
            <div className="space-y-2 overflow-y-auto flex-1">
              {warnings.map((w, i) => (
                <div
                  key={i}
                  className="border-l-2 border-red-500/60 pl-3 py-1 bg-red-500/5 rounded-r text-xs text-slate-300 leading-relaxed"
                >
                  {w.text}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
