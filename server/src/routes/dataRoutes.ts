import { Router } from 'express';
import { CustomerController } from '../controllers/CustomerController';
import { OrderController } from '../controllers/OrderController';
import { DataController } from '../controllers/DataController';

const router = Router();
const customerController = new CustomerController();
const orderController = new OrderController();
const dataController = new DataController();

router.get('/customers', (req, res) => customerController.getAll(req, res));
router.get('/orders', (req, res) => orderController.getAll(req, res));
router.get('/invoices', (req, res) => dataController.getInvoices(req, res));
router.get('/raw-materials', (req, res) => dataController.getRawMaterials(req, res));
router.get('/staff', (req, res) => dataController.getStaff(req, res));
router.get('/job-cards', (req, res) => dataController.getJobCards(req, res));
router.get('/expenses', (req, res) => dataController.getExpenses(req, res));

export default router;
