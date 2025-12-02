-- ============================================
-- IAJ MANAGEMENT HUB - CLEAN SLATE SETUP
-- ============================================
-- This script DROPS everything first, then creates fresh
-- Safe to run on a database with existing objects
-- ============================================

-- ============================================
-- STEP 1: DROP EVERYTHING
-- ============================================

-- Drop materialized views first (they depend on tables)
DROP MATERIALIZED VIEW IF EXISTS system_health_summary CASCADE;

-- Drop functions
DROP FUNCTION IF EXISTS cleanup_old_health_checks() CASCADE;
DROP FUNCTION IF EXISTS refresh_health_summary() CASCADE;

-- Drop tables (CASCADE removes all dependent objects like policies)
DROP TABLE IF EXISTS system_health CASCADE;
DROP TABLE IF EXISTS workflow_events CASCADE;
DROP TABLE IF EXISTS ai_recommendations CASCADE;

-- ============================================
-- STEP 2: CREATE TABLES
-- ============================================

-- TABLE 1: system_health
CREATE TABLE system_health (
    id BIGSERIAL PRIMARY KEY,
    system_name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('healthy', 'unhealthy', 'timeout', 'error')),
    last_check TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_time_ms NUMERIC(10, 2),
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLE 2: workflow_events
CREATE TABLE workflow_events (
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

-- TABLE 3: ai_recommendations
CREATE TABLE ai_recommendations (
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

-- ============================================
-- STEP 3: CREATE INDEXES
-- ============================================

-- Indexes for system_health
CREATE INDEX idx_system_health_system_name ON system_health(system_name);
CREATE INDEX idx_system_health_created_at_desc ON system_health(created_at DESC);
CREATE INDEX idx_system_health_system_created ON system_health(system_name, created_at DESC);
CREATE INDEX idx_system_health_status ON system_health(status) WHERE status != 'healthy';

-- Indexes for workflow_events
CREATE INDEX idx_workflow_events_type_created ON workflow_events(event_type, created_at DESC);
CREATE INDEX idx_workflow_events_source ON workflow_events(source_system, created_at DESC);
CREATE INDEX idx_workflow_events_status ON workflow_events(status) WHERE status IN ('pending', 'in_progress');

-- Indexes for ai_recommendations
CREATE INDEX idx_ai_recommendations_active ON ai_recommendations(priority, created_at DESC) WHERE status = 'active';
CREATE INDEX idx_ai_recommendations_system ON ai_recommendations(system_name, status, created_at DESC);
CREATE INDEX idx_ai_recommendations_type_priority ON ai_recommendations(recommendation_type, priority) WHERE status = 'active';

-- ============================================
-- STEP 4: ENABLE ROW LEVEL SECURITY
-- ============================================

ALTER TABLE system_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_recommendations ENABLE ROW LEVEL SECURITY;

-- ============================================
-- STEP 5: CREATE SECURITY POLICIES
-- ============================================

-- Policies for anon key (backend API access)
CREATE POLICY anon_all_system_health ON system_health FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all_workflow_events ON workflow_events FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_all_ai_recommendations ON ai_recommendations FOR ALL TO anon USING (true) WITH CHECK (true);

-- Policies for authenticated users (read-only for frontend)
CREATE POLICY auth_read_system_health ON system_health FOR SELECT TO authenticated USING (true);
CREATE POLICY auth_read_workflow_events ON workflow_events FOR SELECT TO authenticated USING (true);
CREATE POLICY auth_read_ai_recommendations ON ai_recommendations FOR SELECT TO authenticated USING (true);

-- Policies for service_role (full access)
CREATE POLICY service_all_system_health ON system_health FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all_workflow_events ON workflow_events FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_all_ai_recommendations ON ai_recommendations FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================
-- STEP 6: CREATE FUNCTIONS
-- ============================================

-- Function to cleanup old health checks (keeps last 1000 per system)
CREATE FUNCTION cleanup_old_health_checks()
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
-- STEP 7: CREATE MATERIALIZED VIEW
-- ============================================

-- Pre-computed stats for faster dashboard loading
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
CREATE UNIQUE INDEX idx_health_summary_system ON system_health_summary(system_name);

-- Function to refresh the materialized view
CREATE FUNCTION refresh_health_summary()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY system_health_summary;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- STEP 8: ADD TABLE COMMENTS
-- ============================================

COMMENT ON TABLE system_health IS 'Stores health check results with optimized indexing for performance';
COMMENT ON TABLE workflow_events IS 'Logs workflow events with optimized querying for active events';
COMMENT ON TABLE ai_recommendations IS 'Stores AI-generated recommendations with efficient filtering';

-- ============================================
-- SUCCESS!
-- ============================================
-- ✅ All tables created
-- ✅ All indexes created  
-- ✅ All policies created
-- ✅ All functions created
-- ✅ Materialized view created
-- ✅ Ready to use!
-- ============================================

-- Verify tables exist
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables 
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename;

-- Show indexes
SELECT 
    tablename,
    indexname
FROM pg_indexes 
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename, indexname;

-- Show policies
SELECT 
    tablename,
    policyname
FROM pg_policies
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename, policyname;

-- ============================================
-- DONE! Your database is ready! 🎉
-- ============================================



