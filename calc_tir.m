function r = calc_tir(cf)
% TIR por bisseção sobre o VPL(r) — robusta e sem toolboxes.
    f = @(r) sum(cf ./ (1 + r).^(0:numel(cf)-1)');
    lo = -0.5; hi = 1.0;
    if f(lo)*f(hi) > 0, r = NaN; return; end
    for it = 1:200
        mid = (lo + hi)/2;
        if f(lo)*f(mid) <= 0, hi = mid; else, lo = mid; end
    end
    r = (lo + hi)/2;
end
