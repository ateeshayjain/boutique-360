
import { useState, useEffect } from 'react';
import { Customer, Product, Order, Invoice, OrderStatus, PaymentStatus, RawMaterial, Staff, JobCard, Expense } from '../types';

const mockCustomers: Customer[] = [
    {
        id: 'C001',
        name: 'Priya Sharma',
        email: 'priya.sharma@example.com',
        phone: '9876543210',
        vipStatus: true,
        loyaltyPoints: 1500,
        joinDate: '2023-01-15',
        branchId: 'Mumbai',
        notes: 'Prefers silk over cotton. Daughter getting married in Dec 2024.',
        tags: ['Big Spender', 'Wedding']
    },
    {
        id: 'C002',
        name: 'Rohan Verma',
        email: 'rohan.verma@example.com',
        phone: '8765432109',
        vipStatus: false,
        loyaltyPoints: 250,
        joinDate: '2024-02-20',
        branchId: 'Delhi',
        tags: ['New']
    },
    {
        id: 'C003',
        name: 'Anjali Singh',
        email: 'anjali.singh@example.com',
        phone: '7654321098',
        vipStatus: false,
        loyaltyPoints: 600,
        joinDate: '2023-11-05',
        branchId: 'Online',
        notes: 'Call before delivery.',
        tags: []
    },
    {
        id: 'C004',
        name: 'Meera Reddy',
        email: 'meera.r@example.com',
        phone: '9988776655',
        vipStatus: true,
        loyaltyPoints: 2100,
        joinDate: '2022-05-10',
        branchId: 'Mumbai',
        tags: ['VIP', 'Referral']
    }
];

const mockProducts: Product[] = [
    {
        id: 'P001',
        sku: 'KB-SILK-01',
        name: 'Kanjivaram Silk Saree',
        category: 'Saree',
        branchId: 'Mumbai',
        variants: { size: 'Free', color: 'Royal Blue', style: 'Traditional' },
        stockLevel: 12,
        reorderThreshold: 5,
        costPrice: 8000,
        price: 12500,
        hsnCode: '5007',
        supplier: 'Kanchi Weavers Co-op'
    },
    {
        id: 'P002',
        sku: 'KUR-CTN-M',
        name: 'Block Print Cotton Kurti',
        category: 'Kurti',
        branchId: 'Delhi',
        variants: { size: 'M', color: 'Indigo', style: 'Straight Cut' },
        stockLevel: 45,
        reorderThreshold: 10,
        costPrice: 450,
        price: 1299,
        hsnCode: '6204',
        supplier: 'Jaipur Fab'
    },
    {
        id: 'P003',
        sku: 'LEH-BRD-RD',
        name: 'Bridal Velvet Lehenga',
        category: 'Lehenga',
        branchId: 'Mumbai',
        variants: { size: 'Custom', color: 'Maroon', style: 'Embroidered' },
        stockLevel: 2,
        reorderThreshold: 1,
        costPrice: 15000,
        price: 35000,
        hsnCode: '6204',
        supplier: 'Masterji Ahmed'
    },
    {
        id: 'P004',
        sku: 'DUP-CHI-05',
        name: 'Chiffon Phulkari Dupatta',
        category: 'Accessories',
        branchId: 'Online',
        variants: { size: 'Free', color: 'Multi', style: 'Phulkari' },
        stockLevel: 25,
        reorderThreshold: 8,
        costPrice: 300,
        price: 899,
        hsnCode: '6214',
        supplier: 'Amritsar Traders'
    },
];

