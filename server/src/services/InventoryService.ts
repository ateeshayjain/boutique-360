import { Mutex } from 'async-mutex';
import { InventoryRepository } from '../repositories/InventoryRepository';

export class InventoryService {
    private repo: InventoryRepository;
    private mutex: Mutex;

    constructor() {
        this.repo = new InventoryRepository();
        this.mutex = new Mutex();
    }

    async adjustStock(productId: string, quantityChange: number): Promise<void> {
        // Critical Section: Lock to ensure sequential processing of stock updates
        // Although SQLite handles concurrency, the Mutex adds an application-layer safety 
        // and allows for complex validation logic before hitting the DB.
        const release = await this.mutex.acquire();
        try {
            const product = this.repo.findById(productId);
            if (!product) {
                throw new Error('Product not found');
            }

            if (product.stock_level + quantityChange < 0) {
                throw new Error('Insufficient stock');
            }

            // Optimistic Locking check in DB
            const success = this.repo.updateStock(productId, quantityChange, product.version);
            if (!success) {
                throw new Error('Concurrency conflict: Stock updated by another transaction. Please retry.');
            }
        } finally {
            release();
        }
    }

    getAllProducts() {
        return this.repo.getAll();
    }
}
