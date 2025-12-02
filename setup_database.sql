-- ============================================
-- IAJ MANAGEMENT HUB - Supabase Database Setup
-- ============================================
-- Run this SQL in: Supabase Dashboard → SQL Editor → New Query
-- 
-- Creates 3 tables:
-- 1. system_health - Stores health check results for all monitored systems
-- 2. workflow_events - Logs cross-system workflow events and alerts
-- 3. ai_recommendations - Stores Claude-generated insights and recommendations
-- ============================================

-- ============================================
-- TABLE 1: system_health
-- ============================================
-- Stores health check results for all IAJ systems
-- Each health check creates a new record for trend analysis

CREATE TABLE IF NOT EXISTS system_health (
    -- Primary key
    id BIGSERIAL PRIMARY KEY,
    
    -- System identification
    system_name TEXT NOT NULL,  -- e.g., 'story_grid_pro', 'analytics', 'social_studio'
    
    -- Health status
    status TEXT NOT NULL,  -- 'healthy', 'unhealthy', 'timeout', 'error'
    last_check TIMESTAMPTZ NOT NULL,
    
    -- Performance metrics
    response_time_ms NUMERIC(10, 2),  -- Response time in milliseconds
    
    -- Error tracking
    error_message TEXT,  -- NULL if healthy, error details if not
    
    -- Additional data
    metadata JSONB DEFAULT '{}'::jsonb,  -- Stores response data from /api/status endpoint
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast queries
CREATE INDEX idx_system_health_system_name ON system_health(system_name);
CREATE INDEX idx_system_health_created_at ON system_health(created_at DESC);
CREATE INDEX idx_system_health_status ON system_health(status);
CREATE INDEX idx_system_health_system_created ON system_health(system_name, created_at DESC);

-- Comment for documentation
COMMENT ON TABLE system_health IS 'Stores health check results for all monitored IAJ systems';

-- ============================================
-- TABLE 2: workflow_events
-- ============================================
-- Logs workflow events, system interactions, and alerts

CREATE TABLE IF NOT EXISTS workflow_events (
    -- Primary key
    id BIGSERIAL PRIMARY KEY,
    
    -- Event classification
    event_type TEXT NOT NULL,  -- e.g., 'system_health_alert', 'workflow_started', 'integration_failed'
    
    -- System relationships
    source_system TEXT NOT NULL,  -- System that triggered the event
    target_system TEXT,  -- System affected by the event (can be NULL for system-wide events)
    
    -- Event status
    status TEXT NOT NULL,  -- 'pending', 'in_progress', 'completed', 'failed'
    
    -- Event data
    payload JSONB DEFAULT '{}'::jsonb,  -- Event-specific data
    error_message TEXT,  -- NULL if successful, error details if failed
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ  -- NULL until event completes
);

-- Indexes for fast queries
CREATE INDEX idx_workflow_events_event_type ON workflow_events(event_type);
CREATE INDEX idx_workflow_events_source_system ON workflow_events(source_system);
CREATE INDEX idx_workflow_events_target_system ON workflow_events(target_system);
CREATE INDEX idx_workflow_events_status ON workflow_events(status);
CREATE INDEX idx_workflow_events_created_at ON workflow_events(created_at DESC);

-- Comment for documentation
COMMENT ON TABLE workflow_events IS 'Logs workflow events, system interactions, and alerts across IAJ systems';

-- ============================================
-- TABLE 3: ai_recommendations
-- ============================================
-- Stores AI-generated recommendations from Claude Sonnet 4

CREATE TABLE IF NOT EXISTS ai_recommendations (
    -- Primary key
    id BIGSERIAL PRIMARY KEY,
    
    -- Recommendation classification
    recommendation_type TEXT NOT NULL,  -- 'performance', 'reliability', 'optimization', 'bottleneck', 'issue'
    priority TEXT NOT NULL,  -- 'high', 'medium', 'low'
    
    -- Recommendation content
    title TEXT NOT NULL,  -- Brief, actionable title
    description TEXT NOT NULL,  -- Detailed analysis and recommendation
    
    -- System context
    system_name TEXT NOT NULL,  -- Affected system ('all' for system-wide recommendations)
    
    -- Actionability
    actionable BOOLEAN DEFAULT true,
    action_url TEXT,  -- Optional: Direct link to take action
    
    -- Recommendation status
    status TEXT DEFAULT 'active',  -- 'active', 'resolved', 'dismissed', 'expired'
    
    -- Metadata
    metadata JSONB DEFAULT '{}'::jsonb,  -- Stores metrics, source data, Claude analysis details
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ  -- Optional: When recommendation becomes stale
);

-- Indexes for fast queries
CREATE INDEX idx_ai_recommendations_priority ON ai_recommendations(priority);
CREATE INDEX idx_ai_recommendations_status ON ai_recommendations(status);
CREATE INDEX idx_ai_recommendations_system_name ON ai_recommendations(system_name);
CREATE INDEX idx_ai_recommendations_type ON ai_recommendations(recommendation_type);
CREATE INDEX idx_ai_recommendations_created_at ON ai_recommendations(created_at DESC);
CREATE INDEX idx_ai_recommendations_active ON ai_recommendations(status, priority) WHERE status = 'active';

-- Comment for documentation
COMMENT ON TABLE ai_recommendations IS 'Stores AI-generated insights and recommendations from Claude Sonnet 4';

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================
-- Enable RLS for security (optional but recommended)

-- Enable RLS on all tables
ALTER TABLE system_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_recommendations ENABLE ROW LEVEL SECURITY;

-- Create policies for authenticated users (adjust based on your needs)
-- These policies allow full access to authenticated users
-- Modify these based on your security requirements

CREATE POLICY "Allow all operations for authenticated users"
    ON system_health
    FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Allow all operations for authenticated users"
    ON workflow_events
    FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Allow all operations for authenticated users"
    ON ai_recommendations
    FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Allow service_role (backend API) full access
CREATE POLICY "Allow all operations for service role"
    ON system_health
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Allow all operations for service role"
    ON workflow_events
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Allow all operations for service role"
    ON ai_recommendations
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Allow anon read access (so your backend can query with anon key)
CREATE POLICY "Allow read access for anon"
    ON system_health
    FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "Allow all operations for anon"
    ON system_health
    FOR INSERT
    TO anon
    WITH CHECK (true);

CREATE POLICY "Allow read access for anon"
    ON workflow_events
    FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "Allow insert for anon"
    ON workflow_events
    FOR INSERT
    TO anon
    WITH CHECK (true);

CREATE POLICY "Allow read access for anon"
    ON ai_recommendations
    FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "Allow insert for anon"
    ON ai_recommendations
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- ============================================
-- SAMPLE DATA (Optional - for testing)
-- ============================================
-- Uncomment to insert sample data for testing

/*
-- Sample health check
INSERT INTO system_health (system_name, status, last_check, response_time_ms, metadata)
VALUES ('story_grid_pro', 'healthy', NOW(), 145.23, '{"version": "1.0.0", "uptime": "99.9%"}'::jsonb);

-- Sample workflow event
INSERT INTO workflow_events (event_type, source_system, target_system, status, payload)
VALUES ('system_health_alert', 'management_hub', 'analytics', 'completed', '{"alert_type": "high_latency"}'::jsonb);

-- Sample AI recommendation
INSERT INTO ai_recommendations (
    recommendation_type, 
    priority, 
    title, 
    description, 
    system_name, 
    metadata
)
VALUES (
    'performance',
    'high',
    'Analytics Response Time Degraded',
    'Analytics system response time has increased from 150ms to 450ms over the past 24 hours. This suggests a potential database query optimization issue or increased load.',
    'analytics',
    '{"avg_response_time": 450, "previous_avg": 150, "source": "claude_sonnet_4"}'::jsonb
);
*/

-- ============================================
-- VERIFICATION QUERIES
-- ============================================
-- Run these to verify tables were created successfully

-- Check table structure
SELECT table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY table_name, ordinal_position;

-- Check indexes
SELECT tablename, indexname 
FROM pg_indexes 
WHERE tablename IN ('system_health', 'workflow_events', 'ai_recommendations')
ORDER BY tablename;

-- ============================================
-- SUCCESS!
-- ============================================
-- If you see the table structures and indexes listed above,
-- your database is ready for the IAJ Management Hub!
--
-- Next steps:
-- 1. Update your .env file with real system URLs
-- 2. Run: uvicorn main:app --reload
-- 3. Test: http://localhost:8000/docs
-- ============================================



