function [P_bat_ref, estado] = ems_supervisorio(P_fv, P_load, SOC, falha_bms, params) %#codegen
%EMS_SUPERVISORIO  Lógica supervisória de gerenciamento de energia (EMS).
%   [P_bat_ref, estado] = ems_supervisorio(P_fv, P_load, SOC, falha_bms, params)
%
%   Equivalente em MATLAB Function do chart Stateflow EMS_Controller
%   (FIGURA 08 do TCC), com cinco estados:
%     1 = CARGA_BESS    P_FV > P_carga  e  SOC < SOC_max
%     2 = DESCARGA_BESS P_FV < P_carga  e  SOC > SOC_min
%     3 = EXPORTACAO    SOC >= SOC_max  e  excedente FV
%     4 = IMPORTACAO    SOC <= SOC_min  e  déficit FV
%     5 = FALHA         proteção do BMS ativada
%
%   Convenção de sinal: P_bat_ref > 0 carrega o BESS; < 0 descarrega.
%   Entradas em watts; SOC em %.

P_saldo = P_fv - P_load;

if falha_bms
    estado    = 5;                                   % FALHA
    P_bat_ref = 0;                                   % BESS desconectado
elseif P_saldo > 0 && SOC < params.SOC_max
    estado    = 1;                                   % CARGA_BESS
    P_bat_ref = min(P_saldo, params.P_max_c);
elseif P_saldo < 0 && SOC > params.SOC_min
    estado    = 2;                                   % DESCARGA_BESS
    P_bat_ref = -min(-P_saldo, params.P_max_d);
elseif P_saldo > 0                                   % SOC no teto
    estado    = 3;                                   % EXPORTACAO
    P_bat_ref = 0;                                   % excedente vai à rede
else                                                 % SOC no piso
    estado    = 4;                                   % IMPORTACAO
    P_bat_ref = 0;                                   % déficit vem da rede
end
end
