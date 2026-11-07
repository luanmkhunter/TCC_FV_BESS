function Vref = mppt_PO(V, I) %#codegen
%MPPT_PO  Rastreamento do ponto de máxima potência — Perturba & Observa.
%   Vref = mppt_PO(V,I)
%
%   Implementa o fluxograma da FIGURA 09 do TCC: a cada período de
%   amostragem (Ts = 10 ms, imposto por bloco Rate Transition no
%   Simulink) a tensão de referência é perturbada em dV = 0,5 V e o
%   sinal da variação de potência define o sentido da próxima
%   perturbação (Esram & Chapman, 2007).
%
%   A saída Vref alimenta um controlador PI (Kp = 0,1; Ki = 5) cuja
%   saída é o ciclo de trabalho do conversor boost.

persistent V_ant P_ant Vref_ant
if isempty(V_ant)
    V_ant    = V;
    P_ant    = V*I;
    Vref_ant = max(V, 25);      % partida próxima do joelho da curva
end

dV_step = 0.5;                  % passo de perturbação [V]
P  = V*I;
dP = P - P_ant;
dV = V - V_ant;

if dP > 0
    if dV > 0
        Vref = Vref_ant + dV_step;   % subindo a curva: continua
    else
        Vref = Vref_ant - dV_step;
    end
else
    if dV > 0
        Vref = Vref_ant - dV_step;   % passou do MPP: inverte
    else
        Vref = Vref_ant + dV_step;
    end
end

Vref = max(min(Vref, 40), 10);  % janela física de operação [V]

V_ant    = V;
P_ant    = P;
Vref_ant = Vref;
end
