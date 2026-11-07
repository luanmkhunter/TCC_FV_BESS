%% rodar_simulacao_diaria.m
% Executa o modelo Simulink por 24 h (86.400 s) e plota a operação
% diária do sistema (potências e SOC).
%
% Funciona com:
%   TCC_FV_BESS_R2023.slx  — criado por montar_modelo_TCC (R2020a+)
%   TCC_FV_BESS.slx        — variante chaveada, se estiver na pasta
%
% Uso:
%   >> cd TCC_FV_BESS             % pasta do repositório
%   >> cenario = 'residencial';   % ou 'industrial'
%   >> rodar_simulacao_diaria

clearvars -except cenario
if ~exist('cenario','var'), cenario = 'residencial'; end

addpath(pwd);
setup_TCC_FV_BESS;                 % injeta params/perfis no workspace

% escolhe o modelo disponível/compatível
if exist('TCC_FV_BESS_R2023.slx','file')
    mdl = 'TCC_FV_BESS_R2023';
elseif exist('../TCC_FV_BESS.slx','file') || exist('TCC_FV_BESS.slx','file')
    mdl = 'TCC_FV_BESS';
else
    error(['Nenhum modelo encontrado. Rode montar_modelo_TCC para criar o ' ...
           'TCC_FV_BESS_R2023.slx nesta pasta.']);
end
if ~bdIsLoaded(mdl), load_system(mdl); end
set_param(mdl,'Solver','ode23tb','RelTol','1e-3','AbsTol','1e-4', ...
              'StopTime','86400');

fprintf('Simulando %s (24 h, ode23tb)...\n', mdl);
out = sim(mdl, 'ReturnWorkspaceOutputs', 'on');
fprintf('Simulação concluída.\n');

%% ---------------------------------------------------------------- plots
S   = out.P_FV_sim;                    % Structure With Time
t_h = S.time/3600;
Y   = squeeze(S.signals.values);       % N x 5 (ou 5 x N)
if size(Y,1) == 5 && size(Y,2) ~= 5, Y = Y.'; end
if size(Y,2) >= 5
    P_fv  = Y(:,1)/1e3;  P_ld = Y(:,2)/1e3;  P_bat = Y(:,3)/1e3;
    SOC   = Y(:,4);      P_gr = Y(:,5)/1e3;
else                                    % modelo antigo: apenas P_FV
    P_fv = Y(:,1)/1e3;
    pl = evalin('base','P_load_ts');
    P_ld = interp1(pl.Time/3600, pl.Data/1e3, t_h, 'linear', 0);
    P_bat = nan(size(P_fv)); SOC = nan(size(P_fv)); P_gr = nan(size(P_fv));
end

figure('Name',sprintf('Operação diária — %s',cenario),'Color','w', ...
       'Position',[90 60 900 640]);
subplot(2,1,1); hold on; grid on
area(t_h, P_fv, 'FaceColor',[.96 .75 .48], 'EdgeColor','none');
plot(t_h, P_ld, 'Color',[.24 .35 .50], 'LineWidth',1.4);
plot(t_h, max(P_gr,0), 'Color',[.65 .24 .25], 'LineWidth',1.1);
plot(t_h, -P_bat, 'Color',[.18 .55 .34], 'LineWidth',1.3);
plot(t_h, min(P_gr,0), '--', 'Color',[.56 .72 .66], 'LineWidth',1.0);
yline(0,'k');
legend('P_{FV}','P_{carga}','P_{rede,imp}','P_{bat} (- = carga)', ...
       'P_{rede,exp}','Location','best');
ylabel('Potência [kW]'); xlim([0 24]);
title(sprintf('Operação diária — cenário %s', cenario));
subplot(2,1,2); hold on; grid on
plot(t_h, SOC, 'Color',[.48 .18 .55], 'LineWidth',1.5);
yline(20,':r','SOC_{min}'); yline(90,':g','SOC_{max}');
ylim([0 100]); xlim([0 24]);
ylabel('SOC [%]'); xlabel('Hora do dia');

if ~exist('figuras','dir'), mkdir('figuras'); end
exportgraphics(gcf, sprintf('figuras/fig_operacao_diaria_%s.png', ...
               cenario), 'Resolution', 300);
fprintf(['Figura salva em figuras/. Para os indicadores anuais ' ...
         '(TABELA 04):\n   >> balanco_anual\n']);
