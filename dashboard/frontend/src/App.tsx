import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { useAuthStore } from "./store/authStore";
import Layout from "./components/layout/Layout";
import AlertBanner from "./components/AlertBanner";
import Login from "./pages/Login";
import Overview from "./pages/Overview";
import GGMonitor from "./pages/GGMonitor";
import ScriptRunner from "./pages/ScriptRunner";
import RunbookViewer from "./pages/RunbookViewer";
import DBStatus from "./pages/DBStatus";
import Validation from "./pages/Validation";
import CutoverConsole from "./pages/CutoverConsole";
import RollbackConsole from "./pages/RollbackConsole";
import EventLog from "./pages/EventLog";
import ExecutionHistory from "./pages/ExecutionHistory";
import ConfigRegistry from "./pages/ConfigRegistry";
import Settings from "./pages/Settings";

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token);
  if (!token) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

export default function App() {
  const token = useAuthStore((s) => s.token);
  return (
    <BrowserRouter>
      {token && <AlertBanner />}
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

        <Route path="/cutover" element={<ProtectedRoute><Layout><CutoverConsole /></Layout></ProtectedRoute>} />
        <Route path="/rollback" element={<ProtectedRoute><Layout><RollbackConsole /></Layout></ProtectedRoute>} />
        <Route path="/event-log" element={<ProtectedRoute><Layout><EventLog /></Layout></ProtectedRoute>} />
        <Route path="/execution-history" element={<ProtectedRoute><Layout><ExecutionHistory /></Layout></ProtectedRoute>} />
        <Route path="/config" element={<ProtectedRoute><Layout><ConfigRegistry /></Layout></ProtectedRoute>} />
        <Route path="/settings" element={<ProtectedRoute><Layout><Settings /></Layout></ProtectedRoute>} />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
