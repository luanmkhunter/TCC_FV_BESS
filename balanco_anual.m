%% balanco_anual.m
% Simulador de balanço energético horário (8.760 h) — TCC FV+BESS
% Reproduz os indicadores técnicos e econômicos da TABELA 05 do TCC e
% gera as figuras do Capítulo 4 (operação diária, balanço mensal e
% fluxo de caixa acumulado) para os dois cenários.
%
% Uso:
%   >> balanco_anual
%
% Notas:
% - Mesmas equações das Seções 3.3.3 a 3.3.10 do TCC, em passo horário.
% - rng(42) fixa o ruído gaussiano: resultados determinísticos.
% - Pequenas diferenças (<1-2%) em relação aos valores publicados podem
%   ocorrer entre versões do MATLAB (gerador de números aleatórios).

clear; clc; close all;

cenarios = {'residencial','industrial'};
RES = struct();

for ic = 1:2
    cen = cenarios{ic};
    rng(42);                            % determinístico por cenário

    %% ------------------------------------------------------ parâmetros
    switch cen
        case 'residencial'
            P_fv_kwp  = 5;    E_bess = 10;   E_dia = 20;
            tarifa = 0.95;    tar_inj = 0.45; tar_dem = 0;
            tx = 0.10;        capex_fv_u = 3500; capex_bess_u = 2800;
            opex_pct = 0.010;
        case 'industrial'
            P_fv_kwp  = 100;  E_bess = 200;  E_dia = 1000;
            tarifa = 0.65;    tar_inj = 0.32; tar_dem = 55;
            tx = 0.12;        capex_fv_u = 3000; capex_bess_u = 2500;
            opex_pct = 0.015;
    end
    eta_c = 0.96; eta_d = 0.96;
    eta_conv = 0.98; eta_inv = 0.97;
    SOC_min = 0.20; SOC_max = 0.90;
    P_max_c = 0.5*E_bess;  P_max_d = 0.5*E_bess;   % C/2 [kW]
    gamma_T = -0.004;                              % coef. potência [1/°C]
    NOCT = 45;

    %% -------------------------------------------- perfis anuais (8760 h)
    Nh = 8760; Nd = 365;
    dia  = repelem((1:Nd)', 24);
    hora = repmat((0:23)', Nd, 1);

    % Sazonalidade de irradiância (hemisfério sul): máx. em dezembro
    % Amplitude sazonal calibrada em 0,31 para reproduzir a razão
    % verão/inverno observada nos balanços mensais.
    saz = 1 + 0.31*cos(2*pi*(dia - 355)/365);

    % Índice de claridade diário (nebulosidade), truncado
    kt_dia = min(max(0.71 + 0.18*randn(Nd,1), 0.25), 1.0);
    kt = repelem(kt_dia, 24);

    % Irradiância horária: senoide truncada 6h-18h, pico 1000 W/m²
    G = 1000 * sin(pi*(hora - 6)/12);
    G(hora < 6 | hora >= 18) = 0;
    G = max(G .* saz .* kt, 0);

    % Temperatura ambiente e de célula (NOCT)
    T_amb = 22 + 6*cos(2*pi*(dia - 20)/365) + 6*sin(pi*(hora - 9)/12);
    T_cel = T_amb + (NOCT - 20)/800 .* G;

    % Potência FV (Eq. 1 — Seção 3.3.1) [kW]
    P_fv = P_fv_kwp .* (G/1000) .* (1 + gamma_T*(T_cel - 25)) ...
           .* eta_conv .* eta_inv;
    P_fv = max(P_fv, 0);

    % Carga [kW]
    if strcmp(cen,'residencial')
        base  = 0.35*ones(Nh,1);
        pico1 = 1.8*exp(-((hora - 7).^2)/1.2);
        pico2 = 2.3*exp(-((hora - 19.5).^2)/2.0);
        meiod = 0.9*exp(-((hora - 12.5).^2)/4.0);   % componente de meio-dia
        P_ld  = base + pico1 + pico2 + meiod;
        P_ld  = P_ld .* (1 + 0.03*randn(Nh,1));
        P_ld  = P_ld * (E_dia*Nd / sum(P_ld));       % normalização anual
    else
        dow = mod(dia - 1, 7);                       % 0..6 (0-4 úteis)
        fds = (dow >= 5);
        base   = 17*ones(Nh,1);
        diurno = 60*(hora >= 7 & hora < 18) .* sin(pi*(hora - 7)/11);
        P_ld   = base + max(diurno, 0);
        P_ld(fds) = 0.55 * P_ld(fds);                % finais de semana: 55%
        P_ld   = P_ld .* (1 + 0.05*randn(Nh,1));
        % normalização pelo dia ÚTIL médio (consumo nominal em dia útil)
        fator  = E_dia / (sum(P_ld(~fds)) / (sum(~fds)/24));
        P_ld   = P_ld * fator;
    end
    P_ld = max(P_ld, 0);

    %% ------------------------------------ despacho EMS + SOC (Eq. 3/9)
    SOC   = zeros(Nh+1,1);  SOC(1) = 0.50;
    P_c   = zeros(Nh,1);  P_d = zeros(Nh,1);
    P_imp = zeros(Nh,1);  P_exp = zeros(Nh,1);
    dt = 1;                                          % [h]

    for k = 1:Nh
        saldo = P_fv(k) - P_ld(k);
        if saldo > 0
            % carrega até P_max_c e até o teto de SOC
            cab = (SOC_max - SOC(k)) * E_bess / (eta_c*dt);
            P_c(k)   = min([saldo, P_max_c, max(cab,0)]);
            P_exp(k) = saldo - P_c(k);
        else
            % descarrega até P_max_d e até o piso de SOC
            disp_ = (SOC(k) - SOC_min) * E_bess * eta_d / dt;
            P_d(k)   = min([-saldo, P_max_d, max(disp_,0)]);
            P_imp(k) = -saldo - P_d(k);
        end
        % Coulomb counting em base energética — eficiências separadas
        SOC(k+1) = SOC(k) + (eta_c*P_c(k)*dt)/E_bess ...
                          - (P_d(k)*dt)/(eta_d*E_bess);
        SOC(k+1) = min(max(SOC(k+1), SOC_min), SOC_max);
    end

    %% -------------------------------------------- indicadores técnicos
    E_fv  = sum(P_fv);   E_ld  = sum(P_ld);
    E_imp = sum(P_imp);  E_exp = sum(P_exp);
    E_d   = sum(P_d);    E_c   = sum(P_c);

    I_auto    = (E_fv - E_exp) / E_fv * 100;         % Seção 3.3.7
    I_autosuf = (E_ld - E_imp) / E_ld * 100;         % Seção 3.3.8
    eta_glob  = (E_ld - E_imp) / E_fv * 100;         % Eq. 24 (Seção 3.3.6)

    % Peak shaving (Seção 3.3.9) — pico médio mensal de demanda
    P_liq_sem = max(P_ld - P_fv, 0);                 % sem BESS (com FV)
    P_liq_com = P_imp;                                % com BESS
    mes = min(floor((dia - 1)/30.4167) + 1, 12);
    pico_sem = max(P_liq_sem);   % máximo anual de demanda líquida
    pico_com = max(P_liq_com);   % (métrica sensível a ruído — ver LEIA-ME)
    red_pico = (pico_sem - pico_com)/pico_sem * 100;

    % Referência SEM armazenamento (para H1)
    I_auto_sb    = sum(min(P_fv, P_ld)) / E_fv * 100;
    I_autosuf_sb = sum(min(P_fv, P_ld)) / E_ld * 100;

    %% ------------------------------------------ indicadores econômicos
    capex = capex_fv_u*P_fv_kwp + capex_bess_u*E_bess;
    opex  = opex_pct*capex;
    N = 25; troca = 12; degr = 0.005;

    fc = zeros(N,1);
    for a = 1:N
        f = (1 - degr)^(a-1);
        econ_energia = (E_ld - E_imp)*f * tarifa;    % autoconsumo evita tarifa
        rec_inj      = E_exp*f * tar_inj;            % compensação da injeção
        rec_dem      = 12 * tar_dem * (pico_sem - pico_com); % demanda evitada
        fc(a) = econ_energia + rec_inj + rec_dem - opex;
        if a == troca
            fc(a) = fc(a) - capex_bess_u*E_bess;     % troca do BESS
        end
    end
    econ1 = fc(1);
    acc = cumsum(fc) - capex;
    ipb = find(acc >= 0, 1);
    if isempty(ipb), payback = NaN;
    else
        prev = capex - sum(fc(1:ipb-1));
        payback = (ipb - 1) + prev/fc(ipb);
    end
    vpl = -capex + sum(fc ./ (1 + tx).^(1:N)');
    tir = calc_tir([-capex; fc]);
    E_desc = sum((E_ld - E_imp + E_exp) * (1 - degr).^(0:N-1)' ...
                 ./ (1 + tx).^(1:N)');
    custos = opex*ones(N,1);
    custos(troca) = custos(troca) + capex_bess_u*E_bess;
    C_desc = capex + sum(custos ./ (1 + tx).^(1:N)');
    lcoe = C_desc / E_desc;

    %% ------------------------------------------------------- impressão
    fprintf('\n================ CENÁRIO %s ================\n', upper(cen));
    fprintf('Geração FV total ............ %10.0f kWh/ano\n', E_fv);
    fprintf('Carga total ................. %10.0f kWh/ano\n', E_ld);
    fprintf('Importação da rede .......... %10.0f kWh/ano\n', E_imp);
    fprintf('Exportação para a rede ...... %10.0f kWh/ano\n', E_exp);
    fprintf('Energia descarregada BESS ... %10.0f kWh/ano\n', E_d);
    fprintf('Eficiência global ........... %10.1f %%\n', eta_glob);
    fprintf('Autoconsumo I_auto .......... %10.1f %%   (sem BESS: %.1f %%)\n', I_auto, I_auto_sb);
    fprintf('Autossuficiência I_autosuf .. %10.1f %%   (sem BESS: %.1f %%)\n', I_autosuf, I_autosuf_sb);
    fprintf('Pico sem BESS ............... %10.2f kW\n', pico_sem);
    fprintf('Pico com BESS ............... %10.2f kW\n', pico_com);
    fprintf('Redução de pico ............. %10.1f %%\n', red_pico);
    fprintf('CAPEX total ................. R$ %12.2f\n', capex);
    fprintf('Economia anual (ano 1) ...... R$ %12.2f\n', econ1);
    fprintf('Payback simples ............. %10.1f anos\n', payback);
    fprintf('VPL (25 anos) ............... R$ %12.2f\n', vpl);
    fprintf('TIR ......................... %10.1f %%\n', tir*100);
    fprintf('LCOE ........................ %10.2f R$/kWh\n', lcoe);

    %% ---------------------------------------------------------- figuras
    d0 = 180;                                        % dia típico
    idx = (d0-1)*24 + (1:24);
    figure('Color','w','Position',[80 80 900 520]);
    subplot(2,1,1)
    area(0:23, P_fv(idx), 'FaceColor',[1 .8 .5], 'EdgeColor','none'); hold on
    plot(0:23, P_ld(idx),  'b', 'LineWidth',1.3);
    plot(0:23, P_imp(idx), 'r', 'LineWidth',1.0);
    plot(0:23, P_c(idx)-P_d(idx), 'g', 'LineWidth',1.0);
    legend('P_{FV}','P_{carga}','P_{imp}','P_{bat} (+=carga)','Location','best');
    ylabel('kW'); grid on; title(sprintf('Operação diária — %s (dia %d)', cen, d0));
    subplot(2,1,2)
    plot(0:24, 100*SOC(idx(1):idx(end)+1), 'm', 'LineWidth',1.4);
    yline(100*SOC_min,'--r'); yline(100*SOC_max,'--r');
    ylabel('SOC [%]'); xlabel('Hora do dia'); grid on; ylim([0 100]);

    Efv_m = zeros(12,1); Eld_m = zeros(12,1); Eim_m = zeros(12,1);
    Eex_m = zeros(12,1); Ed_m = zeros(12,1);
    for m = 1:12
        s = (mes == m);
        Efv_m(m) = sum(P_fv(s)); Eld_m(m) = sum(P_ld(s));
        Eim_m(m) = sum(P_imp(s)); Eex_m(m) = sum(P_exp(s));
        Ed_m(m)  = sum(P_d(s));
    end
    figure('Color','w','Position',[100 100 900 420]);
    bar(1:12, [Efv_m Eld_m Eim_m Eex_m Ed_m], 'grouped');
    legend('FV','Carga','Importação','Exportação','BESS desc.','Location','bestoutside');
    xlabel('Mês'); ylabel('kWh'); grid on;
    title(sprintf('Balanço energético mensal — %s', cen));

    figure('Color','w','Position',[120 120 900 420]);
    fcd = cumsum(fc ./ (1 + tx).^(1:N)') - capex;
    plot(0:N, [-capex; acc]/1e3, '-or', 'LineWidth',1.2,'MarkerSize',4); hold on
    plot(0:N, [-capex; fcd]/1e3, '-sg', 'LineWidth',1.2,'MarkerSize',4);
    yline(0,'k'); xline(payback,':m');
    legend('Acumulado simples', sprintf('Acumulado descontado (i=%d%%)', round(tx*100)), ...
           sprintf('Payback = %.1f anos', payback), 'Location','best');
    xlabel('Ano'); ylabel('mil R$'); grid on;
    title(sprintf('Fluxo de caixa — %s (VPL = R$ %.1fk, TIR = %.1f%%)', cen, vpl/1e3, tir*100));

    RES.(cen) = struct('E_fv',E_fv,'E_ld',E_ld,'E_imp',E_imp,'E_exp',E_exp, ...
        'E_d',E_d,'I_auto',I_auto,'I_autosuf',I_autosuf,'eta_glob',eta_glob, ...
        'pico_sem',pico_sem,'pico_com',pico_com,'red_pico',red_pico, ...
        'capex',capex,'econ1',econ1,'payback',payback,'vpl',vpl,'tir',tir,'lcoe',lcoe);
end

fprintf('\nConcluído. Estrutura RES no workspace com todos os indicadores.\n');

% (calc_tir.m em arquivo próprio — compatibilidade ampla)
