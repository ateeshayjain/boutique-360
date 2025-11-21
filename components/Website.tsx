
import React, { useState } from 'react';
import { Product, Order, OrderStatus } from '../types';
import { DashboardIcon, LayoutTemplateIcon, PaletteIcon, MessageSquareIcon, CheckCircleIcon, ClockIcon, EyeIcon, SendIcon, ImagePlusIcon, TrashIcon } from './icons';

interface WebsiteProps {
    products: Product[];
    setProducts: React.Dispatch<React.SetStateAction<Product[]>>;
    orders: Order[];
}

interface Message {
    id: string;
    sender: string;
    email: string;
    subject: string;
    content: string;
    date: string;
    status: 'New' | 'Read' | 'Replied';
}

const mockMessages: Message[] = [
    { id: 'MSG-001', sender: 'Sneha Gupta', email: 'sneha@gmail.com', subject: 'Return Policy for Lehenga', content: 'Hi, I wanted to know if the bridal lehenga is returnable if the fitting is not right?', date: '2024-07-25', status: 'New' },
    { id: 'MSG-002', sender: 'Rahul Mehra', email: 'rahul.m@outlook.com', subject: 'Bulk Order Inquiry', content: 'Do you provide discounts for bulk orders of silk sarees for a wedding?', date: '2024-07-24', status: 'Read' },
    { id: 'MSG-003', sender: 'Kavita R', email: 'kavita.r@yahoo.com', subject: 'Wrong Item Received', content: 'I received a blue kurti instead of the red one I ordered.', date: '2024-07-22', status: 'Replied' },
];

import Storefront from './Storefront';

