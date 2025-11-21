import React from 'react';
import { Product } from '../types';
import { ShoppingCartIcon, XIcon } from './icons';

interface StorefrontProps {
    config: {
        siteTitle: string;
        welcomeMessage: string;
        aboutUs: string;
        primaryColor: string;
        secondaryColor: string;
    };
    bannerImage: string | null;
    galleryImages: string[];
    products: Product[];
    featuredProductIds: string[];
    onClose: () => void;
}

const Storefront: React.FC<StorefrontProps> = ({ config, bannerImage, galleryImages, products, featuredProductIds, onClose }) => {
    const featuredProducts = products.filter(p => featuredProductIds.includes(p.id));

    return (
        <div className="fixed inset-0 z-50 bg-white overflow-y-auto text-gray-800 font-sans">
            {/* Preview Header Control */}
            <div className="fixed top-0 left-0 right-0 bg-gray-900 text-white p-3 flex justify-between items-center z-50 shadow-md">
                <div className="flex items-center gap-2">
                    <span className="bg-green-500 text-xs px-2 py-0.5 rounded font-bold uppercase">Live Preview</span>
                    <span className="text-sm text-gray-400">This is how your store looks to customers.</span>
                </div>
                <button onClick={onClose} className="flex items-center gap-1 hover:text-red-400 transition-colors">
                    <XIcon /> Close Preview
                </button>
            </div>

            {/* Store Navbar */}
            <nav className="sticky top-12 bg-white/90 backdrop-blur-md shadow-sm z-40 mt-12" style={{ borderTop: `4px solid ${config.primaryColor}` }}>
                <div className="container mx-auto px-6 py-4 flex justify-between items-center">
                    <h1 className="text-2xl font-bold tracking-tight" style={{ color: config.primaryColor }}>{config.siteTitle}</h1>
                    <div className="flex items-center gap-6 text-sm font-medium text-gray-600">
                        <a href="#" className="hover:text-black transition-colors">Home</a>
                        <a href="#shop" className="hover:text-black transition-colors">Shop</a>
                        <a href="#about" className="hover:text-black transition-colors">About</a>
                        <a href="#contact" className="hover:text-black transition-colors">Contact</a>
                        <div className="relative cursor-pointer">
                            <ShoppingCartIcon />
                            <span className="absolute -top-2 -right-2 bg-red-500 text-white text-[10px] w-4 h-4 flex items-center justify-center rounded-full">0</span>
                        </div>
                    </div>
                </div>
            </nav>

            {/* Hero Section */}
            <header className="relative h-[600px] flex items-center justify-center text-center text-white">
                <div className="absolute inset-0 bg-gray-900">
                    {bannerImage ? (
                        <img src={bannerImage} alt="Hero" className="w-full h-full object-cover opacity-60" />
                    ) : (
                        <div className="w-full h-full bg-gradient-to-r from-gray-800 to-gray-900 opacity-90" />
                    )}
                </div>
                <div className="relative z-10 max-w-3xl px-6">
                    <h2 className="text-5xl md:text-6xl font-extrabold mb-6 leading-tight">{config.welcomeMessage}</h2>
                    <button
                        className="px-8 py-4 rounded-full font-bold text-lg transition-transform hover:scale-105 shadow-lg"
                        style={{ backgroundColor: config.primaryColor, color: '#fff' }}
                    >
                        Shop Collection
                    </button>
                </div>
            </header>

            {/* Featured Products */}
            <section id="shop" className="py-20 bg-gray-50">
                <div className="container mx-auto px-6">
                    <h3 className="text-3xl font-bold text-center mb-12">Featured Collection</h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
                        {featuredProducts.map(product => (
                            <div key={product.id} className="bg-white rounded-xl overflow-hidden shadow-sm hover:shadow-xl transition-shadow group">
                                <div className="relative h-80 overflow-hidden">
                                    <img
                                        src={product.imageUrl || 'https://via.placeholder.com/400x500?text=No+Image'}
                                        alt={product.name}
                                        className="w-full h-full object-cover transform group-hover:scale-110 transition-transform duration-500"
                                    />
                                    <div className="absolute inset-0 bg-black/20 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                                        <button className="bg-white text-black px-6 py-2 rounded-full font-bold transform translate-y-4 group-hover:translate-y-0 transition-transform">
                                            Quick View
                                        </button>
                                    </div>
                                </div>
                                <div className="p-6">
                                    <div className="text-xs text-gray-500 mb-1">{product.category}</div>
                                    <h4 className="font-bold text-lg mb-2">{product.name}</h4>
                                    <div className="flex justify-between items-center">
                                        <span className="text-xl font-bold" style={{ color: config.primaryColor }}>₹{product.price}</span>
                                        <button className="text-gray-400 hover:text-black transition-colors">
                                            <ShoppingCartIcon />
                                        </button>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            </section>

            {/* Lookbook Gallery */}
            {galleryImages.length > 0 && (
                <section className="py-20">
                    <div className="container mx-auto px-6">
                        <h3 className="text-3xl font-bold text-center mb-12">Follow Us @{config.siteTitle.replace(/\s+/g, '').toLowerCase()}</h3>
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                            {galleryImages.map((img, idx) => (
                                <div key={idx} className="aspect-square overflow-hidden rounded-lg">
                                    <img src={img} alt="Gallery" className="w-full h-full object-cover hover:opacity-90 transition-opacity cursor-pointer" />
                                </div>
                            ))}
                        </div>
                    </div>
                </section>
            )}

            {/* About Section */}
            <section id="about" className="py-20 text-white" style={{ backgroundColor: config.secondaryColor === '#E5E7EB' ? '#1F2937' : config.secondaryColor }}>
                <div className="container mx-auto px-6 text-center max-w-4xl">
                    <h3 className="text-3xl font-bold mb-8">Our Story</h3>
                    <p className="text-xl leading-relaxed opacity-90">{config.aboutUs}</p>
                </div>
            </section>

            {/* Footer */}
            <footer className="bg-gray-900 text-gray-400 py-12 border-t border-gray-800">
                <div className="container mx-auto px-6 grid grid-cols-1 md:grid-cols-4 gap-12">
                    <div>
                        <h4 className="text-white font-bold text-lg mb-4">{config.siteTitle}</h4>
                        <p className="text-sm">Elevating your style with timeless elegance and modern designs.</p>
                    </div>
                    <div>
                        <h4 className="text-white font-bold mb-4">Shop</h4>
                        <ul className="space-y-2 text-sm">
                            <li><a href="#" className="hover:text-white">New Arrivals</a></li>
                            <li><a href="#" className="hover:text-white">Best Sellers</a></li>
                            <li><a href="#" className="hover:text-white">Accessories</a></li>
                        </ul>
                    </div>
                    <div>
                        <h4 className="text-white font-bold mb-4">Support</h4>
                        <ul className="space-y-2 text-sm">
                            <li><a href="#" className="hover:text-white">Contact Us</a></li>
                            <li><a href="#" className="hover:text-white">Shipping & Returns</a></li>
                            <li><a href="#" className="hover:text-white">FAQ</a></li>
                        </ul>
                    </div>
                    <div>
                        <h4 className="text-white font-bold mb-4">Newsletter</h4>
                        <div className="flex">
                            <input type="email" placeholder="Your email" className="bg-gray-800 text-white px-4 py-2 rounded-l-md focus:outline-none w-full" />
                            <button className="bg-indigo-600 px-4 py-2 rounded-r-md text-white font-bold hover:bg-indigo-700">Subscribe</button>
                        </div>
                    </div>
                </div>
                <div className="container mx-auto px-6 mt-12 pt-8 border-t border-gray-800 text-center text-xs">
                    &copy; {new Date().getFullYear()} {config.siteTitle}. All rights reserved. Powered by Boutique 360.
                </div>
            </footer>
        </div>
    );
};

export default Storefront;
