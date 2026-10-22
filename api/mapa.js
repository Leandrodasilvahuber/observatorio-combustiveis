// Mapa da home: lê os dados embutidos em #dados e desenha mapa, legenda e ranking.
(function(){
  var D = JSON.parse(document.getElementById("dados").textContent);
  var ORDEM = ["GASOLINA","GASOLINA ADITIVADA","ETANOL","DIESEL","DIESEL S10","GNV"];
  var ROTULO = {"GASOLINA":"Gasolina comum","GASOLINA ADITIVADA":"Gasolina aditivada","ETANOL":"Etanol",
                "DIESEL":"Diesel","DIESEL S10":"Diesel S10","GNV":"GNV"};
  var FAIXAS = 5;
  var reais = new Intl.NumberFormat("pt-BR",{style:"currency",currency:"BRL",minimumFractionDigits:3,maximumFractionDigits:3});
  var numero = new Intl.NumberFormat("pt-BR",{minimumFractionDigits:3,maximumFractionDigits:3});
  var inteiro = new Intl.NumberFormat("pt-BR");
  function data(iso){ var p = iso.split("-"); return p[2]+"/"+p[1]+"/"+p[0]; }

  var produtos = ORDEM.filter(function(p){ return D.precos.some(function(l){ return l.produto === p; }); });
  D.precos.forEach(function(l){ if (produtos.indexOf(l.produto) < 0) produtos.push(l.produto); });

  document.getElementById("sub").textContent =
    "Período de " + data(D.periodo.inicio) + " a " + data(D.periodo.fim) + " · fonte: ANP (Levantamento de Preços de Combustíveis)";
  if (D.etanol.municipios_analisados) {
    document.getElementById("etanol").innerHTML = "O etanol compensa (até 70% do preço da gasolina) em <b>" +
      inteiro.format(D.etanol.municipios_onde_etanol_compensa) + "</b> de " +
      inteiro.format(D.etanol.municipios_analisados) + " municípios analisados.";
  }

  var svg = document.getElementById("mapa"), NS = "http://www.w3.org/2000/svg";
  svg.setAttribute("viewBox", "0 0 " + D.mapa.largura + " " + D.mapa.altura);
  var caminhos = {};
  Object.keys(D.mapa.ufs).forEach(function(uf){
    var p = document.createElementNS(NS, "path");
    p.setAttribute("d", D.mapa.ufs[uf]);
    p.setAttribute("tabindex", "0");
    p.dataset.uf = uf;
    svg.appendChild(p);
    caminhos[uf] = p;
  });
  // Destaque numa camada própria, por cima de todos os estados. Mover o estado
  // para o fim do SVG tiraria o foco do teclado dele.
  var contorno = document.createElementNS(NS, "path");
  contorno.id = "contorno";
  contorno.setAttribute("aria-hidden", "true");
  svg.appendChild(contorno);
  var destacado = null;

  var porUf = {};
  var dica = document.getElementById("dica"), tbody = document.getElementById("ranking");

  function faixa(pos, total){ return Math.min(FAIXAS, Math.floor((pos - 1) * FAIXAS / total) + 1); }

  function desenhar(produto){
    var linhas = D.precos.filter(function(l){ return l.produto === produto; })
      .sort(function(a, b){ return a.preco_medio - b.preco_medio || a.uf.localeCompare(b.uf); });
    porUf = {};
    linhas.forEach(function(l, i){
      var anterior = i > 0 ? porUf[linhas[i - 1].uf] : null;
      // Preço médio empatado fica na mesma faixa (mesma cor) do anterior.
      var f = anterior && anterior.linha.preco_medio === l.preco_medio ? anterior.faixa : faixa(i + 1, linhas.length);
      porUf[l.uf] = {linha: l, pos: i + 1, total: linhas.length, faixa: f};
    });
    Object.keys(caminhos).forEach(function(uf){
      var info = porUf[uf], p = caminhos[uf];
      p.style.fill = info ? "var(--f" + info.faixa + ")" : "var(--sem-dado)";
      p.setAttribute("aria-label", D.nomes[uf] + (info ? ": " + reais.format(info.linha.preco_medio) +
        ", " + info.pos + "º mais barato de " + info.total : ": sem coletas"));
    });

    tbody.innerHTML = "";
    linhas.forEach(function(l, i){
      var tr = document.createElement("tr");
      tr.dataset.uf = l.uf;
      tr.innerHTML = "<td>" + (i + 1) + "º</td><td><span class=\"cor\"></span></td><td>" +
        numero.format(l.preco_medio) + "</td><td>" + numero.format(l.preco_min) + "</td><td>" + numero.format(l.preco_max) + "</td>";
      tr.querySelector(".cor").style.background = "var(--f" + porUf[l.uf].faixa + ")";
      tr.children[1].appendChild(document.createTextNode(D.nomes[l.uf] || l.uf));
      tbody.appendChild(tr);
    });

    var leg = document.getElementById("legenda");
    leg.innerHTML = "";
    for (var f = 1; f <= FAIXAS; f++) {
      var membros = linhas.filter(function(l){ return porUf[l.uf].faixa === f; });
      if (!membros.length) continue;
      var div = document.createElement("div"), cor = document.createElement("span");
      cor.style.background = "var(--f" + f + ")";
      div.appendChild(cor);
      var de = membros[0].preco_medio, ate = membros[membros.length - 1].preco_medio;
      div.appendChild(document.createTextNode(de === ate ? numero.format(de) : numero.format(de) + " – " + numero.format(ate)));
      leg.appendChild(div);
    }
    esconder();
  }

  function destacar(uf){
    if (uf === destacado) return;
    destacado = uf;
    if (uf && caminhos[uf]) contorno.setAttribute("d", caminhos[uf].getAttribute("d"));
    else contorno.removeAttribute("d");
    Array.prototype.forEach.call(tbody.children, function(tr){ tr.classList.toggle("ativo", tr.dataset.uf === uf); });
  }

  function mostrar(uf, x, y){
    var info = porUf[uf], nome = D.nomes[uf] || uf;
    dica.innerHTML = "";
    var t = document.createElement("strong"); t.textContent = nome + " (" + uf + ")"; dica.appendChild(t);
    var pos = document.createElement("div"); pos.className = "pos";
    if (info) {
      pos.textContent = info.pos === 1 ? "Mais barato do país" :
        info.pos === info.total ? "Mais caro do país" : info.pos + "º mais barato de " + info.total;
      dica.appendChild(pos);
      var dl = document.createElement("dl");
      [["Preço médio", reais.format(info.linha.preco_medio)], ["Mínimo", reais.format(info.linha.preco_min)],
       ["Máximo", reais.format(info.linha.preco_max)], ["Coletas", inteiro.format(info.linha.coletas)]]
        .forEach(function(par){
          var dt = document.createElement("dt"), dd = document.createElement("dd");
          dt.textContent = par[0]; dd.textContent = par[1]; dl.appendChild(dt); dl.appendChild(dd);
        });
      dica.appendChild(dl);
    } else {
      pos.textContent = "Sem coletas deste produto no período"; dica.appendChild(pos);
    }
    destacar(uf);
    dica.classList.add("visivel");
    var w = dica.offsetWidth, h = dica.offsetHeight, m = 12;
    var left = x + m + w > window.innerWidth - 8 ? x - m - w : x + m;
    var top = Math.min(Math.max(8, y - h / 2), window.innerHeight - h - 8);
    dica.style.left = Math.max(8, left) + "px";
    dica.style.top = top + "px";
  }

  function esconder(){ dica.classList.remove("visivel"); destacar(null); }

  svg.addEventListener("pointermove", function(e){
    var uf = e.target.dataset && e.target.dataset.uf;
    if (uf) mostrar(uf, e.clientX, e.clientY); else esconder();
  });
  svg.addEventListener("pointerleave", esconder);
  svg.addEventListener("focusin", function(e){
    var r = e.target.getBoundingClientRect();
    mostrar(e.target.dataset.uf, r.right, r.top + r.height / 2);
  });
  svg.addEventListener("focusout", esconder);
  tbody.addEventListener("pointermove", function(e){
    var tr = e.target.closest("tr"); if (!tr || !caminhos[tr.dataset.uf]) return;
    var r = caminhos[tr.dataset.uf].getBoundingClientRect();
    mostrar(tr.dataset.uf, r.left + r.width / 2, r.top + r.height / 2);
  });
  tbody.addEventListener("pointerleave", esconder);

  var botoes = document.getElementById("produtos");
  produtos.forEach(function(p, i){
    var b = document.createElement("button");
    b.type = "button"; b.textContent = ROTULO[p] || p; b.dataset.produto = p;
    b.setAttribute("aria-pressed", i === 0 ? "true" : "false");
    botoes.appendChild(b);
  });
  botoes.addEventListener("click", function(e){
    var b = e.target.closest("button"); if (!b) return;
    Array.prototype.forEach.call(botoes.children, function(x){ x.setAttribute("aria-pressed", x === b ? "true" : "false"); });
    desenhar(b.dataset.produto);
  });
  if (produtos.length) desenhar(produtos[0]);
})();
