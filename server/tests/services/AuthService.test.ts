import { AuthService } from '../../src/services/AuthService';
import { UserRepository } from '../../src/repositories/UserRepository';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

// Mock dependencies
jest.mock('../../src/repositories/UserRepository');
jest.mock('bcrypt');
jest.mock('jsonwebtoken');

describe('AuthService', () => {
    let authService: AuthService;
    let mockUserRepo: jest.Mocked<UserRepository>;

    beforeEach(() => {
        // Clear all mocks
        jest.clearAllMocks();

        // Setup mock repository
        mockUserRepo = new UserRepository() as jest.Mocked<UserRepository>;

        // Inject mock repo into service (we need to cast to any or modify service to accept repo in constructor)
        // Since we didn't use dependency injection in the original code, we'll mock the prototype or use a slightly different approach.
        // Ideally, we should refactor AuthService to accept UserRepository in constructor.
        // For now, let's mock the module implementation of UserRepository.
        (UserRepository as jest.Mock).mockImplementation(() => mockUserRepo);

        authService = new AuthService();
    });

    describe('register', () => {
        it('should register a new user successfully', async () => {
            const username = 'testuser';
            const password = 'password123';
            const hashedPassword = 'hashedPassword';

            mockUserRepo.findByUsername.mockReturnValue(undefined);
            (bcrypt.hash as jest.Mock).mockResolvedValue(hashedPassword);

            const result = await authService.register(username, password);

            expect(mockUserRepo.findByUsername).toHaveBeenCalledWith(username);
            expect(bcrypt.hash).toHaveBeenCalledWith(password, 10);
            expect(mockUserRepo.create).toHaveBeenCalledWith(expect.objectContaining({
                username,
                password_hash: hashedPassword,
                role: 'user'
            }));
            expect(result).toEqual(expect.objectContaining({
                username,
                role: 'user'
            }));
        });

        it('should throw error if username already exists', async () => {
            mockUserRepo.findByUsername.mockReturnValue({ id: '1', username: 'testuser', password_hash: 'hash', role: 'user' });

            await expect(authService.register('testuser', 'password')).rejects.toThrow('Username already exists');
        });
    });

    describe('login', () => {
        it('should login successfully with correct credentials', async () => {
            const username = 'testuser';
            const password = 'password123';
            const user = { id: '1', username, password_hash: 'hashedPassword', role: 'user' as const };
            const token = 'jwt-token';

            mockUserRepo.findByUsername.mockReturnValue(user);
            (bcrypt.compare as jest.Mock).mockResolvedValue(true);
            (jwt.sign as jest.Mock).mockReturnValue(token);

            const result = await authService.login(username, password);

            expect(result).toEqual({
                token,
                user: { id: '1', username, role: 'user' }
            });
        });

        it('should throw error for invalid username', async () => {
            mockUserRepo.findByUsername.mockReturnValue(undefined);

            await expect(authService.login('wronguser', 'password')).rejects.toThrow('Invalid credentials');
        });

        it('should throw error for invalid password', async () => {
            const user = { id: '1', username: 'testuser', password_hash: 'hashedPassword', role: 'user' as const };
            mockUserRepo.findByUsername.mockReturnValue(user);
            (bcrypt.compare as jest.Mock).mockResolvedValue(false);

            await expect(authService.login('testuser', 'wrongpassword')).rejects.toThrow('Invalid credentials');
        });
    });
});
