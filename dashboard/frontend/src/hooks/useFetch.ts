import { useCallback, useEffect, useRef, useState, type DependencyList } from "react";

interface FetchState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  refresh: () => void;
}

/**
 * Generic data-fetching hook.
 *
 * @param fetcher  Async function that returns the data.
 * @param deps     Dependency list — re-fetches whenever any dep changes.
 *
 * @example
 *   const { data, loading, error, refresh } = useFetch(
 *     () => api.get<Item[]>("/items").then(r => r.data),
 *     [filter]
 *   );
 */
export function useFetch<T>(
  fetcher: () => Promise<T>,
  deps: DependencyList = [],
): FetchState<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // Keep a stable ref to the latest fetcher so refresh() is always current.
  const fetcherRef = useRef(fetcher);
  fetcherRef.current = fetcher;

  const run = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await fetcherRef.current();
      setData(result);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.warn("useFetch error:", err);
      setError(msg);
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    run();
  }, [run]);

  return { data, loading, error, refresh: run };
}
