"""
IAJ Management Hub - Intelligent Monitoring & Recommendation Engine
Production-ready backend service with smart caching, retry logic, and AI insights
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Optional
import uvicorn
import httpx
import os
import logging
from dotenv import load_dotenv
from supabase import create_client, Client
from anthropic import Anthropic
import asyncio
from functools import wraps
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Initialize clients with error handling for missing env vars
def init_supabase() -> Optional[Client]:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    if url and key:
        try:
            return create_client(url, key)
        except Exception as e:
            logger.error(f"Failed to initialize Supabase: {e}")
            return None
    logger.warning("SUPABASE_URL or SUPABASE_KEY not set - database features disabled")
    return None

def init_anthropic() -> Optional[Anthropic]:
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if api_key:
        try:
            return Anthropic(api_key=api_key)
        except Exception as e:
            logger.error(f"Failed to initialize Anthropic: {e}")
            return None
    logger.warning("ANTHROPIC_API_KEY not set - AI features disabled")
    return None

supabase: Optional[Client] = init_supabase()
anthropic_client: Optional[Anthropic] = init_anthropic()

# System configuration with check intervals
SYSTEMS = {
    "story_grid_pro": {
        "name": "Story Grid Pro",
        "url": os.getenv("STORY_GRID_PRO_URL"),
        "endpoint": "/api/status",
        "description": "Production planning and module hub",
        "check_interval": 300,  # 5 minutes
        "priority": "high"
    },
    "iaj_social_main": {
        "name": "IAJ Social Main",
        "url": os.getenv("IAJ_SOCIAL_BASE_URL"),
        "endpoint": "/api/status",
        "description": "Main IAJ Social application",
        "check_interval": 300,  # 5 minutes
        "priority": "high"
    },
    "agent_training": {
        "name": "Agent Training",
        "url": os.getenv("IAJ_SOCIAL_BASE_URL"),
        "endpoint": "/api/agent-training/status",
        "description": "AI agent training module",
        "check_interval": 600,  # 10 minutes
        "priority": "medium"
    },
    "video_processor": {
        "name": "Video Processor",
        "url": os.getenv("IAJ_SOCIAL_BASE_URL"),
        "endpoint": "/api/video-processor/status",
        "description": "Video processing module",
        "check_interval": 600,  # 10 minutes
        "priority": "medium"
    },
    "social_studio": {
        "name": "Social Studio",
        "url": os.getenv("IAJ_SOCIAL_BASE_URL"),
        "endpoint": "/api/social-studio/status",
        "description": "AI content creation module",
        "check_interval": 600,  # 10 minutes
        "priority": "medium"
    },
    "batch_studio": {
        "name": "Batch Studio",
        "url": os.getenv("IAJ_SOCIAL_BASE_URL"),
        "endpoint": "/api/social-studio/batch/status",
        "description": "Batch content processing module",
        "check_interval": 600,  # 10 minutes
        "priority": "medium"
    }
}

# Cache configuration
CACHE = {
    "health_overview": {"data": None, "timestamp": None, "ttl": 60},  # 1 minute
    "recommendations": {"data": None, "timestamp": None, "ttl": 300},  # 5 minutes
}

# Scheduler instance
scheduler = AsyncIOScheduler()

# Simple cache decorator
def cached(cache_key: str, ttl: int):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            now = time.time()
            cache_entry = CACHE.get(cache_key)
            
            if cache_entry and cache_entry["data"] is not None:
                if cache_entry["timestamp"] and (now - cache_entry["timestamp"]) < ttl:
                    logger.info(f"Cache hit for {cache_key}")
                    return cache_entry["data"]
            
            result = await func(*args, **kwargs)
            CACHE[cache_key] = {"data": result, "timestamp": now, "ttl": ttl}
            return result
        return wrapper
    return decorator

# Retry logic with exponential backoff
async def retry_with_backoff(func, max_retries=3, base_delay=1):
    """Execute function with exponential backoff retry logic"""
    for attempt in range(max_retries):
        try:
            return await func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise e
            delay = base_delay * (2 ** attempt)
            logger.warning(f"Retry attempt {attempt + 1} after {delay}s: {str(e)}")
            await asyncio.sleep(delay)

# Lifespan context manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("=" * 80)
    logger.info("🚀 IAJ Management Hub API - Starting")
    logger.info("=" * 80)
    logger.info(f"📊 Monitoring {len(SYSTEMS)} systems with smart intervals")
    
    for key, info in SYSTEMS.items():
        interval_min = info["check_interval"] // 60
        priority_emoji = "🔴" if info["priority"] == "high" else "🟡"
        logger.info(f"  {priority_emoji} {info['name']} (every {interval_min}min)")
    
    logger.info("=" * 80)
    
    # Start the scheduler
    scheduler.start()
    
    # Schedule health checks for high-priority systems (every 5 min)
    scheduler.add_job(
        check_high_priority_systems,
        trigger=IntervalTrigger(seconds=300),
        id="health_check_high_priority",
        name="High Priority Health Checks (5min)",
        replace_existing=True
    )
    
    # Schedule health checks for medium-priority systems (every 10 min)
    scheduler.add_job(
        check_medium_priority_systems,
        trigger=IntervalTrigger(seconds=600),
        id="health_check_medium_priority",
        name="Medium Priority Health Checks (10min)",
        replace_existing=True
    )
    
    # Schedule AI recommendations (daily at 9am)
    scheduler.add_job(
        generate_daily_recommendations,
        trigger=CronTrigger(hour=9, minute=0),
        id="daily_recommendations",
        name="Daily AI Recommendations (9am)",
        replace_existing=True
    )
    
    # Schedule cleanup of old data (daily at 2am)
    scheduler.add_job(
        cleanup_old_data,
        trigger=CronTrigger(hour=2, minute=0),
        id="cleanup_old_data",
        name="Cleanup Old Data (2am)",
        replace_existing=True
    )
    
    logger.info("✅ Scheduler started with optimized intervals")
    logger.info("✅ AI recommendations scheduled daily at 9:00 AM")
    logger.info("✅ Auto-cleanup scheduled daily at 2:00 AM")
    logger.info("=" * 80)
    
    # Schedule initial health check to run after startup (non-blocking)
    # This prevents slow health checks from blocking the app startup
    scheduler.add_job(
        check_all_systems,
        trigger='date',  # Run once
        id="initial_health_check",
        name="Initial Health Check",
        replace_existing=True
    )
    logger.info("📋 Initial health check scheduled (runs in background)")
    
    yield
    
    # Shutdown
    logger.info("🛑 Shutting down IAJ Management Hub")
    scheduler.shutdown()

# Initialize FastAPI app
app = FastAPI(
    title="IAJ Management Hub API",
    description="Intelligent monitoring and recommendation engine for IAJ systems",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS configuration - Allow all origins for development (including file://)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins including file://
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check function with retry logic
async def check_system_health(system_key: str, system_info: Dict[str, str]) -> Dict[str, Any]:
    """Check the health of a single system with retry logic"""
    start_time = datetime.now(timezone.utc)
    
    async def attempt_check():
        async with httpx.AsyncClient(timeout=10.0) as client:
            # Use custom endpoint if specified, otherwise default to /api/status
            base_url = system_info['url'].rstrip('/')
            endpoint = system_info.get('endpoint', '/api/status')
            url = f"{base_url}{endpoint}"
            response = await client.get(url)
            return response
    
    try:
        response = await retry_with_backoff(attempt_check, max_retries=2, base_delay=1)
        response_time = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000
        
        if response.status_code == 200:
            data = response.json()
            return {
                "system_name": system_key,
                "status": "healthy",
                "response_time_ms": round(response_time, 2),
                "last_check": datetime.now(timezone.utc).isoformat(),
                "error_message": None,
                "metadata": data
            }
        else:
            return {
                "system_name": system_key,
                "status": "unhealthy",
                "response_time_ms": round(response_time, 2),
                "last_check": datetime.now(timezone.utc).isoformat(),
                "error_message": f"HTTP {response.status_code}",
                "metadata": {"status_code": response.status_code}
            }
    
    except httpx.TimeoutException:
        return {
            "system_name": system_key,
            "status": "timeout",
            "response_time_ms": None,
            "last_check": datetime.now(timezone.utc).isoformat(),
            "error_message": "Request timeout after retries",
            "metadata": {}
        }
    
    except Exception as e:
        return {
            "system_name": system_key,
            "status": "error",
            "response_time_ms": None,
            "last_check": datetime.now(timezone.utc).isoformat(),
            "error_message": str(e),
            "metadata": {}
        }

# Check high-priority systems
async def check_high_priority_systems():
    """Check systems with 5-minute intervals"""
    high_priority = {k: v for k, v in SYSTEMS.items() if v["priority"] == "high"}
    logger.info(f"🔴 Checking {len(high_priority)} high-priority systems")
    await run_health_checks(high_priority)

# Check medium-priority systems
async def check_medium_priority_systems():
    """Check systems with 10-minute intervals"""
    medium_priority = {k: v for k, v in SYSTEMS.items() if v["priority"] == "medium"}
    logger.info(f"🟡 Checking {len(medium_priority)} medium-priority systems")
    await run_health_checks(medium_priority)

# Check all systems
async def check_all_systems():
    """Check all systems (used for manual triggers)"""
    logger.info(f"🔍 Checking all {len(SYSTEMS)} systems")
    await run_health_checks(SYSTEMS)

# Run health checks for given systems
async def run_health_checks(systems: Dict[str, Dict[str, Any]]):
    """Run health checks and store results"""
    tasks = []
    for system_key, system_info in systems.items():
        tasks.append(check_system_health(system_key, system_info))
    
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    for health_data in results:
        if isinstance(health_data, Exception):
            logger.error(f"Error checking system: {str(health_data)}")
            continue
        
        try:
            # Store in Supabase
            supabase.table("system_health").insert(health_data).execute()
            
            status_emoji = "✅" if health_data["status"] == "healthy" else "❌"
            system_name = SYSTEMS.get(health_data["system_name"], {}).get("name", health_data["system_name"])
            logger.info(f"{status_emoji} {system_name}: {health_data['status']}")
            
            # Clear cache on new data
            CACHE["health_overview"]["data"] = None
            
            # Log alert for unhealthy systems
            if health_data["status"] != "healthy":
                workflow_event = {
                    "event_type": "system_health_alert",
                    "source_system": "management_hub",
                    "target_system": health_data["system_name"],
                    "status": "completed",
                    "payload": health_data,
                    "created_at": datetime.now(timezone.utc).isoformat()
                }
                supabase.table("workflow_events").insert(workflow_event).execute()
        
        except Exception as e:
            logger.error(f"Error storing health data for {health_data.get('system_name')}: {str(e)}")

# Cleanup old data
async def cleanup_old_data():
    """Keep only last 1000 checks per system"""
    logger.info("🧹 Starting cleanup of old data")
    
    try:
        for system_key in SYSTEMS.keys():
            # Get count of records for this system
            response = supabase.table("system_health")\
                .select("id", count="exact")\
                .eq("system_name", system_key)\
                .execute()
            
            total_count = response.count if hasattr(response, 'count') else 0
            
            if total_count > 1000:
                # Get the ID of the 1000th most recent record
                records = supabase.table("system_health")\
                    .select("id")\
                    .eq("system_name", system_key)\
                    .order("created_at", desc=True)\
                    .limit(1)\
                    .range(999, 999)\
                    .execute()
                
                if records.data:
                    cutoff_id = records.data[0]["id"]
                    # Delete records older than this
                    supabase.table("system_health")\
                        .delete()\
                        .eq("system_name", system_key)\
                        .lt("id", cutoff_id)\
                        .execute()
                    
                    deleted = total_count - 1000
                    logger.info(f"🧹 Cleaned {deleted} old records for {system_key}")
        
        logger.info("✅ Cleanup complete")
    
    except Exception as e:
        logger.error(f"❌ Cleanup error: {str(e)}")

# Generate AI recommendations
async def generate_recommendations() -> List[Dict[str, Any]]:
    """Use Claude Sonnet 4 to analyze system performance and generate recommendations"""
    try:
        logger.info("🧠 Generating AI recommendations with Claude Sonnet 4")
        
        # Fetch comprehensive data
        health_data = supabase.table("system_health")\
            .select("*")\
            .order("created_at", desc=True)\
            .limit(200)\
            .execute()
        
        workflow_data = supabase.table("workflow_events")\
            .select("*")\
            .order("created_at", desc=True)\
            .limit(100)\
            .execute()
        
        # Build context
        context = "# IAJ Systems Performance Analysis\n\n"
        
        # Calculate statistics
        system_stats = {}
        for record in health_data.data:
            sys_name = record['system_name']
            if sys_name not in system_stats:
                system_stats[sys_name] = {
                    'total': 0, 'healthy': 0, 'unhealthy': 0,
                    'errors': [], 'response_times': []
                }
            
            system_stats[sys_name]['total'] += 1
            if record['status'] == 'healthy':
                system_stats[sys_name]['healthy'] += 1
            else:
                system_stats[sys_name]['unhealthy'] += 1
                if record.get('error_message'):
                    system_stats[sys_name]['errors'].append(record['error_message'])
            
            if record.get('response_time_ms'):
                system_stats[sys_name]['response_times'].append(record['response_time_ms'])
        
        context += "## System Health Summary\n\n"
        for sys_name, stats in system_stats.items():
            uptime = (stats['healthy'] / stats['total'] * 100) if stats['total'] > 0 else 0
            avg_response = sum(stats['response_times']) / len(stats['response_times']) if stats['response_times'] else 0
            
            context += f"### {SYSTEMS.get(sys_name, {}).get('name', sys_name)}\n"
            context += f"- Uptime: {uptime:.1f}%\n"
            context += f"- Avg Response: {avg_response:.0f}ms\n"
            context += f"- Issues: {stats['unhealthy']}/{stats['total']} checks\n"
            if stats['errors']:
                context += f"- Recent Errors: {', '.join(set(stats['errors'][:3]))}\n"
            context += "\n"
        
        # Call Claude Sonnet 4
        message = anthropic_client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=2000,
            messages=[{
                "role": "user",
                "content": f"""{context}

