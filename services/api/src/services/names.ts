import { randomInt } from 'node:crypto';

const ADJ = ['Swift', 'Quiet', 'Bright', 'Clever', 'Steady', 'Lucky', 'Nimble', 'Brave', 'Calm', 'Sunny', 'Witty', 'Cosmic'];
const NOUN = ['Crate', 'Belt', 'Gear', 'Parcel', 'Loop', 'Lever', 'Sprocket', 'Pallet', 'Robot', 'Widget', 'Bolt', 'Cog'];

export function guestName(): string {
  return `${ADJ[randomInt(ADJ.length)]} ${NOUN[randomInt(NOUN.length)]} ${randomInt(100, 1000)}`;
}

// Minimal blocklist for public leaderboard names; extend via remote moderation tooling later.
const BLOCK = ['admin', 'moderator', 'fuck', 'shit', 'bitch', 'nazi', 'chutiya', 'madarchod', 'bhenchod'];
export function isNameAllowed(name: string): boolean {
  const n = name.toLowerCase().replace(/[^a-z]/g, '');
  return !BLOCK.some((b) => n.includes(b));
}
