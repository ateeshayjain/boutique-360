
import React, { useState, useRef, useEffect } from 'react';
import { generateVirtualTryOnImage, generateDesignFromSketch, generateMakeoverImage, suggestAccessories, enhanceFashionPrompt } from '../services/geminiService';
import { LoaderIcon, BrushIcon, EraserIcon, WandIcon, RefreshIcon, ImagePlusIcon, UploadCloudIcon, TypeIcon, ScissorsIcon, SparklesIcon, SaveIcon, CheckCircleIcon, LayersIcon, WatchIcon, GlassesIcon, HatIcon, ShoppingBagIcon, HighlighterIcon, TagIcon } from './icons';
import { Customer, JobCard } from '../types';
import Modal from './Modal';

interface VirtualTryOnProps {
    customers?: Customer[];
    setJobCards?: React.Dispatch<React.SetStateAction<JobCard[]>>;
}

const FABRICS = [
    { name: 'Banarasi Silk', color: '#B91C1C' }, // Red
    { name: 'Velvet', color: '#4338CA' }, // Indigo
    { name: 'Chiffon', color: '#F472B6' }, // Pink
    { name: 'Georgette', color: '#34D399' }, // Green
    { name: 'Raw Silk', color: '#D97706' }, // Amber
    { name: 'Organza', color: '#FBCFE8' }, // Pale Pink
];

const EMBELLISHMENTS = [
    'Zari Border', 'Mirror Work', 'Gota Patti', 'Zardosi', 'Sequins', 'Phulkari'
];

interface Annotation {
    id: string;
    x: number;
    y: number;
    text: string;
}

