# Eden Railway Deployment Guide

This guide describes how to deploy the Eden FastAPI backend to Railway Pro and verify that it is running correctly.

---

## 1. Create a Railway Project

1. Log into your [Railway Dashboard](https://railway.app/).
2. Click **New Project** in the top-right corner.
3. Choose **Deploy from GitHub repo** and select your repository.
4. If prompted, select the root folder or the directory of the deployment. For this monorepo structure, specify the root or `backend` subdirectory accordingly as the root.

---

## 2. Add Persistent Volume

To ensure that the SQLite database (`eden.db`) persists across redeployments:

1. In your service's settings, click **+ Add** -> **Volume**.
2. Set the volume Mount Path to:
   ```
   /app/data
   ```
3. Set the size (e.g., `5 GB` or custom, SQLite databases are compact).
4. Save the volume configuration.

---

## 3. Configure Environment Variables

Navigate to the **Variables** tab of your service in Railway and set the following environment variables:

| Variable | Description | Value / Format |
|---|---|---|
| `ENVIRONMENT` | Running environment mode | `production` |
| `LOG_LEVEL` | Logging verbosity | `INFO` (or `WARNING` / `DEBUG`) |
| `APP_HOST` | FastAPI server host | `0.0.0.0` |
| `APP_PORT` | FastAPI server port | `8001` |
| `DATABASE_URL` | SQLite database path (must start with `/app/data/`) | `/app/data/eden.db` |
| `GROQ_API_KEY` | Groq API Key | `gsk_...` |
| `GROQ_CHAT_MODEL` | Chat model identifier | `llama-3.3-70b-versatile` |
| `GROQ_FAST_MODEL` | Background extraction model | `llama-3.1-8b-instant` |
| `LLM_TEMPERATURE` | Temperature setting for LLM responses | `0.85` |
| `LLM_MAX_TOKENS` | Max generation tokens | `400` |
| `MAX_CONTEXT_MESSAGES` | Max context history size | `10` |
| `FIREBASE_PROJECT_ID` | Firebase project identifier | `your-firebase-project-id` |
| `FIREBASE_CREDENTIALS_B64` | Base64 encoded string of Firebase JSON credentials (see section below) | `eyJ0eXBlIjog...` |
| `OPS_SECRET_KEY` | Admin operational API key | Change from default (e.g., `prod-secret-random-key`) |
| `PORT` | Auto-provided by Railway | Do not set manually, handled dynamically |

---

## 4. Base64 Encode Firebase Credentials

In production environments, we set `FIREBASE_CREDENTIALS_B64` instead of uploading a `firebase-credentials.json` file.

To encode your Firebase JSON credentials:

### On Windows (PowerShell):
```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("path/to/firebase-credentials.json"))
```

### On macOS / Linux:
```bash
base64 -i path/to/firebase-credentials.json -o -
```

Copy the generated base64 string and paste it into the `FIREBASE_CREDENTIALS_B64` variable in Railway.

---

## 5. Verifying the Deployment

### A. Basic Health Check
To verify that the server is online and running, make a `GET` request to:
```
https://<your-railway-domain>/health
```
**Response Format:**
```json
{
  "status": "ok",
  "version": "2.0.0",
  "environment": "production"
}
```

### B. Deep Health Check (Operational)
To perform a deep check of SQLite tables, database connections, and latency metrics for the LLM gateway:
```bash
curl -H "X-Ops-Key: <your-ops-secret-key>" https://<your-railway-domain>/api/ops/health/deep
```

---

## 6. How to Check Logs in Railway

1. Click on your project service panel in the Railway dashboard.
2. Select the **Deployments** or **Deploy** tab.
3. Click on the current active deployment to view real-time streaming application logs.
4. On startup, look for these log entries to confirm successful preloading:
   - `Loading embedding model all-MiniLM-L6-v2...`
   - `Embedding model loaded: all-MiniLM-L6-v2`
   - `Background scheduler started successfully`

---

## 7. How to Test Push Notifications

To test that push notification routing is working properly for a specific user:

```bash
curl -X POST \
  -H "X-Ops-Key: <your-ops-secret-key>" \
  https://<your-railway-domain>/api/ops/test_notification/<user_firebase_uid>
```

**Possible Responses:**
- `{"sent": true, "token_exists": true}` -> Successfully sent via FCM.
- `{"sent": false, "token_exists": false}` -> FCM Token is not registered for the user yet (register device FCM token in profile settings first).
