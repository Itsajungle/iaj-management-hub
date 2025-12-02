-- ============================================
-- IAJ MANAGEMENT HUB - Optimized Database Schema
-- ============================================
-- Production-ready schema with performance optimizations
-- Run this SQL in: Supabase Dashboard → SQL Editor → New Query
-- ============================================

-- Drop existing tables if rebuilding
-- DROP TABLE IF EXISTS system_health CASCADE;
-- DROP TABLE IF EXISTS workflow_events CASCADE;
-- DROP TABLE IF EXISTS ai_recommendations CASCADE;

-- ============================================
-- TABLE 1: system_health (Optimized)
-- ============================================
CREATE TABLE IF NOT EXISTS system_health (
    id BIGSERIAL PRIMARY KEY,
    system_name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('healthy', 'unhealthy', 'timeout', 'error')),
    last_check TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_time_ms NUMERIC(10, 2),
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Optimized indexes for common queries
CREATE INDEX IF NOT EXISTS idx_system_health_system_name ON system_health(system_name);
CREATE INDEX IF NOT EXISTS idx_system_health_created_at_desc ON system_health(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_health_system_created ON system_health(system_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_health_status ON system_health(status) WHERE status != 'healthy';

-- Note: Removed partial index with NOW() - not IMMUTABLE
-- Use regular index instead for recent data queries

-- Comment
COMMENT ON TABLE system_health IS 'Stores health check results with optimized indexing for performance';

-- ============================================
-- TABLE 2: workflow_events (Optimized)
-- ============================================
CREATE TABLE IF NOT EXISTS workflow_events (
    id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    source_system TEXT NOT NULL,
    target_system TEXT,
    status TEXT NOT NULL CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
    payload JSONB DEFAULT '{}'::jsonb,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Optimized indexes
CREATE INDEX IF NOT EXISTS idx_workflow_events_type_created ON workflow_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_events_source ON workflow_events(source_system, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_events_status ON workflow_events(status) WHERE status IN ('pending', 'in_progress');

-- Note: Removed partial index with NOW() - not IMMUTABLE
-- Use regular index instead for recent event queries

-- Comment
COMMENT ON TABLE workflow_events IS 'Logs workflow events with optimized querying for active events';

-- ============================================
-- TABLE 3: ai_recommendations (Optimized)
-- ============================================
CREATE TABLE IF NOT EXISTS ai_recommendations (
    id BIGSERIAL PRIMARY KEY,
    recommendation_type TEXT NOT NULL,
    priority TEXT NOT NULL CHECK (priority IN ('high', 'medium', 'low')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    system_name TEXT NOT NULL,
    actionable BOOLEAN DEFAULT true,
    action_url TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'dismissed', 'expired')),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ
);

-- Optimized indexes for dashboard queries
CREATE INDEX IF NOT EXISTS idx_ai_recommendations_active 
ON ai_recommendations(priority, created_at DESC) 
WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_ai_recommendations_system 
ON ai_recommendations(system_name, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_recommendations_type_priority 
ON ai_recommendations(recommendation_type, priority) 
WHERE status = 'active';

-- Comment
COMMENT ON TABLE ai_recommendations IS 'Stores AI-generated recommendations with efficient filtering';

-- ============================================
-- ROW LEVEL SECURITY (Production-Ready)
-- ============================================

-- Enable RLS
ALTER TABLE system_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_recommendations ENABLE ROW LEVEL SECURITY;

-- Policies for anon key (backend API access)
DROP POLICY IF EXISTS "anon_all_system_health" ON system_health;
CREATE POLICY "anon_all_system_health" ON system_health FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_workflow_events" ON workflow_events;
CREATE POLICY "anon_all_workflow_events" ON workflow_events FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_ai_recommendations" ON ai_recommendations;
CREATE POLICY "anon_all_ai_recommendations" ON ai_recommendations FOR ALL TO anon USING (true) WITH CHECK (true);

-- Policies for authenticated users (read-only for frontend)
DROP POLICY IF EXISTS "auth_read_system_health" ON system_health;
CREATE POLICY "auth_read_system_health" ON system_health FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_read_workflow_events" ON workflow_events;
CREATE POLICY "auth_read_workflow_events" ON workflow_events FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_read_ai_recommendations" ON ai_recommendations;
CREATE POLICY "auth_read_ai_recommendations" ON ai_recommendations FOR SELECT TO authenticated USING (true);

-- Policies for service_role (full access)
DROP POLICY IF EXISTS "service_all_system_health" ON system_health;
CREATE POLICY "service_all_system_health" ON system_health FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "service_all_workflow_events" ON workflow_events;
CREATE POLICY "service_all_workflow_events" ON workflow_events FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "service_all_ai_recommendations" ON ai_recommendations;
CREATE POLICY "service_all_ai_recommendations" ON ai_recommendations FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================
-- AUTOMATIC CLEANUP FUNCTION (Optional)
-- ============================================
-- Auto-delete old health checks (keeps last 1000 per system)
-- This is a backup to the application-level cleanup

CREATE OR REPLACE FUNCTION cleanup_old_health_checks()
RETURNS void AS $$
DECLARE
    sys_name TEXT;
BEGIN
    FOR sys_name IN SELECT DISTINCT system_name FROM system_health LOOP
        DELETE FROM system_health
        WHERE id IN (
            SELECT id FROM system_health
            WHERE system_name = sys_name
            ORDER BY created_at DESC
            OFFSET 1000
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- MATERIALIZED VIEW FOR PERFORMANCE DASHBOARD
-- ============================================
-- Pre-computed stats for faster dashboard loading

DROP MATERIALIZED VIEW IF EXISTS system_health_summary CASCADE;
CREATE MATERIALIZED VIEW system_health_summary AS
SELECT 
    system_name,
    COUNT(*) as total_checks,
    SUM(CASE WHEN status = 'healthy' THEN 1 ELSE 0 END) as healthy_checks,
    ROUND(AVG(CASE WHEN status = 'healthy' THEN 100 ELSE 0 END), 2) as uptime_percentage,
    ROUND(AVG(response_time_ms), 2) as avg_response_time,
    MAX(created_at) as last_check_time
FROM system_health
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY system_name;

-- Index on materialized view
CREATE UNIQUE INDEX IF NOT EXISTS idx_health_summary_system ON system_health_summary(system_name);

-- Refresh function (call this periodically or after health checks)
CREATE OR REPLACE FUNCTION refresh_health_summary()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY system_health_summary;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Verify tables exist
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables 
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename;

-- Verify indexes
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename, indexname;

-- Verify policies
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles
FROM pg_policies
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename, policyname;

-- Check materialized view
SELECT * FROM system_health_summary;

-- ============================================
-- SAMPLE TEST QUERIES
-- ============================================

-- Test: Get latest health for all systems
-- SELECT DISTINCT ON (system_name) 
--     system_name, status, response_time_ms, last_check
-- FROM system_health 
-- ORDER BY system_name, created_at DESC;

-- Test: Get 24h uptime for each system
-- SELECT 
--     system_name,
--     COUNT(*) as total_checks,
--     SUM(CASE WHEN status = 'healthy' THEN 1 ELSE 0 END) as healthy_checks,
--     ROUND(AVG(CASE WHEN status = 'healthy' THEN 100 ELSE 0 END), 2) as uptime_pct
-- FROM system_health 
-- WHERE created_at > NOW() - INTERVAL '24 hours'
-- GROUP BY system_name;

-- Test: Get active high-priority recommendations
-- SELECT title, system_name, description, created_at
-- FROM ai_recommendations
-- WHERE status = 'active' AND priority = 'high'
-- ORDER BY created_at DESC;

-- ============================================
-- SUCCESS!
-- ============================================
-- ✅ Optimized tables created with performance indexes
-- ✅ Row-level security configured
-- ✅ Auto-cleanup function available
-- ✅ Materialized view for fast dashboard queries
-- ✅ Ready for production use
-- ============================================

