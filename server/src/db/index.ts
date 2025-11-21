import Database from 'better-sqlite3';
import path from 'path';

const dbPath = path.resolve(__dirname, '../../boutique.db');
const db = new Database(dbPath, { verbose: console.log });

// Enable WAL mode for better concurrency
db.pragma('journal_mode = WAL');

export const initDb = () => {
  const schema = `
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS products (
      id TEXT PRIMARY KEY,
      sku TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      stock_level INTEGER NOT NULL DEFAULT 0,
      price REAL NOT NULL,
      version INTEGER NOT NULL DEFAULT 0 -- Optimistic Locking
    );

    CREATE TABLE IF NOT EXISTS customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      branch_id TEXT,
      vip_status BOOLEAN DEFAULT 0,
      loyalty_points INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      branch_id TEXT,
      total_amount REAL NOT NULL,
      status TEXT NOT NULL,
      order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(customer_id) REFERENCES customers(id)
    );

    CREATE TABLE IF NOT EXISTS order_items (
      id TEXT PRIMARY KEY,
      order_id TEXT NOT NULL,
      product_id TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      price_at_purchase REAL NOT NULL,
      FOREIGN KEY(order_id) REFERENCES orders(id),
      FOREIGN KEY(product_id) REFERENCES products(id)
    );

    CREATE TABLE IF NOT EXISTS invoices (
      id TEXT PRIMARY KEY,
      order_id TEXT NOT NULL,
      amount REAL NOT NULL,
      status TEXT NOT NULL,
      due_date DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(order_id) REFERENCES orders(id)
    );

    CREATE TABLE IF NOT EXISTS raw_materials (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      stock_level REAL NOT NULL,
      unit TEXT NOT NULL,
      reorder_level REAL NOT NULL,
      cost_per_unit REAL NOT NULL,
      supplier TEXT
    );

    CREATE TABLE IF NOT EXISTS staff (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      role TEXT NOT NULL,
      branch_id TEXT,
      contact TEXT,
      status TEXT NOT NULL,
      performance_rating REAL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS job_cards (
      id TEXT PRIMARY KEY,
      order_id TEXT NOT NULL,
      assigned_tailor_id TEXT,
      status TEXT NOT NULL,
      stage TEXT NOT NULL,
      start_date DATETIME,
      due_date DATETIME,
      notes TEXT,
      FOREIGN KEY(order_id) REFERENCES orders(id),
      FOREIGN KEY(assigned_tailor_id) REFERENCES staff(id)
    );

    CREATE TABLE IF NOT EXISTS expenses (
      id TEXT PRIMARY KEY,
      category TEXT NOT NULL,
      amount REAL NOT NULL,
      date DATETIME DEFAULT CURRENT_TIMESTAMP,
      description TEXT,
      branch_id TEXT,
      gst_input_credit REAL DEFAULT 0
    );
  `;

  db.exec(schema);

  // Migration: Add gst_input_credit if not exists
  try {
    const tableInfo = db.prepare("PRAGMA table_info(expenses)").all() as any[];
    const hasGstColumn = tableInfo.some(col => col.name === 'gst_input_credit');
    if (!hasGstColumn) {
      db.prepare("ALTER TABLE expenses ADD COLUMN gst_input_credit REAL DEFAULT 0").run();
      console.log("Migrated expenses table: Added gst_input_credit column");
    }
  } catch (err) {
    console.error("Migration failed", err);
  }

  // Seed Admin User if not exists
  const adminExists = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');
  if (!adminExists) {
    // Hash for 'admin123' (bcrypt) - generated for demo
    // In real app, we would use the auth service to hash this properly
    // For now, we will handle this in the seeding script or Auth Service
  }

  // Seed Products if empty
  const productsCount = db.prepare('SELECT count(*) as count FROM products').get() as { count: number };
  if (productsCount.count === 0) {
    const insertProduct = db.prepare(`
      INSERT INTO products (id, sku, name, category, stock_level, price, version)
      VALUES (@id, @sku, @name, @category, @stockLevel, @price, 0)
    `);

    const products = [
      { id: 'P001', sku: 'KB-SILK-01', name: 'Kanjivaram Silk Saree', category: 'Saree', stockLevel: 12, price: 12500 },
      { id: 'P002', sku: 'KUR-CTN-M', name: 'Block Print Cotton Kurti', category: 'Kurti', stockLevel: 45, price: 1299 },
      { id: 'P003', sku: 'LEH-BRD-RD', name: 'Bridal Velvet Lehenga', category: 'Lehenga', stockLevel: 2, price: 35000 },
      { id: 'P004', sku: 'DUP-CHI-05', name: 'Chiffon Phulkari Dupatta', category: 'Accessories', stockLevel: 25, price: 899 }
    ];

    products.forEach(p => insertProduct.run(p));
    console.log('Seeded initial products');
  }

  // Seed Customers
  const customersCount = db.prepare('SELECT count(*) as count FROM customers').get() as { count: number };
  if (customersCount.count === 0) {
    const insertCustomer = db.prepare(`
            INSERT INTO customers (id, name, email, phone, branch_id, vip_status, loyalty_points)
            VALUES (@id, @name, @email, @phone, @branchId, @vipStatus, @loyaltyPoints)
        `);
    const customers = [
      { id: 'C001', name: 'Priya Sharma', email: 'priya@example.com', phone: '9876543210', branchId: 'Mumbai', vipStatus: 1, loyaltyPoints: 1500 },
      { id: 'C002', name: 'Rohan Verma', email: 'rohan@example.com', phone: '8765432109', branchId: 'Delhi', vipStatus: 0, loyaltyPoints: 250 }
    ];
    customers.forEach(c => insertCustomer.run(c));
    console.log('Seeded initial customers');
  }

  // Seed Orders
  const ordersCount = db.prepare('SELECT count(*) as count FROM orders').get() as { count: number };
  if (ordersCount.count === 0) {
    const insertOrder = db.prepare(`
            INSERT INTO orders (id, customer_id, branch_id, total_amount, status, order_date)
            VALUES (@id, @customerId, @branchId, @totalAmount, @status, @orderDate)
        `);
    const insertItem = db.prepare(`
            INSERT INTO order_items (id, order_id, product_id, quantity, price_at_purchase)
            VALUES (@id, @orderId, @productId, @quantity, @price)
        `);

    const orders = [
      { id: 'ORD-001', customerId: 'C001', branchId: 'Mumbai', totalAmount: 35000, status: 'Delivered', orderDate: '2024-07-20' },
      { id: 'ORD-002', customerId: 'C002', branchId: 'Delhi', totalAmount: 12500, status: 'Shipped', orderDate: '2024-07-21' }
    ];

    orders.forEach(o => insertOrder.run(o));
    // Simplified items seeding
    insertItem.run({ id: 'OI-001', orderId: 'ORD-001', productId: 'P003', quantity: 1, price: 35000 });
    insertItem.run({ id: 'OI-002', orderId: 'ORD-002', productId: 'P001', quantity: 1, price: 12500 });

    console.log('Seeded initial orders');
  }

  // Seed Invoices
  const invoicesCount = db.prepare('SELECT count(*) as count FROM invoices').get() as { count: number };
  if (invoicesCount.count === 0) {
    const insertInvoice = db.prepare(`INSERT INTO invoices (id, order_id, amount, status, due_date) VALUES (@id, @orderId, @amount, @status, @dueDate)`);
    insertInvoice.run({ id: 'INV-001', orderId: 'ORD-001', amount: 35000, status: 'Paid', dueDate: '2024-07-20' });
    console.log('Seeded initial invoices');
  }

  // Seed Raw Materials
  const rawMaterialsCount = db.prepare('SELECT count(*) as count FROM raw_materials').get() as { count: number };
  if (rawMaterialsCount.count === 0) {
    const insertRM = db.prepare(`INSERT INTO raw_materials (id, name, type, stock_level, unit, reorder_level, cost_per_unit, supplier) VALUES (@id, @name, @type, @stockLevel, @unit, @reorderLevel, @costPerUnit, @supplier)`);
    const materials = [
      { id: 'RM-001', name: 'Pure Silk Fabric', type: 'Fabric', stockLevel: 150, unit: 'Meters', reorderLevel: 50, costPerUnit: 800, supplier: 'Silk House' },
      { id: 'RM-002', name: 'Gold Zari Thread', type: 'Thread', stockLevel: 45, unit: 'Spools', reorderLevel: 10, costPerUnit: 1200, supplier: 'Zari World' }
    ];
    materials.forEach(m => insertRM.run(m));
    console.log('Seeded initial raw materials');
  }

  // Seed Staff
  const staffCount = db.prepare('SELECT count(*) as count FROM staff').get() as { count: number };
  if (staffCount.count === 0) {
    const insertStaff = db.prepare(`INSERT INTO staff (id, name, role, branch_id, contact, status, performance_rating) VALUES (@id, @name, @role, @branchId, @contact, @status, @performanceRating)`);
    const staff = [
      { id: 'S001', name: 'Rajesh Kumar', role: 'Master Tailor', branchId: 'Mumbai', contact: '9988776655', status: 'Active', performanceRating: 4.8 },
      { id: 'S002', name: 'Sunita Devi', role: 'Sales Manager', branchId: 'Delhi', contact: '8877665544', status: 'Active', performanceRating: 4.5 }
    ];
    staff.forEach(s => insertStaff.run(s));
    console.log('Seeded initial staff');
  }

  // Seed Job Cards
  const jobCardsCount = db.prepare('SELECT count(*) as count FROM job_cards').get() as { count: number };
  if (jobCardsCount.count === 0) {
    const insertJobCard = db.prepare(`INSERT INTO job_cards (id, order_id, assigned_tailor_id, status, stage, start_date, due_date, notes) VALUES (@id, @orderId, @assignedTailorId, @status, @stage, @startDate, @dueDate, @notes)`);
    insertJobCard.run({ id: 'JC-001', orderId: 'ORD-001', assignedTailorId: 'S001', status: 'In Progress', stage: 'Stitching', startDate: '2024-07-21', dueDate: '2024-07-25', notes: 'Custom fitting required' });
    console.log('Seeded initial job cards');
  }

  // Seed Expenses
  const expensesCount = db.prepare('SELECT count(*) as count FROM expenses').get() as { count: number };
  if (expensesCount.count === 0) {
    const insertExpense = db.prepare(`INSERT INTO expenses (id, category, amount, description, branch_id, gst_input_credit) VALUES (@id, @category, @amount, @description, @branchId, @gstInputCredit)`);
    insertExpense.run({ id: 'EXP-001', category: 'Utilities', amount: 4500, description: 'Electricity Bill - July', branchId: 'Mumbai', gstInputCredit: 0 });
    console.log('Seeded initial expenses');
  }
};

export default db;
