
import React, { useState, useRef, useEffect } from 'react';
import { askBoutiqueAssistant } from '../services/geminiService';
import { BotIcon, SendIcon, XIcon, SparklesIcon } from './icons';
import { Order, Product, JobCard, RawMaterial } from '../types';

interface GeminiAssistantProps {
    orders: Order[];
    products: Product[];
    jobCards: JobCard[];
    rawMaterials: RawMaterial[];
}

interface Message {
    sender: 'user' | 'bot';
    text: string;
}

const GeminiAssistant: React.FC<GeminiAssistantProps> = ({ orders, products, jobCards, rawMaterials }) => {
    const [isOpen, setIsOpen] = useState(false);
    const [messages, setMessages] = useState<Message[]>([
        { sender: 'bot', text: 'Hello! I am your Boutique AI Assistant. Ask me about your orders, stock, or production status.' }
    ]);
    const [input, setInput] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const messagesEndRef = useRef<HTMLDivElement>(null);

    const scrollToBottom = () => {
        messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    };

    useEffect(scrollToBottom, [messages]);

    const handleSend = async () => {
        if (!input.trim()) return;
        
        const userMsg = input;
        setInput('');
        setMessages(prev => [...prev, { sender: 'user', text: userMsg }]);
        setIsLoading(true);

        // Prepare Context
        // We summarize data to avoid token limits if lists are huge, but for this scale, JSON stringify is okay.
        // In a real app, we would calculate aggregates here or send a simplified structure.
        const contextData = JSON.stringify({
            pendingOrders: orders.filter(o => o.status === 'Pending').length,
            recentOrders: orders.slice(0, 5),
            lowStockProducts: products.filter(p => p.stockLevel <= p.reorderThreshold).map(p => ({name: p.name, stock: p.stockLevel})),
            activeJobs: jobCards.filter(j => j.status !== 'Ready').map(j => ({customer: j.customerName, status: j.status, due: j.dueDate})),
            lowRawMaterials: rawMaterials.filter(m => m.quantity <= m.lowStockThreshold).map(m => ({name: m.name, quantity: m.quantity}))
        });

        try {
            const reply = await askBoutiqueAssistant(contextData, userMsg);
            setMessages(prev => [...prev, { sender: 'bot', text: reply }]);
        } catch (error) {
            setMessages(prev => [...prev, { sender: 'bot', text: "Sorry, I encountered an error processing your request." }]);
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <>
            {/* Floating Button */}
            <button 
                onClick={() => setIsOpen(!isOpen)}
                className={`fixed bottom-6 right-6 p-4 rounded-full shadow-2xl transition-all duration-300 z-50 flex items-center justify-center ${isOpen ? 'bg-red-500 rotate-90' : 'bg-gradient-to-r from-indigo-600 to-purple-600 hover:scale-110'}`}
            >
                {isOpen ? <XIcon /> : <BotIcon />}
            </button>

            {/* Chat Window */}
            {isOpen && (
                <div className="fixed bottom-24 right-6 w-96 h-[500px] bg-gray-900 border border-gray-700 rounded-2xl shadow-2xl flex flex-col z-50 overflow-hidden animate-fade-in">
                    {/* Header */}
                    <div className="bg-gray-800 p-4 border-b border-gray-700 flex items-center gap-2">
                        <div className="w-8 h-8 bg-indigo-600 rounded-full flex items-center justify-center text-white">
                            <SparklesIcon />
                        </div>
                        <div>
                            <h3 className="font-bold text-white text-sm">Boutique Assistant</h3>
                            <p className="text-xs text-green-400 flex items-center gap-1"><span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span> Online</p>
                        </div>
                    </div>

                    {/* Messages */}
                    <div className="flex-1 overflow-y-auto p-4 space-y-4 bg-gray-900 custom-scrollbar">
                        {messages.map((msg, idx) => (
                            <div key={idx} className={`flex ${msg.sender === 'user' ? 'justify-end' : 'justify-start'}`}>
                                <div className={`max-w-[80%] p-3 rounded-2xl text-sm ${msg.sender === 'user' ? 'bg-indigo-600 text-white rounded-br-none' : 'bg-gray-800 text-gray-200 rounded-bl-none border border-gray-700'}`}>
                                    {msg.text}
                                </div>
                            </div>
                        ))}
                        {isLoading && (
                            <div className="flex justify-start">
                                <div className="bg-gray-800 p-3 rounded-2xl rounded-bl-none border border-gray-700">
                                    <div className="flex gap-1">
                                        <div className="w-2 h-2 bg-gray-500 rounded-full animate-bounce"></div>
                                        <div className="w-2 h-2 bg-gray-500 rounded-full animate-bounce delay-75"></div>
                                        <div className="w-2 h-2 bg-gray-500 rounded-full animate-bounce delay-150"></div>
                                    </div>
                                </div>
                            </div>
                        )}
                        <div ref={messagesEndRef} />
                    </div>

                    {/* Input */}
                    <div className="p-3 bg-gray-800 border-t border-gray-700">
                        <div className="flex items-center gap-2 bg-gray-900 rounded-full px-4 py-2 border border-gray-700 focus-within:border-indigo-500 transition-colors">
                            <input 
                                type="text" 
                                className="bg-transparent text-white text-sm flex-1 focus:outline-none"
                                placeholder="Ask about orders, stock..."
                                value={input}
                                onChange={e => setInput(e.target.value)}
                                onKeyDown={e => e.key === 'Enter' && handleSend()}
                            />
                            <button onClick={handleSend} disabled={!input.trim() || isLoading} className="text-indigo-400 hover:text-white disabled:opacity-50">
                                <SendIcon />
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </>
    );
};

export default GeminiAssistant;
