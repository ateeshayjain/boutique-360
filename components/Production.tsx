
import React, { useState } from 'react';
import { JobCard, RawMaterial, Staff, Product } from '../types';
import { FactoryIcon, ClipboardListIcon, UsersIcon, RulerIcon, ScissorsIcon, AlertTriangleIcon, CheckCircleIcon, TrashIcon, ArrowRightCircleIcon } from './icons';
import Modal from './Modal';

interface ProductionProps {
    jobCards: JobCard[];
    rawMaterials: RawMaterial[];
    staff: Staff[];
    setJobCards: React.Dispatch<React.SetStateAction<JobCard[]>>;
    setRawMaterials: React.Dispatch<React.SetStateAction<RawMaterial[]>>;
    setStaff: React.Dispatch<React.SetStateAction<Staff[]>>;
    setProducts?: React.Dispatch<React.SetStateAction<Product[]>>;
}

const Production: React.FC<ProductionProps> = ({ jobCards, rawMaterials, staff, setJobCards, setRawMaterials, setStaff, setProducts }) => {
    const [activeTab, setActiveTab] = useState<'jobs' | 'materials' | 'staff'>('jobs');
    const [isAddingJob, setIsAddingJob] = useState(false);
    const [newJob, setNewJob] = useState<Partial<JobCard>>({ status: 'Measurements', fabricConsumed: [] });
    const [consumedMaterials, setConsumedMaterials] = useState<{materialId: string, quantity: number}[]>([]);
    
    // Convert Job to Product State
    const [isConverting, setIsConverting] = useState(false);
    const [jobToConvert, setJobToConvert] = useState<JobCard | null>(null);
    const [conversionData, setConversionData] = useState({ price: 0, sku: '', name: '' });
    const [calculatedCost, setCalculatedCost] = useState(0);

    // --- Helpers ---
    const getStaffName = (id: string) => staff.find(s => s.id === id)?.name || 'Unassigned';

    // --- Live Cost Calculation for New Job ---
    const liveMaterialCost = consumedMaterials.reduce((sum, item) => {
        const mat = rawMaterials.find(m => m.id === item.materialId);
        return sum + (Number(item.quantity) * (mat?.costPerUnit || 0));
    }, 0);
    const liveTotalWIPValue = liveMaterialCost + (Number(newJob.laborCost) || 0);

    // --- Job Board Logic ---
    const stages: JobCard['status'][] = ['Measurements', 'Cutting', 'Stitching', 'Finishing', 'QC', 'Ready'];
    
    const handleStatusChange = (id: string, newStatus: JobCard['status']) => {
        setJobCards(prev => prev.map(job => job.id === id ? { ...job, status: newStatus } : job));
    };

    const addMaterialRow = () => {
        setConsumedMaterials([...consumedMaterials, { materialId: '', quantity: 1 }]);
    };

    const updateMaterialRow = (index: number, field: 'materialId' | 'quantity', value: string | number) => {
        const updated = [...consumedMaterials];
        updated[index] = { ...updated[index], [field]: value };
        setConsumedMaterials(updated);
    };

    const removeMaterialRow = (index: number) => {
        setConsumedMaterials(consumedMaterials.filter((_, i) => i !== index));
    };

    const handleStaffChange = (staffId: string) => {
        const selectedStaff = staff.find(s => s.id === staffId);
        let estCost = newJob.laborCost || 0;
        
        // Auto-fill labor cost if staff is on Piece Rate
        if (selectedStaff && selectedStaff.salaryType === 'PieceRate') {
            estCost = selectedStaff.salaryOrRate;
        }
        
        setNewJob({ ...newJob, assignedStaffId: staffId, laborCost: estCost });
    };

    const handleAddJob = (e: React.FormEvent) => {
        e.preventDefault();

        // 1. Deduct Raw Materials from Stock (Transition RM -> WIP)
        const updatedMaterials = [...rawMaterials];
        consumedMaterials.forEach(consumed => {
            const matIndex = updatedMaterials.findIndex(m => m.id === consumed.materialId);
            if (matIndex !== -1) {
                updatedMaterials[matIndex] = {
                    ...updatedMaterials[matIndex],
                    quantity: Math.max(0, updatedMaterials[matIndex].quantity - Number(consumed.quantity))
                };
            }
        });
        setRawMaterials(updatedMaterials);

        // 2. Create Job Card
        const job: JobCard = {
            id: `JC-${Date.now()}`,
            customerName: newJob.customerName || 'Walk-in',
            garmentType: newJob.garmentType || 'Custom',
            assignedStaffId: newJob.assignedStaffId || '',
            status: 'Measurements',
            dueDate: newJob.dueDate || new Date().toISOString().split('T')[0],
            fabricConsumed: consumedMaterials,
            laborCost: Number(newJob.laborCost) || 0,
            designNotes: newJob.designNotes || ''
        };
        setJobCards(prev => [...prev, job]);
        
        // Reset
        setIsAddingJob(false);
        setNewJob({ status: 'Measurements', fabricConsumed: [] });
        setConsumedMaterials([]);
    };

    // --- Conversion Logic (Transition WIP -> FG) ---
    const openConversionModal = (job: JobCard) => {
        setJobToConvert(job);
        
        // Calculate Cost: Sum of (Material Qty * Unit Cost) + Labor Cost
        const materialCost = job.fabricConsumed.reduce((sum, item) => {
            const mat = rawMaterials.find(m => m.id === item.materialId);
            return sum + (item.quantity * (mat?.costPerUnit || 0));
        }, 0);
        const totalCost = materialCost + job.laborCost;
        setCalculatedCost(totalCost);

        setConversionData({
            price: totalCost * 1.5, // Default 50% markup suggestion
            sku: `FG-${job.id.split('-')[1]}`,
            name: `${job.garmentType} for ${job.customerName}`
        });
        setIsConverting(true);
    };

    const handleConvert = (e: React.FormEvent) => {
        e.preventDefault();
        if (jobToConvert && setProducts) {
            const newProduct: Product = {
                id: `P-${Date.now()}`,
                sku: conversionData.sku,
                name: conversionData.name,
                category: jobToConvert.garmentType, // Simple mapping
                branchId: 'Mumbai', // Defaulting to main branch
                variants: { size: 'Custom', color: 'Multi', style: 'Bespoke' },
                stockLevel: 1,
                reorderThreshold: 0,
                costPrice: calculatedCost,
                price: Number(conversionData.price),
                supplier: 'In-House Production'
            };

            setProducts(prev => [...prev, newProduct]);
            
            // Archive/Remove the Job Card as it is now a Finished Good
            setJobCards(prev => prev.filter(j => j.id !== jobToConvert.id));

            setIsConverting(false);
            setJobToConvert(null);
        }
    };

    // --- Renders ---

    const renderJobBoard = () => (
        <div className="flex gap-4 overflow-x-auto pb-4 h-[calc(100vh-240px)]">
            {stages.map(stage => (
                <div key={stage} className="min-w-[280px] bg-gray-800 rounded-xl flex flex-col border border-gray-700">
                    <div className={`p-3 font-bold text-sm uppercase tracking-wide border-b border-gray-700 flex justify-between items-center
                        ${stage === 'Ready' ? 'text-green-400' : 'text-gray-300'}`}>
                        {stage}
                        <span className="bg-gray-700 text-xs px-2 py-0.5 rounded-full text-white">
                            {jobCards.filter(j => j.status === stage).length}
                        </span>
                    </div>
                    <div className="p-3 space-y-3 overflow-y-auto flex-1 custom-scrollbar bg-gray-800/50">
                        {jobCards.filter(j => j.status === stage).map(job => (
                            <div key={job.id} className="bg-gray-700 p-3 rounded-lg shadow border border-gray-600 hover:border-indigo-500 transition-colors group">
                                <div className="flex justify-between items-start mb-1">
                                    <span className="font-mono text-[10px] text-indigo-300">{job.id}</span>
                                    <span className="text-[10px] text-gray-400">{job.dueDate}</span>
                                </div>
                                <div className="font-bold text-white text-sm">{job.customerName}</div>
                                <div className="text-xs text-gray-300 mb-2">{job.garmentType}</div>
                                
                                <div className="flex items-center gap-2 text-xs text-gray-400 bg-gray-800 p-1.5 rounded mb-2">
                                    <ScissorsIcon /> {getStaffName(job.assignedStaffId)}
                                </div>

                                <div className="flex justify-between items-center mt-2 pt-2 border-t border-gray-600">
                                    {/* Status Mover Buttons */}
                                    <div className="flex gap-1">
                                        {stage !== 'Measurements' && (
                                            <button onClick={() => handleStatusChange(job.id, stages[stages.indexOf(stage) - 1])} className="text-xs text-gray-400 hover:text-white px-1">←</button>
                                        )}
                                        {stage !== 'Ready' && (
                                            <button onClick={() => handleStatusChange(job.id, stages[stages.indexOf(stage) + 1])} className="text-xs text-green-400 hover:text-green-300 px-1">→</button>
                                        )}
                                    </div>
                                    {stage === 'Ready' && (
                                        <button onClick={() => openConversionModal(job)} className="text-[10px] bg-green-600 hover:bg-green-700 text-white px-2 py-1 rounded flex items-center gap-1" title="Convert to Retail Stock">
                                            <ArrowRightCircleIcon /> Stock
                                        </button>
                                    )}
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            ))}
        </div>
    );

    const renderMaterials = () => (
        <div className="bg-gray-800 rounded-xl border border-gray-700 overflow-hidden">
             <div className="p-4 flex justify-between items-center border-b border-gray-700">
                <h3 className="font-bold text-white">Raw Material Inventory</h3>
                {/* Add Material is handled in Inventory Component for full functionality, usually linked */}
                <div className="text-xs text-gray-400">Manage stock in Inventory Module</div>
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
                    </tr>
                </thead>
                <tbody className="divide-y divide-gray-700">
                    {rawMaterials.map(mat => (
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
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    );

    const renderStaff = () => (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {staff.map(s => (
                <div key={s.id} className="bg-gray-800 p-6 rounded-xl border border-gray-700 flex items-start gap-4">
                    <div className="w-12 h-12 rounded-full bg-indigo-900/50 flex items-center justify-center text-indigo-400">
                        <UsersIcon />
                    </div>
                    <div className="flex-1">
                        <h3 className="font-bold text-white">{s.name}</h3>
                        <p className="text-sm text-indigo-400 font-medium mb-2">{s.role}</p>
                        <div className="space-y-1 text-sm text-gray-400">
                            <p>Phone: {s.phone}</p>
                            <p>Pay Type: <span className="text-white">{s.salaryType}</span></p>
                            <p>Rate/Salary: <span className="text-green-400 font-mono font-bold">₹{s.salaryOrRate}</span></p>
                        </div>
                        <div className="mt-4 flex gap-2">
                            <button className="flex-1 bg-gray-700 hover:bg-gray-600 py-1.5 rounded text-xs text-white">View Jobs</button>
                            <button className="flex-1 bg-green-600/20 text-green-400 hover:bg-green-600/30 py-1.5 rounded text-xs">Pay Now</button>
                        </div>
                    </div>
                </div>
            ))}
        </div>
    );

    return (
        <div className="p-8 h-full flex flex-col animate-fade-in">
            <div className="flex justify-between items-center mb-6">
                <div>
                    <h1 className="text-3xl font-bold text-white flex items-center gap-3">
                        <FactoryIcon /> Production Floor
                    </h1>
                    <p className="text-sm text-gray-400 mt-1">Manage custom orders, stitching workflow, and karigars.</p>
                </div>
                <div className="flex gap-3">
                     <button 
                        onClick={() => { setIsAddingJob(true); }}
                        className="bg-indigo-600 text-white font-bold py-2 px-4 rounded-lg hover:bg-indigo-700 transition-colors shadow-lg flex items-center gap-2"
                    >
                        + New Job Card
                    </button>
                </div>
            </div>

            {/* Tabs */}
            <div className="flex space-x-1 bg-gray-800 p-1 rounded-lg mb-6 w-fit">
                <button onClick={() => setActiveTab('jobs')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'jobs' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>
                    <ClipboardListIcon /> Job Board
                </button>
                <button onClick={() => setActiveTab('materials')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'materials' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>
                    <RulerIcon /> Raw Materials
                </button>
                <button onClick={() => setActiveTab('staff')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all flex items-center gap-2 ${activeTab === 'staff' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white'}`}>
                    <UsersIcon /> Karigars & Staff
                </button>
            </div>

            <div className="flex-1 overflow-hidden">
                {activeTab === 'jobs' && renderJobBoard()}
                {activeTab === 'materials' && renderMaterials()}
                {activeTab === 'staff' && renderStaff()}
            </div>

            {/* Add Job Modal */}
            <Modal isOpen={isAddingJob} onClose={() => setIsAddingJob(false)} title="Create Job Card">
                <form onSubmit={handleAddJob} className="space-y-4">
                    <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Customer Name</label>
                        <input className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={newJob.customerName} onChange={e => setNewJob({...newJob, customerName: e.target.value})} required />
                    </div>
                    <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Garment Type</label>
                        <input className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={newJob.garmentType} onChange={e => setNewJob({...newJob, garmentType: e.target.value})} placeholder="e.g. Blouse, Lehenga" required />
                    </div>
                     <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Assign Masterji/Karigar</label>
                        <select className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" 
                            value={newJob.assignedStaffId} 
                            onChange={e => handleStaffChange(e.target.value)}>
                            <option value="">-- Select --</option>
                            {staff.map(s => <option key={s.id} value={s.id}>{s.name} ({s.role}) - {s.salaryType}</option>)}
                        </select>
                    </div>
                    
                    {/* Material Consumption Section */}
                    <div className="bg-gray-800 p-4 rounded-lg border border-gray-700">
                        <div className="flex justify-between items-center mb-2">
                             <label className="text-gray-400 text-sm uppercase font-bold">Raw Materials Used</label>
                             <button type="button" onClick={addMaterialRow} className="text-xs text-indigo-400 hover:text-white">+ Add Material</button>
                        </div>
                        {consumedMaterials.map((row, idx) => (
                            <div key={idx} className="flex gap-2 mb-2">
                                <select 
                                    className="flex-1 bg-gray-900 text-white rounded p-2 border border-gray-600 text-sm"
                                    value={row.materialId}
                                    onChange={e => updateMaterialRow(idx, 'materialId', e.target.value)}
                                    required
                                >
                                    <option value="">Select Material</option>
                                    {rawMaterials.map(m => <option key={m.id} value={m.id}>{m.name} (avail: {m.quantity} {m.unit})</option>)}
                                </select>
                                <input 
                                    type="number" 
                                    className="w-20 bg-gray-900 text-white rounded p-2 border border-gray-600 text-sm"
                                    placeholder="Qty"
                                    value={row.quantity}
                                    onChange={e => updateMaterialRow(idx, 'quantity', e.target.value)}
                                    required
                                />
                                <button type="button" onClick={() => removeMaterialRow(idx)} className="text-red-400 hover:text-red-300"><TrashIcon /></button>
                            </div>
                        ))}
                        {consumedMaterials.length === 0 && <p className="text-xs text-gray-500 italic">No materials allocated yet.</p>}
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                        <div>
                             <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Due Date</label>
                             <input type="date" className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={newJob.dueDate} onChange={e => setNewJob({...newJob, dueDate: e.target.value})} />
                        </div>
                        <div>
                             <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Labor Cost (Est.)</label>
                             <input type="number" className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={newJob.laborCost} onChange={e => setNewJob({...newJob, laborCost: Number(e.target.value)})} />
                             <p className="text-[10px] text-gray-500 mt-1">Auto-filled for Piece-Rate staff</p>
                        </div>
                    </div>
                     <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Design Notes</label>
                        <textarea className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" rows={3} value={newJob.designNotes} onChange={e => setNewJob({...newJob, designNotes: e.target.value})} placeholder="Specific instructions for the tailor..." />
                    </div>
                    
                    {/* Live Cost Summary - Visualizing the Move to WIP */}
                    <div className="bg-gray-900 p-3 rounded border border-gray-700">
                        <h4 className="text-xs font-bold text-gray-400 uppercase mb-2">WIP Value Estimation (Moving from Stock)</h4>
                        <div className="flex justify-between text-sm text-gray-300">
                            <span>Material Cost:</span>
                            <span>₹{liveMaterialCost.toLocaleString('en-IN')}</span>
                        </div>
                        <div className="flex justify-between text-sm text-gray-300">
                            <span>Labor Cost:</span>
                            <span>₹{Number(newJob.laborCost || 0).toLocaleString('en-IN')}</span>
                        </div>
                        <div className="flex justify-between text-sm font-bold text-white border-t border-gray-700 pt-1 mt-1">
                            <span>Total WIP Value:</span>
                            <span>₹{liveTotalWIPValue.toLocaleString('en-IN')}</span>
                        </div>
                    </div>

                    <button className="w-full bg-indigo-600 py-3 rounded-lg text-white font-bold hover:bg-indigo-700">Generate Job Card</button>
                </form>
            </Modal>

            {/* Convert to Product Modal */}
            <Modal isOpen={isConverting} onClose={() => setIsConverting(false)} title="Convert Job to Retail Stock">
                <form onSubmit={handleConvert} className="space-y-4">
                    <div className="bg-gray-800 p-4 rounded-lg border border-gray-700 mb-4">
                         <h4 className="text-sm font-bold text-white mb-2">Costing Analysis</h4>
                         <div className="flex justify-between text-sm text-gray-400">
                             <span>Labor Cost:</span>
                             <span>₹{jobToConvert?.laborCost}</span>
                         </div>
                          <div className="flex justify-between text-sm text-gray-400">
                             <span>Material Cost:</span>
                             <span>₹{calculatedCost - (jobToConvert?.laborCost || 0)}</span>
                         </div>
                         <div className="flex justify-between text-lg text-white font-bold mt-2 pt-2 border-t border-gray-600">
                             <span>Total Cost Price:</span>
                             <span>₹{calculatedCost}</span>
                         </div>
                    </div>

                    <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Retail Name</label>
                        <input className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={conversionData.name} onChange={e => setConversionData({...conversionData, name: e.target.value})} required />
                    </div>
                    <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">SKU / Item Code</label>
                        <input className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={conversionData.sku} onChange={e => setConversionData({...conversionData, sku: e.target.value})} required />
                    </div>
                    <div>
                        <label className="block text-gray-400 mb-1 text-sm uppercase font-bold">Selling Price (₹)</label>
                        <input type="number" className="w-full bg-gray-800 text-white rounded p-2 border border-gray-700" value={conversionData.price} onChange={e => setConversionData({...conversionData, price: Number(e.target.value)})} required />
                        <p className="text-xs text-green-400 mt-1">Margin: {Math.round(((conversionData.price - calculatedCost) / conversionData.price) * 100)}%</p>
                    </div>
                    <button className="w-full bg-green-600 py-3 rounded-lg text-white font-bold hover:bg-green-700 mt-4">
                        Confirm & Add to Inventory
                    </button>
                </form>
            </Modal>
        </div>
    );
};

export default Production;
