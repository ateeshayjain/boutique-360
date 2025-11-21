
import React, { useState, useMemo } from 'react';
import { Customer, Order, OrderStatus } from '../types';
import { UserPlusIcon, SearchIcon, PhoneIcon, MailIcon, MessageCircleIcon, StarIcon, TagIcon, EditIcon, SaveIcon, ClockIcon, TrendingUpIcon, ChevronRightIcon, FilterIcon } from './icons';
import Modal from './Modal';

interface CustomersProps {
  customers: Customer[];
  orders: Order[];
  setCustomers: React.Dispatch<React.SetStateAction<Customer[]>>;
  branchId: string;
}

const Customers: React.FC<CustomersProps> = ({ customers, orders, setCustomers, branchId }) => {
  const [selectedCustomerId, setSelectedCustomerId] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterType, setFilterType] = useState<'All' | 'VIP' | 'New' | 'Risk'>('All');
  
  const [isEditing, setIsEditing] = useState(false);
  const [editNote, setEditNote] = useState('');
  const [newTag, setNewTag] = useState('');

  const [isAdding, setIsAdding] = useState(false);
  const [newCustomer, setNewCustomer] = useState({ name: '', email: '', phone: '' });

  const customersWithStats = useMemo(() => {
      return customers.map(customer => {
          const custOrders = orders.filter(o => o.customerId === customer.id);
          const totalSpent = custOrders.reduce((acc, o) => acc + o.totalAmount, 0);
          const lastOrderDate = custOrders.length > 0 
              ? custOrders.reduce((latest, o) => new Date(o.orderDate) > new Date(latest) ? o.orderDate : latest, '1970-01-01') 
              : null;
          const daysSinceLastPurchase = lastOrderDate 
              ? Math.floor((new Date().getTime() - new Date(lastOrderDate).getTime()) / (1000 * 3600 * 24)) 
              : 999;
          
          let calculatedTier = 'Silver';
          if (totalSpent > 50000) calculatedTier = 'Platinum';
          else if (totalSpent > 20000) calculatedTier = 'Gold';
          
          return {
              ...customer,
              totalSpent,
              orderCount: custOrders.length,
              lastOrderDate,
              daysSinceLastPurchase,
              calculatedTier,
              orders: custOrders.sort((a, b) => new Date(b.orderDate).getTime() - new Date(a.orderDate).getTime())
          };
      });
  }, [customers, orders]);

  const filteredCustomers = useMemo(() => {
      return customersWithStats.filter(c => {
          const matchesSearch = c.name.toLowerCase().includes(searchTerm.toLowerCase()) || c.phone.includes(searchTerm);
          let matchesFilter = true;
          if (filterType === 'VIP') matchesFilter = c.vipStatus || c.calculatedTier === 'Platinum';
          if (filterType === 'New') matchesFilter = new Date(c.joinDate) > new Date(new Date().setMonth(new Date().getMonth() - 3));
          if (filterType === 'Risk') matchesFilter = c.daysSinceLastPurchase > 180 && c.orderCount > 0;
          return matchesSearch && matchesFilter;
      });
  }, [customersWithStats, searchTerm, filterType]);

  const activeCustomer = useMemo(() => 
      customersWithStats.find(c => c.id === selectedCustomerId), 
  [customersWithStats, selectedCustomerId]);

  const totalCustomers = customers.length;
  const vipCount = customersWithStats.filter(c => c.vipStatus || c.calculatedTier === 'Platinum').length;
  const churnRisk = customersWithStats.filter(c => c.daysSinceLastPurchase > 180 && c.orderCount > 0).length;

  const handleSaveNote = () => {
      if(activeCustomer) {
          setCustomers(prev => prev.map(c => c.id === activeCustomer.id ? { ...c, notes: editNote } : c));
          setIsEditing(false);
      }
  };

  const handleAddTag = () => {
      if(activeCustomer && newTag) {
           setCustomers(prev => prev.map(c => c.id === activeCustomer.id ? { ...c, tags: [...(c.tags || []), newTag] } : c));
           setNewTag('');
      }
  };

  const handleRemoveTag = (tagToRemove: string) => {
      if(activeCustomer) {
          setCustomers(prev => prev.map(c => c.id === activeCustomer.id ? { ...c, tags: c.tags?.filter(t => t !== tagToRemove) } : c));
      }
  };

  const handleAddCustomer = (e: React.FormEvent) => {
      e.preventDefault();
      const id = `C${String(Date.now())}`;
      const today = new Date().toISOString().split('T')[0];
      const assignBranch = branchId === 'All' ? 'Mumbai' : branchId;

      setCustomers(prev => [...prev, {
          id,
          name: newCustomer.name,
          email: newCustomer.email,
          phone: newCustomer.phone,
          vipStatus: false,
          loyaltyPoints: 0,
          branchId: assignBranch,
          joinDate: today,
          tags: ['New']
      }]);
      setIsAdding(false);
      setNewCustomer({ name: '', email: '', phone: '' });
      setSelectedCustomerId(id);
  };
  
  const renderTierBadge = (tier: string) => {
      const colors = {
          Platinum: 'bg-purple-900/50 text-purple-200 border-purple-700',
          Gold: 'bg-yellow-900/50 text-yellow-200 border-yellow-700',
          Silver: 'bg-gray-700 text-gray-300 border-gray-600'
      };
      return (
          <span className={`px-2 py-0.5 text-xs font-bold uppercase border rounded-full ${(colors as any)[tier] || colors.Silver}`}>
              {tier}
          </span>
      );
  };

  return (
    <div className="flex h-full overflow-hidden bg-gray-900 animate-fade-in">
      {/* Left Sidebar: Customer Directory */}
      <div className="w-full lg:w-1/3 border-r border-gray-800 flex flex-col bg-gray-850">
        <div className="p-4 border-b border-gray-800 space-y-4">
            <div className="flex justify-between items-center">
                 <div>
                     <h1 className="text-xl font-bold text-white">Customers</h1>
                     <span className="text-xs text-gray-500">Branch: {branchId}</span>
                 </div>
                 <button 
                    onClick={() => setIsAdding(true)}
                    className="p-2 bg-indigo-600 rounded-lg text-white hover:bg-indigo-700 transition-colors shadow-lg" title="Add Customer">
                     <UserPlusIcon />
                 </button>
            </div>
            
            <div className="flex justify-between text-xs text-gray-400 bg-gray-800 p-2 rounded-lg">
                <span>Total: <strong className="text-white">{totalCustomers}</strong></span>
                <span>VIP: <strong className="text-yellow-400">{vipCount}</strong></span>
                <span>Risk: <strong className="text-red-400">{churnRisk}</strong></span>
            </div>

            <div className="space-y-2">
                <div className="relative">
                    <input 
                        type="text" 
                        placeholder="Search name or phone..." 
                        className="w-full bg-gray-900 text-white rounded-lg pl-9 pr-4 py-2 border border-gray-700 focus:border-indigo-500 focus:outline-none text-sm"
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                    />
                    <div className="absolute left-3 top-2.5 text-gray-500"><SearchIcon /></div>
                </div>
                <div className="flex gap-2 overflow-x-auto pb-1 no-scrollbar">
                    {['All', 'VIP', 'New', 'Risk'].map(f => (
                        <button 
                            key={f}
                            onClick={() => setFilterType(f as any)}
                            className={`px-3 py-1 rounded-full text-xs font-medium whitespace-nowrap transition-colors ${filterType === f ? 'bg-indigo-600 text-white' : 'bg-gray-800 text-gray-400 hover:bg-gray-700'}`}
                        >
                            {f}
                        </button>
                    ))}
                </div>
            </div>
        </div>

        <div className="flex-1 overflow-y-auto custom-scrollbar">
            {filteredCustomers.map(customer => (
                <div 
                    key={customer.id}
                    onClick={() => setSelectedCustomerId(customer.id)}
                    className={`p-4 border-b border-gray-800 cursor-pointer transition-all hover:bg-gray-800/50 ${selectedCustomerId === customer.id ? 'bg-gray-800 border-l-4 border-indigo-500' : ''}`}
                >
                    <div className="flex justify-between items-start">
                        <div>
                            <div className="font-semibold text-white flex items-center gap-2 text-sm">
                                {customer.name}
                                {customer.vipStatus && <StarIcon />}
                            </div>
                            <div className="text-xs text-gray-500 mt-1">{customer.phone}</div>
                        </div>
                        <div className="text-right">
                            {renderTierBadge(customer.calculatedTier)}
                            <div className="text-[10px] text-gray-500 mt-1">
                                {customer.branchId}
                            </div>
                        </div>
                    </div>
                </div>
            ))}
            {filteredCustomers.length === 0 && <div className="p-6 text-gray-500 text-center text-sm">No customers found.</div>}
        </div>
      </div>

      {/* Right Pane: CRM Details */}
      <div className="hidden lg:flex flex-1 bg-gray-900 flex-col overflow-y-auto custom-scrollbar">
          {activeCustomer ? (
              <div className="flex flex-col h-full animate-fade-in">
                  {/* Customer Hero Header */}
                  <div className="p-8 bg-gray-850 border-b border-gray-800 flex justify-between items-end bg-gradient-to-b from-gray-800 to-gray-900">
                      <div className="flex items-center gap-6">
                          <div className="w-20 h-20 rounded-full bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-2xl font-bold text-white shadow-xl ring-4 ring-gray-800">
                              {activeCustomer.name.charAt(0)}
                          </div>
                          <div>
                              <div className="flex items-center gap-3 mb-1">
                                  <h2 className="text-3xl font-bold text-white">{activeCustomer.name}</h2>
                                  {renderTierBadge(activeCustomer.calculatedTier)}
                              </div>
                              <div className="flex items-center gap-4 text-gray-400 text-sm">
                                  <span className="flex items-center gap-1"><PhoneIcon /> {activeCustomer.phone}</span>
                                  <span className="flex items-center gap-1"><MailIcon /> {activeCustomer.email}</span>
                                  <span className="flex items-center gap-1 text-indigo-400"><StarIcon /> {activeCustomer.loyaltyPoints} Points</span>
                              </div>
                          </div>
                      </div>
                      <div className="flex gap-3">
                          <button className="flex items-center gap-2 px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg font-semibold transition-colors text-sm shadow-lg">
                              <MessageCircleIcon /> WhatsApp
                          </button>
                          <button className="flex items-center gap-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 text-white rounded-lg font-semibold transition-colors text-sm">
                              <MailIcon /> Email
                          </button>
                      </div>
                  </div>

                  {/* Metrics Cards */}
                  <div className="grid grid-cols-3 gap-6 p-8">
                      <div className="bg-gray-800 p-5 rounded-xl border border-gray-700">
                          <div className="text-gray-400 text-xs uppercase font-bold mb-1">Lifetime Value</div>
                          <div className="text-2xl font-bold text-white">₹{activeCustomer.totalSpent.toLocaleString('en-IN')}</div>
                      </div>
                      <div className="bg-gray-800 p-5 rounded-xl border border-gray-700">
                          <div className="text-gray-400 text-xs uppercase font-bold mb-1">Avg. Order Value</div>
                          <div className="text-2xl font-bold text-white">
                              ₹{activeCustomer.orderCount > 0 ? (activeCustomer.totalSpent / activeCustomer.orderCount).toLocaleString('en-IN', {maximumFractionDigits:0}) : 0}
                          </div>
                      </div>
                      <div className="bg-gray-800 p-5 rounded-xl border border-gray-700">
                          <div className="text-gray-400 text-xs uppercase font-bold mb-1">Retention Status</div>
                          <div className={`text-2xl font-bold ${activeCustomer.daysSinceLastPurchase < 90 ? 'text-green-400' : activeCustomer.daysSinceLastPurchase < 180 ? 'text-yellow-400' : 'text-red-400'}`}>
                              {activeCustomer.daysSinceLastPurchase > 365 ? 'Inactive' : activeCustomer.daysSinceLastPurchase} Days Ago
                          </div>
                      </div>
                  </div>

                  {/* Content Tabs Layout */}
                  <div className="flex-1 px-8 pb-8 grid grid-cols-3 gap-8 overflow-hidden">
                      
                      <div className="col-span-1 space-y-6 overflow-y-auto custom-scrollbar pr-2">
                          <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-lg">
                              <h3 className="text-white font-semibold mb-4 flex items-center gap-2 text-sm"><TagIcon /> Customer Tags</h3>
                              <div className="flex flex-wrap gap-2 mb-4">
                                  {activeCustomer.tags?.map(tag => (
                                      <span key={tag} className="bg-gray-700 text-gray-200 px-3 py-1 rounded-full text-xs flex items-center gap-2 border border-gray-600">
                                          {tag}
                                          <button onClick={() => handleRemoveTag(tag)} className="hover:text-red-400">×</button>
                                      </span>
                                  ))}
                                  <input 
                                      className="bg-transparent border-b border-gray-600 text-sm text-white focus:outline-none focus:border-indigo-500 w-24 px-1"
                                      placeholder="+ Add"
                                      value={newTag}
                                      onChange={e => setNewTag(e.target.value)}
                                      onKeyDown={e => e.key === 'Enter' && handleAddTag()}
                                  />
                              </div>
                          </div>

                          <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-lg">
                              <div className="flex justify-between items-center mb-4">
                                  <h3 className="text-white font-semibold flex items-center gap-2 text-sm"><EditIcon /> Notes</h3>
                                  {!isEditing ? (
                                      <button onClick={() => { setIsEditing(true); setEditNote(activeCustomer.notes || ''); }} className="text-xs text-indigo-400 hover:text-white">Edit</button>
                                  ) : (
                                      <button onClick={handleSaveNote} className="text-xs text-green-400 hover:text-white flex items-center gap-1"><SaveIcon /> Save</button>
                                  )}
                              </div>
                              {isEditing ? (
                                  <textarea 
                                      className="w-full bg-gray-900 text-white p-3 rounded border border-gray-600 text-sm"
                                      rows={5}
                                      value={editNote}
                                      onChange={e => setEditNote(e.target.value)}
                                  />
                              ) : (
                                  <p className="text-gray-400 text-sm italic whitespace-pre-wrap">
                                      {activeCustomer.notes || "No notes added yet."}
                                  </p>
                              )}
                          </div>
                      </div>

                      <div className="col-span-2 bg-gray-800 rounded-xl border border-gray-700 flex flex-col overflow-hidden shadow-lg">
                          <div className="p-4 border-b border-gray-700 bg-gray-750">
                              <h3 className="font-bold text-white flex items-center gap-2 text-sm"><ClockIcon /> Order History</h3>
                          </div>
                          <div className="flex-1 overflow-y-auto custom-scrollbar">
                              {activeCustomer.orders.length > 0 ? (
                                  <table className="w-full text-left text-sm">
                                      <thead className="bg-gray-900 text-gray-500 sticky top-0">
                                          <tr>
                                              <th className="p-4">Order ID</th>
                                              <th className="p-4">Date</th>
                                              <th className="p-4">Status</th>
                                              <th className="p-4 text-right">Amount</th>
                                              <th className="p-4"></th>
                                          </tr>
                                      </thead>
                                      <tbody className="divide-y divide-gray-700">
                                          {activeCustomer.orders.map(order => (
                                              <tr key={order.id} className="hover:bg-gray-750">
                                                  <td className="p-4 font-mono text-indigo-400 text-xs">{order.id}</td>
                                                  <td className="p-4 text-gray-300">{order.orderDate}</td>
                                                  <td className="p-4">
                                                      <span className={`px-2 py-1 rounded text-xs ${order.status === 'Delivered' ? 'bg-green-900/50 text-green-300 border border-green-800' : 'bg-gray-700 text-gray-300'}`}>
                                                          {order.status}
                                                      </span>
                                                  </td>
                                                  <td className="p-4 text-right font-bold text-white">₹{order.totalAmount.toLocaleString('en-IN')}</td>
                                                  <td className="p-4 text-gray-500"><ChevronRightIcon /></td>
                                              </tr>
                                          ))}
                                      </tbody>
                                  </table>
                              ) : (
                                  <div className="p-8 text-center text-gray-500">No orders found for this customer.</div>
                              )}
                          </div>
                      </div>
                  </div>
              </div>
          ) : (
              <div className="flex-1 flex flex-col items-center justify-center text-gray-500 p-8">
                   <div className="w-32 h-32 bg-gray-800 rounded-full flex items-center justify-center mb-6">
                       <FilterIcon />
                   </div>
                   <h2 className="text-2xl font-bold text-white mb-2">Select a Customer</h2>
                   <p className="max-w-md text-center">Select a customer from the directory to view their 360-degree profile.</p>
              </div>
          )}
      </div>

      {/* Add Customer Modal */}
      <Modal isOpen={isAdding} onClose={() => setIsAdding(false)} title="Add New Customer">
          <form onSubmit={handleAddCustomer} className="space-y-4">
              <div>
                  <label className="block text-gray-400 mb-1 text-sm font-bold uppercase">Full Name</label>
                  <input required className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" value={newCustomer.name} onChange={e => setNewCustomer({...newCustomer, name: e.target.value})} />
              </div>
              <div>
                  <label className="block text-gray-400 mb-1 text-sm font-bold uppercase">Email</label>
                  <input required type="email" className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" value={newCustomer.email} onChange={e => setNewCustomer({...newCustomer, email: e.target.value})} />
              </div>
              <div>
                  <label className="block text-gray-400 mb-1 text-sm font-bold uppercase">Phone Number</label>
                  <input required className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" value={newCustomer.phone} onChange={e => setNewCustomer({...newCustomer, phone: e.target.value})} />
              </div>
              <button type="submit" className="w-full py-4 rounded-lg bg-green-600 text-white font-bold hover:bg-green-700 mt-4 shadow-lg">Save Customer</button>
          </form>
      </Modal>
    </div>
  );
};

export default Customers;
