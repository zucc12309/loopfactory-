import { describe, expect, it } from 'vitest';
import { EAST, NORTH, SOUTH, WEST, bit, rotateMask } from '../src/directions';
import { connectionMask, inputMask, isRotatable, outputMask, rotationCost } from '../src/tiles';

describe('connection masks', () => {
  it('rotates masks clockwise', () => {
    expect(rotateMask(bit(NORTH), 1)).toBe(bit(EAST));
    expect(rotateMask(bit(WEST), 1)).toBe(bit(NORTH));
    expect(rotateMask(0b0011, 3)).toBe(bit(WEST) | bit(NORTH));
    expect(rotateMask(0b0101, 2)).toBe(0b0101);
    expect(rotateMask(0b0111, -1)).toBe(rotateMask(0b0111, 3));
  });
  it('defines base tile masks', () => {
    expect(connectionMask({ t: 'straight', r: 0 })).toBe(bit(NORTH) | bit(SOUTH));
    expect(connectionMask({ t: 'straight', r: 1 })).toBe(bit(EAST) | bit(WEST));
    expect(connectionMask({ t: 'corner', r: 0 })).toBe(bit(NORTH) | bit(EAST));
    expect(connectionMask({ t: 'corner', r: 2 })).toBe(bit(SOUTH) | bit(WEST));
    expect(connectionMask({ t: 'tee', r: 1 })).toBe(bit(EAST) | bit(SOUTH) | bit(WEST));
    expect(connectionMask({ t: 'cross', r: 0 })).toBe(15);
    expect(connectionMask({ t: 'empty', r: 0 })).toBe(0);
  });
  it('sources only emit and destinations only accept', () => {
    expect(inputMask({ t: 'source', r: 2 })).toBe(0);
    expect(outputMask({ t: 'source', r: 2 })).toBe(bit(SOUTH));
    expect(inputMask({ t: 'dest', r: 0 })).toBe(15);
    expect(outputMask({ t: 'dest', r: 0 })).toBe(0);
  });
  it('knows which tiles rotate', () => {
    expect(isRotatable({ t: 'corner', r: 0 })).toBe(true);
    expect(isRotatable({ t: 'corner', r: 0, l: true })).toBe(false);
    expect(isRotatable({ t: 'cross', r: 0 })).toBe(false);
    expect(isRotatable({ t: 'source', r: 0 })).toBe(false);
    expect(isRotatable({ t: 'blocked', r: 0 })).toBe(false);
  });
  it('computes rotation cost with both directions and symmetry', () => {
    expect(rotationCost({ t: 'corner', r: 0 }, 0, 3)).toBe(1);
    expect(rotationCost({ t: 'corner', r: 0 }, 0, 2)).toBe(2);
    expect(rotationCost({ t: 'straight', r: 0 }, 0, 2)).toBe(0);
    expect(rotationCost({ t: 'straight', r: 0 }, 1, 0)).toBe(1);
    expect(rotationCost({ t: 'straight', r: 0 }, 3, 2)).toBe(1);
    expect(rotationCost({ t: 'tee', r: 0 }, 1, 1)).toBe(0);
  });
});
