import { Request, Response } from 'express';
import { z } from 'zod';
import { AuthService } from '../services/AuthService';

const authService = new AuthService();

const loginSchema = z.object({
    username: z.string().min(3),
    password: z.string().min(6)
});

export class AuthController {
    async login(req: Request, res: Response) {
        try {
            const { username, password } = loginSchema.parse(req.body);
            const result = await authService.login(username, password);
            res.json(result);
        } catch (error) {
            if (error instanceof z.ZodError) {
                res.status(400).json({ error: error });
            } else {
                res.status(401).json({ error: (error as Error).message });
            }
        }
    }

    async register(req: Request, res: Response) {
        try {
            const { username, password } = loginSchema.parse(req.body);
            const user = await authService.register(username, password);
            res.status(201).json({ message: 'User created', userId: user.id });
        } catch (error) {
            res.status(400).json({ error: (error as Error).message });
        }
    }
}
