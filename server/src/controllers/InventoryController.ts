import { Request, Response } from 'express';
import { InventoryService } from '../services/InventoryService';

const inventoryService = new InventoryService();

export class InventoryController {
    async getAllProducts(req: Request, res: Response) {
        try {
            const products = inventoryService.getAllProducts();
            res.json(products);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }

    async updateStock(req: Request, res: Response) {
        try {
            const { id } = req.params;
            const { quantityChange } = req.body;

            if (typeof quantityChange !== 'number') {
                return res.status(400).json({ error: 'quantityChange must be a number' });
            }

            await inventoryService.adjustStock(id, quantityChange);
            res.json({ success: true, message: 'Stock updated successfully' });
        } catch (error) {
            res.status(400).json({ error: (error as Error).message });
        }
    }
}
