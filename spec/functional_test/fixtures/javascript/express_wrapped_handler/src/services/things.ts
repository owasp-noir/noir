export class ThingsService {
	accountability: any;

	constructor(options: any) {
		this.accountability = options.accountability;
	}

	async readPublic(id: string) {
		return { id };
	}

	async readMine(id: string) {
		if (!this.accountability?.user) throw new Error('Forbidden');
		return { id, owner: this.accountability.user };
	}
}
