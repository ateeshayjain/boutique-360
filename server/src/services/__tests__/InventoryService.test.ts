import { InventoryService } from '../InventoryService';
import { InventoryRepository } from '../../repositories/InventoryRepository';

// Mock dependencies
jest.mock('../../repositories/InventoryRepository');

describe('InventoryService', () => {
    let inventoryService: InventoryService;
    let mockRepo: jest.Mocked<InventoryRepository>;

    beforeEach(() => {
        jest.clearAllMocks();
        mockRepo = new InventoryRepository() as jest.Mocked<InventoryRepository>;
        (InventoryRepository as jest.Mock).mockImplementation(() => mockRepo);
        inventoryService = new InventoryService();
    });

    describe('adjustStock', () => {
        it('should successfully adjust stock', async () => {
            const product = { id: 'p1', sku: 'SKU1', name: 'Product 1', stock_level: 10, price: 100, version: 1, category: 'Test' };
            mockRepo.findById.mockReturnValue(product);
            mockRepo.updateStock.mockReturnValue(true);

            await inventoryService.adjustStock('p1', -5);

            expect(mockRepo.findById).toHaveBeenCalledWith('p1');
            expect(mockRepo.updateStock).toHaveBeenCalledWith('p1', -5, 1);
        });

        it('should throw error if product not found', async () => {
            mockRepo.findById.mockReturnValue(undefined);

            await expect(inventoryService.adjustStock('p1', -5)).rejects.toThrow('Product not found');
        });

        it('should throw error if insufficient stock', async () => {
            const product = { id: 'p1', sku: 'SKU1', name: 'Product 1', stock_level: 2, price: 100, version: 1, category: 'Test' };
            mockRepo.findById.mockReturnValue(product);

            await expect(inventoryService.adjustStock('p1', -5)).rejects.toThrow('Insufficient stock');
        });

        it('should throw error on concurrency conflict', async () => {
            const product = { id: 'p1', sku: 'SKU1', name: 'Product 1', stock_level: 10, price: 100, version: 1, category: 'Test' };
            mockRepo.findById.mockReturnValue(product);
            mockRepo.updateStock.mockReturnValue(false); // Simulate failed update due to version mismatch

            await expect(inventoryService.adjustStock('p1', -5)).rejects.toThrow('Concurrency conflict');
        });
    });
});
