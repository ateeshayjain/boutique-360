
import React from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts';
import { Order, OrderStatus } from '../types';
import { TrendingUpIcon, BuildingIcon, ActivityIcon, AlertTriangleIcon, GlobeIcon, ShoppingBagIcon, PackageIcon } from './icons';

interface DashboardProps {
    orders: Order[];
}

const Dashboard: React.FC<DashboardProps> = ({ orders }) => {
    
    // --- Key Metrics Calculation based on FILTERED orders ---
    const totalRevenue = orders.reduce((acc, order) => acc + order.totalAmount, 0);
    // Simulate Cost for Profit Calc (assuming ~35% margin on average)
    const netProfit = totalRevenue * 0.35;
    const activeOrders = orders.filter(o => o.status === OrderStatus.Pending || o.status === OrderStatus.Processing).length;
    
    // Calculate simple conversion rate simulation based on active orders count (just for visual)
    const conversionRate = activeOrders > 0 ? (3.2 + (activeOrders / 10)).toFixed(1) : '0.0';

    // --- Chart Data ---
    // In a real app, this data would be aggregated from the filtered orders array by date.
    // For now, we mock the distribution but scale it by the filtered revenue to look responsive.
    const baseScale = totalRevenue > 0 ? totalRevenue / 200000 : 0;
    
    const revenueTrendData = [
        { name: 'Week 1', revenue: 45000 * baseScale, cost: 30000 * baseScale },
        { name: 'Week 2', revenue: 52000 * baseScale, cost: 34000 * baseScale },
        { name: 'Week 3', revenue: 48000 * baseScale, cost: 31000 * baseScale },
        { name: 'Week 4', revenue: 61000 * baseScale, cost: 39000 * baseScale },
        { name: 'Week 5', revenue: 55000 * baseScale, cost: 36000 * baseScale },
        { name: 'Week 6', revenue: 72000 * baseScale, cost: 45000 * baseScale },
    ];

    // Calculate channel split from actual filtered orders
    const mumbaiOrders = orders.filter(o => o.branchId === 'Mumbai').length;
    const delhiOrders = orders.filter(o => o.branchId === 'Delhi').length;
    const onlineOrders = orders.filter(o => o.branchId === 'Online').length;
    
    let channelData = [
        { name: 'Mumbai Store', value: mumbaiOrders },
        { name: 'Delhi Store', value: delhiOrders },
        { name: 'Online', value: onlineOrders },
    ].filter(d => d.value > 0);
    
    if(channelData.length === 0) {
        channelData = [{ name: 'No Data', value: 1 }];
    }

    const COLORS = ['#6366F1', '#10B981', '#F59E0B'];

    // --- Components ---

    const MetricCard = ({ title, value, subValue, trend, icon, colorClass }: any) => (
        <div className="bg-gray-800 p-6 rounded-xl shadow-lg border border-gray-700 flex justify-between items-start relative overflow-hidden group">
            <div className={`absolute top-0 right-0 p-4 opacity-10 group-hover:opacity-20 transition-opacity ${colorClass}`}>
                {React.cloneElement(icon, { className: 'w-16 h-16' })}
            </div>
            <div>
                <p className="text-gray-400 text-sm font-medium uppercase tracking-wider">{title}</p>
                <h3 className="text-3xl font-bold text-white mt-1">{value}</h3>
                <div className="flex items-center mt-2 gap-2">
                    <span className={`text-xs font-bold px-1.5 py-0.5 rounded ${trend === 'up' ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
                        {trend === 'up' ? '↑' : '↓'} {subValue}
                    </span>
                    <span className="text-gray-500 text-xs">vs last month</span>
                </div>
            </div>
            <div className={`p-3 rounded-lg ${colorClass.replace('text-', 'bg-').replace('500', '500/20')} ${colorClass}`}>
                {icon}
            </div>
        </div>
    );

    const ActionItem = ({ title, count, type }: any) => (
        <div className="flex items-center justify-between p-3 bg-gray-700/50 rounded-lg hover:bg-gray-700 transition-colors cursor-pointer group">
            <div className="flex items-center gap-3">
                {type === 'alert' && <div className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></div>}
                {type === 'warning' && <div className="w-2 h-2 rounded-full bg-yellow-500"></div>}
                {type === 'info' && <div className="w-2 h-2 rounded-full bg-blue-500"></div>}
                <span className="text-sm text-gray-300 font-medium group-hover:text-white">{title}</span>
            </div>
            <div className="bg-gray-800 px-2 py-1 rounded text-xs font-bold text-white border border-gray-600">{count}</div>
        </div>
    );

    return (
        <div className="p-8 space-y-8 animate-fade-in">
            
            {/* Header */}
            <div className="flex flex-col md:flex-row justify-between items-center gap-4">
                <div>
                    <h1 className="text-3xl font-bold text-white">Business Control Tower</h1>
                    <p className="text-gray-400 text-sm mt-1">Real-time overview of your boutique's performance.</p>
                </div>
            </div>

            {/* KPI Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
                <MetricCard 
                    title="Total Revenue" 
                    value={totalRevenue.toLocaleString('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 })} 
                    subValue="12%" 
                    trend="up" 
                    icon={<TrendingUpIcon />} 
                    colorClass="text-indigo-500"
                />
                <MetricCard 
                    title="Net Profit (Est.)" 
                    value={netProfit.toLocaleString('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 })} 
                    subValue="8%" 
                    trend="up" 
                    icon={<ShoppingBagIcon />} 
                    colorClass="text-emerald-500"
                />
                <MetricCard 
                    title="Active Orders" 
                    value={activeOrders} 
                    subValue="2" 
                    trend="down" 
                    icon={<PackageIcon />} 
                    colorClass="text-yellow-500"
                />
                <MetricCard 
                    title="Conversion Rate" 
                    value={`${conversionRate}%`} 
                    subValue="0.4%" 
                    trend="up" 
                    icon={<GlobeIcon />} 
                    colorClass="text-pink-500"
                />
            </div>

            {/* Visual Analytics Row */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Revenue Trend Chart */}
                <div className="lg:col-span-2 bg-gray-800 p-6 rounded-xl shadow-lg border border-gray-700">
                    <div className="flex justify-between items-center mb-6">
                        <h3 className="text-lg font-bold text-white">Revenue Trajectory</h3>
                        <div className="flex items-center gap-2 text-sm text-gray-400">
                            <span className="flex items-center gap-1"><div className="w-3 h-3 bg-indigo-500 rounded-full"></div> Revenue</span>
                            <span className="flex items-center gap-1"><div className="w-3 h-3 bg-indigo-500/20 rounded-full"></div> Cost</span>
                        </div>
                    </div>
                    <div className="h-72">
                        <ResponsiveContainer width="100%" height="100%">
                            <AreaChart data={revenueTrendData}>
                                <defs>
                                    <linearGradient id="colorRevenue" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor="#6366F1" stopOpacity={0.8}/>
                                        <stop offset="95%" stopColor="#6366F1" stopOpacity={0}/>
                                    </linearGradient>
                                </defs>
                                <CartesianGrid strokeDasharray="3 3" stroke="#374151" vertical={false} />
                                <XAxis dataKey="name" stroke="#9CA3AF" axisLine={false} tickLine={false} />
                                <YAxis stroke="#9CA3AF" axisLine={false} tickLine={false} tickFormatter={val => `₹${(val/1000).toFixed(0)}k`} />
                                <Tooltip 
                                    contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #4B5563', borderRadius: '8px' }} 
                                    formatter={(value: number) => [`₹${value.toLocaleString('en-IN')}`, '']}
                                />
                                <Area type="monotone" dataKey="revenue" stroke="#6366F1" strokeWidth={3} fillOpacity={1} fill="url(#colorRevenue)" />
                            </AreaChart>
                        </ResponsiveContainer>
                    </div>
                </div>

                {/* Channel Split & Operations */}
                <div className="space-y-6">
                    {/* Donut Chart */}
                    <div className="bg-gray-800 p-6 rounded-xl shadow-lg border border-gray-700">
                        <h3 className="text-lg font-bold text-white mb-2">Location / Source Split</h3>
                        <div className="h-48">
                            <ResponsiveContainer width="100%" height="100%">
                                <PieChart>
                                    <Pie
                                        data={channelData}
                                        cx="50%"
                                        cy="50%"
                                        innerRadius={50}
                                        outerRadius={70}
                                        paddingAngle={5}
                                        dataKey="value"
                                    >
                                        {channelData.map((entry, index) => (
                                            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                                        ))}
                                    </Pie>
                                    <Legend verticalAlign="bottom" height={36}/>
                                    <Tooltip contentStyle={{ backgroundColor: '#1F2937', borderRadius: '8px' }} />
                                </PieChart>
                            </ResponsiveContainer>
                        </div>
                    </div>

                    {/* Recent Activity Mini Feed (Simulated from Orders) */}
                    <div className="bg-gray-800 p-6 rounded-xl shadow-lg border border-gray-700">
                        <h3 className="text-lg font-bold text-white mb-4 flex items-center gap-2"><ActivityIcon /> Live Activity</h3>
                        <div className="space-y-4">
                            {orders.slice(0, 3).map((o, i) => (
                                <div className="flex gap-3" key={o.id}>
                                    <div className="mt-1"><div className={`w-2 h-2 rounded-full ${o.status === 'Delivered' ? 'bg-green-500' : 'bg-indigo-500'}`}></div></div>
                                    <div>
                                        <p className="text-sm text-white">Order {o.id} - {o.status}</p>
                                        <p className="text-xs text-gray-500">{o.orderDate} • {o.branchId}</p>
                                    </div>
                                </div>
                            ))}
                            {orders.length === 0 && <p className="text-sm text-gray-500">No recent activity in this view.</p>}
                        </div>
                    </div>
                </div>
            </div>

            {/* The Business Pulse (Pending Action Items) */}
            <div className="bg-gray-800 p-6 rounded-xl shadow-lg border border-gray-700">
                <div className="flex items-center justify-between mb-6">
                    <h3 className="text-xl font-bold text-white flex items-center gap-2">
                        <AlertTriangleIcon /> Business Pulse (Action Required)
                    </h3>
                    <button className="text-indigo-400 text-sm hover:text-indigo-300">View All Tasks</button>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <div className="space-y-1">
                        <h4 className="text-xs uppercase text-gray-500 font-bold mb-2">Orders & Logistics</h4>
                        <ActionItem title="Pending Shipments" count={orders.filter(o => o.status === 'Pending').length} type="warning" />
                        <ActionItem title="Returns Approval" count={orders.filter(o => o.status === 'Returned').length} type="alert" />
                    </div>
                    <div className="space-y-1">
                        <h4 className="text-xs uppercase text-gray-500 font-bold mb-2">Inventory & Stock</h4>
                        <ActionItem title="Low Stock Items" count={2} type="alert" />
                        <ActionItem title="Restock Requests" count={1} type="info" />
                    </div>
                    <div className="space-y-1">
                        <h4 className="text-xs uppercase text-gray-500 font-bold mb-2">Financials</h4>
                        <ActionItem title="Unpaid Invoices" count={4} type="warning" />
                        <ActionItem title="Expense Approval" count={2} type="info" />
                    </div>
                    <div className="space-y-1">
                        <h4 className="text-xs uppercase text-gray-500 font-bold mb-2">Customer & Web</h4>
                        <ActionItem title="Unread Enquiries" count={3} type="info" />
                        <ActionItem title="Alteration Due" count={1} type="alert" />
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Dashboard;
