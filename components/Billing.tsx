
import React, { useMemo, useState } from 'react';
import { Invoice, PaymentStatus, Customer, Order, Product, Expense } from '../types';
import { CheckCircleIcon, ClockIcon, XCircleIcon, DownloadIcon, TrendingUpIcon, AlertCircleIcon, CreditCardIcon, SendIcon, ArrowLeftIcon, CalendarIcon, FilterIcon, FileTextIcon } from './icons';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, BarChart, CartesianGrid, XAxis, YAxis, Bar, Legend } from 'recharts';

interface BillingProps {
    invoices: Invoice[];
    customers: Customer[];
    orders: Order[];
    products: Product[];
    setInvoices: React.Dispatch<React.SetStateAction<Invoice[]>>;
    expenses: Expense[]; // NEW
    setExpenses: React.Dispatch<React.SetStateAction<Expense[]>>; // NEW
}

type DateRange = '30_days' | '6_months' | 'this_year' | 'all_time';
type MetricType = 'total' | 'received' | 'pending' | 'lost' | null;
type Tab = 'invoices' | 'expenses' | 'compliance';

const getStatusPill = (status: PaymentStatus) => {
    switch (status) {
        case PaymentStatus.Paid:
            return <span className="flex items-center gap-1 px-2 py-1 text-xs font-semibold rounded-full bg-green-900/50 text-green-400 border border-green-800"><CheckCircleIcon /> Paid</span>;
        case PaymentStatus.Pending:
            return <span className="flex items-center gap-1 px-2 py-1 text-xs font-semibold rounded-full bg-yellow-900/50 text-yellow-400 border border-yellow-800"><ClockIcon /> Due</span>;
        case PaymentStatus.Failed:
            return <span className="flex items-center gap-1 px-2 py-1 text-xs font-semibold rounded-full bg-red-900/50 text-red-400 border border-red-800"><XCircleIcon /> Failed</span>;
    }
};

