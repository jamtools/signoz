import { AlertDef } from './def';

export interface Filters {
	[k: string]: string[];
}

export interface GetTimelineTableRequestProps {
	id: AlertDef['id'];
	start: number;
	end: number;
	offset: number;
	limit: number;
	order: string;
	filters?: Filters;
}
