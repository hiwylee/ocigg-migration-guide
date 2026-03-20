import { useState } from "react";
import { LayoutGrid, Maximize2, X } from "lucide-react";
import Overview from "../pages/Overview";
import GGMonitor from "../pages/GGMonitor";
import Validation from "../pages/Validation";
import CutoverConsole from "../pages/CutoverConsole";

interface Panel {
  id: string;
  title: string;
  component: React.ComponentType;
}

const PANELS: Panel[] = [
  { id: "overview",   title: "Overview",         component: Overview       },
  { id: "gg",         title: "GG Monitor",        component: GGMonitor      },
  { id: "validation", title: "Validation",         component: Validation     },
  { id: "cutover",    title: "Cut-over Console",  component: CutoverConsole },
];

interface DDayLayoutProps {
  onClose: () => void;
}

export default function DDayLayout({ onClose }: DDayLayoutProps) {
  const [popouts, setPopouts] = useState<Set<string>>(new Set());

  const popout = (panel: Panel) => {
    const w = window.open("", `_dday_${panel.id}`, "width=900,height=700,menubar=no,toolbar=no");
    if (!w) return;
    setPopouts((p) => new Set(p).add(panel.id));
    w.document.write(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>${panel.title} — D-Day</title>
        <style>body{margin:0;background:#0f172a;color:white;font-family:sans-serif;padding:1rem}</style>
      </head>
      <body>
        <h2 style="color:#94a3b8;margin-bottom:1rem">${panel.title}</h2>
        <p style="color:#64748b">이 창은 독립 팝아웃입니다. 메인 대시보드를 참조하세요.</p>
      </body>
      </html>
    `);
    w.onbeforeunload = () => setPopouts((p) => { const n = new Set(p); n.delete(panel.id); return n; });
  };

  return (
    <div className="fixed inset-0 z-40 bg-slate-900 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-slate-800 border-b border-slate-700 shrink-0">
        <div className="flex items-center gap-2">
          <LayoutGrid className="w-4 h-4 text-amber-400" />
          <span className="text-white font-bold text-sm">D-Day 모드</span>
          <span className="text-slate-400 text-xs ml-2">4분할 레이아웃</span>
        </div>
        <button onClick={onClose} className="text-slate-400 hover:text-white p-1">
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* 2x2 grid */}
      <div className="flex-1 grid grid-cols-2 grid-rows-2 gap-px bg-slate-700 overflow-hidden">
        {PANELS.map((panel) => {
          const Comp = panel.component;
          const isPopped = popouts.has(panel.id);
          return (
            <div key={panel.id} className="bg-slate-900 overflow-auto relative">
              <div className="flex items-center justify-between px-3 py-1.5 bg-slate-800/80 sticky top-0 z-10 border-b border-slate-700/50">
                <span className="text-xs text-slate-400 font-medium">{panel.title}</span>
                <button
                  onClick={() => popout(panel)}
                  className="p-1 text-slate-500 hover:text-slate-300"
                  title="팝아웃"
                >
                  <Maximize2 className="w-3 h-3" />
                </button>
              </div>
              {isPopped ? (
                <div className="p-4 text-slate-500 text-sm">팝아웃 창에서 표시 중</div>
              ) : (
                <div className="text-[0.75rem] [&_h1]:text-base [&_h2]:text-sm [&_.p-6]:p-3 [&_.p-5]:p-2.5 [&_.p-4]:p-2">
                  <Comp />
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
