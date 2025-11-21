
export interface Customer {
  id: string;
  name: string;
  email: string;
  phone: string;
  vipStatus: boolean;
  loyaltyPoints: number;
  branchId: string; 
  joinDate: string; 
  dob?: string;
  notes?: string;
  tags?: string[]; 
}

export interface Product {
  id: string;
  sku: string;
  name:string;
  category: string; 
  branchId: string; 
  variants: {
    size: string;
    color: string;
    style: string;
  };
  stockLevel: number;
  reorderThreshold: number;
  costPrice: number; 
  price: number; 
  hsnCode?: string; 
  supplier?: string; 
  imageUrl?: string;
}

// NEW: Raw Material for Manufacturing
export interface RawMaterial {
    id: string;
    name: string; // e.g., "Red Velvet Fabric", "Gold Zippers"
    type: 'Fabric' | 'Trim' | 'Thread' | 'Embellishment';
    unit: 'Meters' | 'Pieces' | 'Rolls' | 'Kg';
    quantity: number;
    costPerUnit: number;
    supplier: string;
    lowStockThreshold: number;
}

// NEW: Staff / Karigar
export interface Staff {
    id: string;
    name: string;
    role: 'Masterji' | 'Karigar' | 'Helper' | 'Sales';
    phone: string;
    salaryType: 'Fixed' | 'PieceRate';
    salaryOrRate: number; // Monthly salary or per piece rate
}

// NEW: Production Job Card
export interface JobCard {
    id: string;
    orderId?: string; // Linked to a customer order
    customerName: string;
    garmentType: string; // e.g., Blouse, Lehenga
    assignedStaffId: string; // Who is stitching it
    status: 'Measurements' | 'Cutting' | 'Stitching' | 'Finishing' | 'QC' | 'Ready';
    dueDate: string;
    fabricConsumed: { materialId: string; quantity: number }[]; // Costing
    laborCost: number; // Costing
    designNotes: string;
    measurementsId?: string; // Link to customer measurements
}

export enum OrderStatus {
  Pending = 'Pending',
  Processing = 'Processing',
  Shipped = 'Shipped',
  Delivered = 'Delivered',
  Returned = 'Returned',
}

export interface OrderItem {
  productId: string;
  quantity: number;
}

export interface Order {
  id: string;
  customerId: string;
  branchId: string; 
  orderDate: string;
  status: OrderStatus;
  items: OrderItem[];
  totalAmount: number;
  notes?: string; 
  attachments?: string[]; 
}

export interface Measurements {
    blouse: {
        bust: number;
        waist: number;
        shoulder: number;
        armhole: number;
        sleeveLength: number;
    };
    kurti: {
        chest: number;
        waist: number;
        hips: number;
        length: number;
    };
    bottom: {
        waist: number;
        hips: number;
        length: number;
        inseam: number;
    }
}

export enum PaymentStatus {
    Pending = 'Pending',
    Paid = 'Paid',
    Failed = 'Failed',
}

export interface Invoice {
    id: string;
    orderId: string;
    customerId: string;
    branchId: string; 
    invoiceDate: string;
    totalAmount: number;
    paymentStatus: PaymentStatus;
    taxBreakdown: {
        gst: number;
    };
}

// NEW: Business Expenses
export interface Expense {
    id: string;
    date: string;
    category: 'Rent' | 'Utilities' | 'Labor' | 'Raw Material' | 'Misc';
    amount: number;
    description: string;
    gstInputCredit?: number; // GST paid that can be claimed
}
