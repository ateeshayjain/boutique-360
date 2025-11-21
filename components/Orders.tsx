
import React, { useState, useMemo } from 'react';
import { Order, OrderStatus, Customer, Product, Invoice, PaymentStatus } from '../types';
import { ClockIcon, PackageIcon, TruckIcon, CheckCircleIcon, XCircleIcon, SearchIcon, GridIcon, ImagePlusIcon, LoaderIcon } from './icons';
import Modal from './Modal';
import { useDebounce } from '../hooks/useDebounce';

interface OrdersProps {
  orders: Order[];
  customers: Customer[];
  products?: Product[];
  setOrders: React.Dispatch<React.SetStateAction<Order[]>>;
  setProducts: React.Dispatch<React.SetStateAction<Product[]>>;
  setInvoices: React.Dispatch<React.SetStateAction<Invoice[]>>;
  branchId: string;
}

const getStatusPill = (status: OrderStatus) => {
    switch (status) {
        case OrderStatus.Pending:
            return <span className="flex items-center gap-2 text-yellow-400"><ClockIcon />{status}</span>;
        case OrderStatus.Processing:
            return <span className="flex items-center gap-2 text-indigo-400"><PackageIcon />{status}</span>;
        case OrderStatus.Shipped:
            return <span className="flex items-center gap-2 text-blue-400"><TruckIcon />{status}</span>;
        case OrderStatus.Delivered:
            return <span className="flex items-center gap-2 text-green-400"><CheckCircleIcon />{status}</span>;
        case OrderStatus.Returned:
            return <span className="flex items-center gap-2 text-red-400"><XCircleIcon />{status}</span>;
        default:
            return <span>{status}</span>;
    }
};

