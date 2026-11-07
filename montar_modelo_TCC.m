%% montar_modelo_TCC.m
% Constrói programaticamente o modelo Simulink TCC_FV_BESS_R2023.slx
% (modelo de fluxo de potência, 24 h) — compatível com MATLAB/Simulink
% R2020a ou superior; o projeto foi desenvolvido no R2023b.
%
% O script recria o modelo (FIGURA 04 do TCC) inteiramente por comandos
% add_block/add_line, de modo que funciona em qualquer instalação
% R2020a+ apenas com o Simulink base (sem Simscape).
%
% Uso:
%   >> cd TCC_FV_BESS                % pasta do repositório
%   >> cenario = 'residencial';        % ou 'industrial'
%   >> setup_TCC_FV_BESS               % injeta params e perfis
%   >> montar_modelo_TCC               % cria e salva o .slx
%   >> rodar_simulacao_diaria          % simula 24 h e plota
%
% Arquitetura (cadeia vetorial, sem laços no nível raiz):
%   [G;T] -> SolarPlant -> P_fv -> BoostConverter -> P_dc ---+
%                                              P_load_ts ----+--> Mux
%   -> EMS_Controller -> [P_dc;P_load;P_bat_ref]
%   -> BESS           -> [P_dc;P_load;P_bat;SOC]      (SOC interno)
%   -> Inverter       -> [P_dc;P_load;P_bat;SOC;P_grid] -> Out/Scope
%
% Convenções (idênticas ao TCC): P_bat > 0 carrega o BESS; P_grid > 0
% importa da rede. O EMS decide a referência pelo saldo P_dc - P_load
% (regras da Seção 3.3.5 e da FIGURA 08) e o BESS aplica a janela
% 20% <= SOC <= 90% (Eq. 13) — decomposição equivalente às Eqs. 16 e 19.

if ~evalin('base','exist(''params'',''var'')')
    error('Rode setup_TCC_FV_BESS antes (params não está no workspace).');
end
params = evalin('base','params');

mdl = 'TCC_FV_BESS_R2023';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
open_system(mdl);

%% ------------------------------------------------------------- entradas
add_block('simulink/Sources/From Workspace', [mdl '/G_ts'], ...
    'VariableName','G_ts','Position',[40 40 110 70], ...
    'Interpolate','on','OutputAfterFinalValue','Holding final value');
add_block('simulink/Sources/From Workspace', [mdl '/T_ts'], ...
    'VariableName','T_ts','Position',[40 110 110 140], ...
    'Interpolate','on','OutputAfterFinalValue','Holding final value');
add_block('simulink/Sources/From Workspace', [mdl '/P_load_ts'], ...
    'VariableName','P_load_ts','Position',[40 190 110 220], ...
    'Interpolate','on','OutputAfterFinalValue','Holding final value');

add_block('simulink/Signal Routing/Mux', [mdl '/MuxGT'], ...
    'Inputs','2','Position',[150 65 155 115]);

%% -------------------------------------------------- funções embarcadas
% Os parâmetros numéricos do cenário são "assados" no corpo de cada
% MATLAB Function no momento da montagem (dispensa escopo Parameter).
P_stc_W  = params.P_fv_kwp*1e3;
eta_conv = params.eta_conv;   eta_inv = params.eta_inv;
eta_c    = params.eta_c;      eta_d   = params.eta_d;
E_J      = params.E_bess_kwh*3.6e6;            % capacidade [J]
SOCmin   = params.SOC_min;    SOCmax  = params.SOC_max;
Pmax_c   = params.P_max_c;    Pmax_d  = params.P_max_d;

fcn_solar = sprintf([ ...
 'function P_fv = fcn(u)\n' ...
 '%% SolarPlant — Eqs. 01 e 02 do TCC (potência corrigida por temperatura)\n' ...
 'G = u(1); T = u(2);\n' ...
 'T_cel = T + (45-20)/800*G;                %% modelo NOCT\n' ...
 'P_fv  = %.6g*(G/1000)*(1 - 0.004*(T_cel-25));\n' ...
 'P_fv  = max(P_fv, 0);\n'], P_stc_W);

