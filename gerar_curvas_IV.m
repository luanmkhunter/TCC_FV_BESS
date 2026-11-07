%% gerar_curvas_IV.m
% Levanta as curvas I-V e P-V do módulo (modelo de um diodo resolvido
% por Newton-Raphson) e valida o ponto de máxima potência em STC.
% Gera as FIGURAS 07 e 08 do TCC em figuras/ (300 dpi).
%
% Uso:
%   >> cenario = 'residencial';  setup_TCC_FV_BESS;  gerar_curvas_IV

if ~exist('params','var')
    if evalin('base','exist(''params'',''var'')')
        params = evalin('base','params');
    else
        error('Rode setup_TCC_FV_BESS antes.');
    end
end
if ~exist('../figuras','dir'), mkdir('../figuras'); end

V = linspace(0, params.Voc*1.05, 400);

%% ------------------------------------ FIGURA 07 — variação de irradiância
f1 = figure('Color','w','Position',[80 80 1000 380]);
Gs = 200:200:1000;
subplot(1,2,1); hold on; grid on
for G = Gs
    I = arrayfun(@(v) pv_model_newton_raphson(v, G, 25, params), V);
    plot(V, I, 'LineWidth', 1.1, 'DisplayName', sprintf('%d W/m²', G));
end
xlabel('Tensão (V)'); ylabel('Corrente (A)');
title('Curva I-V — Variação de Irradiância (T=25°C)'); legend('Location','best');
subplot(1,2,2); hold on; grid on
for G = Gs
    I = arrayfun(@(v) pv_model_newton_raphson(v, G, 25, params), V);
    plot(V, V.*I, 'LineWidth', 1.1, 'DisplayName', sprintf('%d W/m²', G));
end
xlabel('Tensão (V)'); ylabel('Potência (W)');
title('Curva P-V — Variação de Irradiância (T=25°C)'); legend('Location','best');
exportgraphics(f1, '../figuras/fig07_curvas_irradiancia.png', 'Resolution', 300);

%% ---------------------------------- FIGURA 08 — variação de temperatura
f2 = figure('Color','w','Position',[120 120 640 400]); hold on; grid on
for T = [25 50 75]
    I = arrayfun(@(v) pv_model_newton_raphson(v, 1000, T, params), V);
    plot(V, I, 'LineWidth', 1.2, 'DisplayName', sprintf('T=%d°C', T));
end
xlabel('Tensão (V)'); ylabel('Corrente (A)');
title('Curva I-V — Variação de Temperatura (G=1000 W/m²)');
legend('Location','best');
exportgraphics(f2, '../figuras/fig08_curvas_temperatura.png', 'Resolution', 300);

%% -------------------------------------------- validação STC (Eq. 11)
Vf = linspace(0, params.Voc, 2000);
P  = Vf .* arrayfun(@(v) pv_model_newton_raphson(v, 1000, 25, params), Vf);
[Pmax, im] = max(P);
fprintf('=== VALIDAÇÃO DO MODELO (STC: 1000 W/m², 25 °C) ===\n');
fprintf('Pmax calculado: %7.2f W  | Vmp: %6.2f V | Imp: %5.2f A\n', ...
        Pmax, Vf(im), Pmax/Vf(im));
fprintf(['Compare com a ficha técnica do módulo adotado e reporte o erro\n' ...
         'percentual no texto (Eq. 11: P_max,calc = P_max,datasheet).\n' ...
         'Se o erro exceder 1%%, ajuste Rs/Rsh (Sera et al., 2007).\n']);