const Website: React.FC<WebsiteProps> = ({ products, setProducts, orders }) => {
    const [activeTab, setActiveTab] = useState<'overview' | 'design' | 'catalog' | 'inbox'>('overview');

    // Preview & Publish State
    const [isPreviewOpen, setIsPreviewOpen] = useState(false);
    const [isPublished, setIsPublished] = useState(false);
    const [publishedUrl, setPublishedUrl] = useState<string | null>(null);

    // Design State
    const [config, setConfig] = useState({
        siteTitle: "My Awesome Boutique",
        welcomeMessage: "Welcome to our online store! Discover the latest trends in ethnic wear.",
        aboutUs: "We are a family-owned boutique specializing in handloom sarees and bespoke bridal wear.",
        primaryColor: "#4F46E5",
        secondaryColor: "#E5E7EB"
    });
    const [bannerImage, setBannerImage] = useState<string | null>(null);
    const [galleryImages, setGalleryImages] = useState<string[]>([
        'https://images.unsplash.com/photo-1585487000160-6ebcfceb0d03?auto=format&fit=crop&w=300&q=80',
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?auto=format&fit=crop&w=300&q=80'
    ]);

    // Inbox State
    const [messages, setMessages] = useState<Message[]>(mockMessages);
    const [selectedMessageId, setSelectedMessageId] = useState<string | null>(null);
    const [replyText, setReplyText] = useState('');

    // Catalog State
    const [featuredProductIds, setFeaturedProductIds] = useState<string[]>(['P001', 'P003']);

    const handleSaveConfig = (e: React.FormEvent) => {
        e.preventDefault();
        alert("Website configuration updated successfully!");
    };

    const handlePublish = () => {
        if (isPublished) {
            setIsPublished(false);
            setPublishedUrl(null);
            localStorage.removeItem('publishedSiteConfig');
            alert("Site unpublished.");
        } else {
            setIsPublished(true);
            // Save snapshot to localStorage for the public view
            const siteData = {
                config,
                bannerImage,
                galleryImages,
                featuredProductIds,
                products // In a real app, products would be fetched from API by the store
            };
            localStorage.setItem('publishedSiteConfig', JSON.stringify(siteData));

            const mockUrl = `${window.location.origin}/store`;
            setPublishedUrl(mockUrl);
            alert(`Site published successfully! Live at: ${mockUrl}`);
        }
    };

    const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
        if (e.target.files && e.target.files[0]) {
            const reader = new FileReader();
            reader.onload = (ev) => setBannerImage(ev.target?.result as string);
            reader.readAsDataURL(e.target.files[0]);
        }
    };

    const handleAddGalleryImage = (e: React.ChangeEvent<HTMLInputElement>) => {
        if (e.target.files && e.target.files[0]) {
            const reader = new FileReader();
            reader.onload = (ev) => {
                if (ev.target?.result) {
                    setGalleryImages([...galleryImages, ev.target.result as string]);
                }
            };
            reader.readAsDataURL(e.target.files[0]);
        }
    };

    const removeGalleryImage = (index: number) => {
        setGalleryImages(prev => prev.filter((_, i) => i !== index));
    };

    const handleProductImageUpload = (productId: string, e: React.ChangeEvent<HTMLInputElement>) => {
        if (e.target.files && e.target.files[0]) {
            const reader = new FileReader();
            reader.onload = (ev) => {
                const newImageUrl = ev.target?.result as string;
                setProducts(prev => prev.map(p => p.id === productId ? { ...p, imageUrl: newImageUrl } : p));
            };
            reader.readAsDataURL(e.target.files[0]);
        }
    };

    const toggleFeatured = (id: string) => {
        setFeaturedProductIds(prev =>
            prev.includes(id) ? prev.filter(p => p !== id) : [...prev, id]
        );
    };

    const handleReply = () => {
        if (!selectedMessageId || !replyText) return;
        setMessages(prev => prev.map(msg =>
            msg.id === selectedMessageId ? { ...msg, status: 'Replied' } : msg
        ));
        setReplyText('');
        alert("Reply sent to customer!");
    };

    const selectedMessage = messages.find(m => m.id === selectedMessageId);

    // Overview Stats
    const pendingWebOrders = orders.filter(o => o.status === OrderStatus.Pending).length;
    const unreadMessages = messages.filter(m => m.status === 'New').length;

    const renderOverview = () => (
        <div className="space-y-6 animate-fade-in">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <div className="bg-gray-800 p-6 rounded-lg shadow border-l-4 border-indigo-500">
                    <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-400 text-sm uppercase font-bold">Site Visitors (Today)</span>
                        <EyeIcon />
                    </div>
                    <div className="text-3xl font-bold text-white">1,245</div>
                    <div className="text-green-400 text-sm mt-2">↑ 12% from yesterday</div>
                </div>
                <div className="bg-gray-800 p-6 rounded-lg shadow border-l-4 border-yellow-500">
                    <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-400 text-sm uppercase font-bold">Pending Web Orders</span>
                        <ClockIcon />
                    </div>
                    <div className="text-3xl font-bold text-white">{pendingWebOrders}</div>
                    <div className="text-gray-500 text-sm mt-2">Requires attention</div>
                </div>
                <div className="bg-gray-800 p-6 rounded-lg shadow border-l-4 border-pink-500">
                    <div className="flex justify-between items-center mb-2">
                        <span className="text-gray-400 text-sm uppercase font-bold">Unread Inquiries</span>
                        <MessageSquareIcon />
                    </div>
                    <div className="text-3xl font-bold text-white">{unreadMessages}</div>
                    <div className="text-gray-500 text-sm mt-2">Check Inbox</div>
                </div>
            </div>

            <div className="bg-gray-800 p-6 rounded-lg shadow">
                <h3 className="text-xl font-semibold text-white mb-4">Website Health</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div className="flex items-center justify-between p-3 bg-gray-700 rounded">
                        <span className="text-gray-300">Domain Status</span>
                        <span className="text-green-400 flex items-center gap-1"><CheckCircleIcon /> Active</span>
                    </div>
                    <div className="flex items-center justify-between p-3 bg-gray-700 rounded">
                        <span className="text-gray-300">SSL Certificate</span>
                        <span className="text-green-400 flex items-center gap-1"><CheckCircleIcon /> Valid</span>
                    </div>
                    <div className="flex items-center justify-between p-3 bg-gray-700 rounded">
                        <span className="text-gray-300">Last Backup</span>
                        <span className="text-gray-400">2 Hours ago</span>
                    </div>
                    <div className="flex items-center justify-between p-3 bg-gray-700 rounded">
                        <span className="text-gray-300">Plan</span>
                        <span className="text-indigo-400 font-bold">Premium Boutique</span>
                    </div>
                </div>
            </div>

            {/* Published URL Display */}
            {isPublished && publishedUrl && (
                <div className="bg-green-900/20 border border-green-500/50 p-4 rounded-lg flex items-center justify-between">
                    <div>
                        <h4 className="text-green-400 font-bold">Your site is LIVE!</h4>
                        <a href={publishedUrl} target="_blank" rel="noopener noreferrer" className="text-green-300 hover:underline text-sm">{publishedUrl}</a>
                    </div>
                    <button onClick={() => window.open(publishedUrl, '_blank')} className="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 text-sm font-bold">Visit Site</button>
                </div>
            )}
        </div>
    );

    const renderDesign = () => (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 animate-fade-in">
            <div className="lg:col-span-2 space-y-6">
                <div className="bg-gray-800 p-6 rounded-lg shadow">
                    <h3 className="text-xl font-semibold text-white mb-4 flex items-center gap-2"><LayoutTemplateIcon /> Brand & Content</h3>
                    <form className="space-y-4" onSubmit={handleSaveConfig}>
                        <div>
                            <label className="block text-gray-400 text-sm mb-1">Site Title</label>
                            <input type="text" className="w-full bg-gray-700 text-white rounded p-2 border border-gray-600"
                                value={config.siteTitle} onChange={e => setConfig({ ...config, siteTitle: e.target.value })} />
                        </div>
                        <div>
                            <label className="block text-gray-400 text-sm mb-1">Welcome Message (Hero Text)</label>
                            <textarea rows={2} className="w-full bg-gray-700 text-white rounded p-2 border border-gray-600"
                                value={config.welcomeMessage} onChange={e => setConfig({ ...config, welcomeMessage: e.target.value })} />
                        </div>
                        <div>
                            <label className="block text-gray-400 text-sm mb-1">About Us Description</label>
                            <textarea rows={4} className="w-full bg-gray-700 text-white rounded p-2 border border-gray-600"
                                value={config.aboutUs} onChange={e => setConfig({ ...config, aboutUs: e.target.value })} />
                        </div>
                        <button type="submit" className="bg-indigo-600 text-white font-bold py-2 px-6 rounded hover:bg-indigo-700">Save Changes</button>
                    </form>
                </div>

                <div className="bg-gray-800 p-6 rounded-lg shadow">
                    <h3 className="text-xl font-semibold text-white mb-4 flex items-center gap-2"><ImagePlusIcon /> Hero Banner</h3>
                    <div className="border-2 border-dashed border-gray-600 rounded-lg p-8 text-center hover:border-indigo-500 transition-colors cursor-pointer relative overflow-hidden group">
                        <input type="file" accept="image/*" onChange={handleImageUpload} className="absolute inset-0 w-full h-full opacity-0 cursor-pointer" />
                        {bannerImage ? (
                            <img src={bannerImage} alt="Banner Preview" className="w-full h-48 object-cover rounded" />
                        ) : (
                            <div className="flex flex-col items-center text-gray-400">
                                <ImagePlusIcon />
                                <span className="mt-2 text-sm">Click to upload banner image</span>
                            </div>
                        )}
                    </div>
                </div>

                {/* Lookbook / Gallery Section */}
                <div className="bg-gray-800 p-6 rounded-lg shadow">
                    <h3 className="text-xl font-semibold text-white mb-4 flex items-center gap-2"><PaletteIcon /> Lookbook Gallery</h3>
                    <div className="grid grid-cols-3 md:grid-cols-4 gap-4">
                        {galleryImages.map((img, idx) => (
                            <div key={idx} className="relative group rounded-lg overflow-hidden aspect-square border border-gray-600">
                                <img src={img} alt={`Gallery ${idx}`} className="w-full h-full object-cover" />
                                <button
                                    onClick={() => removeGalleryImage(idx)}
                                    className="absolute top-1 right-1 bg-red-600 p-1 rounded-full text-white opacity-0 group-hover:opacity-100 transition-opacity"
                                >
                                    <TrashIcon />
                                </button>
                            </div>
                        ))}
                        <div className="relative border-2 border-dashed border-gray-600 rounded-lg aspect-square flex items-center justify-center hover:border-indigo-500 transition-colors cursor-pointer text-gray-500 hover:text-white">
                            <input type="file" accept="image/*" onChange={handleAddGalleryImage} className="absolute inset-0 w-full h-full opacity-0 cursor-pointer" />
                            <div className="flex flex-col items-center">
                                <ImagePlusIcon />
                                <span className="text-xs mt-1">Add Image</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div className="space-y-6">
                <div className="bg-gray-800 p-6 rounded-lg shadow">
                    <h3 className="text-xl font-semibold text-white mb-4 flex items-center gap-2"><PaletteIcon /> Theme Colors</h3>
                    <div className="space-y-4">
                        <div>
                            <label className="block text-gray-400 text-sm mb-1">Primary Color</label>
                            <div className="flex items-center gap-2">
                                <input type="color" value={config.primaryColor} onChange={e => setConfig({ ...config, primaryColor: e.target.value })} className="h-10 w-10 rounded cursor-pointer bg-transparent border-0" />
                                <span className="text-gray-300 font-mono">{config.primaryColor}</span>
                            </div>
                        </div>
                        <div>
                            <label className="block text-gray-400 text-sm mb-1">Secondary/Background Color</label>
                            <div className="flex items-center gap-2">
                                <input type="color" value={config.secondaryColor} onChange={e => setConfig({ ...config, secondaryColor: e.target.value })} className="h-10 w-10 rounded cursor-pointer bg-transparent border-0" />
                                <span className="text-gray-300 font-mono">{config.secondaryColor}</span>
                            </div>
                        </div>
                    </div>
                </div>
                <div className="bg-gray-800 p-6 rounded-lg shadow">
                    <h3 className="text-sm font-semibold text-gray-400 mb-2 uppercase">Mobile Preview</h3>
                    <div className="border border-gray-600 rounded-xl h-64 w-full overflow-hidden relative bg-gray-900 flex flex-col">
                        <div className="h-4 bg-gray-700 w-full"></div>
                        <div className="flex-1 p-2 overflow-y-auto custom-scrollbar">
                            <div className="h-24 w-full rounded mb-2" style={{
                                backgroundColor: config.primaryColor,
                                backgroundImage: bannerImage ? `url(${bannerImage})` : 'none',
                                backgroundSize: 'cover'
                            }}></div>
                            <div className="h-4 w-3/4 bg-gray-700 rounded mb-2"></div>
                            <div className="h-20 w-full bg-gray-800 rounded mb-2 border border-gray-700 p-1">
                                <div className="text-[8px] text-gray-400">{config.welcomeMessage}</div>
                            </div>
                            <div className="flex overflow-x-auto gap-1 pb-2 no-scrollbar">
                                {galleryImages.map((img, i) => (
                                    <div key={i} className="h-16 w-16 flex-shrink-0 bg-gray-700 rounded overflow-hidden">
                                        <img src={img} className="w-full h-full object-cover" />
                                    </div>
                                ))}
                            </div>
                            <div className="grid grid-cols-2 gap-1">
                                <div className="h-16 bg-gray-700 rounded"></div>
                                <div className="h-16 bg-gray-700 rounded"></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );

    const renderCatalog = () => (
        <div className="bg-gray-800 rounded-lg shadow overflow-hidden animate-fade-in">
            <div className="p-6 border-b border-gray-700">
                <h2 className="text-xl font-semibold text-white">Featured Products</h2>
                <p className="text-gray-400 text-sm mt-1">Select products to showcase on your website's homepage. Click the image icon to upload a product photo.</p>
            </div>
            <div className="overflow-x-auto">
                <table className="w-full text-left">
                    <thead className="bg-gray-700">
                        <tr>
                            <th className="p-4 font-semibold w-24">Image</th>
                            <th className="p-4 font-semibold">Product</th>
                            <th className="p-4 font-semibold">Category</th>
                            <th className="p-4 font-semibold">Stock</th>
                            <th className="p-4 font-semibold text-center">Featured on Home</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-700">
                        {products.map(product => (
                            <tr key={product.id} className="hover:bg-gray-700/50">
                                <td className="p-4">
                                    <div className="relative w-16 h-16 bg-gray-700 rounded-lg overflow-hidden group cursor-pointer border border-gray-600 hover:border-indigo-500">
                                        {product.imageUrl ? (
                                            <img src={product.imageUrl} alt={product.name} className="w-full h-full object-cover" />
                                        ) : (
                                            <div className="w-full h-full flex items-center justify-center text-gray-500">
                                                <ImagePlusIcon />
                                            </div>
                                        )}
                                        <input type="file" className="absolute inset-0 opacity-0 cursor-pointer" accept="image/*" onChange={(e) => handleProductImageUpload(product.id, e)} />
                                        <div className="absolute inset-0 bg-black/50 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity text-xs text-white font-bold">
                                            Change
                                        </div>
                                    </div>
                                </td>
                                <td className="p-4">
                                    <div className="font-bold text-white">{product.name}</div>
                                    <div className="text-xs text-gray-500">{product.sku}</div>
                                </td>
                                <td className="p-4 text-gray-300">{product.category}</td>
                                <td className="p-4 text-gray-300">{product.stockLevel}</td>
                                <td className="p-4 text-center">
                                    <button
                                        onClick={() => toggleFeatured(product.id)}
                                        className={`w-12 h-6 rounded-full p-1 transition-colors duration-200 ease-in-out ${featuredProductIds.includes(product.id) ? 'bg-indigo-600' : 'bg-gray-600'}`}
                                    >
                                        <div className={`bg-white w-4 h-4 rounded-full shadow-md transform transition-transform duration-200 ease-in-out ${featuredProductIds.includes(product.id) ? 'translate-x-6' : 'translate-x-0'}`}></div>
                                    </button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );

    const renderInbox = () => (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-[calc(100vh-200px)] animate-fade-in">
            {/* Message List */}
            <div className="bg-gray-800 rounded-lg shadow overflow-hidden flex flex-col">
                <div className="p-4 border-b border-gray-700 bg-gray-750">
                    <h3 className="font-bold text-white">Inbox ({unreadMessages})</h3>
                </div>
                <div className="overflow-y-auto flex-1">
                    {messages.map(msg => (
                        <div
                            key={msg.id}
                            onClick={() => { setSelectedMessageId(msg.id); if (msg.status === 'New') { setMessages(prev => prev.map(m => m.id === msg.id ? { ...m, status: 'Read' } : m)) } }}
                            className={`p-4 border-b border-gray-700 cursor-pointer hover:bg-gray-700 transition-colors ${selectedMessageId === msg.id ? 'bg-indigo-900/30 border-l-4 border-indigo-500' : ''} ${msg.status === 'New' ? 'bg-gray-800 font-semibold' : 'bg-gray-800/50 text-gray-400'}`}
                        >
                            <div className="flex justify-between items-center mb-1">
                                <span className="truncate text-sm">{msg.sender}</span>
                                <span className="text-xs opacity-70">{msg.date}</span>
                            </div>
                            <div className="text-sm truncate text-white">{msg.subject}</div>
                            <div className="flex mt-2">
                                {msg.status === 'New' && <span className="bg-blue-500 text-[10px] px-2 py-0.5 rounded text-white">New</span>}
                                {msg.status === 'Replied' && <span className="bg-green-500 text-[10px] px-2 py-0.5 rounded text-white">Replied</span>}
                            </div>
                        </div>
                    ))}
                </div>
            </div>

            {/* Message Detail View */}
            <div className="lg:col-span-2 bg-gray-800 rounded-lg shadow flex flex-col">
                {selectedMessage ? (
                    <>
                        <div className="p-6 border-b border-gray-700">
                            <div className="flex justify-between items-start">
                                <div>
                                    <h2 className="text-xl font-bold text-white mb-2">{selectedMessage.subject}</h2>
                                    <div className="text-sm text-gray-300">From: <span className="text-white font-semibold">{selectedMessage.sender}</span> &lt;{selectedMessage.email}&gt;</div>
                                    <div className="text-xs text-gray-500 mt-1">Received: {selectedMessage.date}</div>
                                </div>
                                <div className="flex gap-2">
                                    <button className="text-gray-400 hover:text-white" title="Mark Unread"><EyeIcon /></button>
                                </div>
                            </div>
                        </div>
                        <div className="p-6 flex-1 overflow-y-auto bg-gray-900/30">
                            <p className="text-gray-200 whitespace-pre-wrap">{selectedMessage.content}</p>
                        </div>
                        <div className="p-4 bg-gray-750 border-t border-gray-700">
                            <div className="mb-2 flex items-center gap-2 text-sm text-gray-400">
                                <SendIcon /> Reply to Customer
                            </div>
                            <textarea
                                className="w-full bg-gray-700 text-white rounded p-3 border border-gray-600 focus:border-indigo-500 focus:outline-none resize-none h-24"
                                placeholder="Type your reply here..."
                                value={replyText}
                                onChange={e => setReplyText(e.target.value)}
                            ></textarea>
                            <div className="flex justify-end mt-2">
                                <button
                                    onClick={handleReply}
                                    className="bg-indigo-600 text-white font-bold py-2 px-6 rounded hover:bg-indigo-700 flex items-center gap-2"
                                >
                                    <SendIcon /> Send Reply
                                </button>
                            </div>
                        </div>
                    </>
                ) : (
                    <div className="flex-1 flex flex-col items-center justify-center text-gray-500">
                        <MessageSquareIcon />
                        <p className="mt-4">Select a message to read</p>
                    </div>
                )}
            </div>
        </div>
    );

    return (
        <div className="p-8 h-full flex flex-col">
            <div className="flex justify-between items-center mb-6">
                <h1 className="text-3xl font-bold text-white">Website Manager</h1>
                <div className="flex items-center gap-4">
                    <button
                        onClick={() => setIsPreviewOpen(true)}
                        className="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded font-medium flex items-center gap-2"
                    >
                        <EyeIcon /> Preview Site
                    </button>
                    <button
                        onClick={handlePublish}
                        className={`${isPublished ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'} text-white px-4 py-2 rounded font-medium flex items-center gap-2`}
                    >
                        {isPublished ? 'Unpublish' : 'Publish Live'}
                    </button>
                    <div className={`bg-green-500/10 text-green-400 px-3 py-1 rounded-full text-sm border border-green-500/50 flex items-center gap-2 ${isPublished ? 'opacity-100' : 'opacity-50'}`}>
                        <div className={`w-2 h-2 bg-green-500 rounded-full ${isPublished ? 'animate-pulse' : ''}`}></div>
                        {isPublished ? 'Live' : 'Offline'}
                    </div>
                </div>
            </div>

            {/* Tabs */}
            <div className="flex space-x-1 bg-gray-800 p-1 rounded-lg mb-6 w-fit">
                <button onClick={() => setActiveTab('overview')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'overview' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white hover:bg-gray-700'}`}>Overview</button>
                <button onClick={() => setActiveTab('design')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'design' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white hover:bg-gray-700'}`}>Design & Content</button>
                <button onClick={() => setActiveTab('catalog')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'catalog' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white hover:bg-gray-700'}`}>Catalog</button>
                <button onClick={() => setActiveTab('inbox')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'inbox' ? 'bg-indigo-600 text-white shadow' : 'text-gray-400 hover:text-white hover:bg-gray-700'}`}>Inbox <span className="ml-1 bg-red-500 text-white text-[10px] px-1.5 rounded-full">{unreadMessages}</span></button>
            </div>

            <div className="flex-1">
                {activeTab === 'overview' && renderOverview()}
                {activeTab === 'design' && renderDesign()}
                {activeTab === 'catalog' && renderCatalog()}
                {activeTab === 'inbox' && renderInbox()}
            </div>

            {/* Storefront Preview Modal */}
            {isPreviewOpen && (
                <Storefront
                    config={config}
                    bannerImage={bannerImage}
                    galleryImages={galleryImages}
                    products={products}
                    featuredProductIds={featuredProductIds}
                    onClose={() => setIsPreviewOpen(false)}
                />
            )}
        </div>
    );
};

export default Website;