fcn_ems = sprintf([ ...
 'function y = fcn(u)\n' ...
 '%% EMS_Controller — regras da Seção 3.3.5 (referência pelo saldo)\n' ...
 'P_dc = u(1); P_load = u(2);\n' ...
 'saldo = P_dc - P_load;\n' ...
 'if saldo > 0\n' ...
 '    P_bat_ref = min(saldo, %.6g);          %% pedido de carga\n' ...
 'else\n' ...
 '    P_bat_ref = -min(-saldo, %.6g);        %% pedido de descarga\n' ...
 'end\n' ...
 'y = [P_dc; P_load; P_bat_ref];\n'], Pmax_c, Pmax_d);

fcn_bess = sprintf([ ...
 'function [P_bat, dSOC] = fcn(P_bat_ref, SOC)\n' ...
 '%% BESS — Eq. 13 (Coulomb counting em base energética) + janela SOC\n' ...
 'if P_bat_ref > 0 && SOC < %.6g\n' ...
 '    P_bat = min(P_bat_ref, %.6g);\n' ...
 '    dSOC  = 100*%.6g*P_bat/%.6g;           %% [%%/s]\n' ...
 'elseif P_bat_ref < 0 && SOC > %.6g\n' ...
 '    P_bat = max(P_bat_ref, -%.6g);\n' ...
 '    dSOC  = 100*P_bat/(%.6g*%.6g);\n' ...
 'else\n' ...
 '    P_bat = 0; dSOC = 0;\n' ...
 'end\n'], SOCmax, Pmax_c, eta_c, E_J, SOCmin, Pmax_d, eta_d, E_J);

fcn_inv = sprintf([ ...
 'function y = fcn(u)\n' ...
 '%% Inverter — Eqs. 14 a 20 (balanço com a rede)\n' ...
 'P_dc = u(1); P_load = u(2); P_bat = u(3); SOC = u(4);\n' ...
 'P_ac   = %.6g*(P_dc - P_bat);              %% CC liquido -> CA\n' ...
 'P_grid = P_load - P_ac;                    %% >0 importa, <0 exporta\n' ...
 'y = [P_dc; P_load; P_bat; SOC; P_grid];\n'], eta_inv);

set_mlfcn = @(blk, code) set_mlfcn_code(blk, code);

%% --------------------------------------------------------- SolarPlant
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [mdl '/SolarPlant'], 'Position',[200 70 280 110]);
set_mlfcn([mdl '/SolarPlant'], fcn_solar);

%% ------------------------------------------------------ BoostConverter
add_block('simulink/Math Operations/Gain', [mdl '/BoostConverter'], ...
    'Gain', num2str(eta_conv), 'Position',[320 75 370 105]);

add_block('simulink/Signal Routing/Mux', [mdl '/MuxPL'], ...
    'Inputs','2','Position',[410 90 415 200]);

%% ------------------------------------------------------ EMS_Controller
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [mdl '/EMS_Controller'], 'Position',[460 120 550 170]);
set_mlfcn([mdl '/EMS_Controller'], fcn_ems);

%% ----------------------------------------------------------------- BESS
% Subsistema com laço interno de SOC quebrado pelo Integrator.
add_block('built-in/Subsystem', [mdl '/BESS'], 'Position',[600 120 690 170]);
b = [mdl '/BESS'];
add_block('built-in/Inport',  [b '/In1'],  'Position',[30 95 60 115]);
add_block('built-in/Outport', [b '/Out1'], 'Position',[560 95 590 115]);
add_block('simulink/Signal Routing/Demux', [b '/Demux'], ...
    'Outputs','3','Position',[100 60 105 150]);
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [b '/bess_limiter'], 'Position',[200 120 300 170]);
set_mlfcn([b '/bess_limiter'], fcn_bess);
add_block('simulink/Continuous/Integrator', [b '/SOC_int'], ...
    'InitialCondition', num2str(params.SOC_ini), ...
    'LimitOutput','on', ...
    'UpperSaturationLimit', num2str(SOCmax), ...
    'LowerSaturationLimit', num2str(SOCmin), ...
    'Position',[350 190 380 220]);
