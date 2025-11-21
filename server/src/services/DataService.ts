import { DataRepository } from '../repositories/DataRepository';

export class DataService {
    private repo: DataRepository;

    constructor() {
        this.repo = new DataRepository();
    }

    getInvoices() {
        return this.repo.getInvoices();
    }

    getRawMaterials() {
        return this.repo.getRawMaterials();
    }

    getStaff() {
        return this.repo.getStaff();
    }

    getJobCards() {
        return this.repo.getJobCards();
    }

    getExpenses() {
        return this.repo.getExpenses();
    }
}
