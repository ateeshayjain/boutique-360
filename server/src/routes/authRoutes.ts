import { Router } from 'express';
import { AuthController } from '../controllers/AuthController';

import rateLimit from 'express-rate-limit';

const router = Router();
const authController = new AuthController();

// Rate Limiter: Max 100 requests per 15 minutes
const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100,
    message: 'Too many login attempts from this IP, please try again after 15 minutes',
    standardHeaders: true,
    legacyHeaders: false,
});

router.post('/login', authLimiter, (req, res) => authController.login(req, res));
router.post('/register', authLimiter, (req, res) => authController.register(req, res));

export default router;
