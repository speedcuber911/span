/**
 * VOICE grounding tests — the non-LLM guardrails (no DB / no creds needed).
 *
 *  - intentRouter flags an emergency phrase and hard-escalates.
 *  - groundingGuard refuses a number not in the context, allows one that is.
 */

import { describe, it, expect } from 'vitest';
import {
  intentRouter,
  groundingGuard,
  renderContextBlock,
  EMERGENCY_SCRIPT,
} from '../grounding.js';
import type { GroundedContext, GroundedSource } from '../types.js';

function ctxOf(sources: GroundedSource[]): GroundedContext {
  return { userId: 'u1', sources, contextBlock: renderContextBlock(sources) };
}

const HBA1C: GroundedSource = {
  parameter: 'HbA1c',
  value: 5.4,
  unit: '%',
  refLow: 4.0,
  refHigh: 5.6,
  flag: 'Normal',
  date: '2026-05-01',
  lab: 'Tata 1mg',
};

describe('intentRouter', () => {
  it('hard-escalates an explicit emergency phrase', () => {
    const r = intentRouter('I have severe chest pain and cannot breathe');
    expect(r.intent).toBe('EMERGENCY');
    expect(r.hardEscalate).toBe(true);
  });

  it('hard-escalates self-harm phrasing', () => {
    const r = intentRouter('i want to die');
    expect(r.intent).toBe('EMERGENCY');
    expect(r.hardEscalate).toBe(true);
  });

  it('classifies a data-lookup question', () => {
    const r = intentRouter('what is my latest HbA1c level?');
    expect(r.intent).toBe('data-lookup');
    expect(r.hardEscalate).toBe(false);
  });

  it('classifies an onboarding statement', () => {
    const r = intentRouter('my height is 175 cm');
    expect(r.intent).toBe('onboarding');
    expect(r.hardEscalate).toBe(false);
  });

  it('falls back to smalltalk', () => {
    const r = intentRouter('hello there, how are you today');
    expect(r.intent).toBe('smalltalk');
    expect(r.hardEscalate).toBe(false);
  });

  it('emergency outranks a data-lookup in the same utterance', () => {
    const r = intentRouter('what is my cholesterol — also I am having a heart attack');
    expect(r.intent).toBe('EMERGENCY');
    expect(r.hardEscalate).toBe(true);
    expect(EMERGENCY_SCRIPT).toMatch(/emergency/i);
  });
});

describe('groundingGuard', () => {
  const ctx = ctxOf([HBA1C]);

  it('allows an answer whose number is present in the context', () => {
    const g = groundingGuard('Your HbA1c was 5.4 percent on 2026-05-01.', ctx);
    expect(g.allowed).toBe(true);
    expect(g.ungroundedNumbers).toHaveLength(0);
    expect(g.safeText).toContain('5.4');
  });

  it('allows a reference-bound number that is in the context', () => {
    const g = groundingGuard('That sits inside the 4 to 5.6 reference range.', ctx);
    expect(g.allowed).toBe(true);
  });

  it('refuses a number that is NOT in the context', () => {
    const g = groundingGuard('Your HbA1c was 9.9 percent.', ctx);
    expect(g.allowed).toBe(false);
    expect(g.ungroundedNumbers).toContain('9.9');
    expect(g.safeText).toMatch(/clinician/i);
  });

  it('refuses a fabricated number even alongside a real one', () => {
    const g = groundingGuard('Your HbA1c 5.4 suggests an eGFR of 88.', ctx);
    expect(g.allowed).toBe(false);
    expect(g.ungroundedNumbers).toContain('88');
  });

  it('treats trailing-zero forms as equal (5.4 vs 5.40)', () => {
    const g = groundingGuard('It was 5.40 percent.', ctx);
    expect(g.allowed).toBe(true);
  });

  it('allows a purely qualitative answer with no numbers', () => {
    const g = groundingGuard(
      'Your latest reading is in the normal range. Discuss with your clinician.',
      ctx,
    );
    expect(g.allowed).toBe(true);
  });
});

describe('renderContextBlock', () => {
  it('renders only value/unit/ref/flag/date/lab', () => {
    const block = renderContextBlock([HBA1C]);
    expect(block).toContain('HbA1c');
    expect(block).toContain('5.4');
    expect(block).toContain('%');
    expect(block).toContain('4–5.6');
    expect(block).toContain('Normal');
    expect(block).toContain('2026-05-01');
    expect(block).toContain('Tata 1mg');
  });

  it('handles an empty context', () => {
    const block = renderContextBlock([]);
    expect(block).toMatch(/empty/i);
  });
});
