// Mapa da home: lê os dados embutidos em #dados e desenha mapa, legenda e ranking.
(function(){
  var D = JSON.parse(document.getElementById("dados").textContent);
  var ORDEM = ["GASOLINA","GASOLINA ADITIVADA","ETANOL","DIESEL","DIESEL S10","GNV"];
  var ROTULO = {"GASOLINA":"Gasolina comum","GASOLINA ADITIVADA":"Gasolina aditivada","ETANOL":"Etanol",
                "DIESEL":"Diesel","DIESEL S10":"Diesel S10","GNV":"GNV"};
  var FAIXAS = 5;
  var FOSSEIS = ["GASOLINA","GASOLINA ADITIVADA","DIESEL","DIESEL S10"];
  // Camadas de pontos por cima do mapa; cada uma aparece só nos produtos dela.
  var CAMADAS = [
    {chave:"refinarias", simbolo:"refinaria", rotulo:"Refinarias", tipo:"Refinaria de petróleo",
     perto:"Refinaria mais perto", produtos:FOSSEIS},
    {chave:"portos", simbolo:"porto", rotulo:"Portos", tipo:"Porto que recebe combustível importado",
     perto:"Porto mais perto", produtos:FOSSEIS},
    {chave:"polos_etanol", simbolo:"etanol", rotulo:"Polos de usinas", tipo:"Polo de usinas de etanol",
     perto:"Polo de etanol mais perto", produtos:["ETANOL"]},
    {chave:"gasodutos", linha:"gasoduto", simbolo:"gas", rotulo:"Gasoduto", tipo:"Gasoduto", produtos:["GNV"]},
    {chave:"ferrovias", linha:"ferrovia", simbolo:"trem", rotulo:"Ferrovias", tipo:"Ferrovia", produtos:FOSSEIS},
    {chave:"rodovias", linha:"rodovia", simbolo:"caminhao", rotulo:"Rodovia", tipo:"Rodovia", produtos:FOSSEIS}
  ];
  // Traços sobrepostos de cada tipo de rota, de baixo para cima (estilo em estilo.css).
  var TRACOS = {
    gasoduto: ["cano-borda", "cano", "cano-fluxo"],
    ferrovia: ["trilho", "trilho-vao", "trilho-dormente"],
    rodovia: ["estrada", "estrada-faixa"]
  };
  var ligada = {};
  CAMADAS.forEach(function(c){ ligada[c.chave] = true; });
  var reais = new Intl.NumberFormat("pt-BR",{style:"currency",currency:"BRL",minimumFractionDigits:3,maximumFractionDigits:3});
  var numero = new Intl.NumberFormat("pt-BR",{minimumFractionDigits:3,maximumFractionDigits:3});
  var inteiro = new Intl.NumberFormat("pt-BR");
  // Sprite com as bandeiras em ordem alfabética da sigla (scripts/gerar_bandeiras.py).
  var SIGLAS = Object.keys(D.nomes).sort();
  function bandeira(uf){
    var b = document.createElement("span"), i = SIGLAS.indexOf(uf);
    b.className = "bandeira-uf";
    b.setAttribute("aria-hidden", "true");
    if (i >= 0 && D.bandeiras) {
      b.style.backgroundImage = "url(" + D.bandeiras + ")";
      // Em % para a bandeira acompanhar o tamanho da caixa (menor no celular).
      b.style.backgroundSize = (SIGLAS.length * 100) + "% 100%";
      b.style.backgroundPosition = (i * 100 / (SIGLAS.length - 1)) + "% 0";
    }
    return b;
  }
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
    p.setAttribute("class", "uf");
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

  // Bonecos das camadas, desenhados em coordenadas próprias (viewBox -11 -16 22 28).
  var ROSTO = function(dy){
    return '<circle class="bochecha" cx="-5" cy="' + (5 + dy) + '" r="1.3"/><circle class="bochecha" cx="5" cy="' + (5 + dy) + '" r="1.3"/>' +
      '<circle class="olho" cx="-2.8" cy="' + (2.5 + dy) + '" r="1.3"/><circle class="olho" cx="2.8" cy="' + (2.5 + dy) + '" r="1.3"/>' +
      '<circle class="brilho" cx="-2.4" cy="' + (2 + dy) + '" r=".45"/><circle class="brilho" cx="3.2" cy="' + (2 + dy) + '" r=".45"/>' +
      '<path class="boca" d="M-2,' + (5.2 + dy) + 'Q0,' + (7.2 + dy) + ' 2,' + (5.2 + dy) + '"/>';
  };
  var GOTA = "M0,-10C4,-4 8,-1 8,3A8,8 0 0 1 -8,3C-8,-1 -4,-4 0,-10Z";
  var CHAMA = "M0,-13C5,-7 9,-3 8,3A8,8 0 0 1 -8,3C-8,-2 -4,-4 -3,-9C-1.5,-6 -0.5,-5.5 1,-4.5C2,-7.5 1.5,-10 0,-13Z";
  var defs = document.createElementNS(NS, "defs");
  defs.innerHTML =
    '<symbol id="s-refinaria" viewBox="-11 -16 22 28">' +
      '<circle class="fumaca" cx="6.5" cy="-12.5" r="2.2"/><circle class="fumaca" cx="9" cy="-14.5" r="1.4"/>' +
      '<rect class="chamine" x="4" y="-10" width="3.5" height="9" rx=".8"/>' +
      '<path class="halo-boneco" d="' + GOTA + '"/>' +
      '<path class="gota refinaria" d="' + GOTA + '"/>' + ROSTO(0) + '</symbol>' +
    '<symbol id="s-etanol" viewBox="-11 -16 22 28">' +
      '<path class="folha" d="M0,-10C2,-14 6,-15 9.5,-14C7.5,-11 4,-9 0,-10Z"/>' +
      '<path class="halo-boneco" d="' + GOTA + '"/>' +
      '<path class="gota alcool" d="' + GOTA + '"/>' + ROSTO(0) + '</symbol>' +
    '<symbol id="s-porto" viewBox="-11 -16 22 28">' +
      '<rect class="cabine" x="-.6" y="-13" width="1.2" height="9"/><path class="bandeira" d="M.6,-13L6,-11L.6,-9Z"/>' +
      '<rect class="cabine" x="-5" y="-5" width="8" height="5.5" rx="1.5"/>' +
      '<path class="halo-boneco" d="M-10,0H10L7,8.5H-7Z"/><path class="casco" d="M-10,0H10L7,8.5H-7Z"/>' + ROSTO(-0.5) +
      '<path class="onda" d="M-10,10.5Q-7.5,9 -5,10.5T0,10.5T5,10.5T10,10.5"/></symbol>' +
    '<symbol id="s-gas" viewBox="-11 -16 22 28">' +
      '<path class="halo-boneco" d="' + CHAMA + '"/><path class="chama" d="' + CHAMA + '"/>' +
      '<path class="chama-miolo" d="M0,-4C2.5,-1 3.5,1 3,3.5A3,3 0 0 1 -3,3.5C-3,1.5 -1.5,0 0,-4Z"/>' + ROSTO(0) + '</symbol>' +
    '<symbol id="s-trem" viewBox="-11 -16 22 28">' +
      '<circle class="fumaca" cx="-5" cy="-13" r="2"/><circle class="fumaca" cx="-8" cy="-14.5" r="1.3"/>' +
      '<rect class="trem-chamine" x="-6.5" y="-11.5" width="3" height="4" rx=".6"/>' +
      '<rect class="halo-boneco" x="-9" y="-8" width="18" height="15" rx="4"/>' +
      '<rect class="trem" x="-9" y="-8" width="18" height="15" rx="4"/>' +
      '<rect class="janela" x="-6" y="-6" width="12" height="4.5" rx="1.5"/>' +
      '<circle class="roda" cx="-5" cy="8" r="2.4"/><circle class="roda" cx="5" cy="8" r="2.4"/>' + ROSTO(-0.5) + '</symbol>' +
    '<symbol id="s-caminhao" viewBox="-11 -16 22 28">' +
      '<rect class="halo-boneco" x="-10.5" y="-7" width="21" height="11" rx="4"/>' +
      '<rect class="cabine-caminhao" x="3" y="-7" width="7.5" height="11" rx="2"/>' +
      '<rect class="janela" x="5" y="-5.5" width="4" height="3.5" rx="1"/>' +
      '<rect class="tanque" x="-10.5" y="-6" width="14.5" height="10" rx="5"/>' +
      '<circle class="roda" cx="-6" cy="5.5" r="2.4"/><circle class="roda" cx="6.5" cy="5.5" r="2.4"/>' +
      '<circle class="olho" cx="-6" cy="-1.5" r="1.2"/><circle class="olho" cx="-0.5" cy="-1.5" r="1.2"/>' +
      '<path class="boca" d="M-5,1Q-3.2,2.8 -1.5,1"/><circle class="bochecha" cx="-8.5" cy=".8" r="1.1"/>' +
      '<circle class="bochecha" cx="1.8" cy=".8" r="1.1"/></symbol>';
  svg.insertBefore(defs, svg.firstChild);
  var rotas = document.createElementNS(NS, "g");
  svg.appendChild(rotas);
  var pontos = document.createElementNS(NS, "g");
  pontos.setAttribute("class", "pontos");
  svg.appendChild(pontos);

  var P = D.mapa.projecao, INST = D.instalacoes || {};
  function projetar(lon, lat){ return [(lon - P.lon_min) * P.k * P.escala, (P.lat_max - lat) * P.escala]; }
  function lonLat(x, y){ return [x / (P.k * P.escala) + P.lon_min, P.lat_max - y / P.escala]; }
  function km(a, b){
    var r = Math.PI / 180, dLat = (b[1] - a[1]) * r, dLon = (b[0] - a[0]) * r;
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(a[1] * r) * Math.cos(b[1] * r) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 6371 * 2 * Math.asin(Math.sqrt(h));
  }
  var produtoAtual = null, itens = [];

  function pontoNoMeio(xy){
    var total = 0, i;
    for (i = 1; i < xy.length; i++) total += Math.hypot(xy[i][0] - xy[i - 1][0], xy[i][1] - xy[i - 1][1]);
    var falta = total / 2;
    for (i = 1; i < xy.length; i++) {
      var dx = xy[i][0] - xy[i - 1][0], dy = xy[i][1] - xy[i - 1][1], seg = Math.hypot(dx, dy);
      if (falta <= seg) return [xy[i - 1][0] + dx * falta / seg, xy[i - 1][1] + dy * falta / seg];
      falta -= seg;
    }
    return xy[xy.length - 1];
  }

  function camadasDoProduto(){
    return CAMADAS.filter(function(c){ return c.produtos.indexOf(produtoAtual) >= 0 && (INST[c.chave] || []).length; });
  }

  function desenharPontos(){
    pontos.innerHTML = "";
    itens = [];
    rotas.innerHTML = "";
    camadasDoProduto().forEach(function(c){
      if (!ligada[c.chave]) return;
      if (c.linha) return INST[c.chave].forEach(function(rota){
        var xy = rota.pontos.map(function(p){ return projetar(p[0], p[1]); });
        var d = "M" + xy.map(function(p){ return p[0].toFixed(1) + "," + p[1].toFixed(1); }).join("L");
        var g = document.createElementNS(NS, "g");
        g.setAttribute("class", "rota " + c.linha);
        ["rota-halo"].concat(TRACOS[c.linha], ["rota-alvo"]).forEach(function(classe){
          var p = document.createElementNS(NS, "path");
          p.setAttribute("d", d); p.setAttribute("class", classe);
          g.appendChild(p);
        });
        var alvo = g.lastChild;
        alvo.setAttribute("tabindex", "0");
        alvo.setAttribute("aria-label", c.tipo + " " + rota.nome + ": " + rota.descricao);
        alvo.dataset.item = itens.length;
        rotas.appendChild(g);
        // O boneco da rota fica no meio do caminho e mostra a mesma dica.
        var meio = pontoNoMeio(xy);
        itens.push({camada: c, inst: {nome: rota.nome, cidade: rota.descricao}, x: meio[0], y: meio[1]});
      });
      INST[c.chave].forEach(function(inst){
        var xy = projetar(inst.lon, inst.lat);
        itens.push({camada: c, inst: inst, x: xy[0], y: xy[1]});
      });
    });
    // Afasta bonecos sobrepostos (SP, por exemplo); a posição real segue nas contas de distância.
    var MIN = 15, bonecos = itens;
    for (var it = 0; it < 40; it++) {
      for (var i = 0; i < bonecos.length; i++) for (var j = i + 1; j < bonecos.length; j++) {
        var a = bonecos[i], b = bonecos[j], dx = b.x - a.x, dy = b.y - a.y, d = Math.hypot(dx, dy);
        if (d >= MIN) continue;
        if (d < 0.01) { dx = 1; dy = 0; d = 1; }
        var m = (MIN - d) / 2 / d;
        a.x -= dx * m; a.y -= dy * m; b.x += dx * m; b.y += dy * m;
      }
    }
    itens.forEach(function(item, i){
      var g = document.createElementNS(NS, "g");
      g.setAttribute("class", "ponto");
      g.setAttribute("transform", "translate(" + item.x.toFixed(1) + "," + item.y.toFixed(1) + ")");
      g.setAttribute("tabindex", "0");
      g.setAttribute("aria-label", item.camada.tipo + ": " + item.inst.nome + ", " + item.inst.cidade);
      g.dataset.item = i;
      var u = document.createElementNS(NS, "use");
      u.setAttribute("href", "#s-" + item.camada.simbolo);
      u.setAttribute("class", "boneco");
      u.setAttribute("x", "-9.5"); u.setAttribute("y", "-16.5"); u.setAttribute("width", "19"); u.setAttribute("height", "24.2");
      u.style.animationDelay = (i * 25) + "ms";
      g.appendChild(u);
      pontos.appendChild(g);
    });
  }

  var camadasEl = document.getElementById("camadas");
  function desenharCamadas(){
    camadasEl.innerHTML = "";
    camadasDoProduto().forEach(function(c){
      var label = document.createElement("label"), cb = document.createElement("input");
      label.className = "mostrar";
      cb.type = "checkbox"; cb.checked = ligada[c.chave]; cb.dataset.camada = c.chave;
      var ico = document.createElementNS(NS, "svg"), u = document.createElementNS(NS, "use");
      ico.setAttribute("viewBox", "-11 -16 22 28"); ico.setAttribute("aria-hidden", "true");
      u.setAttribute("href", "#s-" + c.simbolo);
      u.setAttribute("x", "-11"); u.setAttribute("y", "-16"); u.setAttribute("width", "22"); u.setAttribute("height", "28");
      ico.appendChild(u);
      if (c.linha) {
        // Amostra do traço da rota ao lado do boneco.
        var amostra = document.createElementNS(NS, "svg");
        amostra.setAttribute("viewBox", "0 0 30 12"); amostra.setAttribute("aria-hidden", "true");
        amostra.setAttribute("class", "amostra rota " + c.linha);
        TRACOS[c.linha].forEach(function(classe){
          var p = document.createElementNS(NS, "path");
          p.setAttribute("d", "M3,6H27"); p.setAttribute("class", classe);
          amostra.appendChild(p);
        });
        label.appendChild(cb); label.appendChild(ico); label.appendChild(amostra);
        label.appendChild(document.createTextNode(c.rotulo));
        return camadasEl.appendChild(label);
      }
      label.appendChild(cb); label.appendChild(ico); label.appendChild(document.createTextNode(c.rotulo));
      camadasEl.appendChild(label);
    });
  }
  camadasEl.addEventListener("change", function(e){
    ligada[e.target.dataset.camada] = e.target.checked;
    desenharPontos();
  });

  // Mais perto do centro do estado (centro da caixa do contorno), em linha reta.
  function maisPerto(uf){
    var caixa = caminhos[uf].getBBox(), centro = lonLat(caixa.x + caixa.width / 2, caixa.y + caixa.height / 2);
    return camadasDoProduto().filter(function(c){ return ligada[c.chave] && !c.linha; }).map(function(c){
      var melhor = null;
      INST[c.chave].forEach(function(inst){
        var d = km(centro, [inst.lon, inst.lat]);
        if (!melhor || d < melhor.d) melhor = {inst: inst, d: d};
      });
      return {camada: c, inst: melhor.inst, d: melhor.d};
    });
  }

  var porUf = {};
  var dica = document.getElementById("dica"), tbody = document.getElementById("ranking");

  function faixa(pos, total){ return Math.min(FAIXAS, Math.floor((pos - 1) * FAIXAS / total) + 1); }

  function desenhar(produto){
    produtoAtual = produto;
    desenharCamadas();
    desenharPontos();
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
      tr.children[1].appendChild(bandeira(l.uf));
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
    var t = document.createElement("strong");
    t.appendChild(bandeira(uf)); t.appendChild(document.createTextNode(nome + " (" + uf + ")")); dica.appendChild(t);
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
    maisPerto(uf).forEach(function(p){
      var div = document.createElement("div"), b = document.createElement("b");
      div.className = "perto";
      div.appendChild(document.createTextNode(p.camada.perto + ": "));
      b.textContent = p.inst.nome; div.appendChild(b);
      div.appendChild(document.createTextNode(", " + p.inst.cidade +
        (p.d < 30 ? " · no estado" : " · ~" + inteiro.format(Math.round(p.d / 10) * 10) + " km")));
      dica.appendChild(div);
    });
    destacar(uf);
    posicionar(x, y);
  }

  function mostrarPonto(i, x, y){
    var item = itens[i];
    dica.innerHTML = "";
    var t = document.createElement("strong"); t.textContent = item.inst.nome; dica.appendChild(t);
    var pos = document.createElement("div"); pos.className = "pos"; pos.textContent = item.camada.tipo; dica.appendChild(pos);
    dica.appendChild(document.createTextNode(item.inst.cidade));
    destacar(null);
    posicionar(x, y);
  }

  function posicionar(x, y){
    dica.classList.add("visivel");
    var w = dica.offsetWidth, h = dica.offsetHeight, m = 12;
    var left = x + m + w > window.innerWidth - 8 ? x - m - w : x + m;
    var top = Math.min(Math.max(8, y - h / 2), window.innerHeight - h - 8);
    dica.style.left = Math.max(8, left) + "px";
    dica.style.top = top + "px";
  }

  function esconder(){ dica.classList.remove("visivel"); destacar(null); }

  function apontar(e){
    var ponto = e.target.closest && e.target.closest("[data-item]");
    if (ponto) return mostrarPonto(+ponto.dataset.item, e.clientX, e.clientY);
    var uf = e.target.dataset && e.target.dataset.uf;
    if (uf) mostrar(uf, e.clientX, e.clientY); else esconder();
  }
  svg.addEventListener("pointermove", apontar);
  // No celular não há "passar o mouse": o toque mostra a dica e tocar fora esconde.
  svg.addEventListener("click", apontar);
  document.addEventListener("click", function(e){
    if (!svg.contains(e.target) && !tbody.contains(e.target)) esconder();
  });
  svg.addEventListener("pointerleave", esconder);
  svg.addEventListener("focusin", function(e){
    var r = e.target.getBoundingClientRect();
    if (e.target.dataset.item !== undefined) mostrarPonto(+e.target.dataset.item, r.right, r.top + r.height / 2);
    else mostrar(e.target.dataset.uf, r.right, r.top + r.height / 2);
  });
  svg.addEventListener("focusout", esconder);
  function apontarLinha(e){
    var tr = e.target.closest("tr"); if (!tr || !caminhos[tr.dataset.uf]) return;
    var r = caminhos[tr.dataset.uf].getBoundingClientRect();
    mostrar(tr.dataset.uf, r.left + r.width / 2, r.top + r.height / 2);
  }
  tbody.addEventListener("pointermove", apontarLinha);
  tbody.addEventListener("click", apontarLinha);
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
