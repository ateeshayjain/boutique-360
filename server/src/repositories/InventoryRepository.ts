import db from '../db';

export interface Product {
    id: string;
    sku: string;
    name: string;
    stock_level: number;
    price: number;
    version: number;
}

export class InventoryRepository {
    findById(id: string): Product | undefined {
        return db.prepare('SELECT * FROM products WHERE id = ?').get(id) as Product | undefined;
    }

    updateStock(id: string, quantityChange: number, expectedVersion: number): boolean {
        const stmt = db.prepare(`
      UPDATE products 
      SET stock_level = stock_level + ?, version = version + 1
      WHERE id = ? AND version = ? AND (stock_level + ?) >= 0
    `);
        const result = stmt.run(quantityChange, id, expectedVersion, quantityChange);
        return result.changes > 0;
    }

    getAll(): Product[] {
        return db.prepare('SELECT * FROM products').all() as Product[];
    }
}
