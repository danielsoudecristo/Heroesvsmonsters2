package com.hvm;

import android.app.Activity;
import android.util.Log;

import androidx.annotation.NonNull;

import com.android.billingclient.api.AccountIdentifiers;
import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.ConsumeParams;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryPurchasesParams;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * LOJA DE MOEDAS PELA GOOGLE PLAY (Heroes vs Monsters) — Google Play Billing Library 8.
 * No GDScript (scripts/sistema/loja_moedas.gd): var p = Engine.get_singleton("LojaPlay")
 *   p.conectar()                 -> liga com a Play Store (responde em estado())
 *   p.estado()                   -> "" conectando / "pronto" / "erro:<código>:<texto>"
 *   p.buscar_produtos("a,b,c")   -> pergunta preços e nomes (responde em produtos())
 *   p.produtos()                 -> JSON [{id, titulo, preco, micros, moeda}]  (preço já no formato do país: "R$ 4,90")
 *   p.comprar(id, conta)         -> abre a janela de pagamento do Google (conta = id da conta do jogo, vai junto na compra)
 *   p.recuperar()                -> procura compras pagas que ainda não foram entregues (vão para eventos())
 *   p.consumir(token)            -> marca a compra como entregue (aí dá para comprar o mesmo pacote de novo)
 *   p.eventos()                  -> JSON com o que aconteceu desde a última pergunta (e esvazia a fila):
 *        {"tipo":"compra","token","produto","pedido","estado":"pago"|"pendente","conta"}
 *        {"tipo":"cancelou"}  {"tipo":"erro","codigo","texto"}  {"tipo":"consumiu","token","ok"}
 */
public class LojaPlay extends GodotPlugin {
    private static final String TAG = "LojaPlay";
    private BillingClient cliente;
    private volatile String estado = "";
    private volatile String produtosJson = "[]";
    private final Map<String, ProductDetails> detalhes = new HashMap<>();
    private final List<JSONObject> fila = new ArrayList<>();

    private final PurchasesUpdatedListener ouvinte = (resultado, compras) -> {
        int c = resultado.getResponseCode();
        if (c == BillingClient.BillingResponseCode.OK && compras != null) {
            for (Purchase p : compras) avisarCompra(p);
        } else if (c == BillingClient.BillingResponseCode.USER_CANCELED) {
            avisar(evento("cancelou"));
        } else if (c == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) {
            recuperar();                                  // já pagou antes e não foi entregue: entrega agora
        } else {
            JSONObject e = evento("erro");
            try {
                e.put("codigo", c);
                e.put("texto", resultado.getDebugMessage());
            } catch (Exception ignored) { }
            avisar(e);
        }
    };

    public LojaPlay(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "LojaPlay";
    }

    private JSONObject evento(String tipo) {
        JSONObject e = new JSONObject();
        try { e.put("tipo", tipo); } catch (Exception ignored) { }
        return e;
    }

    private void avisar(JSONObject e) {
        synchronized (fila) { fila.add(e); }
    }

    private void avisarCompra(Purchase p) {
        int st = p.getPurchaseState();
        if (st != Purchase.PurchaseState.PURCHASED && st != Purchase.PurchaseState.PENDING) return;
        JSONObject e = evento("compra");
        try {
            e.put("token", p.getPurchaseToken());
            e.put("produto", p.getProducts().isEmpty() ? "" : p.getProducts().get(0));
            e.put("pedido", p.getOrderId() == null ? "" : p.getOrderId());
            e.put("estado", st == Purchase.PurchaseState.PURCHASED ? "pago" : "pendente");
            AccountIdentifiers ids = p.getAccountIdentifiers();
            e.put("conta", ids != null && ids.getObfuscatedAccountId() != null ? ids.getObfuscatedAccountId() : "");
        } catch (Exception ignored) { }
        avisar(e);
    }

    @UsedByGodot
    public String estado() {
        return estado;
    }

    @UsedByGodot
    public String produtos() {
        return produtosJson;
    }

    @UsedByGodot
    public String eventos() {
        JSONArray a = new JSONArray();
        synchronized (fila) {
            for (JSONObject e : fila) a.put(e);
            fila.clear();
        }
        return a.toString();
    }

