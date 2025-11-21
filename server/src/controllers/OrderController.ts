import { Request, Response } from 'express';
import db from '../db';

export class OrderController {
    async getAll(req: Request, res: Response) {
        try {
            const orders = db.prepare('SELECT * FROM orders').all();
            // Fetch items for each order (N+1 problem here, but okay for demo scale)
            // In production, use JOINs or dataloader
            const mapped = orders.map((o: any) => {
                const items = db.prepare(`
              SELECT oi.quantity, p.id as productId 
              FROM order_items oi 
              JOIN products p ON oi.product_id = p.id 
              WHERE oi.order_id = ?
          `).all(o.id);

                return {
                    id: o.id,
                    customerId: o.customer_id,
                    branchId: o.branch_id,
                    orderDate: o.order_date,
                    status: o.status,
                    totalAmount: o.total_amount,
                    items: items.map((i: any) => ({ productId: i.productId, quantity: i.quantity }))
                };
            });
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }
}
