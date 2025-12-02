# ⚡ Quick Start - IAJ Management Hub

## Status: Server Running ✅

Your backend is currently running at: **http://localhost:8000**

---

## 🚨 ONE CRITICAL STEP REMAINING

### Create Supabase Tables (5 minutes)

**Without this, you'll see database errors!**

1. Open: https://supabase.com/dashboard/project/yljdgsywqombavyzxhqj
2. Click: **SQL Editor** → **New Query**
3. Copy: All content from `setup_database_optimized.sql`
4. Paste: Into Supabase editor
5. Click: **Run**

You should see green checkmarks for:
- 3 tables created
- 15+ indexes created
- 9+ security policies created
- Materialized view created

**After this, your system will be fully operational!**

---

## ✅ What's Already Working

- ✅ Server running on port 8000
- ✅ 6 systems configured for monitoring
- ✅ Smart intervals (5min/10min)
- ✅ Scheduler configured
- ✅ AI recommendations ready
- ✅ Auto-cleanup scheduled
- ✅ API documentation at /docs

---

## 🧪 Test It (After Creating Tables)

### 1. View API Docs
Open: **http://localhost:8000/docs**

### 2. Get Health Overview
```bash
curl http://localhost:8000/api/health/overview
```

### 3. Trigger Manual Check
```bash
curl -X POST http://localhost:8000/api/health/check
```

### 4. Generate AI Recommendations
```bash
curl -X POST http://localhost:8000/api/recommendations/generate
```

---

## 📊 Monitoring Configuration

### High Priority (Every 5 min)
- Story Grid Pro: `https://storygrid-pro-production.up.railway.app`
- IAJ Social Main: `https://web-production-29982.up.railway.app`

### Medium Priority (Every 10 min)
- Agent Training: `.../api/agent-training`
- Video Processor: `.../api/video-processor`
- Social Studio: `.../api/social-studio`
- Batch Studio: `.../api/social-studio/batch`

---

## 🤖 AI Features

- **Claude Sonnet 4** analyzes your systems daily at 9:00 AM
- Identifies performance issues
- Suggests optimizations
- Flags bottlenecks
- Provides actionable recommendations

---

## 📁 Important Files

| File | Purpose |
|------|---------|
| `main.py` | Main application (already running) |
| `setup_database_optimized.sql` | **Run this in Supabase!** |
| `.env` | Configuration (already set) |
| `DEPLOYMENT_GUIDE.md` | Full documentation |
| `SETUP_COMPLETE.md` | Detailed setup info |

---

## 🚀 For Story Grid Pro

Once tables are created, integrate with:

```javascript
// Get system health
const health = await fetch('https://your-hub-url/api/health/overview');

// Get AI recommendations  
const recs = await fetch('https://your-hub-url/api/recommendations');

// Get performance metrics
const metrics = await fetch('https://your-hub-url/api/metrics/performance');
```

---

## 🆘 Need Help?

1. **Check server logs** in your terminal
2. **View API docs** at http://localhost:8000/docs
3. **Read DEPLOYMENT_GUIDE.md** for detailed info
4. **Check SETUP_COMPLETE.md** for troubleshooting

---

## ⏭️ Next: Deploy to Railway

Once everything works locally:

1. Push to GitHub
2. Connect to Railway
3. Add environment variables
4. Deploy!

Railway will use the same `main.py` and `.env` configuration.

---

**Remember:** Run that SQL file in Supabase! That's the only thing left! 🎯