add_block('simulink/Signal Routing/Mux', [b '/Mux4'], ...
    'Inputs','4','Position',[480 60 485 150]);
add_line(b, 'In1/1', 'Demux/1');
add_line(b, 'Demux/1', 'Mux4/1');                 % P_dc
add_line(b, 'Demux/2', 'Mux4/2');                 % P_load
add_line(b, 'Demux/3', 'bess_limiter/1');         % P_bat_ref
add_line(b, 'bess_limiter/1', 'Mux4/3');          % P_bat
add_line(b, 'bess_limiter/2', 'SOC_int/1');       % dSOC
add_line(b, 'SOC_int/1', 'bess_limiter/2', 'autorouting','on');  % SOC
add_line(b, 'SOC_int/1', 'Mux4/4', 'autorouting','on');
add_line(b, 'Mux4/1', 'Out1/1');

%% -------------------------------------------------------------- Inverter
add_block('simulink/User-Defined Functions/MATLAB Function', ...
    [mdl '/Inverter'], 'Position',[740 120 830 170]);
set_mlfcn([mdl '/Inverter'], fcn_inv);

%% --------------------------------------------------- registro e Scope
add_block('simulink/Sinks/To Workspace', [mdl '/Out_P_FV'], ...
    'VariableName','P_FV_sim', 'SaveFormat','Structure With Time', ...
    'SampleTime','60', 'Position',[880 120 950 150]);
add_block('simulink/Sinks/Scope', [mdl '/Scope_Operation'], ...
    'Position',[880 190 920 230]);

%% ----------------------------------------------------------- ligações
add_line(mdl, 'G_ts/1',  'MuxGT/1');
add_line(mdl, 'T_ts/1',  'MuxGT/2');
add_line(mdl, 'MuxGT/1', 'SolarPlant/1');
add_line(mdl, 'SolarPlant/1', 'BoostConverter/1');
add_line(mdl, 'BoostConverter/1', 'MuxPL/1');
add_line(mdl, 'P_load_ts/1', 'MuxPL/2');
add_line(mdl, 'MuxPL/1', 'EMS_Controller/1');
add_line(mdl, 'EMS_Controller/1', 'BESS/1');
add_line(mdl, 'BESS/1', 'Inverter/1');
add_line(mdl, 'Inverter/1', 'Out_P_FV/1');
add_line(mdl, 'Inverter/1', 'Scope_Operation/1', 'autorouting','on');

%% -------------------------------------------------------------- solver
set_param(mdl, 'Solver','ode23tb', 'RelTol','1e-3', 'AbsTol','1e-4', ...
               'MaxStep','60', 'StopTime','86400');

save_system(mdl, [mdl '.slx']);
fprintf(['Modelo %s.slx criado e salvo (solver ode23tb, 86400 s).\n' ...
         'Agora rode: rodar_simulacao_diaria\n'], mdl);

%% -------------------------------------------------------------- helper
function set_mlfcn_code(blk, code)
% Define o corpo de um bloco MATLAB Function (R2020a+: via
% MATLABFunctionConfiguration; fallback: API Stateflow).
try
    cfg = get_param(blk, 'MATLABFunctionConfiguration');
    cfg.FunctionScript = code;
catch
    rt = sfroot;
    ch = rt.find('-isa','Stateflow.EMChart', 'Path', blk);
    ch.Script = code;
end
end
