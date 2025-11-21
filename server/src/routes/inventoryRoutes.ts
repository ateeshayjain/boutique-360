import { Router } from 'express';
import { InventoryController } from '../controllers/InventoryController';

const router = Router();
const inventoryController = new InventoryController();

// In a real app, we would add authMiddleware here to protect these routes
router.get('/', (req, res) => inventoryController.getAllProducts(req, res));
router.post('/:id/stock', (req, res) => inventoryController.updateStock(req, res));

export default router;
