"""balanco_anual.py — Balanço energético horário (8.760 h) do TCC FV+BESS.

Implementação em Python (NumPy) da mesma lógica de balanco_anual.m. Com a
semente 42 do gerador do NumPy, reproduz exatamente os valores da TABELA 04
do TCC e os pontos de equilíbrio da análise de sensibilidade (Seção 5.4).

Uso:
    python balanco_anual.py

Requisitos: Python 3.9+ e NumPy. O openpyxl é opcional: se estiver instalado,
os resultados também são gravados em TCC_FV_BESS_Resultados.xlsx.
"""
import numpy as np

CENARIOS = {
    "residencial": dict(P_fv_kwp=5, E_bess=10, E_dia=20, tarifa=0.95, tar_inj=0.45, tar_dem=0,
                        tx=0.10, capex_fv_u=3500, capex_bess_u=2800, opex_pct=0.010),
    "industrial": dict(P_fv_kwp=100, E_bess=200, E_dia=1000, tarifa=0.65, tar_inj=0.32, tar_dem=55,
                       tx=0.12, capex_fv_u=3000, capex_bess_u=2500, opex_pct=0.015),
}
ETA_C, ETA_D = 0.96, 0.96            # eficiências de carga e descarga do BESS
ETA_CONV, ETA_INV = 0.98, 0.97       # conversor CC-CC e inversor
SOC_MIN, SOC_MAX, SOC_INI = 0.20, 0.90, 0.50
GAMMA_T, NOCT = -0.004, 45           # coef. térmico de potência [1/°C]; NOCT [°C]
N_ANOS, ANO_TROCA, DEGR = 25, 12, 0.005
DIA_TIPICO = 180


def calc_tir(cf):
    """TIR por bisseção sobre o VPL(r) — mesma rotina de calc_tir.m."""
    f = lambda r: np.sum(cf / (1 + r) ** np.arange(len(cf)))
    lo, hi = -0.5, 1.0
    if f(lo) * f(hi) > 0:
        return np.nan
    for _ in range(200):
        mid = (lo + hi) / 2
        if f(lo) * f(mid) <= 0:
            hi = mid
        else:
            lo = mid
    return (lo + hi) / 2


