import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { UserRepository } from '../repositories/UserRepository';
import { User } from '../models/User';

const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET) {
    throw new Error('JWT_SECRET environment variable is not set.');
}

const SECRET_KEY = JWT_SECRET;

export class AuthService {
    private userRepo: UserRepository;

    constructor() {
        this.userRepo = new UserRepository();
    }

    async register(username: string, password: string): Promise<User> {
        const existing = this.userRepo.findByUsername(username);
        if (existing) {
            throw new Error('Username already exists');
        }

        const hashedPassword = await bcrypt.hash(password, 10);
        const newUser: User = {
            id: uuidv4(),
            username,
            password_hash: hashedPassword,
            role: 'user'
        };

        this.userRepo.create(newUser);
        return newUser;
    }

    async login(username: string, password: string): Promise<{ token: string, user: Omit<User, 'password_hash'> }> {
        const user = this.userRepo.findByUsername(username);
        if (!user) {
            throw new Error('Invalid credentials');
        }

        const isValid = await bcrypt.compare(password, user.password_hash);
        if (!isValid) {
            throw new Error('Invalid credentials');
        }

        const token = jwt.sign(
            { id: user.id, username: user.username, role: user.role },
            SECRET_KEY,
            { expiresIn: '1h' }
        );

        const { password_hash, ...userWithoutPassword } = user;
        return { token, user: userWithoutPassword };
    }
}