const mockOrders: Order[] = [
    { id: 'ORD-001', customerId: 'C001', branchId: 'Mumbai', orderDate: '2024-07-20', status: OrderStatus.Delivered, items: [{ productId: 'P003', quantity: 1 }], totalAmount: 35000 },
    { id: 'ORD-002', customerId: 'C002', branchId: 'Delhi', orderDate: '2024-07-21', status: OrderStatus.Shipped, items: [{ productId: 'P001', quantity: 1 }], totalAmount: 12500 },
    { id: 'ORD-003', customerId: 'C001', branchId: 'Mumbai', orderDate: '2024-07-22', status: OrderStatus.Processing, items: [{ productId: 'P004', quantity: 2 }], totalAmount: 1798 },
    { id: 'ORD-004', customerId: 'C003', branchId: 'Online', orderDate: '2024-07-23', status: OrderStatus.Pending, items: [{ productId: 'P002', quantity: 1 }], totalAmount: 1299 },
    { id: 'ORD-005', customerId: 'C004', branchId: 'Mumbai', orderDate: '2024-06-15', status: OrderStatus.Delivered, items: [{ productId: 'P001', quantity: 2 }], totalAmount: 25000 },
];

const mockInvoices: Invoice[] = [
    { id: 'INV-001', orderId: 'ORD-001', customerId: 'C001', branchId: 'Mumbai', invoiceDate: '2024-07-20', totalAmount: 35000, paymentStatus: PaymentStatus.Paid, taxBreakdown: { gst: 1750 } },
    { id: 'INV-002', orderId: 'ORD-002', customerId: 'C002', branchId: 'Delhi', invoiceDate: '2024-07-21', totalAmount: 12500, paymentStatus: PaymentStatus.Paid, taxBreakdown: { gst: 625 } },
];

const mockRawMaterials: RawMaterial[] = [
    { id: 'RM-001', name: 'Red Velvet Thaan', type: 'Fabric', unit: 'Meters', quantity: 45, costPerUnit: 350, supplier: 'Surat Mills', lowStockThreshold: 10 },
    { id: 'RM-002', name: 'Gold Zari Thread', type: 'Thread', unit: 'Rolls', quantity: 120, costPerUnit: 80, supplier: 'Local Market', lowStockThreshold: 20 },
    { id: 'RM-003', name: 'Raw Silk Lining', type: 'Fabric', unit: 'Meters', quantity: 12, costPerUnit: 120, supplier: 'Surat Mills', lowStockThreshold: 15 },
    { id: 'RM-004', name: 'Swarovski Crystals', type: 'Embellishment', unit: 'Pieces', quantity: 500, costPerUnit: 5, supplier: 'Imported', lowStockThreshold: 100 },
];

const mockStaff: Staff[] = [
    { id: 'S-001', name: 'Ahmed Masterji', role: 'Masterji', phone: '9876500001', salaryType: 'Fixed', salaryOrRate: 35000 },
    { id: 'S-002', name: 'Raju Karigar', role: 'Karigar', phone: '9876500002', salaryType: 'PieceRate', salaryOrRate: 450 },
    { id: 'S-003', name: 'Sunita Helper', role: 'Helper', phone: '9876500003', salaryType: 'Fixed', salaryOrRate: 12000 },
];

const mockJobCards: JobCard[] = [
    { id: 'JC-101', customerName: 'Priya Sharma', garmentType: 'Custom Blouse', assignedStaffId: 'S-002', status: 'Stitching', dueDate: '2024-08-05', fabricConsumed: [{ materialId: 'RM-001', quantity: 1.5 }], laborCost: 800, designNotes: 'Deep back neck, golden piping' },
    { id: 'JC-102', customerName: 'Meera Reddy', garmentType: 'Anarkali Suit', assignedStaffId: 'S-001', status: 'Cutting', dueDate: '2024-08-10', fabricConsumed: [{ materialId: 'RM-003', quantity: 4 }], laborCost: 1500, designNotes: 'Floor length, side zip' },
    { id: 'JC-103', customerName: 'Anjali Singh', garmentType: 'Lehenga Skirt', assignedStaffId: 'S-002', status: 'Finishing', dueDate: '2024-08-01', fabricConsumed: [{ materialId: 'RM-001', quantity: 5 }], laborCost: 2000, designNotes: 'Heavy can-can required' },
];

