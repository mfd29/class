"""Numerical contract for the register-backed single-head INT8 baseline.

All matmuls use NumPy int64. Arithmetic shifts floor negative values; saturate
only at stage boundaries. No bias, residual, layer norm, mask or output projection.
"""
import math
import numpy as np

def sat(value, shift):
    return np.clip(np.asarray(value, dtype=np.int64) >> shift, -128, 127).astype(np.int64)

def softmax(logits):
    delta = logits.max(axis=1, keepdims=True) - logits
    exp = np.floor(np.exp(-delta.astype(np.float64)/16)*65536+0.5).astype(np.int64)
    denominator = exp.sum(axis=1, keepdims=True)
    assert np.all(denominator > 0)
    return exp*32768 // denominator

def evaluate(inputs, d, proj_shift=4, score_shift=4, ff_shift=4):
    x, wq, wk, wv, w1, w2 = inputs
    q, k, v = [sat(x @ w, proj_shift) for w in (wq, wk, wv)]
    # Fixed-point approximation to 1/sqrt(D), denominator 2**9.
    scale = int(math.floor(512/math.sqrt(d)+0.5))
    score = sat((q @ k.T)*scale, 9+score_shift)
    p = softmax(score)
    context = sat(p @ v, 15)
    hidden = np.maximum(sat(context @ w1, ff_shift), 0)
    out = sat(hidden @ w2, ff_shift)
    return [out, q, k, v, score, p, context, hidden]

def make_inputs(n, d, f, kind, seed):
    rng = np.random.default_rng(seed)
    shapes = [(n,d), (d,d), (d,d), (d,d), (d,f), (f,d)]
    if kind == "zero":
        return [np.zeros(s, dtype=np.int64) for s in shapes]
    if kind == "extreme":
        return [rng.choice([-128,127], size=s).astype(np.int64) for s in shapes]
    if kind == "identity":
        x = rng.integers(-32,33,size=(n,d),dtype=np.int64)
        return [x, *[np.eye(d,dtype=np.int64)*16 for _ in range(3)],
                np.eye(d,f,dtype=np.int64)*16, np.eye(f,d,dtype=np.int64)*16]
    return [rng.integers(-16,17,size=s,dtype=np.int64) for s in shapes]

def self_test():
    assert sat(np.array([-2049,-2048,-1,0,2032,2048]),4).tolist() == [-128,-128,-1,0,127,127]
    worst = 0.0
    for n in (1,3,4,8,64):
        rng = np.random.default_rng(n)
        logits = np.vstack([np.full((1,n),-128),np.full((1,n),127),
                            rng.integers(-128,128,size=(256,n))])
        p = softmax(logits)
        ex = np.exp((logits-logits.max(axis=1,keepdims=True))/16)
        ref = ex/ex.sum(axis=1,keepdims=True)
        error = float(np.max(np.abs(p/32768-ref)))
        worst = max(worst,error)
        assert error < 0.002
        assert np.all(p.sum(axis=1) <= 32768)
        assert np.all(p.sum(axis=1) > 32768-n-16)
    return {"softmax_max_absolute_error":worst,"softmax_float_test_rows":1290}

if __name__ == "__main__":
    print(self_test())
