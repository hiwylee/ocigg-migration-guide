import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { useAuthStore } from "./store/authStore";
import Layout from "./components/layout/Layout";
import Login from "./pages/Login";
import Overview from "./pages/Overview";
import GGMonitor from "./pages/GGMonitor";
import ScriptRunner from "./pages/ScriptRunner";
import RunbookViewer from "./pages/RunbookViewer";
import DBStatus from "./pages/DBStatus";
import Placeholder from "./pages/Placeholder";
import Validation from "./pages/Validation";

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token);
  if (!token) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

const PLACEHOLDER_ROUTES = [
  { path: "/cutover",           title: "Cut-over Console"  },
  { path: "/event-log",         title: "Event Log"         },
  { path: "/execution-history", title: "Execution History" },
  { path: "/config",            title: "Config Registry"   },
  { path: "/settings",          title: "Settings"          },
];

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />

        <Route
          path="/"
          element={
            <ProtectedRoute>
              <Layout>
                <Overview />
              </Layout>
            </ProtectedRoute>
          }
        />

        <Route
          path="/gg-monitor"
          element={
            <ProtectedRoute>
              <Layout>
                <GGMonitor />
              </Layout>
            </ProtectedRoute>
          }
        />

        <Route
          path="/script-runner"
          element={
            <ProtectedRoute>
              <Layout>
                <ScriptRunner />
              </Layout>
            </ProtectedRoute>
          }
        />

        <Route
          path="/runbook"
          element={
            <ProtectedRoute>
              <Layout>
                <RunbookViewer />
              </Layout>
            </ProtectedRoute>
          }
        />

        <Route
          path="/db-status"
          element={
            <ProtectedRoute>
              <Layout>
                <DBStatus />
              </Layout>
            </ProtectedRoute>
          }
        />

        <Route
          path="/validation"
          element={
            <ProtectedRoute>
              <Layout>
                <Validation />
              </Layout>
            </ProtectedRoute>
          }
        />

        {PLACEHOLDER_ROUTES.map(({ path, title }) => (
          <Route
            key={path}
            path={path}
            element={
              <ProtectedRoute>
                <Layout>
                  <Placeholder title={title} />
                </Layout>
              </ProtectedRoute>
            }
          />
        ))}

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
