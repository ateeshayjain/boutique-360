import { Request, Response } from 'express';
import db from '../db';

export class CustomerController {
    async getAll(req: Request, res: Response) {
        try {
            const customers = db.prepare('SELECT * FROM customers').all();
            // Map snake_case to camelCase
            const mapped = customers.map((c: any) => ({
                id: c.id,
                name: c.name,
                email: c.email,
                phone: c.phone,
                branchId: c.branch_id,
                vipStatus: !!c.vip_status,
                loyaltyPoints: c.loyalty_points,
                joinDate: c.created_at
            }));
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }
}