def simular(cen):
    """Perfis anuais, despacho do EMS e balanço de energia (Seções 3.3.1 a 3.3.9)."""
    p = CENARIOS[cen]
    rs = np.random.RandomState(42)                      # determinístico por cenário
    E_bess = p["E_bess"]
    P_max = 0.5 * E_bess                                # C/2 [kW]

    Nd, Nh = 365, 8760
    dia = np.repeat(np.arange(1, Nd + 1), 24)
    hora = np.tile(np.arange(24), Nd)

    # Irradiância: senoide 6 h-18 h (1.000 W/m²) x fator sazonal x índice de claridade
    saz = 1 + 0.31 * np.cos(2 * np.pi * (dia - 355) / 365)
    kt = np.repeat(np.clip(0.71 + 0.18 * rs.randn(Nd), 0.25, 1.0), 24)
    G = 1000 * np.sin(np.pi * (hora - 6) / 12)
    G[(hora < 6) | (hora >= 18)] = 0
    G = np.maximum(G * saz * kt, 0)

    # Temperaturas ambiente e de célula (NOCT) e potência FV (Eqs. 01 e 02) [kW]
    T_amb = 22 + 6 * np.cos(2 * np.pi * (dia - 20) / 365) + 6 * np.sin(np.pi * (hora - 9) / 12)
    T_cel = T_amb + (NOCT - 20) / 800 * G
    P_fv = np.maximum(p["P_fv_kwp"] * G / 1000 * (1 + GAMMA_T * (T_cel - 25)) * ETA_CONV * ETA_INV, 0)

    # Carga [kW]
    if cen == "residencial":
        P_ld = (0.35 + 1.8 * np.exp(-((hora - 7) ** 2) / 1.2) + 2.3 * np.exp(-((hora - 19.5) ** 2) / 2.0)
                + 0.9 * np.exp(-((hora - 12.5) ** 2) / 4.0))
        P_ld = P_ld * (1 + 0.03 * rs.randn(Nh))
        P_ld = P_ld * (p["E_dia"] * Nd / P_ld.sum())          # normalização anual
    else:
        fds = np.mod(dia - 1, 7) >= 5                          # fins de semana
        P_ld = 17 + np.maximum(60 * ((hora >= 7) & (hora < 18)) * np.sin(np.pi * (hora - 7) / 11), 0)
        P_ld[fds] *= 0.55
        P_ld = P_ld * (1 + 0.05 * rs.randn(Nh))
        P_ld = P_ld * (p["E_dia"] / (P_ld[~fds].sum() / ((~fds).sum() / 24)))  # dia útil médio
    P_ld = np.maximum(P_ld, 0)

    # Despacho do EMS e SOC por contagem de Coulomb em base energética (Eqs. 13 e 16 a 20)
    SOC = np.zeros(Nh + 1)
    SOC[0] = SOC_INI
    P_c, P_d, P_imp, P_exp = (np.zeros(Nh) for _ in range(4))
    for k in range(Nh):
        saldo = P_fv[k] - P_ld[k]
        if saldo > 0:
            cab = (SOC_MAX - SOC[k]) * E_bess / ETA_C
            P_c[k] = min(saldo, P_max, max(cab, 0))
            P_exp[k] = saldo - P_c[k]
        else:
            disp = (SOC[k] - SOC_MIN) * E_bess * ETA_D
            P_d[k] = min(-saldo, P_max, max(disp, 0))
            P_imp[k] = -saldo - P_d[k]
        SOC[k + 1] = SOC[k] + ETA_C * P_c[k] / E_bess - P_d[k] / (ETA_D * E_bess)
        SOC[k + 1] = min(max(SOC[k + 1], SOC_MIN), SOC_MAX)

    E = dict(E_fv=P_fv.sum(), E_ld=P_ld.sum(), E_imp=P_imp.sum(), E_exp=P_exp.sum(), E_d=P_d.sum())
    E["eta_glob"] = (E["E_ld"] - E["E_imp"]) / E["E_fv"] * 100            # Eq. 21
    E["I_auto"] = (E["E_fv"] - E["E_exp"]) / E["E_fv"] * 100              # Eq. 22
    E["I_autosuf"] = (E["E_ld"] - E["E_imp"]) / E["E_ld"] * 100           # Eq. 23
    E["I_auto_sb"] = np.minimum(P_fv, P_ld).sum() / E["E_fv"] * 100       # sem BESS (H1)
    E["I_autosuf_sb"] = np.minimum(P_fv, P_ld).sum() / E["E_ld"] * 100
    E["pico_sem"] = np.maximum(P_ld - P_fv, 0).max()                     # Eq. 24 (máximo anual)
    E["pico_com"] = P_imp.max()
    E["red_pico"] = (E["pico_sem"] - E["pico_com"]) / E["pico_sem"] * 100
    serie = dict(dia=dia, hora=hora, P_fv=P_fv, P_ld=P_ld, P_c=P_c, P_d=P_d, P_imp=P_imp,
                 P_exp=P_exp, SOC=SOC)
    return E, serie


def economia(E, cen, tarifa=None, tx=None, capex_bess_u=None):
    """Fluxo de caixa (Eq. 25), payback, VPL, TIR e LCOE (Seção 3.3.10)."""
    p = CENARIOS[cen]
    tarifa = p["tarifa"] if tarifa is None else tarifa
    tx = p["tx"] if tx is None else tx
    cbu = p["capex_bess_u"] if capex_bess_u is None else capex_bess_u
    capex = p["capex_fv_u"] * p["P_fv_kwp"] + cbu * p["E_bess"]
    opex = p["opex_pct"] * capex
    fc = np.zeros(N_ANOS)
    for a in range(1, N_ANOS + 1):
        f = (1 - DEGR) ** (a - 1)
        fc[a - 1] = ((E["E_ld"] - E["E_imp"]) * f * tarifa + E["E_exp"] * f * p["tar_inj"]
                     + 12 * p["tar_dem"] * (E["pico_sem"] - E["pico_com"]) - opex)
        if a == ANO_TROCA:
            fc[a - 1] -= cbu * p["E_bess"]                               # troca do BESS
    acc = np.cumsum(fc) - capex
    payback = np.nan
    if (acc >= 0).any():
        ipb = int(np.argmax(acc >= 0)) + 1
        payback = (ipb - 1) + (capex - fc[:ipb - 1].sum()) / fc[ipb - 1]
    desc = (1 + tx) ** np.arange(1, N_ANOS + 1)
    vpl = -capex + (fc / desc).sum()
    tir = calc_tir(np.concatenate([[-capex], fc]))
    E_desc = ((E["E_ld"] - E["E_imp"] + E["E_exp"]) * (1 - DEGR) ** np.arange(N_ANOS) / desc).sum()
    custos = np.full(N_ANOS, opex)
    custos[ANO_TROCA - 1] += cbu * p["E_bess"]
    lcoe = (capex + (custos / desc).sum()) / E_desc
    return dict(capex=capex, opex=opex, econ1=fc[0], payback=payback, vpl=vpl, tir=tir * 100, lcoe=lcoe)


