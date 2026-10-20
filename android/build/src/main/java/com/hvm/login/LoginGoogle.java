package com.hvm.login;

import android.app.Activity;
import android.os.CancellationSignal;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.NoCredentialException;

import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * LOGIN COM GOOGLE DENTRO DO APP (Heroes vs Monsters).
 * Mostra a janelinha do Android com as contas Google (Credential Manager) e devolve o "ID token" para o jogo.
 * O jogo troca esse token pela sessão no Supabase (grant_type=id_token). Sem navegador.
 * No GDScript: Engine.get_singleton("LoginGoogle").entrar(web_client_id, nonce_sha256) e depois .resultado()
 *   resultado(): ""             = ainda esperando
 *                "ok:<token>"   = deu certo
 *                "cancelado:"   = a pessoa fechou a janelinha
 *                "erro:<texto>" = deu errado (o texto diz o motivo)
 */
public class LoginGoogle extends GodotPlugin {
    private static final String TAG = "LoginGoogle";
    private volatile String resultado = "";

    public LoginGoogle(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "LoginGoogle";
    }

    @UsedByGodot
    public String resultado() {
        return resultado;
    }

    @UsedByGodot
    public void entrar(final String webClientId, final String nonce) {
        resultado = "";
        final Activity act = getActivity();
        if (act == null) {
            resultado = "erro:sem activity";
            return;
        }
        act.runOnUiThread(() -> {
            try {
                GetSignInWithGoogleOption.Builder b = new GetSignInWithGoogleOption.Builder(webClientId);
                if (nonce != null && !nonce.isEmpty()) b.setNonce(nonce);
                GetCredentialRequest pedido = new GetCredentialRequest.Builder()
                        .addCredentialOption(b.build())
                        .build();
                CredentialManager cm = CredentialManager.create(act);
                cm.getCredentialAsync(act, pedido, new CancellationSignal(), ContextCompat.getMainExecutor(act),
                        new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                            @Override
                            public void onResult(GetCredentialResponse resposta) {
                                Credential c = resposta.getCredential();
                                if (c instanceof CustomCredential
                                        && GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(c.getType())) {
                                    try {
                                        GoogleIdTokenCredential g = GoogleIdTokenCredential.createFrom(c.getData());
                                        resultado = "ok:" + g.getIdToken();
                                    } catch (Exception e) {
                                        resultado = "erro:token invalido (" + e.getMessage() + ")";
                                    }
                                } else {
                                    resultado = "erro:tipo de credencial inesperado " + c.getType();
                                }
                            }

                            @Override
                            public void onError(GetCredentialException e) {
                                Log.w(TAG, "login google", e);
                                if (e instanceof GetCredentialCancellationException) resultado = "cancelado:";
                                else if (e instanceof NoCredentialException) resultado = "erro:nenhuma conta Google neste celular (ou falta a chave Android no Google Cloud)";
                                else resultado = "erro:" + e.getClass().getSimpleName() + ": " + e.getMessage();
                            }
                        });
            } catch (Throwable t) {
                Log.w(TAG, "login google", t);
                resultado = "erro:" + t.getClass().getSimpleName() + ": " + t.getMessage();
            }
        });
    }
}
