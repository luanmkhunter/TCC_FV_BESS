# TCC_FV_BESS

Simulação e códigos do Trabalho de Conclusão de Curso **"Integração de sistemas fotovoltaicos com
armazenamento em baterias: análise técnica e econômica aplicada a sistemas residenciais e
industriais"**.

- **Autor:** Luan Mesquita de Sousa Holanda
- **Orientador:** Prof. MSc. José Antônio Toledo Júnior
- **Instituição:** Centro de Ensino Superior de Conselheiro Lafaiete (CES-CL) — Engenharia Elétrica, 2026

O trabalho compara, com e sem baterias, um sistema residencial (5 kWp + 10 kWh) e um industrial
(100 kWp + 200 kWh) em Conselheiro Lafaiete – MG, por indicadores técnicos (eficiência global,
autoconsumo, autossuficiência e redução de pico) e econômicos (*payback*, VPL, TIR e LCOE).

Projeto desenvolvido no **MATLAB/Simulink R2023b**.

## Arquivos

| Arquivo | Função | Seção do TCC |
|---|---|---|
| `setup_TCC_FV_BESS.m` | Parâmetros dos cenários, perfis de 24 h (passo de 60 s) e configuração do *solver* | 3.5.1 e 4.2 |
| `TCC_FV_BESS_R2023.slx` | Modelo Simulink de 24 h (SolarPlant, BoostConverter, EMS_Controller, BESS e Inverter), salvo no MATLAB R2023b | 3.5.1 |
| `montar_modelo_TCC.m` | Recria o `TCC_FV_BESS_R2023.slx` por comandos (`add_block`/`add_line`) | 3.5.1 |
| `rodar_simulacao_diaria.m` | Simula 24 h e plota as potências e o SOC | 3.5 |
| `balanco_anual.m` | Balanço energético horário anual (8.760 h) e indicadores técnicos e econômicos | 3.3.4 a 3.3.10 e 3.5 |
| `calc_tir.m` | TIR por bisseção, usada por `balanco_anual.m` | 3.3.10 |
| `balanco_anual.py` | Mesma lógica do balanço anual em Python (NumPy); reproduz a TABELA 04 e os pontos de equilíbrio da Seção 5.4 e grava a planilha de resultados | Cap. 5 |
| `pv_model_newton_raphson.m` | Modelo de um diodo do módulo fotovoltaico, resolvido por Newton-Raphson | 3.3.2 |
| `gerar_curvas_IV.m` | Curvas I-V e P-V (FIGURAS 05 e 06) e ponto de máxima potência em STC | 3.5.2 |
| `mppt_PO.m` | Rastreamento do ponto de máxima potência por Perturba e Observa | 3.5.3 |
| `ems_supervisorio.m` | Lógica supervisória do EMS em *MATLAB Function*, equivalente à máquina de estados em Stateflow | 3.5.4 |
| `TCC_FV_BESS_Resultados.xlsx` | Resultados gerados por `balanco_anual.py`: resumo, balanço mensal, dia típico, sensibilidade e parâmetros | Cap. 5 |

## Requisitos

- **MATLAB/Simulink R2023b**, versão em que o projeto foi desenvolvido, para as rotinas `.m` e o
  `TCC_FV_BESS_R2023.slx`; o `montar_modelo_TCC.m` recria o modelo em versões a partir da R2020a.
- **Python 3.9 ou superior com NumPy**, para `balanco_anual.py` (o `openpyxl` é opcional e serve
  apenas para gravar a planilha).

## Como executar

No MATLAB, com a pasta do repositório como pasta atual:

```matlab
cenario = 'residencial';    % ou 'industrial'
rodar_simulacao_diaria      % carrega setup_TCC_FV_BESS e simula 24 h
gerar_curvas_IV             % curvas I-V e P-V e ponto de máxima potência em STC
balanco_anual               % balanço anual dos dois cenários e indicadores
```

As figuras são gravadas na pasta `figuras/`.

## Reprodutibilidade

Os perfis de irradiância e de carga usam ruído gaussiano com semente fixa 42. Os valores da
TABELA 04 e os pontos de equilíbrio da Seção 5.4 são reproduzidos exatamente por
`balanco_anual.py`, que usa o gerador do NumPy. O `balanco_anual.m` aplica a mesma lógica, mas o
`randn` do MATLAB gera outra sequência pseudoaleatória, de modo que seus indicadores podem diferir
ligeiramente dos publicados. A redução de pico usa o máximo anual da demanda líquida, métrica
sensível a esse ruído.

