import { NavLink } from "react-router-dom";
import {
  LayoutDashboard,
  Activity,
  BookOpen,
  Database,
  Terminal,
  CheckSquare,
  Zap,
  Clock,
  History,
  Cog,
  Settings,
} from "lucide-react";
import { cn } from "../../lib/utils";

const NAV_ITEMS = [
  { path: "/",                  icon: LayoutDashboard, label: "Overview"      },
  { path: "/gg-monitor",        icon: Activity,        label: "GG Monitor"    },
  { path: "/runbook",           icon: BookOpen,        label: "Runbook"       },
  { path: "/db-status",         icon: Database,        label: "DB Status"     },
  { path: "/script-runner",     icon: Terminal,        label: "Script Runner" },
  { path: "/validation",        icon: CheckSquare,     label: "Validation"    },
  { path: "/cutover",           icon: Zap,             label: "Cut-over"      },
  { path: "/event-log",         icon: Clock,           label: "Event Log"     },
  { path: "/execution-history", icon: History,         label: "Exec History"  },
  { path: "/config",            icon: Cog,             label: "Config"        },
  { path: "/settings",          icon: Settings,        label: "Settings"      },
];

export default function Sidebar() {
  return (
    <nav className="w-44 bg-slate-800 border-r border-slate-700 flex flex-col shrink-0 overflow-y-auto">
      <ul className="py-2">
        {NAV_ITEMS.map(({ path, icon: Icon, label }) => (
          <li key={path}>
            <NavLink
              to={path}
              end={path === "/"}
              className={({ isActive }) =>
                cn(
                  "flex items-center gap-3 px-4 py-2.5 text-sm transition-colors",
                  isActive
                    ? "bg-blue-600/20 text-blue-400 border-r-2 border-blue-400"
                    : "text-slate-400 hover:text-white hover:bg-slate-700/50"
                )
              }
            >
              <Icon className="w-4 h-4 shrink-0" />
              <span className="truncate">{label}</span>
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