    @UsedByGodot
    public void conectar() {
        final Activity act = getActivity();
        if (act == null) {
            estado = "erro:0:sem activity";
            return;
        }
        if (cliente != null && cliente.isReady()) {
            estado = "pronto";
            return;
        }
        estado = "";
        act.runOnUiThread(() -> {
            try {
                if (cliente == null) {
                    cliente = BillingClient.newBuilder(act)
                            .setListener(ouvinte)
                            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                            .build();
                }
                cliente.startConnection(new BillingClientStateListener() {
                    @Override
                    public void onBillingSetupFinished(@NonNull BillingResult r) {
                        if (r.getResponseCode() == BillingClient.BillingResponseCode.OK) {
                            estado = "pronto";
                        } else {
                            estado = "erro:" + r.getResponseCode() + ":" + r.getDebugMessage();
                        }
                    }

                    @Override
                    public void onBillingServiceDisconnected() {
                        estado = "erro:-1:desconectou";       // o GDScript chama conectar() de novo
                    }
                });
            } catch (Exception e) {
                Log.w(TAG, "conectar", e);
                estado = "erro:0:" + e.getMessage();
            }
        });
    }

    @UsedByGodot
    public void buscar_produtos(String ids) {
        if (cliente == null || !cliente.isReady()) return;
        List<QueryProductDetailsParams.Product> lista = new ArrayList<>();
        for (String id : ids.split(",")) {
            String s = id.trim();
            if (s.isEmpty()) continue;
            lista.add(QueryProductDetailsParams.Product.newBuilder()
                    .setProductId(s)
                    .setProductType(BillingClient.ProductType.INAPP)
                    .build());
        }
        if (lista.isEmpty()) return;
        QueryProductDetailsParams params = QueryProductDetailsParams.newBuilder().setProductList(lista).build();
        cliente.queryProductDetailsAsync(params, (r, resultado) -> {
            if (r.getResponseCode() != BillingClient.BillingResponseCode.OK || resultado == null) {
                Log.w(TAG, "produtos: " + r.getResponseCode() + " " + r.getDebugMessage());
                return;
            }
            JSONArray a = new JSONArray();
            for (ProductDetails d : resultado.getProductDetailsList()) {
                detalhes.put(d.getProductId(), d);
                ProductDetails.OneTimePurchaseOfferDetails o = d.getOneTimePurchaseOfferDetails();
                JSONObject j = new JSONObject();
                try {
                    j.put("id", d.getProductId());
                    j.put("titulo", d.getName());
                    j.put("preco", o != null ? o.getFormattedPrice() : "");
                    j.put("micros", o != null ? o.getPriceAmountMicros() : 0);
                    j.put("moeda", o != null ? o.getPriceCurrencyCode() : "");
                } catch (Exception ignored) { }
                a.put(j);
            }
            produtosJson = a.toString();
        });
    }

    @UsedByGodot
    public void comprar(final String id, final String conta) {
        final Activity act = getActivity();
        final ProductDetails d = detalhes.get(id);
        if (act == null || cliente == null || !cliente.isReady() || d == null) {
            JSONObject e = evento("erro");
            try {
                e.put("codigo", -100);
                e.put("texto", d == null ? "produto não encontrado na Play Store" : "loja não conectada");
            } catch (Exception ignored) { }
            avisar(e);
            return;
        }
        act.runOnUiThread(() -> {
            try {
                BillingFlowParams.Builder b = BillingFlowParams.newBuilder()
                        .setProductDetailsParamsList(Collections.singletonList(
                                BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(d).build()));
                if (conta != null && !conta.isEmpty()) b.setObfuscatedAccountId(conta);   // o servidor confere de quem é
                BillingResult r = cliente.launchBillingFlow(act, b.build());
                if (r.getResponseCode() != BillingClient.BillingResponseCode.OK) ouvinte.onPurchasesUpdated(r, null);
            } catch (Exception e) {
                Log.w(TAG, "comprar", e);
                JSONObject ev = evento("erro");
                try {
                    ev.put("codigo", -101);
                    ev.put("texto", e.getMessage());
                } catch (Exception ignored) { }
                avisar(ev);
            }
        });
    }

    @UsedByGodot
    public void recuperar() {
        if (cliente == null || !cliente.isReady()) return;
        cliente.queryPurchasesAsync(
                QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),
                (r, compras) -> {
                    if (r.getResponseCode() == BillingClient.BillingResponseCode.OK && compras != null) {
                        for (Purchase p : compras) avisarCompra(p);
                    }
                });
    }

    @UsedByGodot
    public void consumir(final String token) {
        if (cliente == null || !cliente.isReady()) return;
        cliente.consumeAsync(ConsumeParams.newBuilder().setPurchaseToken(token).build(), (r, t) -> {
            JSONObject e = evento("consumiu");
            try {
                e.put("token", token);
                e.put("ok", r.getResponseCode() == BillingClient.BillingResponseCode.OK
                        || r.getResponseCode() == BillingClient.BillingResponseCode.ITEM_NOT_OWNED);
            } catch (Exception ignored) { }
            avisar(e);
        });
    }

    @Override
    public void onMainDestroy() {
        if (cliente != null) {
            try { cliente.endConnection(); } catch (Exception ignored) { }
        }
        super.onMainDestroy();
    }
}