def equilibrio(fun, lo, hi):
    """Valor da variável que anula o VPL (bisseção)."""
    for _ in range(100):
        mid = (lo + hi) / 2
        if fun(lo) * fun(mid) <= 0:
            hi = mid
        else:
            lo = mid
    return (lo + hi) / 2


def sensibilidade(E, cen):
    """Pontos de equilíbrio (VPL = 0) da Seção 5.4."""
    return dict(
        tarifa=equilibrio(lambda t: economia(E, cen, tarifa=t)["vpl"], 0.2, 3.0),
        tx=equilibrio(lambda r: economia(E, cen, tx=r)["vpl"], 0.001, 0.5) * 100,
        capex_bess=equilibrio(lambda c: economia(E, cen, capex_bess_u=c)["vpl"], 100, 10000),
    )


def exportar_xlsx(res, caminho="TCC_FV_BESS_Resultados.xlsx"):
    """Grava os resultados em planilha (requer openpyxl)."""
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill

    fonte, negrito = Font(name="Arial", size=10), Font(name="Arial", size=10, bold=True)
    cab = PatternFill("solid", fgColor="D9E1F2")
    nota = "Valores gerados por balanco_anual.py (NumPy, semente 42); TABELA 04 e Seção 5.4 do TCC."
    wb = Workbook()

    def folha(ws, titulo, cabecalho, linhas, formatos):
        ws.append([titulo])
        ws.append([nota])
        ws.append(cabecalho)
        for linha in linhas:
            ws.append(linha)
        for row in ws.iter_rows():
            for c in row:
                c.font = fonte
        ws["A1"].font = Font(name="Arial", size=12, bold=True)
        ws["A2"].font = Font(name="Arial", size=9, italic=True)
        for c in ws[3]:
            c.font, c.fill = negrito, cab
            c.alignment = Alignment(wrap_text=True, vertical="center")
        for row in ws.iter_rows(min_row=4):
            for c, fmt in zip(row, formatos):
                if fmt and isinstance(c.value, (int, float)):
                    c.number_format = fmt
        ws.column_dimensions["A"].width = 34
        for col in "BCDEFGHIJKLM":
            ws.column_dimensions[col].width = 15

    r, i = res["residencial"], res["industrial"]
    linhas = [
        ("Geração FV total [kWh/ano]", "E_fv", "#,##0"), ("Carga total [kWh/ano]", "E_ld", "#,##0"),
        ("Importação da rede [kWh/ano]", "E_imp", "#,##0"), ("Exportação para a rede [kWh/ano]", "E_exp", "#,##0"),
        ("Energia descarregada do BESS [kWh/ano]", "E_d", "#,##0"), ("Eficiência global (Eq. 21) [%]", "eta_glob", "0.0"),
        ("Autoconsumo (Eq. 22) [%]", "I_auto", "0.0"), ("Autossuficiência (Eq. 23) [%]", "I_autosuf", "0.0"),
        ("Autoconsumo sem BESS [%]", "I_auto_sb", "0.0"), ("Autossuficiência sem BESS [%]", "I_autosuf_sb", "0.0"),
        ("Pico sem BESS [kW]", "pico_sem", "0.00"), ("Pico com BESS [kW]", "pico_com", "0.00"),
        ("Redução de pico (Eq. 24) [%]", "red_pico", "0.0"), ("CAPEX total [R$]", "capex", "#,##0.00"),
        ("Economia anual, ano 1 [R$]", "econ1", "#,##0.00"), ("Payback simples [anos]", "payback", "0.0"),
        ("VPL em 25 anos [R$]", "vpl", "#,##0.00"), ("TIR [%]", "tir", "0.0"), ("LCOE [R$/kWh]", "lcoe", "0.00"),
        ("Equilíbrio: tarifa de energia [R$/kWh]", "eq_tarifa", "0.00"),
        ("Equilíbrio: taxa de desconto [% a.a.]", "eq_tx", "0.0"),
        ("Equilíbrio: CAPEX do BESS [R$/kWh]", "eq_capex", "#,##0"),
    ]
    ws = wb.active
    ws.title = "Resumo"
    dados = [[rot, r[k], i[k]] for rot, k, _ in linhas]
    folha(ws, "TCC FV+BESS — Indicadores consolidados", ["Indicador", "Residencial (5 kWp + 10 kWh)",
          "Industrial (100 kWp + 200 kWh)"], dados, [None, None, None])
    for n, (_, _, fmt) in enumerate(linhas, start=4):
        ws.cell(n, 2).number_format = fmt
        ws.cell(n, 3).number_format = fmt

    ws = wb.create_sheet("Mensal")
    meses = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]
    cols = ["P_fv", "P_ld", "P_imp", "P_exp", "P_d"]
    dados = []
    for m in range(12):
        lin = [meses[m]]
        for cen in ("residencial", "industrial"):
            s = res[cen]["serie"]
            mes = np.minimum(np.floor((s["dia"] - 1) / 30.4167) + 1, 12)
            lin += [float(s[c][mes == m + 1].sum()) for c in cols]
        dados.append(lin)
    nomes = ["FV", "Carga", "Importação", "Exportação", "BESS desc."]
    folha(ws, "Balanço energético mensal [kWh]", ["Mês"] + [f"{n} — Res." for n in nomes]
          + [f"{n} — Ind." for n in nomes], dados, [None] + ["#,##0"] * 10)
    ws.append(["Total"] + [f"=SUM({chr(66 + j)}4:{chr(66 + j)}15)" for j in range(10)])
    for c in ws[16]:
        c.font = negrito
        c.number_format = "#,##0"

    ws = wb.create_sheet("DiaTipico")
    dados = []
    for h in range(24):
        lin = [h]
        for cen in ("residencial", "industrial"):
            s = res[cen]["serie"]
            k = (DIA_TIPICO - 1) * 24 + h
            lin += [float(s["P_fv"][k]), float(s["P_ld"][k]), float(s["P_c"][k]), float(s["P_d"][k]),
                    float(s["P_imp"][k]), float(s["P_exp"][k]), float(s["SOC"][k] * 100)]
        dados.append(lin)
    nomes = ["P_FV [kW]", "P_carga [kW]", "P_bat,carga [kW]", "P_bat,desc [kW]", "P_rede,imp [kW]",
             "P_rede,exp [kW]", "SOC [%]"]
    folha(ws, f"Operação horária no dia {DIA_TIPICO}", ["Hora"] + [f"{n} — Res." for n in nomes]
          + [f"{n} — Ind." for n in nomes], dados, [None] + ["0.00"] * 14)

    ws = wb.create_sheet("Sensibilidade")
    dados = []
    grades = {"residencial": dict(tarifa=[0.60, 0.70, 0.80, 0.90, 0.95, 1.00, 1.10, 1.20]),
              "industrial": dict(tarifa=[0.45, 0.55, 0.65, 0.70, 0.75, 0.80, 0.85, 0.95])}
    for cen in ("residencial", "industrial"):
        E = res[cen]
        for t in grades[cen]["tarifa"]:
            dados.append([cen, "Tarifa de energia [R$/kWh]", t, economia(E, cen, tarifa=t)["vpl"]])
        for tx in [0.06, 0.08, 0.09, 0.10, 0.12, 0.14]:
            dados.append([cen, "Taxa de desconto [% a.a.]", tx * 100, economia(E, cen, tx=tx)["vpl"]])
        for c in [1500, 2000, 2500, 2800, 3000, 3500]:
            dados.append([cen, "CAPEX do BESS [R$/kWh]", c, economia(E, cen, capex_bess_u=c)["vpl"]])
    folha(ws, "Análise de sensibilidade: VPL em 25 anos", ["Cenário", "Variável", "Valor", "VPL [R$]"],
          dados, [None, None, "#,##0.00", "#,##0.00"])
    ws.column_dimensions["A"].width = 14
    ws.column_dimensions["B"].width = 30

    ws = wb.create_sheet("Parametros")
    dados = [[k, CENARIOS["residencial"][k], CENARIOS["industrial"][k]] for k in CENARIOS["residencial"]]
    dados += [["eta_c = eta_d", ETA_C, ETA_C], ["eta_conv; eta_inv", f"{ETA_CONV}; {ETA_INV}",
              f"{ETA_CONV}; {ETA_INV}"], ["SOC mín.; máx.; inicial", "0,20; 0,90; 0,50", "0,20; 0,90; 0,50"],
              ["Horizonte; troca do BESS; degradação", "25 anos; ano 12; 0,5% a.a.",
               "25 anos; ano 12; 0,5% a.a."]]
    folha(ws, "Parâmetros dos cenários (TABELA 03)", ["Parâmetro", "Residencial", "Industrial"], dados,
          [None, None, None])
    wb.save(caminho)
    return caminho


