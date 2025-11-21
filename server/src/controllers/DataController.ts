import { Request, Response } from 'express';
import { DataService } from '../services/DataService';

const dataService = new DataService();

export class DataController {
    async getInvoices(req: Request, res: Response) {
        try {
            const invoices = dataService.getInvoices();
            const mapped = invoices.map((i: any) => ({
                id: i.id,
                orderId: i.order_id,
                customerId: i.customer_id,
                branchId: i.branch_id,
                totalAmount: i.amount,
                paymentStatus: i.status,
                invoiceDate: i.created_at,
                taxBreakdown: { gst: i.amount * 0.18 } // Simulated GST for now
            }));
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }

    async getRawMaterials(req: Request, res: Response) {
        try {
            const materials = dataService.getRawMaterials();
            const mapped = materials.map((m: any) => ({
                id: m.id,
                name: m.name,
                type: m.type,
                stockLevel: m.stock_level,
                unit: m.unit,
                reorderLevel: m.reorder_level,
                costPerUnit: m.cost_per_unit,
                supplier: m.supplier
            }));
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }

    async getStaff(req: Request, res: Response) {
        try {
            const staff = dataService.getStaff();
            const mapped = staff.map((s: any) => ({
                id: s.id,
                name: s.name,
                role: s.role,
                branchId: s.branch_id,
                contact: s.contact,
                status: s.status,
                performanceRating: s.performance_rating
            }));
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }

    async getJobCards(req: Request, res: Response) {
        try {
            const cards = dataService.getJobCards();
            const mapped = cards.map((c: any) => ({
                id: c.id,
                orderId: c.order_id,
                assignedTailorId: c.assigned_tailor_id,
                status: c.status,
                stage: c.stage,
                startDate: c.start_date,
                dueDate: c.due_date,
                notes: c.notes
            }));
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }

    async getExpenses(req: Request, res: Response) {
        try {
            const expenses = dataService.getExpenses();
            const mapped = expenses.map((e: any) => ({
                id: e.id,
                category: e.category,
                amount: e.amount,
                date: e.date,
                description: e.description,
                branchId: e.branch_id,
                gstInputCredit: e.gst_input_credit
            }));
            res.json(mapped);
        } catch (error) {
            res.status(500).json({ error: (error as Error).message });
        }
    }
}
