import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';
import { initDb } from './db';
import authRoutes from './routes/authRoutes';
import inventoryRoutes from './routes/inventoryRoutes'; // To be implemented

const app = express();

// Security Middleware
app.use(helmet());

// CORS Configuration - Allow both dev and production origins
const allowedOrigins = [
    'http://localhost:3001', 
    'http://localhost:5173',
    process.env.FRONTEND_URL // Production frontend URL from Render
].filter(Boolean); // Remove undefined values

app.use(cors({
    origin: (origin, callback) => {
        // Allow requests with no origin (like mobile apps or curl)
        if (!origin) return callback(null, true);
        
        if (allowedOrigins.indexOf(origin) !== -1 || origin.endsWith('.onrender.com')) {
            callback(null, true);
        } else {
            callback(new Error('Not allowed by CORS'));
        }
    },
    credentials: true
}));
app.use(express.json({ limit: '10kb' })); // Limit body size to prevent DoS
app.use(morgan('dev'));

// XSS Sanitization Middleware
import xss from 'xss';
app.use((req, res, next) => {
    if (req.body) {
        const sanitize = (obj: any) => {
            for (const key in obj) {
                if (typeof obj[key] === 'string') {
                    obj[key] = xss(obj[key]);
                } else if (typeof obj[key] === 'object' && obj[key] !== null) {
                    sanitize(obj[key]);
                }
            }
        };
        sanitize(req.body);
    }
    next();
});

// Database Init
initDb();

import dataRoutes from './routes/dataRoutes';

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/inventory', inventoryRoutes);
app.use('/api/data', dataRoutes);

// Health Check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Global Error Handler
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
    console.error(err.stack);
    res.status(500).json({ error: 'Internal Server Error' });
});

export default app;
