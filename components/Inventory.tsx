
import React, { useState, useMemo } from 'react';
import { Product, RawMaterial, JobCard } from '../types';
import { InventoryIcon, RulerIcon, LayersIcon, AlertTriangleIcon, FileSpreadsheetIcon, EditIcon } from './icons';
import Modal from './Modal';
import { useDebounce } from '../hooks/useDebounce';

interface InventoryProps {
  products: Product[];
  setProducts: React.Dispatch<React.SetStateAction<Product[]>>;
  branchId: string;
  rawMaterials?: RawMaterial[];
  jobCards?: JobCard[];
  setRawMaterials?: React.Dispatch<React.SetStateAction<RawMaterial[]>>;
}

const Inventory: React.FC<InventoryProps> = ({ products, setProducts, branchId, rawMaterials = [], jobCards = [], setRawMaterials }) => {
  const [activeTab, setActiveTab] = useState<'finished' | 'raw' | 'wip'>('finished');
  const [isAdding, setIsAdding] = useState(false);
  const [isAddingMaterial, setIsAddingMaterial] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const debouncedSearchTerm = useDebounce(searchTerm, 300); // Debounce search
  const [categoryFilter, setCategoryFilter] = useState('All');

  // Raw Material Edit State
  const [isEditingStock, setIsEditingStock] = useState(false);
  const [selectedMaterial, setSelectedMaterial] = useState<RawMaterial | null>(null);
  const [newStockQuantity, setNewStockQuantity] = useState<number>(0);

  const [newProduct, setNewProduct] = useState<Partial<Product> & { size: string; color: string; style: string }>({
      name: '', sku: '', category: 'Saree', price: 0, costPrice: 0, stockLevel: 0, size: '', color: '', style: '', hsnCode: '', supplier: ''
  });

  const [newMaterial, setNewMaterial] = useState<Partial<RawMaterial>>({
      name: '', type: 'Fabric', unit: 'Meters', quantity: 0, costPerUnit: 0, supplier: '', lowStockThreshold: 10
  });

  // Analytics
  const totalInventoryValue = products.reduce((acc, curr) => acc + (curr.stockLevel * curr.price), 0);
  const totalInventoryCost = products.reduce((acc, curr) => acc + (curr.stockLevel * curr.costPrice), 0);
  const potentialProfit = totalInventoryValue - totalInventoryCost;

  const categories = ['All', ...Array.from(new Set(products.map(p => p.category)))];

  const filteredProducts = useMemo(() => {
    return products.filter(p => {
        const matchesSearch = p.name.toLowerCase().includes(debouncedSearchTerm.toLowerCase()) || p.sku.toLowerCase().includes(debouncedSearchTerm.toLowerCase());
        const matchesCategory = categoryFilter === 'All' || p.category === categoryFilter;
        return matchesSearch && matchesCategory;
    });
  }, [products, debouncedSearchTerm, categoryFilter]);

  const filteredRawMaterials = useMemo(() => {
      return rawMaterials.filter(m => m.name.toLowerCase().includes(debouncedSearchTerm.toLowerCase()));
  }, [rawMaterials, debouncedSearchTerm]);

  const filteredWIP = useMemo(() => {
      return jobCards.filter(j => j.status !== 'Ready' && j.status !== 'QC'); // Show only active work
  }, [jobCards]);

  // Helper to prevent negative inputs
  const preventNegative = (e: React.KeyboardEvent) => {
    if (e.key === '-' || e.key === 'e') e.preventDefault();
  };

  const handleAddProduct = (e: React.FormEvent) => {
      e.preventDefault();
      // Validate inputs
      if (newProduct.stockLevel! < 0 || newProduct.price! < 0 || newProduct.costPrice! < 0) {
          alert("Cannot add negative values");
          return;
      }

      if(newProduct.name && newProduct.sku) {
          const assignBranch = branchId === 'All' ? 'Mumbai' : branchId;

          const product: Product = {
              id: `P${String(Date.now())}`, 
              sku: newProduct.sku,
              name: newProduct.name,
              category: newProduct.category || 'General',
              branchId: assignBranch,
              variants: {
                  size: newProduct.size,
                  color: newProduct.color,
                  style: newProduct.style
              },
              stockLevel: Math.max(0, Number(newProduct.stockLevel)),
              reorderThreshold: 5,
              price: Math.max(0, Number(newProduct.price)),
              costPrice: Math.max(0, Number(newProduct.costPrice)),
              hsnCode: newProduct.hsnCode,
              supplier: newProduct.supplier
          };
          
          setProducts(prev => [...prev, product]);
          
          setIsAdding(false);
          setNewProduct({ name: '', sku: '', category: 'Saree', price: 0, costPrice: 0, stockLevel: 0, size: '', color: '', style: '', hsnCode: '', supplier: '' });
      }
  };

  const handleAddMaterial = (e: React.FormEvent) => {
      e.preventDefault();
      if (newMaterial.quantity! < 0 || newMaterial.costPerUnit! < 0) {
          alert("Values cannot be negative");
          return;
      }

      if (newMaterial.name && setRawMaterials) {
          const material: RawMaterial = {
              id: `RM-${Date.now()}`,
              name: newMaterial.name!,
              type: newMaterial.type as any,
              unit: newMaterial.unit as any,
              quantity: Math.max(0, Number(newMaterial.quantity)),
              costPerUnit: Math.max(0, Number(newMaterial.costPerUnit)),
              supplier: newMaterial.supplier || 'Unknown',
              lowStockThreshold: Math.max(0, Number(newMaterial.lowStockThreshold)) || 10
          };
          setRawMaterials(prev => [...prev, material]);
          setIsAddingMaterial(false);
          setNewMaterial({ name: '', type: 'Fabric', unit: 'Meters', quantity: 0, costPerUnit: 0, supplier: '', lowStockThreshold: 10 });
      }
  };

  const openStockEdit = (material: RawMaterial) => {
      setSelectedMaterial(material);
      setNewStockQuantity(material.quantity);
      setIsEditingStock(true);
  };

  const handleStockUpdate = (e: React.FormEvent) => {
      e.preventDefault();
      if (newStockQuantity < 0) {
          alert("Stock cannot be negative");
          return;
      }
      if (selectedMaterial && setRawMaterials) {
          setRawMaterials(prev => prev.map(m => m.id === selectedMaterial.id ? { ...m, quantity: Number(newStockQuantity) } : m));
          setIsEditingStock(false);
          setSelectedMaterial(null);
      }
  };

  const downloadCSV = () => {
      let headers = '';
      let rows = [];

      if (activeTab === 'finished') {
          headers = 'ID,SKU,Name,Category,Stock,Cost,Price,Supplier\n';
          rows = filteredProducts.map(p => `${p.id},${p.sku},${p.name},${p.category},${p.stockLevel},${p.costPrice},${p.price},${p.supplier}`);
      } else if (activeTab === 'raw') {
          headers = 'ID,Name,Type,Quantity,Unit,CostPerUnit,Supplier\n';
          rows = filteredRawMaterials.map(m => `${m.id},${m.name},${m.type},${m.quantity},${m.unit},${m.costPerUnit},${m.supplier}`);
      } else {
          headers = 'JobID,Customer,Garment,Status,DueDate\n';
          rows = filteredWIP.map(j => `${j.id},${j.customerName},${j.garmentType},${j.status},${j.dueDate}`);
      }

      const csvContent = "data:text/csv;charset=utf-8," + headers + rows.join("\n");
      const encodedUri = encodeURI(csvContent);
      const link = document.createElement("a");
      link.setAttribute("href", encodedUri);
      link.setAttribute("download", `${activeTab}_inventory_report.csv`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
  };

  const renderFinishedGoods = () => (
      <>
      {/* Valuation Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="bg-gray-800 p-5 rounded-xl border border-gray-700 relative overflow-hidden group">
              <div className="absolute top-0 right-0 w-24 h-24 bg-blue-500/10 rounded-bl-full -mr-4 -mt-4 group-hover:scale-110 transition-transform"></div>
              <p className="text-gray-400 text-xs uppercase font-bold tracking-wider">Retail Value</p>
              <p className="text-3xl font-bold text-white mt-2">₹{totalInventoryValue.toLocaleString('en-IN')}</p>
          </div>
          <div className="bg-gray-800 p-5 rounded-xl border border-gray-700 relative overflow-hidden group">
               <div className="absolute top-0 right-0 w-24 h-24 bg-yellow-500/10 rounded-bl-full -mr-4 -mt-4 group-hover:scale-110 transition-transform"></div>
              <p className="text-gray-400 text-xs uppercase font-bold tracking-wider">Investment Value</p>
              <p className="text-3xl font-bold text-white mt-2">₹{totalInventoryCost.toLocaleString('en-IN')}</p>
          </div>
          <div className="bg-gray-800 p-5 rounded-xl border border-gray-700 relative overflow-hidden group">
               <div className="absolute top-0 right-0 w-24 h-24 bg-green-500/10 rounded-bl-full -mr-4 -mt-4 group-hover:scale-110 transition-transform"></div>
              <p className="text-gray-400 text-xs uppercase font-bold tracking-wider">Projected Profit</p>
              <p className="text-3xl font-bold text-green-400 mt-2">₹{potentialProfit.toLocaleString('en-IN')}</p>
          </div>
      </div>

      {/* Filters */}
      <div className="glass-panel p-4 rounded-xl flex flex-col md:flex-row gap-4 items-center mb-6">
          <input 
            type="text" 
            placeholder="Search Finished Goods..." 
            className="flex-1 bg-gray-900 text-white rounded-lg px-4 py-2.5 border border-gray-700 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 transition-all"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
          <select 
            className="bg-gray-900 text-white rounded-lg px-4 py-2.5 border border-gray-700 focus:border-indigo-500 focus:outline-none"
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
          >
              {categories.map(cat => <option key={cat} value={cat}>{cat}</option>)}
          </select>
      </div>

      {/* Table */}
      <div className="bg-gray-800 rounded-xl shadow-xl overflow-hidden border border-gray-700">
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="bg-gray-750 text-gray-400 text-xs uppercase tracking-wider">
              <tr>
                <th className="p-5 font-semibold">Product Details</th>
                <th className="p-5 font-semibold">Location</th>
                <th className="p-5 font-semibold text-right">Cost</th>
                <th className="p-5 font-semibold text-right">Retail</th>
                <th className="p-5 font-semibold text-center">Margin</th>
                <th className="p-5 font-semibold text-center">Stock</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-700">
              {filteredProducts.map((product, index) => {
                  const margin = product.price > 0 ? ((product.price - product.costPrice) / product.price) * 100 : 0;
                  return (
                    <tr key={product.id} className={`hover:bg-gray-700/40 transition-colors ${index % 2 === 0 ? 'bg-gray-800' : 'bg-gray-900/30'}`}>
                    <td className="p-5">
                        <div className="flex items-start gap-3">
                            <div className="w-10 h-10 rounded bg-gray-700 flex items-center justify-center flex-shrink-0 text-xs text-gray-400">
                                {product.imageUrl ? <img src={product.imageUrl} className="w-full h-full object-cover rounded"/> : 'IMG'}
                            </div>
                            <div>
                                <div className="font-bold text-white text-sm">{product.name}</div>
                                <div className="text-xs text-gray-400 mt-0.5">{product.sku} • {product.category}</div>
                            </div>
                        </div>
                    </td>
                    <td className="p-5 text-sm text-gray-300">
                        <span className="px-2 py-1 rounded bg-gray-700 text-xs border border-gray-600">{product.branchId}</span>
                        <div className="mt-1 text-xs text-gray-500">{product.supplier}</div>
                    </td>
                    <td className="p-5 text-right font-mono text-gray-400 text-sm">
                        ₹{product.costPrice.toLocaleString('en-IN')}
                    </td>
                    <td className="p-5 text-right font-bold text-white text-sm">
                        ₹{product.price.toLocaleString('en-IN')}
                    </td>
                    <td className="p-5 text-center">
                        <span className={`px-2 py-0.5 text-xs rounded font-bold ${margin > 50 ? 'bg-green-900/50 text-green-400 border border-green-800' : 'bg-gray-700 text-gray-300'}`}>
                            {margin.toFixed(0)}%
                        </span>
                    </td>
                    <td className="p-5 text-center">
                        <div className={`font-bold ${product.stockLevel <= product.reorderThreshold ? 'text-red-500' : 'text-white'}`}>
                            {product.stockLevel}
                        </div>
                    </td>
                    </tr>
                );
              })}
            </tbody>
          </table>
          {filteredProducts.length === 0 && (
              <div className="p-12 text-center text-gray-500 bg-gray-800">No products found matching your criteria.</div>
          )}
        </div>
      </div>
      </>
  );

  const renderRawMaterials = () => (
      <div className="bg-gray-800 rounded-xl shadow-xl overflow-hidden border border-gray-700">
          <div className="p-4 border-b border-gray-700 flex justify-between items-center">
              <input 
                type="text" 
                placeholder="Search Raw Materials..." 
                className="w-64 bg-gray-900 text-white rounded-lg px-4 py-2 border border-gray-700 focus:border-indigo-500 focus:outline-none text-sm"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
          </div>
          <table className="w-full text-left text-sm">
                <thead className="bg-gray-750 text-gray-400 uppercase text-xs">
                    <tr>
                        <th className="p-4">Item Name</th>
                        <th className="p-4">Type</th>
                        <th className="p-4 text-right">Quantity</th>
                        <th className="p-4 text-right">Cost/Unit</th>
                        <th className="p-4">Supplier</th>
                        <th className="p-4 text-center">Status</th>
                        <th className="p-4 text-center">Actions</th>
                    </tr>
                </thead>
                <tbody className="divide-y divide-gray-700">
                    {filteredRawMaterials.map(mat => (
                        <tr key={mat.id} className="hover:bg-gray-700/50">
                            <td className="p-4 font-medium text-white">{mat.name}</td>
                            <td className="p-4 text-gray-400">{mat.type}</td>
                            <td className="p-4 text-right text-white font-mono">{mat.quantity} <span className="text-xs text-gray-500">{mat.unit}</span></td>
                            <td className="p-4 text-right text-gray-300">₹{mat.costPerUnit}</td>
                            <td className="p-4 text-gray-400">{mat.supplier}</td>
                            <td className="p-4 text-center">
                                {mat.quantity <= mat.lowStockThreshold ? (
                                    <span className="text-red-400 flex items-center justify-center gap-1 text-xs font-bold"><AlertTriangleIcon /> Low</span>
                                ) : (
                                    <span className="text-green-500 text-xs">OK</span>
                                )}
                            </td>
                            <td className="p-4 text-center">
                                <button onClick={() => openStockEdit(mat)} className="text-gray-400 hover:text-white p-2 bg-gray-700 rounded hover:bg-gray-600">
                                    <EditIcon />
                                </button>
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
      </div>
  );

  const renderWIP = () => (
      <div className="bg-gray-800 rounded-xl shadow-xl overflow-hidden border border-gray-700">
            <div className="p-6 border-b border-gray-700">
                <h3 className="font-bold text-white">Work In Progress (Factory Floor)</h3>
                <p className="text-sm text-gray-400">Items currently being stitched or processed.</p>
            </div>
            <table className="w-full text-left text-sm">
                <thead className="bg-gray-750 text-gray-400 uppercase text-xs">
                    <tr>
                        <th className="p-4">Job ID</th>
                        <th className="p-4">Customer</th>
                        <th className="p-4">Garment</th>
                        <th className="p-4">Stage</th>
                        <th className="p-4">Due Date</th>
                    </tr>
                </thead>
                <tbody className="divide-y divide-gray-700">
                    {filteredWIP.map(job => (
                        <tr key={job.id} className="hover:bg-gray-700/50">
                            <td className="p-4 font-mono text-indigo-400">{job.id}</td>
                            <td className="p-4 text-white font-medium">{job.customerName}</td>
                            <td className="p-4 text-gray-300">{job.garmentType}</td>
                            <td className="p-4">
                                <span className="bg-indigo-900/50 text-indigo-300 px-2 py-1 rounded text-xs border border-indigo-800">{job.status}</span>
                            </td>
                            <td className="p-4 text-white">{job.dueDate}</td>
                        </tr>
                    ))}
                    {filteredWIP.length === 0 && (
                        <tr><td colSpan={5} className="p-8 text-center text-gray-500">No active jobs in WIP.</td></tr>
                    )}
                </tbody>
            </table>
      </div>
  );

  return (
    <div className="p-8 space-y-6 animate-fade-in">
      <div className="flex justify-between items-center">
        <div>
            <h1 className="text-3xl font-bold text-white">Inventory Management</h1>
            <p className="text-sm text-gray-400 mt-1">
                Branch: <span className="text-indigo-400 font-semibold">{branchId === 'All' ? 'All Locations' : branchId}</span>
            </p>
        </div>
        <div className="flex gap-3">
            <button 
                onClick={downloadCSV}
                className="bg-gray-700 text-white font-bold py-2 px-4 rounded-lg hover:bg-gray-600 transition-colors flex items-center gap-2"
            >
                <FileSpreadsheetIcon /> Export Report
            </button>
            {activeTab === 'finished' && (
                <button 
                    onClick={() => setIsAdding(true)}
                    className="bg-indigo-600 text-white font-bold py-2 px-4 rounded-lg hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-900/20 flex items-center gap-2"
                >
                + Add Retail Item
                </button>
            )}
            {activeTab === 'raw' && (
                <button 
                    onClick={() => setIsAddingMaterial(true)}
                    className="bg-indigo-600 text-white font-bold py-2 px-4 rounded-lg hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-900/20 flex items-center gap-2"
                >
                + Add Material
                </button>
            )}
        </div>
      </div>

      {/* Unified Tabs */}
      <div className="flex space-x-1 bg-gray-800 p-1 rounded-lg w-fit">
          <button onClick={() => setActiveTab('finished')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'finished' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>
              <InventoryIcon /> Finished Goods (Retail)
          </button>
          <button onClick={() => setActiveTab('raw')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'raw' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>
              <RulerIcon /> Raw Materials
          </button>
          <button onClick={() => setActiveTab('wip')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'wip' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>
              <LayersIcon /> Work In Progress (WIP)
          </button>
      </div>

      {/* Tab Content */}
      {activeTab === 'finished' && renderFinishedGoods()}
      {activeTab === 'raw' && renderRawMaterials()}
      {activeTab === 'wip' && renderWIP()}

      {/* Modal for Adding Product (Only for Finished Goods) */}
      <Modal isOpen={isAdding} onClose={() => setIsAdding(false)} title={`Add New Product to ${branchId === 'All' ? 'Mumbai (Default)' : branchId}`} size="lg">
         <form onSubmit={handleAddProduct} className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="col-span-2">
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Product Name</label>
                      <input required type="text" placeholder="e.g. Banarasi Silk Saree" className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" 
                          value={newProduct.name} onChange={e => setNewProduct({...newProduct, name: e.target.value})} />
                  </div>
                  
                  <div>
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">SKU</label>
                      <input required type="text" className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" 
                          value={newProduct.sku} onChange={e => setNewProduct({...newProduct, sku: e.target.value})} />
                  </div>
                  <div>
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Category</label>
                      <select className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none"
                        value={newProduct.category} onChange={e => setNewProduct({...newProduct, category: e.target.value})}>
                            <option value="Saree">Saree</option>
                            <option value="Lehenga">Lehenga</option>
                            <option value="Kurti">Kurti</option>
                            <option value="Suit Set">Suit Set</option>
                            <option value="Fabric">Fabric</option>
                            <option value="Accessories">Accessories</option>
                        </select>
                  </div>
                  
                  <div className="col-span-2 bg-gray-800 p-4 rounded-lg border border-gray-700">
                      <h4 className="text-white font-bold mb-4 text-sm">Pricing & Economics</h4>
                      <div className="grid grid-cols-3 gap-4">
                           <div>
                                <label className="block text-gray-400 mb-1 text-xs">Cost Price (₹)</label>
                                <input required type="number" min="0" onKeyDown={preventNegative} className="w-full bg-gray-900 text-white rounded p-2 border border-gray-600" 
                                    value={newProduct.costPrice} onChange={e => setNewProduct({...newProduct, costPrice: Number(e.target.value)})} />
                           </div>
                           <div>
                                <label className="block text-gray-400 mb-1 text-xs">Selling Price (₹)</label>
                                <input required type="number" min="0" onKeyDown={preventNegative} className="w-full bg-gray-900 text-white rounded p-2 border border-gray-600" 
                                    value={newProduct.price} onChange={e => setNewProduct({...newProduct, price: Number(e.target.value)})} />
                           </div>
                           <div>
                                <label className="block text-gray-400 mb-1 text-xs">HSN Code</label>
                                <input type="text" className="w-full bg-gray-900 text-white rounded p-2 border border-gray-600" 
                                    value={newProduct.hsnCode} onChange={e => setNewProduct({...newProduct, hsnCode: e.target.value})} />
                           </div>
                      </div>
                  </div>

                  <div>
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Initial Stock</label>
                      <input required type="number" min="0" onKeyDown={preventNegative} className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" 
                          value={newProduct.stockLevel} onChange={e => setNewProduct({...newProduct, stockLevel: Number(e.target.value)})} />
                  </div>
                  <div>
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Size</label>
                      <input type="text" className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" 
                          value={newProduct.size} onChange={e => setNewProduct({...newProduct, size: e.target.value})} />
                  </div>
                  
                  <div>
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Color</label>
                      <input type="text" className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" 
                          value={newProduct.color} onChange={e => setNewProduct({...newProduct, color: e.target.value})} />
                  </div>
                  <div>
                      <label className="block text-gray-400 mb-1 text-xs font-bold uppercase">Supplier</label>
                      <input type="text" className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700 focus:border-indigo-500 focus:outline-none" 
                          value={newProduct.supplier} onChange={e => setNewProduct({...newProduct, supplier: e.target.value})} />
                  </div>
              </div>
              
              <button type="submit" className="w-full bg-green-600 text-white font-bold py-4 px-6 rounded-lg hover:bg-green-700 transition-colors shadow-lg">
                  Save Product
              </button>
         </form>
      </Modal>

      {/* Modal for Adding Raw Material */}
      <Modal isOpen={isAddingMaterial} onClose={() => setIsAddingMaterial(false)} title="Add New Raw Material" size="md">
          <form onSubmit={handleAddMaterial} className="space-y-4">
              <div>
                  <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Material Name</label>
                  <input required className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700" 
                    placeholder="e.g. Silk Thread" value={newMaterial.name} onChange={e => setNewMaterial({...newMaterial, name: e.target.value})} />
              </div>
              <div className="grid grid-cols-2 gap-4">
                  <div>
                      <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Type</label>
                      <select className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700"
                        value={newMaterial.type} onChange={e => setNewMaterial({...newMaterial, type: e.target.value as any})}>
                          <option value="Fabric">Fabric</option>
                          <option value="Trim">Trim</option>
                          <option value="Thread">Thread</option>
                          <option value="Embellishment">Embellishment</option>
                      </select>
                  </div>
                  <div>
                      <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Unit</label>
                      <select className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700"
                        value={newMaterial.unit} onChange={e => setNewMaterial({...newMaterial, unit: e.target.value as any})}>
                          <option value="Meters">Meters</option>
                          <option value="Pieces">Pieces</option>
                          <option value="Rolls">Rolls</option>
                          <option value="Kg">Kg</option>
                      </select>
                  </div>
              </div>
               <div className="grid grid-cols-2 gap-4">
                  <div>
                      <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Quantity</label>
                      <input required type="number" min="0" onKeyDown={preventNegative} className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700" 
                        value={newMaterial.quantity} onChange={e => setNewMaterial({...newMaterial, quantity: Number(e.target.value)})} />
                  </div>
                  <div>
                      <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Cost Per Unit</label>
                      <input required type="number" min="0" onKeyDown={preventNegative} className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700" 
                        value={newMaterial.costPerUnit} onChange={e => setNewMaterial({...newMaterial, costPerUnit: Number(e.target.value)})} />
                  </div>
              </div>
              <div>
                  <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Supplier</label>
                  <input className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700" 
                    value={newMaterial.supplier} onChange={e => setNewMaterial({...newMaterial, supplier: e.target.value})} />
              </div>
              <button className="w-full bg-green-600 py-3 rounded font-bold text-white hover:bg-green-700 mt-2">Add To Inventory</button>
          </form>
      </Modal>

      {/* Modal for Editing Stock */}
      <Modal isOpen={isEditingStock} onClose={() => setIsEditingStock(false)} title="Update Raw Material Stock" size="md">
          <form onSubmit={handleStockUpdate} className="space-y-4">
              {selectedMaterial && (
                  <>
                    <div className="p-4 bg-gray-800 rounded border border-gray-700">
                        <p className="text-sm text-gray-400 uppercase font-bold">Item</p>
                        <p className="text-white font-bold text-lg">{selectedMaterial.name}</p>
                        <p className="text-xs text-gray-500">{selectedMaterial.supplier}</p>
                    </div>
                    <div>
                        <label className="block text-gray-400 mb-1 text-sm font-bold uppercase">Current Stock ({selectedMaterial.unit})</label>
                        <input type="number" min="0" onKeyDown={preventNegative} className="w-full bg-gray-800 text-white rounded p-3 border border-gray-700" 
                            value={newStockQuantity} onChange={e => setNewStockQuantity(Number(e.target.value))} />
                        <p className="text-xs text-gray-500 mt-2">Enter the new physical count. This will adjust opening/closing stock records.</p>
                    </div>
                    <button className="w-full bg-indigo-600 py-3 rounded font-bold text-white hover:bg-indigo-700">Update Stock</button>
                  </>
              )}
          </form>
      </Modal>
    </div>
  );
};

export default Inventory;
