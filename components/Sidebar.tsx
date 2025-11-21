
import React from 'react';
import { DashboardIcon, CustomersIcon, OrdersIcon, InventoryIcon, BillingIcon, VirtualTryOnIcon, WebsiteIcon, FactoryIcon } from './icons';

interface SidebarProps {
  activeView: string;
  setActiveView: (view: string) => void;
  inventoryEnabled: boolean;
  isOpen: boolean;
  setIsOpen: (isOpen: boolean) => void;
}

const NavItem: React.FC<{
  icon: React.ReactNode;
  label: string;
  viewName: string;
  activeView: string;
  onClick: (view: string) => void;
}> = ({ icon, label, viewName, activeView, onClick }) => {
  const isActive = activeView === viewName;
  return (
    <li
      className={`flex items-center p-3 rounded-lg cursor-pointer transition-colors ${
        isActive
          ? 'bg-indigo-600 text-white shadow-lg'
          : 'text-gray-400 hover:bg-gray-700 hover:text-white'
      }`}
      onClick={() => onClick(viewName)}
    >
      {icon}
      <span className="ml-4 font-medium">{label}</span>
    </li>
  );
};

const Sidebar: React.FC<SidebarProps> = ({ activeView, setActiveView, inventoryEnabled, isOpen, setIsOpen }) => {
    return (
        <aside className={`bg-gray-800 text-white h-screen transition-all duration-300 ease-in-out fixed lg:relative z-20 ${isOpen ? 'w-64' : 'w-0 lg:w-20'} overflow-hidden`}>
            <div className={`p-4 ${isOpen ? '' : 'lg:p-0'} flex flex-col h-full`}>
                <div className={`flex items-center mb-10 ${isOpen ? 'justify-between' : 'lg:justify-center'}`}>
                    <h1 className={`text-2xl font-bold text-white transition-opacity ${isOpen ? 'opacity-100' : 'opacity-0 lg:hidden'}`}>Boutique360</h1>
                    <span className={`text-2xl font-bold text-white transition-opacity ${!isOpen ? 'lg:opacity-100' : 'hidden'}`}>B</span>
                </div>
                <nav>
                    <ul className="space-y-3">
                        <NavItem icon={<DashboardIcon />} label="Dashboard" viewName="dashboard" activeView={activeView} onClick={setActiveView} />
                        <NavItem icon={<FactoryIcon />} label="Production & Factory" viewName="production" activeView={activeView} onClick={setActiveView} />
                        <NavItem icon={<CustomersIcon />} label="Customers" viewName="customers" activeView={activeView} onClick={setActiveView} />
                        <NavItem icon={<OrdersIcon />} label="Orders" viewName="orders" activeView={activeView} onClick={setActiveView} />
                        {inventoryEnabled && <NavItem icon={<InventoryIcon />} label="Inventory" viewName="inventory" activeView={activeView} onClick={setActiveView} />}
                        <NavItem icon={<BillingIcon />} label="Billing & Finance" viewName="billing" activeView={activeView} onClick={setActiveView} />
                        <NavItem icon={<VirtualTryOnIcon />} label="Virtual Try-On" viewName="vto" activeView={activeView} onClick={setActiveView} />
                        <NavItem icon={<WebsiteIcon />} label="Website" viewName="website" activeView={activeView} onClick={setActiveView} />
                    </ul>
                </nav>
                <div className="mt-auto p-4 text-center text-gray-500 text-xs">
                    <p className={`${isOpen ? '' : 'lg:hidden'}`}>&copy; 2024 Boutique 360</p>
                </div>
            </div>
        </aside>
    );
};

export default Sidebar;
