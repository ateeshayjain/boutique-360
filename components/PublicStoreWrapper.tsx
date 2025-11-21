import React, { useEffect, useState } from 'react';
import Storefront from './Storefront';
import { Product } from '../types';

const PublicStoreWrapper: React.FC = () => {
    const [config, setConfig] = useState<any>(null);
    const [products, setProducts] = useState<Product[]>([]);
    const [bannerImage, setBannerImage] = useState<string | null>(null);
    const [galleryImages, setGalleryImages] = useState<string[]>([]);
    const [featuredProductIds, setFeaturedProductIds] = useState<string[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        try {
            const savedConfig = localStorage.getItem('publishedSiteConfig');
            if (savedConfig) {
                const parsed = JSON.parse(savedConfig);
                setConfig(parsed.config);
                setProducts(parsed.products || []);
                setBannerImage(parsed.bannerImage);
                setGalleryImages(parsed.galleryImages || []);
                setFeaturedProductIds(parsed.featuredProductIds || []);
            }
        } catch (e) {
            console.error("Failed to load store config", e);
        } finally {
            setLoading(false);
        }
    }, []);

    if (loading) {
        return <div className="flex items-center justify-center h-screen bg-gray-100 text-gray-600">Loading Store...</div>;
    }

    if (!config) {
        return (
            <div className="flex flex-col items-center justify-center h-screen bg-gray-100 text-gray-800 p-8 text-center">
                <h1 className="text-4xl font-bold mb-4">Store Not Found</h1>
                <p className="text-lg text-gray-600 mb-8">The store you are looking for has not been published yet.</p>
                <a href="/" className="text-indigo-600 hover:underline">Return to Boutique 360</a>
            </div>
        );
    }

    return (
        <Storefront
            config={config}
            bannerImage={bannerImage}
            galleryImages={galleryImages}
            products={products}
            featuredProductIds={featuredProductIds}
            onClose={() => window.location.href = '/'} // "Close" goes back to app
        />
    );
};

export default PublicStoreWrapper;