const Orders: React.FC<OrdersProps> = ({ orders, customers, products = [], setOrders, setProducts, setInvoices, branchId }) => {
  const [isCreating, setIsCreating] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false); // Prevent button mashing
  const [newOrder, setNewOrder] = useState<{customerId: string; productId: string; quantity: number}>({
      customerId: '', productId: '', quantity: 1
  });
  const [error, setError] = useState<string>('');
  const [productSearch, setProductSearch] = useState('');
  const debouncedSearch = useDebounce(productSearch, 300);

  const getCustomerName = (customerId: string) => {
    return customers.find(c => c.id === customerId)?.name || 'Unknown Customer';
  };
  
  const handleCreateOrder = async (e: React.FormEvent) => {
      e.preventDefault();
      if(isSubmitting) return; // Race condition guard

      setError('');
      setIsSubmitting(true);

      // Simulate API delay to test disabled button state
      await new Promise(resolve => setTimeout(resolve, 500));

      const product = products.find(p => p.id === newOrder.productId);
      if (!product) {
          setError("Selected product not found.");
          setIsSubmitting(false);
          return;
      }

      if (product.stockLevel < newOrder.quantity) {
          setError(`Insufficient stock! Only ${product.stockLevel} remaining.`);
          setIsSubmitting(false);
          return;
      }

      if(newOrder.customerId) {
          const assignBranch = branchId === 'All' ? 'Mumbai' : branchId;
          const orderId = `ORD-${String(Date.now())}`;
          const totalAmount = product.price * newOrder.quantity;

          // 1. Create Order
          const order: Order = {
              id: orderId,
              customerId: newOrder.customerId,
              branchId: assignBranch,
              orderDate: new Date().toISOString().split('T')[0],
              status: OrderStatus.Pending,
              items: [{ productId: newOrder.productId, quantity: newOrder.quantity }],
              totalAmount: totalAmount
          };
          
          setOrders(prev => [order, ...prev]);

          // 2. Deduct Inventory
          setProducts(prevProducts => prevProducts.map(p => {
              if (p.id === newOrder.productId) {
                  return { ...p, stockLevel: p.stockLevel - newOrder.quantity };
              }
              return p;
          }));

          // 3. Auto-Generate Invoice
          const invoice: Invoice = {
              id: `INV-${Date.now()}`,
              orderId: orderId,
              customerId: newOrder.customerId,
              branchId: assignBranch,
              invoiceDate: order.orderDate,
              totalAmount: totalAmount,
              paymentStatus: PaymentStatus.Pending,
              taxBreakdown: { gst: totalAmount * 0.05 } // Assuming 5% GST on garments
          };
          setInvoices(prev => [invoice, ...prev]);

          setIsCreating(false);
          setNewOrder({ customerId: '', productId: '', quantity: 1 });
      } else {
          setError("Please select a customer.");
      }
      setIsSubmitting(false);
  };

  // Visual POS Product Filter
  const posProducts = useMemo(() => {
      return products.filter(p => 
          p.stockLevel > 0 && 
          (p.name.toLowerCase().includes(debouncedSearch.toLowerCase()) || p.sku.toLowerCase().includes(debouncedSearch.toLowerCase()))
      );
  }, [products, debouncedSearch]);

  return (
    <div className="p-8 animate-fade-in">
      <div className="flex justify-between items-center mb-6">
        <div>
             <h1 className="text-3xl font-bold text-white">Orders</h1>
             <p className="text-sm text-gray-400 mt-1">
                Location: <span className="text-indigo-400 font-semibold">{branchId === 'All' ? 'All Locations' : branchId}</span>
            </p>
        </div>
        <button 
            onClick={() => setIsCreating(true)}
            className="bg-indigo-600 text-white font-bold py-2 px-4 rounded-lg hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-900/20 flex items-center gap-2"
        >
          + Create New Order
        </button>
      </div>

      {/* Modal for Visual POS Order Creation */}
      <Modal isOpen={isCreating} onClose={() => setIsCreating(false)} title="New Point of Sale Order" size="xl">
           <div className="flex flex-col h-full">
               {/* Top Bar: Customer & Search */}
               <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                   <div>
                       <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Select Customer</label>
                       <select className="w-full bg-gray-800 text-white rounded-lg p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none"
                          value={newOrder.customerId} onChange={e => setNewOrder({...newOrder, customerId: e.target.value})}>
                          <option value="">-- Choose Customer --</option>
                          {customers.map(c => <option key={c.id} value={c.id}>{c.name} ({c.phone})</option>)}
                      </select>
                   </div>
                   <div>
                        <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Search Products</label>
                        <div className="relative">
                            <input 
                                type="text" 
                                placeholder="Search by Name or SKU..." 
                                className="w-full bg-gray-800 text-white rounded-lg p-3 pl-10 border border-gray-700 focus:border-indigo-500 focus:outline-none"
                                value={productSearch}
                                onChange={(e) => setProductSearch(e.target.value)}
                            />
                            <div className="absolute left-3 top-3.5 text-gray-500"><SearchIcon /></div>
                        </div>
                   </div>
               </div>

               {/* Visual Grid */}
               <div className="flex-1 overflow-y-auto bg-gray-800/50 rounded-xl border border-gray-700 p-4 mb-4 custom-scrollbar">
                    {posProducts.length === 0 && <div className="text-center text-gray-500 py-10">No products found.</div>}
                    <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                        {posProducts.map(p => (
                            <div 
                                key={p.id} 
                                onClick={() => setNewOrder({...newOrder, productId: p.id})}
                                className={`relative rounded-lg overflow-hidden border cursor-pointer transition-all group ${newOrder.productId === p.id ? 'border-indigo-500 ring-2 ring-indigo-500/50' : 'border-gray-700 hover:border-gray-500'}`}
                            >
                                <div className="aspect-square bg-gray-700 flex items-center justify-center relative">
                                    {p.imageUrl ? (
                                        <img src={p.imageUrl} className="w-full h-full object-cover" alt={p.name} />
                                    ) : (
                                        <div className="text-gray-500"><ImagePlusIcon /></div>
                                    )}
                                    {/* Price Tag */}
                                    <div className="absolute top-2 right-2 bg-black/70 text-white text-xs font-bold px-2 py-1 rounded">
                                        ₹{p.price}
                                    </div>
                                </div>
                                <div className="p-3 bg-gray-800">
                                    <div className="font-bold text-white text-sm truncate">{p.name}</div>
                                    <div className="flex justify-between items-center mt-1">
                                        <div className="text-xs text-gray-400">{p.variants.color}</div>
                                        <div className="text-xs text-gray-400">Qty: {p.stockLevel}</div>
                                    </div>
                                </div>
                                {newOrder.productId === p.id && (
                                    <div className="absolute inset-0 bg-indigo-500/20 flex items-center justify-center">
                                        <div className="bg-indigo-600 text-white rounded-full p-2">
                                            <CheckCircleIcon />
                                        </div>
                                    </div>
                                )}
                            </div>
                        ))}
                    </div>
               </div>

               {/* Footer Action */}
               <div className="flex items-center gap-4 bg-gray-800 p-4 rounded-xl border border-gray-700">
                   <div className="flex-1">
                       <div className="text-sm text-gray-400">Selected Product:</div>
                       <div className="font-bold text-white text-lg">
                           {products.find(p => p.id === newOrder.productId)?.name || 'None'}
                       </div>
                   </div>
                   <div className="w-24">
                       <label className="text-xs text-gray-400 block mb-1">Quantity</label>
                       <input type="number" min="1" className="w-full bg-gray-900 border border-gray-600 rounded p-2 text-white"
                            value={newOrder.quantity} 
                            onChange={e => {
                                const val = parseInt(e.target.value);
                                if (val > 0) setNewOrder({...newOrder, quantity: val});
                            }} 
                        />
                   </div>
                   <button 
                        onClick={handleCreateOrder}
                        disabled={!newOrder.productId || !newOrder.customerId || isSubmitting}
                        className="bg-green-600 disabled:bg-gray-600 disabled:cursor-not-allowed hover:bg-green-700 text-white font-bold py-3 px-8 rounded-lg transition-colors shadow-lg flex items-center gap-2"
                   >
                       {isSubmitting ? <LoaderIcon /> : 'Confirm Order'}
                   </button>
               </div>
               {error && <div className="mt-4 text-red-400 text-sm text-center font-bold">{error}</div>}
           </div>
      </Modal>

      <div className="bg-gray-800 rounded-xl shadow-xl overflow-hidden border border-gray-700">
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="bg-gray-750 text-gray-400 text-xs uppercase tracking-wider">
              <tr>
                <th className="p-4 font-semibold">Order ID</th>
                <th className="p-4 font-semibold">Customer</th>
                <th className="p-4 font-semibold">Branch</th>
                <th className="p-4 font-semibold">Date</th>
                <th className="p-4 font-semibold">Status</th>
                <th className="p-4 font-semibold text-right">Total</th>
                <th className="p-4 font-semibold text-center">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-700">
              {orders.map((order, index) => (
                <tr key={order.id} className={`hover:bg-gray-700/40 transition-colors ${index % 2 === 0 ? 'bg-gray-800' : 'bg-gray-900/30'}`}>
                  <td className="p-4 font-mono text-sm text-indigo-400 font-bold">{order.id}</td>
                  <td className="p-4 text-white font-medium">{getCustomerName(order.customerId)}</td>
                  <td className="p-4 text-sm text-gray-400">
                      <span className="bg-gray-700 px-2 py-1 rounded text-xs border border-gray-600">{order.branchId}</span>
                  </td>
                  <td className="p-4 text-gray-400 text-sm">{order.orderDate}</td>
                  <td className="p-4 font-medium text-sm">{getStatusPill(order.status)}</td>
                  <td className="p-4 text-right font-bold text-white">{order.totalAmount.toLocaleString('en-IN', { style: 'currency', currency: 'INR' })}</td>
                  <td className="p-4 text-center">
                    <button className="text-gray-400 hover:text-white p-2 rounded hover:bg-gray-700">
                        <GridIcon />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {orders.length === 0 && (
              <div className="p-8 text-center text-gray-500">No orders found for this location.</div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Orders;
