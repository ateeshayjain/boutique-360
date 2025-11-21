import db from '../db';
import { User } from '../models/User';

export class UserRepository {
    findByUsername(username: string): User | undefined {
        const stmt = db.prepare('SELECT * FROM users WHERE username = ?');
        return stmt.get(username) as User | undefined;
    }

    create(user: User): void {
        const stmt = db.prepare(`
      INSERT INTO users (id, username, password_hash, role)
      VALUES (@id, @username, @passwordHash, @role)
    `);
        stmt.run({
            id: user.id,
            username: user.username,
            passwordHash: user.password_hash,
            role: user.role
        });
    }
}