const VirtualTryOn: React.FC<VirtualTryOnProps> = ({ customers = [], setJobCards }) => {
    const [mode, setMode] = useState<'sketch' | 'upload' | 'describe'>('sketch');
    
    // --- Global State ---
    const [customerImage, setCustomerImage] = useState<string | null>(null);
    const [isProcessing, setIsProcessing] = useState(false);
    const [processingStage, setProcessingStage] = useState<string>('');
    const [resultImage, setResultImage] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [showOriginal, setShowOriginal] = useState(false);

    // --- Sketch Mode State ---
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [isDrawing, setIsDrawing] = useState(false);
    const [tool, setTool] = useState<'brush' | 'eraser' | 'annotate'>('brush');
    const [brushSize, setBrushSize] = useState(5);
    const [brushColor, setBrushColor] = useState('#ffffff');
    const [sketchPrompt, setSketchPrompt] = useState('');
    const [generatedGarment, setGeneratedGarment] = useState<string | null>(null);
    const [isGeneratingGarment, setIsGeneratingGarment] = useState(false);

    // --- Annotation State ---
    const [annotations, setAnnotations] = useState<Annotation[]>([]);
    const [currentAnnotationPos, setCurrentAnnotationPos] = useState<{x: number, y: number} | null>(null);
    const [showAnnotationModal, setShowAnnotationModal] = useState(false);

    // --- Swatch State ---
    const [selectedFabrics, setSelectedFabrics] = useState<string[]>([]);
    const [selectedEmbellishments, setSelectedEmbellishments] = useState<string[]>([]);

    // --- Upload Mode State ---
    const [uploadedGarment, setUploadedGarment] = useState<string | null>(null);

    // --- Describe Mode State ---
    const [describePrompt, setDescribePrompt] = useState('');

    // --- Save to Job State ---
    const [isSavingJob, setIsSavingJob] = useState(false);
    const [jobCustomer, setJobCustomer] = useState('');
    const [jobGarmentType, setJobGarmentType] = useState('');

    // --- Styling Studio State ---
    const [stylingMode, setStylingMode] = useState<'magic' | 'stylist' | 'stickers' | null>(null);
    const [magicPrompt, setMagicPrompt] = useState('');
    const [suggestedAccessories, setSuggestedAccessories] = useState<string[]>([]);
    const [isSuggesting, setIsSuggesting] = useState(false);
    const [stickers, setStickers] = useState<{id: string, type: string, x: number, y: number}[]>([]);

    // Initialize Canvas
    useEffect(() => {
        if (mode === 'sketch') {
            const canvas = canvasRef.current;
            if (canvas) {
                const ctx = canvas.getContext('2d');
                if (ctx) {
                    ctx.fillStyle = '#1F2937'; // bg-gray-800
                    ctx.fillRect(0, 0, canvas.width, canvas.height);
                    ctx.lineCap = 'round';
                    ctx.lineJoin = 'round';
                }
            }
        }
    }, [mode]);

    // --- Handlers ---

    const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>, setter: (val: string) => void) => {
        if (e.target.files && e.target.files[0]) {
            const file = e.target.files[0];
            // SECURITY: Enforce max file size (5MB)
            if (file.size > 5 * 1024 * 1024) {
                setError("File too large. Maximum size is 5MB.");
                return;
            }
            const reader = new FileReader();
            reader.onload = (ev) => setter(ev.target?.result as string);
            reader.readAsDataURL(file);
        }
    };

    const handleCustomerUpload = (e: React.ChangeEvent<HTMLInputElement>) => handleImageUpload(e, setCustomerImage);
    const handleGarmentUpload = (e: React.ChangeEvent<HTMLInputElement>) => handleImageUpload(e, setUploadedGarment);

    const toggleFabric = (name: string) => {
        setSelectedFabrics(prev => prev.includes(name) ? prev.filter(f => f !== name) : [...prev, name]);
    };

    const toggleEmbellishment = (name: string) => {
        setSelectedEmbellishments(prev => prev.includes(name) ? prev.filter(e => e !== name) : [...prev, name]);
    };

    // --- Canvas Logic ---
    const startDrawing = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
        setIsDrawing(true);
        
        if (tool === 'annotate') {
             const canvas = canvasRef.current;
             if(!canvas) return;
             const rect = canvas.getBoundingClientRect();
             let x, y;
             if ('touches' in e) {
                 x = e.touches[0].clientX - rect.left;
                 y = e.touches[0].clientY - rect.top;
             } else {
                 x = (e as React.MouseEvent).nativeEvent.offsetX;
                 y = (e as React.MouseEvent).nativeEvent.offsetY;
             }
             // Record start pos to calc center later (simplified: just use mouse up pos for popup)
        }
        draw(e);
    };
    const stopDrawing = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
        setIsDrawing(false);
        const canvas = canvasRef.current;
        if(canvas) {
            canvas.getContext('2d')?.beginPath();
            
            // If annotation tool, trigger popup
            if (tool === 'annotate') {
                 const rect = canvas.getBoundingClientRect();
                 let x, y;
                 // Touch end doesn't have coords usually, simplistic approach for mouse/touch fallback
                 if ('changedTouches' in e) {
                     x = e.changedTouches[0].clientX - rect.left;
                     y = e.changedTouches[0].clientY - rect.top;
                 } else {
                     x = (e as React.MouseEvent).nativeEvent.offsetX;
                     y = (e as React.MouseEvent).nativeEvent.offsetY;
                 }
                 
                 setCurrentAnnotationPos({ x, y });
                 setShowAnnotationModal(true);
            }
        }
    };
    const draw = (e: React.MouseEvent<HTMLCanvasElement> | React.TouchEvent<HTMLCanvasElement>) => {
        if (!isDrawing) return;
        const canvas = canvasRef.current;
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        const rect = canvas.getBoundingClientRect();
        let x, y;
        if ('touches' in e) {
            x = e.touches[0].clientX - rect.left;
            y = e.touches[0].clientY - rect.top;
        } else {
            x = (e as React.MouseEvent).nativeEvent.offsetX;
            y = (e as React.MouseEvent).nativeEvent.offsetY;
        }
        
        ctx.lineWidth = tool === 'annotate' ? 2 : brushSize;
        ctx.strokeStyle = tool === 'eraser' ? '#1F2937' : (tool === 'annotate' ? '#F59E0B' : brushColor);
        
        if (tool === 'annotate') {
             // Dashed line for annotation
             ctx.setLineDash([5, 5]);
        } else {
             ctx.setLineDash([]);
        }

        ctx.lineTo(x, y);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(x, y);
    };
    const clearCanvas = () => {
        const canvas = canvasRef.current;
        if(canvas) {
            const ctx = canvas.getContext('2d');
            if(ctx) {
                ctx.fillStyle = '#1F2937';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
            }
            setAnnotations([]);
        }
    };

    const addAnnotation = (text: string) => {
        if (currentAnnotationPos) {
            setAnnotations(prev => [...prev, {
                id: Date.now().toString(),
                x: currentAnnotationPos.x,
                y: currentAnnotationPos.y,
                text
            }]);
            setShowAnnotationModal(false);
            setTool('brush'); // Reset to brush
            
            // Clear the dashed line from canvas (rudimentary redraw or just leave it as visual marker)
            // In a complex app we'd use layers. Here we accept the line stays as the "circle".
        }
    };

    // --- Generation Logic ---

    const generateGarmentFromSketch = async () => {
        const canvas = canvasRef.current;
        if(!canvas) return;
        
        setIsGeneratingGarment(true);
        setProcessingStage('Analyzing texture physics...');
        setError(null);

        try {
            // Construct Prompt with Annotations
            let fullPrompt = sketchPrompt || "A designer garment";
            if (annotations.length > 0) {
                fullPrompt += ". Specific Details: ";
                annotations.forEach((ann, i) => {
                    fullPrompt += `The area labeled '${ann.text}' should be rendered with that material. `;
                });
            }

            // 1. Enhance Prompt via Gemini Text Model
            const enhancedPrompt = await enhanceFashionPrompt(
                fullPrompt, 
                selectedFabrics, 
                selectedEmbellishments
            );
            
            setProcessingStage('Rendering photorealistic textures...');
            
            // 2. Generate Image with Enhanced Prompt
            const sketchBase64 = canvas.toDataURL('image/png').split(',')[1];
            const result = await generateDesignFromSketch(sketchBase64, enhancedPrompt);
            setGeneratedGarment(`data:image/png;base64,${result}`);

        } catch (err) { 
            setError((err as Error).message); 
        } finally { 
            setIsGeneratingGarment(false); 
            setProcessingStage('');
        }
    };

    const handleTryOn = async () => {
        if (!customerImage) { setError("Please upload a customer photo first."); return; }
        setError(null);
        setIsProcessing(true);
        setProcessingStage('Simulating fit...');
        setStylingMode(null); // Reset styling studio
        setStickers([]);
        try {
            const customerBase64 = customerImage.split(',')[1];
            let resultBase64 = '';

            if (mode === 'describe') {
                if (!describePrompt) throw new Error("Please enter a description.");
                resultBase64 = await generateMakeoverImage(customerBase64, describePrompt);
            } else {
                // Sketch or Upload modes use Virtual Try-On (Superimpose)
                let garmentBase64 = '';
                if (mode === 'sketch') {
                    if (!generatedGarment) throw new Error("Please generate a garment from your sketch first.");
                    garmentBase64 = generatedGarment.split(',')[1];
                } else if (mode === 'upload') {
                    if (!uploadedGarment) throw new Error("Please upload a garment image.");
                    garmentBase64 = uploadedGarment.split(',')[1];
                }
                resultBase64 = await generateVirtualTryOnImage(customerBase64, garmentBase64);
            }
            setResultImage(`data:image/png;base64,${resultBase64}`);
        } catch (err) {
            setError((err as Error).message);
        } finally {
            setIsProcessing(false);
            setProcessingStage('');
        }
    };

    const handleMagicEdit = async () => {
        if (!resultImage || !magicPrompt) return;
        setIsProcessing(true);
        setProcessingStage('Applying changes...');
        setError(null);
        try {
             // We use the CURRENT result image as the base for modification
            const base64 = resultImage.split(',')[1];
            const newResultBase64 = await generateMakeoverImage(base64, magicPrompt);
            setResultImage(`data:image/png;base64,${newResultBase64}`);
            setMagicPrompt('');
        } catch (err) {
            setError("Magic Edit Failed: " + (err as Error).message);
        } finally {
            setIsProcessing(false);
            setProcessingStage('');
        }
    };

    const handleGetSuggestions = async () => {
        if(!resultImage) return;
        setIsSuggesting(true);
        try {
            const base64 = resultImage.split(',')[1];
            const items = await suggestAccessories(base64);
            setSuggestedAccessories(items);
        } catch(err) { console.error(err); }
        finally { setIsSuggesting(false); }
    };

    const addSticker = (type: string) => {
        setStickers(prev => [...prev, { id: Date.now().toString(), type, x: 50, y: 50 }]);
    };

    const handleCreateJobCard = (e: React.FormEvent) => {
        e.preventDefault();
        if(setJobCards) {
             // 1. Construct Fabric Notes
            let notes = "AI Designed: ";
            if (selectedFabrics.length > 0) notes += `Fabric: ${selectedFabrics.join(', ')}. `;
            if (selectedEmbellishments.length > 0) notes += `Work: ${selectedEmbellishments.join(', ')}. `;
            notes += sketchPrompt || describePrompt;
            if(annotations.length > 0) notes += ` | Annotations: ${annotations.map(a => a.text).join(', ')}`;
            if(suggestedAccessories.length > 0) notes += `\nRecommended Accessories: ${suggestedAccessories.join(', ')}`;

            // 2. Determine Customer Name
            const custName = customers.find(c => c.id === jobCustomer)?.name || 'Walk-in Customer';

            const job: JobCard = {
                id: `JC-${Date.now()}`,
                customerName: custName,
                garmentType: jobGarmentType || 'Custom Designer Wear',
                assignedStaffId: '',
                status: 'Measurements',
                dueDate: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
                fabricConsumed: [], // To be allocated by factory
                laborCost: 0,
                designNotes: notes
            };

            setJobCards(prev => [...prev, job]);
            setIsSavingJob(false);
            alert("Job Card Created Successfully! Sent to Production.");
        }
    };

    return (
        <div className="h-full flex flex-col bg-gray-900 overflow-hidden">
            {/* Header */}
            <div className="p-4 bg-gray-800 shadow-md flex justify-between items-center z-10">
                <div>
                    <h1 className="text-2xl font-bold text-white flex items-center gap-2">
                        <SparklesIcon /> AI Design Studio & Try-On
                    </h1>
                    <p className="text-xs text-gray-400">Professional Sketching, Material Selection & Virtual Visualization.</p>
                </div>
            </div>

            {/* Main Workspace (3-Column Layout) */}
            <div className="flex-1 flex flex-col lg:flex-row overflow-hidden">
                
                {/* Col 1: Customer Context */}
                <div className="w-full lg:w-1/4 bg-gray-850 border-r border-gray-800 p-6 flex flex-col">
                    <h3 className="text-sm font-bold text-gray-400 uppercase mb-4">1. The Customer</h3>
                    <div className="flex-1 flex flex-col">
                         <div className="border-2 border-dashed border-gray-700 rounded-xl flex-1 flex flex-col items-center justify-center relative hover:border-indigo-500 transition-colors bg-gray-800 overflow-hidden group shadow-inner">
                            <input type="file" accept="image/*" onChange={handleCustomerUpload} className="absolute inset-0 opacity-0 cursor-pointer z-20" />
                            {customerImage ? (
                                <>
                                    <img src={customerImage} alt="Customer" className="absolute inset-0 w-full h-full object-cover" />
                                    <div className="absolute bottom-0 left-0 right-0 bg-black/60 p-2 text-center text-white text-xs opacity-0 group-hover:opacity-100 transition-opacity z-10">
                                        Click to Change Photo
                                    </div>
                                </>
                            ) : (
                                <div className="text-center p-4">
                                    <div className="w-16 h-16 bg-gray-700 rounded-full flex items-center justify-center mx-auto mb-4 text-gray-400">
                                        <ImagePlusIcon />
                                    </div>
                                    <p className="text-gray-300 font-medium">Upload Photo</p>
                                    <p className="text-xs text-gray-500 mt-2">Front facing, good lighting. Max 5MB.</p>
                                </div>
                            )}
                         </div>
                    </div>
                </div>

                {/* Col 2: The Method (Input) */}
                <div className="w-full lg:w-1/2 bg-gray-900 flex flex-col border-r border-gray-800">
                    {/* Mode Tabs */}
                    <div className="flex border-b border-gray-800 bg-gray-850 shadow-sm">
                        <button onClick={() => setMode('sketch')} className={`flex-1 py-4 text-sm font-bold flex items-center justify-center gap-2 border-b-2 transition-colors ${mode === 'sketch' ? 'border-indigo-500 text-white bg-gray-800' : 'border-transparent text-gray-500 hover:text-gray-300'}`}>
                            <ScissorsIcon /> Design Studio
                        </button>
                        <button onClick={() => setMode('upload')} className={`flex-1 py-4 text-sm font-bold flex items-center justify-center gap-2 border-b-2 transition-colors ${mode === 'upload' ? 'border-indigo-500 text-white bg-gray-800' : 'border-transparent text-gray-500 hover:text-gray-300'}`}>
                            <UploadCloudIcon /> Upload Reference
                        </button>
                        <button onClick={() => setMode('describe')} className={`flex-1 py-4 text-sm font-bold flex items-center justify-center gap-2 border-b-2 transition-colors ${mode === 'describe' ? 'border-indigo-500 text-white bg-gray-800' : 'border-transparent text-gray-500 hover:text-gray-300'}`}>
                            <TypeIcon /> Text-to-Fashion
                        </button>
                    </div>

                    <div className="flex-1 p-6 overflow-y-auto bg-gray-900 relative custom-scrollbar">
                        {error && (
                            <div className="absolute top-2 left-4 right-4 bg-red-500/90 text-white p-3 rounded-lg z-50 text-sm shadow-lg flex justify-between animate-fade-in">
                                <span>{error}</span>
                                <button onClick={() => setError(null)}>×</button>
                            </div>
                        )}

                        {/* SKETCH MODE */}
                        {mode === 'sketch' && (
                            <div className="h-full flex flex-col gap-4">
                                {/* Toolbar */}
                                <div className="flex items-center justify-between bg-gray-800 p-2 rounded-lg border border-gray-700">
                                    <div className="flex gap-2">
                                        <button onClick={() => setTool('brush')} className={`p-2 rounded ${tool === 'brush' ? 'bg-indigo-600 text-white' : 'text-gray-400 hover:text-white'}`} title="Brush"><BrushIcon /></button>
                                        <button onClick={() => setTool('eraser')} className={`p-2 rounded ${tool === 'eraser' ? 'bg-indigo-600 text-white' : 'text-gray-400 hover:text-white'}`} title="Eraser"><EraserIcon /></button>
                                        <button onClick={() => setTool('annotate')} className={`p-2 rounded ${tool === 'annotate' ? 'bg-yellow-600 text-white' : 'text-gray-400 hover:text-white'}`} title="Annotate Area"><HighlighterIcon /></button>
                                        <button onClick={clearCanvas} className="p-2 rounded text-gray-400 hover:text-red-400" title="Clear Canvas"><RefreshIcon /></button>
                                    </div>
                                    <div className="flex items-center gap-2">
                                        <input type="color" value={brushColor} onChange={(e) => { setBrushColor(e.target.value); setTool('brush'); }} className="w-6 h-6 rounded cursor-pointer bg-transparent border-none" />
                                        <input type="range" min="1" max="20" value={brushSize} onChange={(e) => setBrushSize(Number(e.target.value))} className="w-24 accent-indigo-500" />
                                    </div>
                                </div>
                                
                                {/* Canvas Area */}
                                <div className="flex-1 bg-gray-800 rounded-lg relative overflow-hidden border border-gray-700 shadow-inner cursor-crosshair">
                                    <canvas 
                                        ref={canvasRef} width={500} height={500} 
                                        className="absolute inset-0 w-full h-full touch-none"
                                        onMouseDown={startDrawing} onMouseUp={stopDrawing} onMouseMove={draw}
                                        onTouchStart={startDrawing} onTouchEnd={stopDrawing} onTouchMove={draw}
                                    />
                                    {isGeneratingGarment && (
                                        <div className="absolute inset-0 bg-black/70 flex flex-col items-center justify-center z-20">
                                            <LoaderIcon />
                                            <p className="text-white font-bold mt-4 animate-pulse text-sm">{processingStage}</p>
                                        </div>
                                    )}
                                    
                                    {/* Render Annotations Overlays */}
                                    {annotations.map(ann => (
                                        <div key={ann.id} className="absolute bg-yellow-900/80 text-yellow-100 text-[10px] px-2 py-1 rounded border border-yellow-600 shadow-lg backdrop-blur-sm transform -translate-x-1/2 -translate-y-full pointer-events-none"
                                            style={{ left: ann.x, top: ann.y }}
                                        >
                                            <TagIcon /> {ann.text}
                                        </div>
                                    ))}

                                    {/* Annotation Selection Modal */}
                                    {showAnnotationModal && currentAnnotationPos && (
                                        <div className="absolute z-30 bg-gray-900 border border-gray-600 p-2 rounded shadow-xl w-48"
                                            style={{ left: Math.min(currentAnnotationPos.x, 300), top: Math.min(currentAnnotationPos.y, 300) }}>
                                            <p className="text-xs text-gray-400 mb-2 font-bold uppercase">Select Material for this area</p>
                                            <div className="grid grid-cols-2 gap-1 max-h-40 overflow-y-auto custom-scrollbar">
                                                {FABRICS.map(f => (
                                                    <button key={f.name} onClick={() => addAnnotation(f.name)} className="text-xs bg-gray-800 hover:bg-gray-700 text-white p-1 rounded text-left truncate">
                                                        {f.name}
                                                    </button>
                                                ))}
                                                {EMBELLISHMENTS.map(e => (
                                                     <button key={e} onClick={() => addAnnotation(e)} className="text-xs bg-gray-800 hover:bg-gray-700 text-white p-1 rounded text-left truncate">
                                                        {e}
                                                    </button>
                                                ))}
                                            </div>
                                            <button onClick={() => setShowAnnotationModal(false)} className="w-full text-xs text-red-400 mt-2 hover:text-red-300">Cancel</button>
                                        </div>
                                    )}
                                </div>

                                {/* Material & Prompt Selector */}
                                <div className="bg-gray-800 p-4 rounded-lg border border-gray-700 space-y-4">
                                    <div>
                                        <h4 className="text-xs font-bold text-gray-400 uppercase mb-2">Select Fabric (Global)</h4>
                                        <div className="flex gap-2 overflow-x-auto pb-2 no-scrollbar">
                                            {FABRICS.map(fab => (
                                                <button 
                                                    key={fab.name}
                                                    onClick={() => toggleFabric(fab.name)}
                                                    className={`flex-shrink-0 px-3 py-1.5 rounded-full text-xs border flex items-center gap-2 transition-all ${selectedFabrics.includes(fab.name) ? 'bg-indigo-600 text-white border-indigo-500' : 'bg-gray-700 text-gray-300 border-gray-600'}`}
                                                >
                                                    <div className="w-3 h-3 rounded-full" style={{background: fab.color}}></div>
                                                    {fab.name}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                    
                                    <textarea 
                                        value={sketchPrompt} onChange={(e) => setSketchPrompt(e.target.value)}
                                        placeholder="Additional details (e.g. Neckline style, sleeve length...)"
                                        className="w-full bg-gray-900 text-white rounded p-2 border border-gray-600 text-sm h-20 resize-none"
                                    />
                                    <button 
                                        onClick={generateGarmentFromSketch} 
                                        disabled={isGeneratingGarment}
                                        className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-3 rounded-lg transition-colors flex items-center justify-center gap-2"
                                    >
                                        {isGeneratingGarment ? <LoaderIcon /> : <><WandIcon /> Generate Design</>}
                                    </button>
                                </div>
                            </div>
                        )}

                        {/* UPLOAD MODE */}
                        {mode === 'upload' && (
                            <div className="h-full flex flex-col items-center justify-center p-6 border-2 border-dashed border-gray-700 rounded-xl bg-gray-800 relative hover:border-indigo-500 transition-colors">
                                <input type="file" accept="image/*" onChange={handleGarmentUpload} className="absolute inset-0 w-full h-full opacity-0 cursor-pointer" />
                                {uploadedGarment ? (
                                    <img src={uploadedGarment} alt="Garment" className="max-h-full object-contain rounded-lg shadow-lg" />
                                ) : (
                                    <div className="text-center text-gray-400">
                                        <UploadCloudIcon />
                                        <p className="mt-4 font-bold">Upload Garment Image</p>
                                        <p className="text-xs mt-2">PNG/JPG with clear background preferred</p>
                                    </div>
                                )}
                            </div>
                        )}

                        {/* DESCRIBE MODE */}
                        {mode === 'describe' && (
                            <div className="h-full flex flex-col gap-4">
                                <div className="bg-gray-800 p-6 rounded-xl border border-gray-700 flex-1">
                                    <h3 className="text-white font-bold mb-4 flex items-center gap-2"><TypeIcon /> Describe the Look</h3>
                                    <textarea 
                                        value={describePrompt}
                                        onChange={(e) => setDescribePrompt(e.target.value)}
                                        className="w-full h-48 bg-gray-900 text-white p-4 rounded-lg border border-gray-600 focus:border-indigo-500 focus:outline-none resize-none"
                                        placeholder="e.g. A red velvet lehenga with gold embroidery, bollywood style, heavy borders..."
                                    ></textarea>
                                    <p className="text-xs text-gray-500 mt-2">Be specific about fabric, color, and style for best results.</p>
                                </div>
                            </div>
                        )}
                    </div>
                </div>

                {/* Col 3: The Result (Output) */}
                <div className="w-full lg:w-1/4 bg-gray-850 p-6 flex flex-col border-l border-gray-800">
                    <h3 className="text-sm font-bold text-gray-400 uppercase mb-4">3. Result & Styling</h3>
                    
                    <div className="flex-1 bg-gray-800 rounded-xl border border-gray-700 overflow-hidden relative shadow-lg flex items-center justify-center">
                         {resultImage ? (
                             <div className="relative w-full h-full group">
                                 <img src={showOriginal ? (customerImage || '') : resultImage} className="w-full h-full object-cover" alt="Result" />
                                 <button 
                                    onMouseDown={() => setShowOriginal(true)} 
                                    onMouseUp={() => setShowOriginal(false)}
                                    onMouseLeave={() => setShowOriginal(false)}
                                    className="absolute bottom-4 right-4 bg-white/20 backdrop-blur text-white px-3 py-1 rounded-full text-xs font-bold border border-white/30 hover:bg-white/30"
                                 >
                                     Hold for Original
                                 </button>
                                 
                                 {/* Stickers Overlay */}
                                 {stickers.map(s => (
                                     <div key={s.id} className="absolute text-4xl pointer-events-none" style={{top: `${s.y}%`, left: `${s.x}%`}}>
                                         {s.type === 'watch' && '⌚'}
                                         {s.type === 'glasses' && '👓'}
                                         {s.type === 'hat' && '👒'}
                                         {s.type === 'bag' && '👜'}
                                     </div>
                                 ))}
                             </div>
                         ) : (
                             <div className="text-center text-gray-500 p-4">
                                 <SparklesIcon />
                                 <p className="mt-2 text-sm">Generated look will appear here.</p>
                             </div>
                         )}

                         {isProcessing && (
                             <div className="absolute inset-0 bg-black/80 flex flex-col items-center justify-center z-20">
                                 <LoaderIcon />
                                 <p className="text-white font-bold mt-4 animate-pulse">{processingStage}</p>
                             </div>
                         )}
                    </div>

                    {/* Action Bar */}
                    <div className="mt-4 space-y-3">
                        <button 
                            onClick={handleTryOn} 
                            disabled={isProcessing || !customerImage}
                            className="w-full bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-700 hover:to-purple-700 text-white font-bold py-4 rounded-xl shadow-lg transition-all flex items-center justify-center gap-2 disabled:opacity-50"
                        >
                            <SparklesIcon /> Visualize / Try-On
                        </button>

                        {resultImage && (
                            <div className="grid grid-cols-2 gap-2">
                                <button onClick={() => setIsSavingJob(true)} className="bg-green-600 hover:bg-green-700 text-white py-2 rounded-lg font-semibold text-sm flex items-center justify-center gap-1">
                                    <SaveIcon /> Save to Job
                                </button>
                                <button onClick={handleGetSuggestions} disabled={isSuggesting} className="bg-gray-700 hover:bg-gray-600 text-white py-2 rounded-lg font-semibold text-sm flex items-center justify-center gap-1">
                                    {isSuggesting ? <LoaderIcon /> : <><ShoppingBagIcon /> Suggest Acc.</>}
                                </button>
                            </div>
                        )}
                    </div>
                    
                    {/* Accessories Suggestions */}
                    {suggestedAccessories.length > 0 && (
                        <div className="mt-4 bg-gray-800 p-3 rounded-lg border border-gray-700 animate-fade-in">
                            <h4 className="text-xs font-bold text-gray-400 mb-2">AI Suggested Accessories</h4>
                            <div className="flex flex-wrap gap-2">
                                {suggestedAccessories.map((acc, i) => (
                                    <span key={i} className="text-xs bg-indigo-900/50 text-indigo-200 px-2 py-1 rounded border border-indigo-800">{acc}</span>
                                ))}
                            </div>
                        </div>
                    )}
                </div>
            </div>

            {/* Job Card Modal */}
            <Modal isOpen={isSavingJob} onClose={() => setIsSavingJob(false)} title="Create Production Job from Design">
                <form onSubmit={handleCreateJobCard} className="space-y-4">
                    <div>
                        <label className="block text-gray-400 text-sm font-bold mb-1">Select Customer</label>
                        <select className="w-full bg-gray-800 text-white p-3 rounded border border-gray-700" required value={jobCustomer} onChange={e => setJobCustomer(e.target.value)}>
                            <option value="">-- Select --</option>
                            {customers.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                        </select>
                    </div>
                    <div>
                        <label className="block text-gray-400 text-sm font-bold mb-1">Garment Type</label>
                        <input type="text" className="w-full bg-gray-800 text-white p-3 rounded border border-gray-700" required placeholder="e.g. Lehenga, Suit" value={jobGarmentType} onChange={e => setJobGarmentType(e.target.value)} />
                    </div>
                    <div className="p-4 bg-gray-800 rounded border border-gray-700">
                        <p className="text-sm font-bold text-white mb-1">Design Notes (Auto-Generated)</p>
                        <p className="text-xs text-gray-400">
                            {sketchPrompt || describePrompt || 'AI Design'} 
                            {selectedFabrics.length > 0 && ` | Fabrics: ${selectedFabrics.join(', ')}`}
                            {annotations.length > 0 && ` | Details: ${annotations.map(a => a.text).join(', ')}`}
                        </p>
                    </div>
                    <button type="submit" className="w-full bg-indigo-600 py-3 rounded text-white font-bold hover:bg-indigo-700">Confirm & Send to Factory</button>
                </form>
            </Modal>
        </div>
    );
};

export default VirtualTryOn;
