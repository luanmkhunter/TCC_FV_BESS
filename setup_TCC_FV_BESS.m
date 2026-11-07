%% setup_TCC_FV_BESS.m
% Configuração de parâmetros, perfis de entrada e solver para o modelo
% TCC_FV_BESS.slx  —  TCC FV+BESS (Luan M. S. Holanda, CES-CL, 2026)
%
% Uso:
%   >> cenario = 'residencial';   % ou 'industrial'
%   >> setup_TCC_FV_BESS
%
% O script injeta no Base Workspace:
%   params      struct com todos os parâmetros do cenário
%   G_ts        timeseries de irradiância [W/m²]     (24 h, passo 60 s)
%   T_ts        timeseries de temperatura [°C]       (24 h, passo 60 s)
%   P_load_ts   timeseries de carga [W]              (24 h, passo 60 s)
% e configura o solver do modelo (ode23tb, RelTol 1e-3, AbsTol 1e-4,
% StopTime 86400 s).

if ~exist('cenario','var'), cenario = 'residencial'; end
rng(42);                                  % resultados determinísticos

%% ---------------------------------------------------------------- cenário
switch lower(cenario)
    case 'residencial'
        params.P_fv_kwp   = 5;            % potência FV instalada [kWp]
        params.E_bess_kwh = 10;           % capacidade do BESS [kWh]
        params.E_dia_kwh  = 20;           % consumo diário médio [kWh]
        params.tarifa     = 0.95;         % R$/kWh (energia)
        params.tar_inj    = 0.45;         % R$/kWh (injeção)
        params.tar_dem    = 0;            % R$/kW.mês (demanda)
        params.tx_desc    = 0.10;         % taxa de desconto a.a.
        params.capex_fv_u   = 3500;       % R$/kWp
        params.capex_bess_u = 2800;       % R$/kWh
        params.opex_pct     = 0.010;      % OPEX anual (% CAPEX)
    case 'industrial'
        params.P_fv_kwp   = 100;
        params.E_bess_kwh = 200;
        params.E_dia_kwh  = 1000;
        params.tarifa     = 0.65;
        params.tar_inj    = 0.32;
        params.tar_dem    = 55;
        params.tx_desc    = 0.12;
        params.capex_fv_u   = 3000;
        params.capex_bess_u = 2500;
        params.opex_pct     = 0.015;
    otherwise
        error('Cenário desconhecido: use ''residencial'' ou ''industrial''.');
end
params.cenario = lower(cenario);

%% -------------------------------------------------- módulo FV (um diodo)
% Módulo de referência de 60 células: Pmáx ≈ 237 W em STC (gerar_curvas_IV)
% Modelo de um diodo: Villalva et al. (2009)
params.Isc = 8.5;          % corrente de curto-circuito STC [A]
params.Voc = 38.0;         % tensão de circuito aberto STC [V]
params.Ki  = 0.005;        % coef. térmico de Isc [A/°C]
params.Kv  = -0.123;       % coef. térmico de Voc [V/°C]
params.Ns  = 60;           % células em série por módulo
params.a   = 1.3;          % fator de idealidade do diodo
params.Rs  = 0.30;         % resistência série [ohm]
params.Rsh = 300;          % resistência shunt [ohm]
params.Cpv_mod = 100e-9;   % capacitância intrínseca por módulo [F]

%% --------------------------------------------------------------- BESS
params.eta_c   = 0.96;     % eficiência de carga
params.eta_d   = 0.96;     % eficiência de descarga (round-trip ~92%)
params.SOC_min = 20;       % [%]
params.SOC_max = 90;       % [%]
params.SOC_ini = 50;       % [%]
params.V_bat_nom = 48;     % [V]
params.R_int     = 0.05;   % resistência interna (modelo Rint) [ohm]
params.P_max_c = 0.5*params.E_bess_kwh*1e3;   % C/2 em carga  [W]
params.P_max_d = 0.5*params.E_bess_kwh*1e3;   % C/2 em descarga [W]

%% -------------------------------------------------------- conversores
params.eta_conv = 0.98;    % conversor CC-CC
params.eta_inv  = 0.97;    % inversor CC-CA
params.f_sw     = 20e3;    % frequência de chaveamento [Hz]
params.Vdc_ref  = 400;     % tensão do barramento CC [V]

%% ------------------------------------------------- perfis (24 h, 60 s)
dt   = 60;                          % [s]
t    = (0:dt:86400-dt)';            % [s]
h    = t/3600;                      % [h]

% Irradiância: senoide truncada 6h-18h, pico ~1000 W/m²
G = 1000*sin(pi*(h-6)/12);
G(h<6 | h>18) = 0;
G = max(G + 20*randn(size(G)).*(G>0), 0);

% Temperatura ambiente: mínimo 14 °C às 3h, máximo 30 °C às 15h
T = 22 + 8*sin(pi*(h-9)/12);
T = max(min(T,45),10);

% Carga
if strcmp(params.cenario,'residencial')
    base  = 0.35;                                    % kW
    pico1 = 1.8*exp(-((h-7).^2)/1.2);                % manhã
    pico2 = 2.3*exp(-((h-19.5).^2)/2.0);             % noite
    meiod = 0.9*exp(-((h-12.5).^2)/4.0);             % meio-dia
    P = base + pico1 + pico2 + meiod;                % kW
else
    base = 17;                                       % kW (madrugada)
    diurno = 60*(h>=7 & h<18).*sin(pi*(h-7)/11);     % 7h-18h
    P = base + max(diurno,0);                        % kW
end
P = P .* (1 + 0.03*randn(size(P)));
P = P * (params.E_dia_kwh / (sum(P)*dt/3600));       % normaliza p/ consumo diário
P_load = P*1e3;                                      % [W]

G_ts      = timeseries(G,      t, 'Name','Irradiancia');
T_ts      = timeseries(T,      t, 'Name','Temperatura');
P_load_ts = timeseries(P_load, t, 'Name','Carga');

assignin('base','params',params);
assignin('base','G_ts',G_ts);
assignin('base','T_ts',T_ts);
assignin('base','P_load_ts',P_load_ts);

%% ------------------------------------------------------------- solver
% Configura o solver do modelo que estiver disponível/carregado.
% - TCC_FV_BESS_R2023 (fluxo de potência): MaxStep 60 s
% - TCC_FV_BESS (original R2025b):         MaxStep 1e-4 s
for mdl_ = {'TCC_FV_BESS_R2023','TCC_FV_BESS'}
    mdl = mdl_{1};
    if bdIsLoaded(mdl) || exist([mdl '.slx'],'file') || exist(['../' mdl '.slx'],'file')
        try
            if ~bdIsLoaded(mdl), load_system(mdl); end
            if strcmp(mdl,'TCC_FV_BESS_R2023'), ms = '60'; else, ms = '1e-4'; end
            set_param(mdl,'Solver','ode23tb','RelTol','1e-3', ...
                          'AbsTol','1e-4','MaxStep',ms,'StopTime','86400');
            fprintf('Solver de %s: ode23tb | RelTol 1e-3 | AbsTol 1e-4 | 86400 s\n', mdl);
            break
        catch
            % modelo incompatível com esta versão do MATLAB — ignora
        end
    end
end
fprintf('Cenário "%s" carregado no Base Workspace.\n', params.cenario);