def main():
    res = {}
    for cen in ("residencial", "industrial"):
        E, serie = simular(cen)
        E.update(economia(E, cen))
        eq = sensibilidade(E, cen)
        E.update(eq_tarifa=eq["tarifa"], eq_tx=eq["tx"], eq_capex=eq["capex_bess"], serie=serie)
        res[cen] = E
        print(f"\n================ CENÁRIO {cen.upper()} ================")
        print(f"Geração FV total ............ {E['E_fv']:10.0f} kWh/ano")
        print(f"Carga total ................. {E['E_ld']:10.0f} kWh/ano")
        print(f"Importação da rede .......... {E['E_imp']:10.0f} kWh/ano")
        print(f"Exportação para a rede ...... {E['E_exp']:10.0f} kWh/ano")
        print(f"Energia descarregada BESS ... {E['E_d']:10.0f} kWh/ano")
        print(f"Eficiência global ........... {E['eta_glob']:10.1f} %")
        print(f"Autoconsumo I_auto .......... {E['I_auto']:10.1f} %   (sem BESS: {E['I_auto_sb']:.1f} %)")
        print(f"Autossuficiência I_autosuf .. {E['I_autosuf']:10.1f} %   (sem BESS: {E['I_autosuf_sb']:.1f} %)")
        print(f"Pico sem BESS ............... {E['pico_sem']:10.2f} kW")
        print(f"Pico com BESS ............... {E['pico_com']:10.2f} kW")
        print(f"Redução de pico ............. {E['red_pico']:10.1f} %")
        print(f"CAPEX total ................. R$ {E['capex']:12.2f}")
        print(f"Economia anual (ano 1) ...... R$ {E['econ1']:12.2f}")
        print(f"Payback simples ............. {E['payback']:10.1f} anos")
        print(f"VPL (25 anos) ............... R$ {E['vpl']:12.2f}")
        print(f"TIR ......................... {E['tir']:10.1f} %")
        print(f"LCOE ........................ {E['lcoe']:10.2f} R$/kWh")
        print(f"VPL = 0 para tarifa de R$ {E['eq_tarifa']:.2f}/kWh, taxa de {E['eq_tx']:.1f}% a.a. "
              f"ou CAPEX do BESS de R$ {E['eq_capex']:.0f}/kWh (Seção 5.4)")
    try:
        print(f"\nPlanilha gravada: {exportar_xlsx(res)}")
    except ImportError:
        print("\nopenpyxl não instalado: planilha não gravada (resultados acima).")


if __name__ == "__main__":
    main()
