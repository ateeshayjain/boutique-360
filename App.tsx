
import React, { useState, useMemo } from 'react';
import Sidebar from './components/Sidebar';
import Dashboard from './components/Dashboard';
import Customers from './components/Customers';
import Orders from './components/Orders';
import Inventory from './components/Inventory';
import Billing from './components/Billing';
import VirtualTryOn from './components/VirtualTryOn';
import Website from './components/Website';
import Production from './components/Production';
import GeminiAssistant from './components/GeminiAssistant';
import Login from './components/Login';
import { useMockData } from './hooks/useMockData';
import { MenuIcon, SettingsIcon, MapPinIcon } from './components/icons';

import PublicStoreWrapper from './components/PublicStoreWrapper';

const App: React.FC = () => {
  // Simple routing check for Public Store
  if (window.location.pathname.startsWith('/store')) {
    return <PublicStoreWrapper />;
  }

  const [isAuthenticated, setIsAuthenticated] = useState(false); // Auth State
  const [activeView, setActiveView] = useState('dashboard');
  const [inventoryEnabled, setInventoryEnabled] = useState(true);
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);
  const [selectedBranch, setSelectedBranch] = useState('All');

  const {
    customers, products, orders, invoices, rawMaterials, staff, jobCards, expenses,
    setCustomers, setProducts, setOrders, setInvoices, setRawMaterials, setStaff, setJobCards, setExpenses
  } = useMockData();

  // --- Global Filter Logic ---
  const filteredOrders = useMemo(() =>
    selectedBranch === 'All' ? orders : orders.filter(o => o.branchId === selectedBranch),
    [orders, selectedBranch]);

  const filteredProducts = useMemo(() =>
    selectedBranch === 'All' ? products : products.filter(p => p.branchId === selectedBranch),
    [products, selectedBranch]);

  const filteredCustomers = useMemo(() =>
    selectedBranch === 'All' ? customers : customers.filter(c => c.branchId === selectedBranch),
    [customers, selectedBranch]);

  const filteredInvoices = useMemo(() =>
    selectedBranch === 'All' ? invoices : invoices.filter(i => i.branchId === selectedBranch),
    [invoices, selectedBranch]);

  const renderView = () => {
    switch (activeView) {
      case 'dashboard':
        return <Dashboard orders={filteredOrders} />;
      case 'production':
        return <Production
          jobCards={jobCards} rawMaterials={rawMaterials} staff={staff}
          setJobCards={setJobCards} setRawMaterials={setRawMaterials} setStaff={setStaff}
          setProducts={setProducts}
        />;
      case 'customers':
        return <Customers customers={filteredCustomers} setCustomers={setCustomers} orders={filteredOrders} branchId={selectedBranch} />;
      case 'orders':
        return <Orders orders={filteredOrders} customers={filteredCustomers} products={filteredProducts} setOrders={setOrders} setProducts={setProducts} setInvoices={setInvoices} branchId={selectedBranch} />;
      case 'inventory':
        return inventoryEnabled ? <Inventory
          products={filteredProducts} setProducts={setProducts} branchId={selectedBranch}
          rawMaterials={rawMaterials} jobCards={jobCards}
          setRawMaterials={setRawMaterials}
        /> : null;
      case 'billing':
        return <Billing
          invoices={filteredInvoices} customers={filteredCustomers} orders={filteredOrders} products={filteredProducts}
          setInvoices={setInvoices} expenses={expenses} setExpenses={setExpenses}
        />;
      case 'vto':
        return <VirtualTryOn
          customers={customers}
          setJobCards={setJobCards}
        />;
      case 'website':
        return <Website products={products} setProducts={setProducts} orders={filteredOrders} />;
      default:
        return <Dashboard orders={filteredOrders} />;
    }
  };

  // Auth Check
  if (!isAuthenticated) {
    return <Login onLogin={() => setIsAuthenticated(true)} />;
  }

  return (
    <div className="flex h-screen bg-gray-900 text-gray-200">
      {/* Global AI Assistant - Always present */}
      <GeminiAssistant
        orders={orders}
        products={products}
        jobCards={jobCards}
        rawMaterials={rawMaterials}
      />

      <Sidebar
        activeView={activeView}
        setActiveView={setActiveView}
        inventoryEnabled={inventoryEnabled}
        isOpen={isSidebarOpen}
        setIsOpen={setIsSidebarOpen}
      />
      <main className="flex-1 flex flex-col overflow-hidden">
        <header className="bg-gray-800 shadow-md p-4 flex flex-col md:flex-row justify-between items-center gap-4">
          <div className="flex items-center w-full md:w-auto">
            <button onClick={() => setIsSidebarOpen(!isSidebarOpen)} className="text-gray-400 hover:text-white mr-4">
              <MenuIcon />
            </button>

            {/* Location Selector */}
            <div className="flex items-center bg-gray-700 rounded-lg px-3 py-2 border border-gray-600">
              <MapPinIcon />
              <select
                value={selectedBranch}
                onChange={(e) => setSelectedBranch(e.target.value)}
                className="bg-transparent text-white outline-none ml-2 text-sm font-medium cursor-pointer"
              >
                <option value="All">All Locations</option>
                <option value="Mumbai">Mumbai Flagship</option>
                <option value="Delhi">Delhi South Ext.</option>
                <option value="Online">Online Store</option>
              </select>
            </div>
          </div>

          <div className="flex items-center space-x-4 w-full md:w-auto justify-end">
            <label htmlFor="inventoryToggle" className="flex items-center cursor-pointer">
              <span className="mr-3 text-sm font-medium hidden md:inline">Inventory Module</span>
              <div className="relative">
                <input
                  type="checkbox"
                  id="inventoryToggle"
                  className="sr-only"
                  checked={inventoryEnabled}
                  onChange={() => setInventoryEnabled(!inventoryEnabled)}
                />
                <div className="block bg-gray-600 w-14 h-8 rounded-full"></div>
                <div className={`dot absolute left-1 top-1 bg-white w-6 h-6 rounded-full transition ${inventoryEnabled ? 'transform translate-x-6 bg-indigo-400' : ''}`}></div>
              </div>
            </label>
            <button className="text-gray-400 hover:text-white">
              <SettingsIcon />
            </button>
          </div>
        </header>
        <div className="flex-1 overflow-y-auto">
          {renderView()}
        </div>
      </main>
    </div>
  );
};

export default App;
