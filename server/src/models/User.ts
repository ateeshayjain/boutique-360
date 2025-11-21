export interface User {
    id: string;
    username: string;
    password_hash: string;
    role: 'admin' | 'user';
    created_at?: string;
}