Analyze this data and provide 3-5 actionable recommendations as JSON:

[{{"title": "...", "description": "...", "priority": "high|medium|low", "system_name": "...", "recommendation_type": "performance|reliability|optimization", "action": "..."}}]"""
            }]
        )
        
        # Parse response
        import json
        import re
        
        recommendations_text = message.content[0].text
        json_match = re.search(r'\[[\s\S]*\]', recommendations_text)
        
        if json_match:
            try:
                parsed_recs = json.loads(json_match.group())
                formatted_recs = []
                
                for rec in parsed_recs:
                    formatted_recs.append({
                        "recommendation_type": rec.get("recommendation_type", "general"),
                        "priority": rec.get("priority", "medium"),
                        "title": rec.get("title", "System Recommendation"),
                        "description": rec.get("description", ""),
                        "system_name": rec.get("system_name", "all"),
                        "actionable": True,
                        "action_url": None,
                        "status": "active",
                        "metadata": {
                            "source": "claude_sonnet_4",
                            "action": rec.get("action", ""),
                            "generated_at": datetime.now(timezone.utc).isoformat()
                        },
                        "created_at": datetime.now(timezone.utc).isoformat()
                    })
                
                logger.info(f"✅ Generated {len(formatted_recs)} recommendations")
                return formatted_recs
            
            except json.JSONDecodeError:
                logger.warning("⚠️ Could not parse JSON from Claude")
        
        # Fallback
        return [{
            "recommendation_type": "analysis",
            "priority": "medium",
            "title": "System Analysis Complete",
            "description": recommendations_text[:1000],
            "system_name": "all",
            "actionable": True,
            "action_url": None,
            "status": "active",
            "metadata": {"source": "claude_sonnet_4"},
            "created_at": datetime.now(timezone.utc).isoformat()
        }]
    
    except Exception as e:
        logger.error(f"❌ Error generating recommendations: {str(e)}")
        return []

# Daily recommendations
async def generate_daily_recommendations():
    """Generate recommendations daily at 9am"""
    logger.info("📊 Running daily AI recommendation generation")
    recommendations = await generate_recommendations()
    
    for rec in recommendations:
        try:
            supabase.table("ai_recommendations").insert(rec).execute()
        except Exception as e:
            logger.error(f"Error storing recommendation: {str(e)}")
    
    # Clear recommendations cache
    CACHE["recommendations"]["data"] = None

# API Endpoints

@app.get("/")
async def root():
    """API information"""
    return {
        "service": "IAJ Management Hub API",
        "version": "2.0.0",
        "description": "Intelligent monitoring with optimized intervals and AI insights",
        "features": [
            "Smart health monitoring (5min/10min intervals)",
            "AI-powered recommendations (Claude Sonnet 4)",
            "Performance metrics with caching",
            "Auto-cleanup (keep last 1000 checks)",
            "Retry logic with exponential backoff"
        ],
        "endpoints": {
            "health_overview": "/api/health/overview",
            "health_detailed": "/api/health/detailed",
            "recommendations": "/api/recommendations",
            "generate_recommendations": "/api/recommendations/generate",
            "performance_metrics": "/api/metrics/performance",
            "trigger_check": "/api/health/check"
        },
        "docs": "/docs"
    }

@app.get("/api/health/overview")
@cached("health_overview", 60)
async def get_health_overview():
    """Quick status overview (cached 1min)"""
    try:
        results = {}
        
        for system_key, system_info in SYSTEMS.items():
            response = supabase.table("system_health")\
                .select("*")\
                .eq("system_name", system_key)\
                .order("created_at", desc=True)\
                .limit(1)\
                .execute()
            
            if response.data:
                latest = response.data[0]
                results[system_key] = {
                    "name": system_info["name"],
                    "status": latest["status"],
                    "response_time_ms": latest.get("response_time_ms"),
                    "last_check": latest["last_check"],
                    "priority": system_info["priority"]
                }
            else:
                results[system_key] = {
                    "name": system_info["name"],
                    "status": "unknown",
                    "priority": system_info["priority"]
                }
        
        overall_healthy = sum(1 for s in results.values() if s["status"] == "healthy")
        
        return {
            "overall_health": f"{overall_healthy}/{len(SYSTEMS)}",
            "systems": results,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "cached": True
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/health/detailed")
async def get_health_detailed():
    """Detailed health status with recent history"""
    try:
        results = {}
        
        for system_key, system_info in SYSTEMS.items():
            response = supabase.table("system_health")\
                .select("*")\
                .eq("system_name", system_key)\
                .order("created_at", desc=True)\
                .limit(10)\
                .execute()
            
            if response.data:
                # Calculate uptime from last 10 checks
                healthy_count = sum(1 for r in response.data if r["status"] == "healthy")
                uptime = (healthy_count / len(response.data)) * 100
                
                results[system_key] = {
                    "name": system_info["name"],
                    "description": system_info["description"],
                    "priority": system_info["priority"],
                    "check_interval": system_info["check_interval"],
                    "current_status": response.data[0],
                    "recent_history": response.data,
                    "uptime_percentage": round(uptime, 1)
                }
        
        return {
            "systems": results,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/recommendations")
@cached("recommendations", 300)
async def get_recommendations(status: str = "active", limit: int = 10):
    """Get AI recommendations (cached 5min)"""
    try:
        query = supabase.table("ai_recommendations").select("*").eq("status", status)
        response = query.order("created_at", desc=True).limit(limit).execute()
        
        return {
            "recommendations": response.data,
            "count": len(response.data),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "cached": True
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/recommendations/generate")
async def trigger_recommendations():
    """Manually trigger AI recommendation generation"""
    try:
        recommendations = await generate_recommendations()
        
        for rec in recommendations:
            supabase.table("ai_recommendations").insert(rec).execute()
        
        # Clear cache
        CACHE["recommendations"]["data"] = None
        
        return {
            "message": "Recommendations generated",
            "count": len(recommendations),
            "recommendations": recommendations
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/metrics/performance")
async def get_performance_metrics():
    """Get performance trends and metrics"""
    try:
        # Get last 24 hours of data
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
        
        metrics = {}
        
        for system_key, system_info in SYSTEMS.items():
            response = supabase.table("system_health")\
                .select("*")\
                .eq("system_name", system_key)\
                .gte("created_at", cutoff.isoformat())\
                .order("created_at", desc=True)\
                .execute()
            
            if response.data:
                response_times = [r["response_time_ms"] for r in response.data if r.get("response_time_ms")]
                healthy_count = sum(1 for r in response.data if r["status"] == "healthy")
                
                metrics[system_key] = {
                    "name": system_info["name"],
                    "total_checks": len(response.data),
                    "healthy_checks": healthy_count,
                    "uptime_24h": round((healthy_count / len(response.data)) * 100, 2),
                    "avg_response_time": round(sum(response_times) / len(response_times), 2) if response_times else None,
                    "min_response_time": round(min(response_times), 2) if response_times else None,
                    "max_response_time": round(max(response_times), 2) if response_times else None
                }
        
        return {
            "period": "24 hours",
            "systems": metrics,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/health/check")
async def trigger_health_check():
    """Manually trigger health check for all systems"""
    try:
        await check_all_systems()
        return {
            "message": "Health check completed",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "systems_checked": len(SYSTEMS)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Run the application
if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        reload=True,
        log_level="info"
    )
