# Boutique 360 Deployment Guide

## Overview

This guide covers deploying the Boutique 360 full-stack application to **Render**. The application consists of:
- **Frontend**: React + Vite (Static Site)
- **Backend**: Node.js + Express + SQLite (Web Service)

## Prerequisites

1. **Render Account**: Sign up at [render.com](https://render.com) (free tier available)
2. **GitHub Repository**: Push your code to GitHub
3. **Environment Variables**:
   - `GEMINI_API_KEY` - Your Google Gemini API key
   - `JWT_SECRET` - A secure random string (min 32 characters)

## Deployment Steps

### Option 1: Deploy via render.yaml (Recommended)

This method uses the included `render.yaml` file for infrastructure-as-code deployment.

1. **Push to GitHub**:
   ```bash
   git init
   git add .
   git commit -m "Initial commit - ready for deployment"
   git remote add origin <your-github-repo-url>
   git push -u origin main
   ```

2. **Connect to Render**:
   - Go to [Render Dashboard](https://dashboard.render.com)
   - Click **"New"** → **"Blueprint"**
   - Connect your GitHub repository
   - Render will automatically detect `render.yaml`

3. **Set Environment Variables**:
   - In the Render dashboard, go to each service
   - Add the following environment variables:
     - **Backend Service**:
       - `GEMINI_API_KEY`: Your Gemini API key
       - `JWT_SECRET`: Auto-generated (or set your own)
       - `NODE_ENV`: `production` (auto-set)
     - **Frontend Service**:
       - `GEMINI_API_KEY`: Your Gemini API key
       - `VITE_API_URL`: Will auto-populate from backend service

4. **Deploy**:
   - Click **"Apply"** to create both services
   - Render will build and deploy automatically
   - Wait 5-10 minutes for initial deployment

### Option 2: Manual Deployment

#### Deploy Backend

1. **Create Web Service**:
   - Dashboard → **"New"** → **"Web Service"**
   - Connect GitHub repository
   - Configure:
     - **Name**: `boutique-360-backend`
     - **Root Directory**: `server`
     - **Environment**: `Node`
     - **Build Command**: `npm install && npm run build`
     - **Start Command**: `npm start`
     - **Plan**: Free

2. **Environment Variables**:
   - Add `GEMINI_API_KEY`, `JWT_SECRET`, `NODE_ENV=production`

3. **Deploy**: Click **"Create Web Service"**

#### Deploy Frontend

1. **Create Static Site**:
   - Dashboard → **"New"** → **"Static Site"**
   - Connect GitHub repository
   - Configure:
     - **Name**: `boutique-360-frontend`
     - **Build Command**: `npm install && npm run build`
     - **Publish Directory**: `dist`

2. **Environment Variables**:
   - `VITE_API_URL`: `https://boutique-360-backend.onrender.com` (your backend URL)
   - `GEMINI_API_KEY`: Your Gemini API key

3. **Deploy**: Click **"Create Static Site"**

## Post-Deployment

### Verify Deployment

1. **Backend Health Check**:
   - Visit: `https://your-backend-url.onrender.com/health`
   - Should return: `{"status": "ok", "timestamp": "..."}`

2. **Frontend**:
   - Visit: `https://your-frontend-url.onrender.com`
   - Should load the Boutique 360 interface

3. **Test Authentication**:
   - Register a new user
   - Login and verify JWT token works
   - Check browser console for errors

### Important Notes

> [!WARNING]
> **SQLite on Render Free Tier**: The free tier has an ephemeral filesystem. Your database will reset on each deploy or service restart. For production use, consider:
> - Upgrading to a paid plan with persistent disk
> - Migrating to PostgreSQL (Render offers free PostgreSQL databases)

> [!IMPORTANT]
> **First Load**: Render free tier services spin down after 15 minutes of inactivity. The first request after inactivity may take 30-60 seconds to wake up.

### Custom Domain (Optional)

1. Go to your frontend service settings
2. Click **"Custom Domain"**
3. Add your domain and follow DNS configuration instructions

## Troubleshooting

### CORS Errors
- Verify `VITE_API_URL` in frontend matches your backend URL
- Check backend CORS configuration allows your frontend origin

### Build Failures
- Check build logs in Render dashboard
- Verify all dependencies are in `package.json`
- Ensure Node version compatibility (app uses Node 20)

### Database Issues
- On free tier, database resets on deploy
- Check if `boutique.db` file exists in `/app/data`
- Consider migrating to PostgreSQL for persistence

### Environment Variables Not Working
- Ensure variables are set in Render dashboard
- Restart services after adding new variables
- Check variable names match exactly (case-sensitive)

## Updating the Application

```bash
# Make changes locally
git add .
git commit -m "Update description"
git push origin main

# Render will automatically redeploy
```

## Alternative Platforms

### Vercel (Frontend Only)

```bash
npm install -g vercel
cd /path/to/boutique-360
vercel --prod
```

### Railway (Full-Stack)

1. Install Railway CLI: `npm install -g @railway/cli`
2. Login: `railway login`
3. Deploy: `railway up`

## Support

- **Render Docs**: https://render.com/docs
- **Vite Deployment**: https://vitejs.dev/guide/static-deploy.html
- **Express Production**: https://expressjs.com/en/advanced/best-practice-performance.html