const mockExpenses: Expense[] = [
    { id: 'EXP-001', date: '2024-07-01', category: 'Rent', amount: 45000, description: 'Shop Rent July', gstInputCredit: 0 },
    { id: 'EXP-002', date: '2024-07-05', category: 'Raw Material', amount: 15000, description: 'Fabric Purchase Invoice #445', gstInputCredit: 750 },
    { id: 'EXP-003', date: '2024-07-10', category: 'Labor', amount: 8500, description: 'Weekly Karigar Payout', gstInputCredit: 0 },
    { id: 'EXP-004', date: '2024-07-15', category: 'Utilities', amount: 3200, description: 'Electricity Bill', gstInputCredit: 0 },
];

export const useMockData = () => {
    const [customers, setCustomers] = useState<Customer[]>([]);
    const [products, setProducts] = useState<Product[]>([]);

    useEffect(() => {
        // Fetch products from backend
        import('../services/api').then(m => {
            // Products
            m.api.get('/inventory').then(res => {
                const mappedProducts = res.data.map((p: any) => ({
                    id: p.id,
                    sku: p.sku,
                    name: p.name,
                    category: p.category,
                    branchId: 'Mumbai',
                    variants: { size: 'Free', color: 'Standard', style: 'Standard' },
                    stockLevel: p.stock_level,
                    reorderThreshold: 5,
                    costPrice: p.price * 0.6,
                    price: p.price,
                    hsnCode: '0000',
                    supplier: 'Unknown'
                }));
                setProducts(mappedProducts);
            }).catch(err => {
                console.error("Failed to fetch products", err);
                setProducts([]);
            });

            // Customers
            m.api.get('/data/customers').then(res => {
                setCustomers(res.data);
            }).catch(err => {
                console.error("Failed to fetch customers", err);
                setCustomers([]);
            });

            // Orders
            m.api.get('/data/orders').then(res => {
                setOrders(res.data);
            }).catch(err => {
                console.error("Failed to fetch orders", err);
                setOrders([]);
            });

            // Invoices
            m.api.get('/data/invoices').then(res => {
                setInvoices(res.data);
            }).catch(err => {
                console.error("Failed to fetch invoices", err);
                setInvoices([]);
            });

            // Raw Materials
            m.api.get('/data/raw-materials').then(res => {
                setRawMaterials(res.data);
            }).catch(err => {
                console.error("Failed to fetch raw materials", err);
                setRawMaterials([]);
            });

            // Staff
            m.api.get('/data/staff').then(res => {
                setStaff(res.data);
            }).catch(err => {
                console.error("Failed to fetch staff", err);
                setStaff([]);
            });

            // Job Cards
            m.api.get('/data/job-cards').then(res => {
                setJobCards(res.data);
            }).catch(err => {
                console.error("Failed to fetch job cards", err);
                setJobCards([]);
            });

            // Expenses
            m.api.get('/data/expenses').then(res => {
                setExpenses(res.data);
            }).catch(err => {
                console.error("Failed to fetch expenses", err);
                setExpenses([]);
            });
        });
    }, []);
    const [orders, setOrders] = useState<Order[]>([]);
    const [invoices, setInvoices] = useState<Invoice[]>([]);
    const [rawMaterials, setRawMaterials] = useState<RawMaterial[]>([]);
    const [staff, setStaff] = useState<Staff[]>([]);
    const [jobCards, setJobCards] = useState<JobCard[]>([]);
    const [expenses, setExpenses] = useState<Expense[]>([]);

    return {
        customers,
        products,
        orders,
        invoices,
        rawMaterials,
        staff,
        jobCards,
        expenses,
        setCustomers,
        setProducts,
        setOrders,
        setInvoices,
        setRawMaterials,
        setStaff,
        setJobCards,
        setExpenses
    };
};
