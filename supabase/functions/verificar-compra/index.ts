// =====================================================================
// verificar-compra — confere com o GOOGLE se a compra de moedas é verdadeira e paga, e só então dá as moedas.
// O jogo (scripts/sistema/loja_moedas.gd) chama: POST /functions/v1/verificar-compra {token, produto}
// com o login da pessoa. Responde {ok, novo, moedas_ganhas, em_dobro, saldo} ou {ok:false, erro, pendente?}.
//
// SEGREDOS (Supabase > Edge Functions > Secrets):
//   GOOGLE_SERVICE_ACCOUNT_JSON  = o arquivo .json inteiro da conta de serviço do Google Cloud
//   PLAY_PACOTE                  = com.danielsoucristo.heroesvsmonsters   (opcional: já é o padrão)
// (SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY o Supabase já coloca sozinho)
//
// Publicar:  supabase functions deploy verificar-compra
// =====================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const PACOTE = Deno.env.get("PLAY_PACOTE") ?? "com.danielsoucristo.heroesvsmonsters";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

function resposta(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function b64url(dados: Uint8Array | string): string {
  const bytes = typeof dados === "string" ? new TextEncoder().encode(dados) : dados;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Token de acesso do Google para a conta de serviço (JWT assinado com a chave dela). Guarda até vencer.
let cacheToken = { valor: "", vence: 0 };
async function tokenGoogle(): Promise<string> {
  const agora = Math.floor(Date.now() / 1000);
  if (cacheToken.valor && agora < cacheToken.vence - 60) return cacheToken.valor;
  const sa = JSON.parse(Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? "{}");
  if (!sa.client_email || !sa.private_key) throw new Error("falta o segredo GOOGLE_SERVICE_ACCOUNT_JSON");
  const cab = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const corpo = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: agora,
    exp: agora + 3600,
  }));
  const pem = String(sa.private_key).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const chave = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const assinatura = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", chave, new TextEncoder().encode(`${cab}.${corpo}`)));
  const jwt = `${cab}.${corpo}.${b64url(assinatura)}`;
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = await r.json();
  if (!r.ok || !j.access_token) throw new Error("Google recusou a conta de serviço: " + JSON.stringify(j));
  cacheToken = { valor: j.access_token, vence: agora + Number(j.expires_in ?? 3600) };
  return cacheToken.valor;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return resposta({ ok: false, erro: "use POST" }, 405);
  try {
    // 1) quem está comprando (o login do jogo)
    const url = Deno.env.get("SUPABASE_URL")!;
    const adm = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return resposta({ ok: false, erro: "entre na sua conta para comprar" }, 401);
    const { data: quem, error: semLogin } = await adm.auth.getUser(jwt);
    if (semLogin || !quem?.user) return resposta({ ok: false, erro: "entre na sua conta para comprar" }, 401);
    const usuario = quem.user.id;

    const { token, produto } = await req.json();
    if (typeof token !== "string" || token.length < 10 || typeof produto !== "string" || !/^[a-z0-9_.]+$/.test(produto)) {
      return resposta({ ok: false, erro: "compra inválida" }, 400);
    }

    // 2) pergunta ao Google sobre esta compra
    const g = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACOTE}/purchases/products/${produto}/tokens/${encodeURIComponent(token)}`,
      { headers: { Authorization: `Bearer ${await tokenGoogle()}` } },
    );
    const compra = await g.json();
    if (!g.ok) {
      console.error("Google:", g.status, JSON.stringify(compra));
      return resposta({ ok: false, erro: "o Google não confirmou esta compra" }, 400);
    }
    // purchaseState: 0 = paga, 1 = cancelada, 2 = pendente (ex.: boleto ainda não pago)
    if (compra.purchaseState === 2) return resposta({ ok: false, pendente: true, erro: "pagamento ainda pendente" });
    if (compra.purchaseState !== 0) return resposta({ ok: false, erro: "compra cancelada" }, 400);
    // a compra leva o id da conta do jogo (setObfuscatedAccountId): ninguém usa a compra de outra pessoa
    if (compra.obfuscatedExternalAccountId && compra.obfuscatedExternalAccountId !== usuario) {
      return resposta({ ok: false, erro: "esta compra é de outra conta" }, 403);
    }

    // 3) dá as moedas (uma vez por token) — só a chave service_role consegue chamar
    const { data, error } = await adm.rpc("creditar_compra_moedas", {
      p_usuario: usuario,
      p_token: token,
      p_produto: produto,
      p_pedido: compra.orderId ?? "",
      p_teste: compra.purchaseType === 0,           // 0 = compra de testador de licença (ninguém pagou)
    });
    if (error) {
      console.error("creditar:", error);
      return resposta({ ok: false, erro: error.message }, 400);
    }
    return resposta({ ok: true, ...data });
  } catch (e) {
    console.error(e);
    return resposta({ ok: false, erro: String((e as Error)?.message ?? e) }, 500);
  }
});
