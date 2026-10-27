import { Server } from 'socket.io';
import type { Engine } from './engine';

let _io: Server | null = null;
let _engine: Engine | null = null;
export const setIO = (s: Server) => { _io = s; };
export const setEngine = (e: Engine) => { _engine = e; };
export const getEngine = () => _engine;

export function notifyUser(userId: number, data: { balance?: number; text?: string }) {
  _io?.to(`user:${userId}`).emit('balance', data);
}