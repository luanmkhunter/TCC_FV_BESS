function I = pv_model_newton_raphson(V, G, T, params) %#codegen
%PV_MODEL_NEWTON_RAPHSON  Corrente do módulo FV — modelo de um diodo.
%   I = pv_model_newton_raphson(V,G,T,params)
%
%   Resolve a equação implícita do modelo de um diodo (Villalva et al.,
%   2009; Sera et al., 2007) pelo método de Newton-Raphson com quatro
%   salvaguardas numéricas:
%     1) clip do argumento da exponencial em [-50, +50];
%     2) limites físicos: 0 <= I <= Isc(G,T);
%     3) chute inicial I0 = Iph (curto-circuito);
%     4) teto de 100 iterações.
%
%   Projetada para uso no bloco MATLAB Function que comanda a
%   Controlled Current Source do subsistema SolarPlant (passo médio
%   10-100 us vs ~1 us do bloco PV Array padrão — MathWorks, 2023).

k  = 1.380649e-23;          % constante de Boltzmann [J/K]
q  = 1.602176634e-19;       % carga elementar [C]
Tk = T + 273.15;            % temperatura absoluta [K]

% Eq. (06) — tensão térmica
Vt  = params.Ns * params.a * k * Tk / q;

% Eq. (05) — fotocorrente
Iph = (params.Isc + params.Ki*(T-25)) * (G/1000);

% Eq. (07) — corrente de saturação reversa (Shockley)
Irs = (params.Isc + params.Ki*(T-25)) / ...
      (exp((params.Voc + params.Kv*(T-25))/Vt) - 1);

% Newton-Raphson — Eqs. (09)-(11)
I = Iph;                                          % salvaguarda 3
for n = 1:100                                     % salvaguarda 4
    arg = max(min((V + I*params.Rs)/Vt, 50), -50);% salvaguarda 1
    e   = exp(arg);
    f   = Iph - Irs*(e-1) - (V + I*params.Rs)/params.Rsh - I;   % Eq. (09)
    df  = -Irs*(params.Rs/Vt)*e - params.Rs/params.Rsh - 1;     % Eq. (10)
    I_new = I - f/df;                                            % Eq. (11)
    if abs(I_new - I) < 1e-6
        I = I_new;
        break;
    end
    I = I_new;
end

% Salvaguarda 2 — limites físicos escalados pela irradiância
I = max(0, min(I, (params.Isc + params.Ki*(T-25))*(G/1000)));
end