const Billing: React.FC<BillingProps> = ({ invoices: propInvoices, customers: propCustomers, orders: propOrders, products: propProducts, setInvoices, expenses: propExpenses, setExpenses }) => {
    const invoices = propInvoices || [];
    const customers = propCustomers || [];
    const orders = propOrders || [];
    const products = propProducts || [];
    const expenses = propExpenses || [];
    const [activeTab, setActiveTab] = useState<Tab>('invoices');
    const [dateRange, setDateRange] = useState<DateRange>('all_time');
    const [selectedMetric, setSelectedMetric] = useState<MetricType>(null);

    // Filter Invoices by Date Range
    const dateFilteredInvoices = useMemo(() => {
        const now = new Date();
        return invoices.filter(inv => {
            const invDate = new Date(inv.invoiceDate);
            if (dateRange === '30_days') {
                const thirtyDaysAgo = new Date();
                thirtyDaysAgo.setDate(now.getDate() - 30);
                return invDate >= thirtyDaysAgo;
            }
            if (dateRange === '6_months') {
                const sixMonthsAgo = new Date();
                sixMonthsAgo.setMonth(now.getMonth() - 6);
                return invDate >= sixMonthsAgo;
            }
            if (dateRange === 'this_year') {
                return invDate.getFullYear() === now.getFullYear();
            }
            return true; // all_time
        });
    }, [invoices, dateRange]);

    // Financial Aggregates based on DATE filtered data
    const financialStats = useMemo(() => {
        return dateFilteredInvoices.reduce((acc, inv) => {
            acc.totalBilled += inv.totalAmount;
            if (inv.paymentStatus === PaymentStatus.Paid) acc.received += inv.totalAmount;
            if (inv.paymentStatus === PaymentStatus.Pending) acc.pending += inv.totalAmount;
            if (inv.paymentStatus === PaymentStatus.Failed) acc.lost += inv.totalAmount;
            return acc;
        }, { totalBilled: 0, received: 0, pending: 0, lost: 0 });
    }, [dateFilteredInvoices]);

    // GST Calculation
    const gstStats = useMemo(() => {
        const totalOutputGST = dateFilteredInvoices.reduce((acc, inv) => acc + (inv.taxBreakdown?.gst || 0), 0);
        const totalInputGST = expenses.reduce((acc, exp) => acc + (exp.gstInputCredit || 0), 0);
        return {
            output: totalOutputGST,
            input: totalInputGST,
            netLiability: totalOutputGST - totalInputGST
        };
    }, [dateFilteredInvoices, expenses]);

    // Filter invoices for Detailed View (Date + Metric)
    const detailInvoices = useMemo(() => {
        if (!selectedMetric) return dateFilteredInvoices;
        if (selectedMetric === 'total') return dateFilteredInvoices;
        if (selectedMetric === 'received') return dateFilteredInvoices.filter(i => i.paymentStatus === PaymentStatus.Paid);
        if (selectedMetric === 'pending') return dateFilteredInvoices.filter(i => i.paymentStatus === PaymentStatus.Pending);
        if (selectedMetric === 'lost') return dateFilteredInvoices.filter(i => i.paymentStatus === PaymentStatus.Failed);
        return dateFilteredInvoices;
    }, [dateFilteredInvoices, selectedMetric]);

    // Data for Charts: Revenue by Category (Date Filtered)
    const categoryData = useMemo(() => {
        const catMap: { [key: string]: number } = {};
        dateFilteredInvoices.filter(inv => inv.paymentStatus === PaymentStatus.Paid).forEach(inv => {
            const order = orders.find(o => o.id === inv.orderId);
            if (order) {
                order.items.forEach(item => {
                    const product = products.find(p => p.id === item.productId);
                    if (product) {
                        const amount = product.price * item.quantity;
                        catMap[product.category] = (catMap[product.category] || 0) + amount;
                    }
                });
            }
        });
        return Object.keys(catMap).map(key => ({ name: key, value: catMap[key] }));
    }, [dateFilteredInvoices, orders, products]);

    const handleMarkPaid = (id: string) => {
        setInvoices(prev => prev.map(inv => inv.id === id ? { ...inv, paymentStatus: PaymentStatus.Paid } : inv));
    };

    const formatCurrency = (val: number) => val.toLocaleString('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });

    // --- Renders ---

    const renderInvoicesTab = () => (
        <div className="space-y-6 animate-fade-in">
            {/* Financial Health Cards (Clickable) */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div onClick={() => setSelectedMetric('total')} className={`bg-gray-800 p-5 rounded-xl border-l-4 border-indigo-500 shadow-lg transition-all cursor-pointer group relative overflow-hidden ${selectedMetric === 'total' ? 'ring-2 ring-indigo-400 bg-gray-750' : 'hover:bg-gray-750 hover:scale-105'}`}>
                    <div className="flex justify-between items-start mb-2">
                        <div className="text-gray-400 text-xs uppercase font-bold tracking-wider group-hover:text-indigo-300">Total Invoiced</div>
                        <div className="p-2 bg-indigo-900/50 rounded-lg text-indigo-400"><CreditCardIcon /></div>
                    </div>
                    <div className="text-2xl font-bold text-white">{formatCurrency(financialStats.totalBilled)}</div>
                </div>

                <div onClick={() => setSelectedMetric('received')} className={`bg-gray-800 p-5 rounded-xl border-l-4 border-green-500 shadow-lg transition-all cursor-pointer group relative overflow-hidden ${selectedMetric === 'received' ? 'ring-2 ring-green-400 bg-gray-750' : 'hover:bg-gray-750 hover:scale-105'}`}>
                    <div className="flex justify-between items-start mb-2">
                        <div className="text-gray-400 text-xs uppercase font-bold tracking-wider group-hover:text-green-300">Realized</div>
                        <div className="p-2 bg-green-900/50 rounded-lg text-green-400"><TrendingUpIcon /></div>
                    </div>
                    <div className="text-2xl font-bold text-white">{formatCurrency(financialStats.received)}</div>
                </div>

                <div onClick={() => setSelectedMetric('pending')} className={`bg-gray-800 p-5 rounded-xl border-l-4 border-yellow-500 shadow-lg transition-all cursor-pointer group relative overflow-hidden ${selectedMetric === 'pending' ? 'ring-2 ring-yellow-400 bg-gray-750' : 'hover:bg-gray-750 hover:scale-105'}`}>
                    <div className="flex justify-between items-start mb-2">
                        <div className="text-gray-400 text-xs uppercase font-bold tracking-wider group-hover:text-yellow-300">Outstanding</div>
                        <div className="p-2 bg-yellow-900/50 rounded-lg text-yellow-400"><ClockIcon /></div>
                    </div>
                    <div className="text-2xl font-bold text-white">{formatCurrency(financialStats.pending)}</div>
                </div>

                <div onClick={() => setSelectedMetric('lost')} className={`bg-gray-800 p-5 rounded-xl border-l-4 border-red-500 shadow-lg transition-all cursor-pointer group relative overflow-hidden ${selectedMetric === 'lost' ? 'ring-2 ring-red-400 bg-gray-750' : 'hover:bg-gray-750 hover:scale-105'}`}>
                    <div className="flex justify-between items-start mb-2">
                        <div className="text-gray-400 text-xs uppercase font-bold tracking-wider group-hover:text-red-300">Lost Revenue</div>
                        <div className="p-2 bg-red-900/50 rounded-lg text-red-400"><AlertCircleIcon /></div>
                    </div>
                    <div className="text-2xl font-bold text-white">{formatCurrency(financialStats.lost)}</div>
                </div>
            </div>

            {/* Charts & Tables Area */}
            {!selectedMetric && (
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
                    <div className="lg:col-span-2 bg-gray-800 p-6 rounded-xl shadow-lg">
                        <h3 className="text-lg font-bold text-white mb-4">Revenue by Category</h3>
                        <div className="h-64">
                            <ResponsiveContainer width="100%" height="100%">
                                <BarChart data={categoryData} layout="vertical" margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
                                    <CartesianGrid strokeDasharray="3 3" stroke="#374151" horizontal={false} />
                                    <XAxis type="number" stroke="#9CA3AF" tickFormatter={(val) => `₹${val / 1000}k`} />
                                    <YAxis dataKey="name" type="category" stroke="#E5E7EB" width={100} />
                                    <Tooltip contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #4B5563' }} formatter={(value: number) => formatCurrency(value)} cursor={{ fill: '#374151' }} />
                                    <Bar dataKey="value" fill="#6366F1" radius={[0, 4, 4, 0]} barSize={20} />
                                </BarChart>
                            </ResponsiveContainer>
                        </div>
                    </div>
                    {/* Invoice Table Snippet */}
                    <div className="lg:col-span-1 bg-gray-800 rounded-xl shadow-lg overflow-hidden border border-gray-700">
                        <div className="p-4 border-b border-gray-700 bg-gray-750">
                            <h3 className="font-bold text-white text-sm">Recent Transactions</h3>
                        </div>
                        <div className="overflow-y-auto h-64">
                            <table className="w-full text-left">
                                <tbody className="divide-y divide-gray-700">
                                    {dateFilteredInvoices.slice(0, 10).map((invoice) => (
                                        <tr key={invoice.id} className="hover:bg-gray-700/50 text-xs">
                                            <td className="p-3">
                                                <div className="font-bold text-white">{customers.find(c => c.id === invoice.customerId)?.name}</div>
                                                <div className="text-gray-500">{invoice.invoiceDate}</div>
                                            </td>
                                            <td className="p-3 text-right">
                                                <div className="font-bold text-white">{formatCurrency(invoice.totalAmount)}</div>
                                                <div className="scale-75 origin-right">{getStatusPill(invoice.paymentStatus)}</div>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            )}

            {selectedMetric && (
                <div className="bg-gray-800 rounded-xl shadow-lg overflow-hidden border border-gray-700 animate-fade-in">
                    <div className="p-4 border-b border-gray-700 flex justify-between items-center">
                        <h3 className="font-bold text-white">Detailed Invoice List</h3>
                        <button onClick={() => setSelectedMetric(null)} className="text-sm text-gray-400 hover:text-white flex items-center gap-1"><ArrowLeftIcon /> Back</button>
                    </div>
                    <div className="overflow-x-auto">
                        <table className="w-full text-left text-sm">
                            <thead className="bg-gray-750 text-gray-400 uppercase font-semibold">
                                <tr>
                                    <th className="p-4">Invoice</th>
                                    <th className="p-4">Customer</th>
                                    <th className="p-4 text-right">Amount</th>
                                    <th className="p-4">Status</th>
                                    <th className="p-4 text-center">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-700">
                                {detailInvoices.map((invoice) => (
                                    <tr key={invoice.id} className="hover:bg-gray-700/50">
                                        <td className="p-4 text-indigo-400 font-bold">{invoice.id}</td>
                                        <td className="p-4 text-white">{customers.find(c => c.id === invoice.customerId)?.name}</td>
                                        <td className="p-4 text-right font-bold">{formatCurrency(invoice.totalAmount)}</td>
                                        <td className="p-4">{getStatusPill(invoice.paymentStatus)}</td>
                                        <td className="p-4 flex justify-center gap-2">
                                            {invoice.paymentStatus === PaymentStatus.Pending && (
                                                <button onClick={() => handleMarkPaid(invoice.id)} className="p-1.5 bg-green-600 rounded hover:bg-green-700 text-white" title="Mark Paid"><CheckCircleIcon /></button>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}
        </div>
    );

    const renderExpensesTab = () => (
        <div className="space-y-6 animate-fade-in">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="bg-gray-800 p-6 rounded-xl border border-gray-700">
                    <h3 className="font-bold text-white mb-4">Expense Ledger</h3>
                    <div className="h-64 overflow-y-auto custom-scrollbar">
                        <table className="w-full text-left text-sm">
                            <thead className="bg-gray-750 text-gray-400 uppercase text-xs">
                                <tr>
                                    <th className="p-2">Date</th>
                                    <th className="p-2">Category</th>
                                    <th className="p-2">Description</th>
                                    <th className="p-2 text-right">Amount</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-700">
                                {expenses.map(exp => (
                                    <tr key={exp.id}>
                                        <td className="p-2 text-gray-400">{exp.date}</td>
                                        <td className="p-2"><span className="bg-gray-700 px-2 py-0.5 rounded text-xs text-gray-300">{exp.category}</span></td>
                                        <td className="p-2 text-white">{exp.description}</td>
                                        <td className="p-2 text-right text-red-400 font-mono">- {formatCurrency(exp.amount)}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                    <div className="mt-4 pt-4 border-t border-gray-700 flex justify-between items-center">
                        <span className="text-gray-400 font-bold">Total Expenses</span>
                        <span className="text-red-400 font-bold text-xl">{formatCurrency(expenses.reduce((a, b) => a + b.amount, 0))}</span>
                    </div>
                </div>

                <div className="space-y-6">
                    <div className="bg-gray-800 p-6 rounded-xl border border-gray-700">
                        <h3 className="font-bold text-white mb-2">Add Expense</h3>
                        <form className="space-y-3" onSubmit={(e) => {
                            e.preventDefault();
                            // Simplified Add Logic
                            alert('Expense Added (Simulated)');
                        }}>
                            <div className="grid grid-cols-2 gap-3">
                                <input type="date" className="bg-gray-700 text-white p-2 rounded border border-gray-600" required />
                                <select className="bg-gray-700 text-white p-2 rounded border border-gray-600">
                                    <option>Rent</option>
                                    <option>Labor</option>
                                    <option>Raw Material</option>
                                    <option>Utilities</option>
                                    <option>Misc</option>
                                </select>
                            </div>
                            <input type="text" placeholder="Description" className="w-full bg-gray-700 text-white p-2 rounded border border-gray-600" required />
                            <div className="grid grid-cols-2 gap-3">
                                <input type="number" placeholder="Amount" className="bg-gray-700 text-white p-2 rounded border border-gray-600" required />
                                <input type="number" placeholder="Input GST Credit" className="bg-gray-700 text-white p-2 rounded border border-gray-600" />
                            </div>
                            <button className="w-full bg-red-600 hover:bg-red-700 text-white font-bold py-2 rounded">Record Expense</button>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    );

    const renderComplianceTab = () => (
        <div className="space-y-6 animate-fade-in">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-gray-800 p-6 rounded-xl border border-gray-700 text-center">
                    <p className="text-gray-400 text-xs uppercase font-bold mb-2">Output GST (Sales)</p>
                    <p className="text-3xl font-bold text-white">{formatCurrency(gstStats.output)}</p>
                    <p className="text-xs text-gray-500 mt-1">Collected from Customers</p>
                </div>
                <div className="bg-gray-800 p-6 rounded-xl border border-gray-700 text-center">
                    <p className="text-gray-400 text-xs uppercase font-bold mb-2">Input GST Credit (Purchases)</p>
                    <p className="text-3xl font-bold text-green-400">{formatCurrency(gstStats.input)}</p>
                    <p className="text-xs text-gray-500 mt-1">Paid on Raw Materials</p>
                </div>
                <div className="bg-gray-800 p-6 rounded-xl border border-gray-700 text-center relative overflow-hidden">
                    <div className={`absolute inset-0 opacity-10 ${gstStats.netLiability > 0 ? 'bg-red-500' : 'bg-green-500'}`}></div>
                    <p className="text-gray-400 text-xs uppercase font-bold mb-2">Net Liability Payable</p>
                    <p className={`text-3xl font-bold ${gstStats.netLiability > 0 ? 'text-red-400' : 'text-green-400'}`}>
                        {formatCurrency(Math.abs(gstStats.netLiability))}
                    </p>
                    <p className="text-xs text-gray-500 mt-1">{gstStats.netLiability > 0 ? 'To be paid to Govt' : 'Credit carried forward'}</p>
                </div>
            </div>

            <div className="bg-gray-800 p-6 rounded-xl border border-gray-700">
                <h3 className="font-bold text-white flex items-center gap-2 mb-4">
                    <FileTextIcon /> GSTR-1 & GSTR-3B Summary
                </h3>
                <div className="overflow-x-auto">
                    <table className="w-full text-left text-sm border-collapse">
                        <thead className="bg-gray-750 text-gray-400 border-b border-gray-700">
                            <tr>
                                <th className="p-3">Type</th>
                                <th className="p-3">Total Value</th>
                                <th className="p-3">Taxable Value</th>
                                <th className="p-3">Integrated Tax</th>
                                <th className="p-3">Central Tax</th>
                                <th className="p-3">State Tax</th>
                            </tr>
                        </thead>
                        <tbody className="text-gray-300 divide-y divide-gray-700">
                            <tr>
                                <td className="p-3 font-bold">B2C Sales (Large)</td>
                                <td className="p-3">₹45,000</td>
                                <td className="p-3">₹40,000</td>
                                <td className="p-3">₹0</td>
                                <td className="p-3">₹2,500</td>
                                <td className="p-3">₹2,500</td>
                            </tr>
                            <tr>
                                <td className="p-3 font-bold">B2C Sales (Small)</td>
                                <td className="p-3">₹12,500</td>
                                <td className="p-3">₹11,000</td>
                                <td className="p-3">₹1,500</td>
                                <td className="p-3">₹0</td>
                                <td className="p-3">₹0</td>
                            </tr>
                            <tr className="bg-gray-900/50 font-bold text-white">
                                <td className="p-3">Total Output</td>
                                <td className="p-3">₹57,500</td>
                                <td className="p-3">₹51,000</td>
                                <td className="p-3">₹1,500</td>
                                <td className="p-3">₹2,500</td>
                                <td className="p-3">₹2,500</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div className="mt-4 flex justify-end">
                    <button className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded flex items-center gap-2 text-sm">
                        <DownloadIcon /> Download JSON for GST Portal
                    </button>
                </div>
            </div>
        </div>
    );

    return (
        <div className="p-8 space-y-8">
            {/* Header & Tabs */}
            <div className="flex flex-col justify-between gap-4">
                <div className="flex justify-between items-center">
                    <h1 className="text-3xl font-bold text-white">Financial & Compliance</h1>
                    <div className="bg-gray-800 border border-gray-600 rounded-lg flex items-center px-3 py-2">
                        <CalendarIcon />
                        <select className="bg-transparent text-white text-sm outline-none ml-2 cursor-pointer" value={dateRange} onChange={(e) => setDateRange(e.target.value as DateRange)}>
                            <option value="30_days">Last 30 Days</option>
                            <option value="6_months">Last 6 Months</option>
                            <option value="this_year">This Year</option>
                            <option value="all_time">All Time</option>
                        </select>
                    </div>
                </div>
                <div className="flex space-x-1 bg-gray-800 p-1 rounded-lg w-fit">
                    <button onClick={() => setActiveTab('invoices')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'invoices' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>Invoices (AR)</button>
                    <button onClick={() => setActiveTab('expenses')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'expenses' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>Expenses (AP)</button>
                    <button onClick={() => setActiveTab('compliance')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'compliance' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>GST Compliance</button>
                </div>
            </div>

            {activeTab === 'invoices' && renderInvoicesTab()}
            {activeTab === 'expenses' && renderExpensesTab()}
            {activeTab === 'compliance' && renderComplianceTab()}
        </div>
    );
};

export default Billing;
