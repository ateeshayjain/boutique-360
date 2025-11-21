import db from '../db';

export class DataRepository {
    getInvoices() {
        return db.prepare(`
            SELECT i.*, o.customer_id, o.branch_id 
            FROM invoices i
            JOIN orders o ON i.order_id = o.id
        `).all();
    }

    getRawMaterials() {
        return db.prepare('SELECT * FROM raw_materials').all();
    }

    getStaff() {
        return db.prepare('SELECT * FROM staff').all();
    }

    getJobCards() {
        return db.prepare('SELECT * FROM job_cards').all();
    }

    getExpenses() {
        return db.prepare('SELECT * FROM expenses').all();
    }
}
