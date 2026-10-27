import { Pool } from 'pg';
import { cfg } from '../config';
export const pool = new Pool({ connectionString: cfg.db });