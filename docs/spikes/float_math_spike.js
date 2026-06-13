#!/usr/bin/env node

const f32 = (value) => new Float32Array([value])[0];

const bezierCases = [
  { name: "ease", c: [0.25, 0.1, 0.25, 1.0] },
  { name: "ease-in-out", c: [0.42, 0.0, 0.58, 1.0] },
  { name: "crossing-slopes", c: [0.17, 0.67, 0.83, 0.33] },
];

const ikCases = [
  { name: "reachable", v: [100, 70, 80, 50] },
  { name: "over-extended", v: [100, 70, 200, 0] },
  { name: "too-close", v: [100, 70, 5, 2] },
  { name: "mixed-quadrant", v: [23.75, 97.125, -42.5, 31.25] },
];

const pathCase = {
  name: "representative-cubic",
  p0: [0, 0],
  p1: [30.25, 80.5],
  p2: [90.75, -20.125],
  p3: [130.5, 40.25],
};

function cubicBezier(c1x, c1y, c2x, c2y, t, roundInputs) {
  if (roundInputs) {
    c1x = f32(c1x); c1y = f32(c1y); c2x = f32(c2x); c2y = f32(c2y); t = f32(t);
  }

  const bx = (s) => {
    const a = 1 - s;
    return 3 * a * a * s * c1x + 3 * a * s * s * c2x + s * s * s;
  };
  const by = (s) => {
    const a = 1 - s;
    return 3 * a * a * s * c1y + 3 * a * s * s * c2y + s * s * s;
  };
  const dbx = (s) => {
    const a = 1 - s;
    return 3 * a * a * c1x + 6 * a * s * (c2x - c1x) + 3 * s * s * (1 - c2x);
  };

  const samples = Array.from({ length: 16 }, (_, i) => bx(i / 15));
  let idx = 0;
  while (idx < 15 && !(samples[idx] <= t && t <= samples[idx + 1])) idx++;
  if (idx >= 15) idx = 14;

  const denom = samples[idx + 1] - samples[idx];
  let s = idx / 15 + (denom === 0 ? 0 : ((t - samples[idx]) / denom)) / 15;
  for (let i = 0; i < 2; i++) {
    const d = dbx(s);
    if (d !== 0) s -= (bx(s) - t) / d;
    s = Math.max(0, Math.min(1, s));
  }
  return by(s);
}

function twoBoneIk(l1, l2, tx, ty, roundInputs) {
  if (roundInputs) {
    l1 = f32(l1); l2 = f32(l2); tx = f32(tx); ty = f32(ty);
  }
  const d = Math.hypot(tx, ty);
  const cos2 = Math.max(-1, Math.min(1, (d * d - l1 * l1 - l2 * l2) / (2 * l1 * l2)));
  const a2 = Math.acos(cos2);
  const k1 = l1 + l2 * Math.cos(a2);
  const k2 = l2 * Math.sin(a2);
  const a1 = Math.atan2(ty, tx) - Math.atan2(k2, k1);
  const ex = l1 * Math.cos(a1) + l2 * Math.cos(a1 + a2);
  const ey = l1 * Math.sin(a1) + l2 * Math.sin(a1 + a2);
  return [ex, ey, a1, a2];
}

function pathPoint(p0, p1, p2, p3, u, roundInputs) {
  if (roundInputs) {
    p0 = p0.map(f32); p1 = p1.map(f32); p2 = p2.map(f32); p3 = p3.map(f32); u = f32(u);
  }
  const a = 1 - u;
  const w0 = a * a * a;
  const w1 = 3 * a * a * u;
  const w2 = 3 * a * u * u;
  const w3 = u * u * u;
  return [
    w0 * p0[0] + w1 * p1[0] + w2 * p2[0] + w3 * p3[0],
    w0 * p0[1] + w1 * p1[1] + w2 * p2[1] + w3 * p3[1],
  ];
}

let maxBezierDrift = 0;
for (const testCase of bezierCases) {
  for (let i = 0; i <= 100; i++) {
    const t = i / 100;
    const expected = f32(cubicBezier(...testCase.c, t, false));
    const actual = f32(cubicBezier(...testCase.c, t, true));
    maxBezierDrift = Math.max(maxBezierDrift, Math.abs(expected - actual));
  }
}

let maxIkComponentDrift = 0;
for (const testCase of ikCases) {
  const expected = twoBoneIk(...testCase.v, false).map(f32);
  const actual = twoBoneIk(...testCase.v, true).map(f32);
  for (let i = 0; i < expected.length; i++) {
    maxIkComponentDrift = Math.max(maxIkComponentDrift, Math.abs(expected[i] - actual[i]));
  }
}

let maxPathComponentDrift = 0;
for (let i = 0; i <= 100; i++) {
  const u = i / 100;
  const expected = pathPoint(pathCase.p0, pathCase.p1, pathCase.p2, pathCase.p3, u, false).map(f32);
  const actual = pathPoint(pathCase.p0, pathCase.p1, pathCase.p2, pathCase.p3, u, true).map(f32);
  maxPathComponentDrift = Math.max(
    maxPathComponentDrift,
    Math.abs(expected[0] - actual[0]),
    Math.abs(expected[1] - actual[1]),
  );
}

const result = {
  runtime: "node",
  comparison: "f64-style inputs vs f32-quantized loaded inputs, f32-rounded outputs",
  tolerance: 1e-4,
  samplesPerCurve: 101,
  bezierCases,
  ikCases,
  pathCase,
  maxBezierDrift,
  maxIkComponentDrift,
  maxPathComponentDrift,
  pass: maxBezierDrift <= 1e-4 && maxIkComponentDrift <= 1e-4 && maxPathComponentDrift <= 1e-4,
};

console.log(JSON.stringify(result, null, 2));
