package com.hvm;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;

import com.google.android.play.core.appupdate.AppUpdateInfo;
import com.google.android.play.core.appupdate.AppUpdateManager;
import com.google.android.play.core.appupdate.AppUpdateManagerFactory;
import com.google.android.play.core.appupdate.AppUpdateOptions;
import com.google.android.play.core.install.InstallStateUpdatedListener;
import com.google.android.play.core.install.model.AppUpdateType;
import com.google.android.play.core.install.model.InstallStatus;
import com.google.android.play.core.install.model.UpdateAvailability;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * ATUALIZAÇÃO OFICIAL DA PLAY STORE DENTRO DO JOGO (Heroes vs Monsters) — Google Play In-App Updates.
 * No GDScript: var p = Engine.get_singleton("AtualizarPlay")
 *   p.verificar()            -> pergunta para a Play Store se tem versão nova (responde em estado())
 *   p.estado()               -> ""                       ainda perguntando
 *                               "sem"                    está na versão mais nova
 *                               "disponivel:<codigo>:<dias>:<flex>:<imediata>"  tem versão nova
 *                               "em_andamento"           uma atualização obrigatória já começou (continua)
 *                               "erro:<texto>"           não deu (ex.: jogo não instalado pela Play Store)
 *   p.atualizar(imediata)    -> imediata=true: tela cheia do Google (obrigatória); false: baixa em segundo plano
 *   p.progresso()            -> "baixando:<baixado>:<total>" / "baixado" / "instalando" / "cancelado" / "falhou:<código>" / ""
 *   p.concluir()             -> instala o que já baixou (o jogo reinicia sozinho)
 *   p.codigo_versao()        -> o versionCode instalado (ex.: 4)
 */
public class AtualizarPlay extends GodotPlugin {
    private static final String TAG = "AtualizarPlay";
    private static final int PEDIDO = 4710;
    private AppUpdateManager gerente;
    private AppUpdateInfo info;
    private volatile String estado = "";
    private volatile String progresso = "";
    private boolean ouvindo = false;

    private final InstallStateUpdatedListener ouvinte = s -> {
        int st = s.installStatus();
        if (st == InstallStatus.DOWNLOADING) {
            progresso = "baixando:" + s.bytesDownloaded() + ":" + s.totalBytesToDownload();
        } else if (st == InstallStatus.DOWNLOADED) {
            progresso = "baixado";
        } else if (st == InstallStatus.INSTALLING) {
            progresso = "instalando";
        } else if (st == InstallStatus.FAILED) {
            progresso = "falhou:" + s.installErrorCode();
        } else if (st == InstallStatus.CANCELED) {
            progresso = "cancelado";
        } else if (st == InstallStatus.PENDING) {
            progresso = "baixando:0:0";
        }
    };

    public AtualizarPlay(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "AtualizarPlay";
    }

    private AppUpdateManager gerente() {
        if (gerente == null) {
            Activity act = getActivity();
            if (act != null) gerente = AppUpdateManagerFactory.create(act);
        }
        return gerente;
    }

    @UsedByGodot
    public String estado() {
        return estado;
    }

    @UsedByGodot
    public String progresso() {
        return progresso;
    }

    @UsedByGodot
    public int codigo_versao() {
        try {
            Activity act = getActivity();
            PackageInfo pi = act.getPackageManager().getPackageInfo(act.getPackageName(), 0);
            if (Build.VERSION.SDK_INT >= 28) return (int) pi.getLongVersionCode();
            return pi.versionCode;
        } catch (Exception e) {
            return 0;
        }
    }

    @UsedByGodot
    public void verificar() {
        estado = "";
        final Activity act = getActivity();
        if (act == null) {
            estado = "erro:sem activity";
            return;
        }
        act.runOnUiThread(() -> {
            try {
                AppUpdateManager m = gerente();
                m.getAppUpdateInfo()
                        .addOnSuccessListener(i -> {
                            info = i;
                            int disp = i.updateAvailability();
                            if (disp == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                                estado = "em_andamento";
                            } else if (disp == UpdateAvailability.UPDATE_AVAILABLE) {
                                Integer dias = i.clientVersionStalenessDays();
                                estado = "disponivel:" + i.availableVersionCode() + ":" + (dias == null ? -1 : dias) + ":"
                                        + (i.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE) ? 1 : 0) + ":"
                                        + (i.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE) ? 1 : 0);
                            } else {
                                estado = "sem";
                            }
                            if (i.installStatus() == InstallStatus.DOWNLOADED) progresso = "baixado";
                        })
                        .addOnFailureListener(e -> {
                            Log.w(TAG, "verificar", e);
                            estado = "erro:" + e.getMessage();
                        });
            } catch (Exception e) {
                estado = "erro:" + e.getMessage();
            }
        });
    }

    @UsedByGodot
    public void atualizar(final boolean imediata) {
        final Activity act = getActivity();
        if (act == null || info == null) {
            progresso = "falhou:sem informacao";
            return;
        }
        act.runOnUiThread(() -> {
            try {
                AppUpdateManager m = gerente();
                if (!imediata && !ouvindo) {
                    m.registerListener(ouvinte);
                    ouvindo = true;
                }
                progresso = imediata ? "instalando" : "baixando:0:0";
                m.startUpdateFlowForResult(info, act,
                        AppUpdateOptions.newBuilder(imediata ? AppUpdateType.IMMEDIATE : AppUpdateType.FLEXIBLE).build(),
                        PEDIDO);
            } catch (Exception e) {
                Log.w(TAG, "atualizar", e);
                progresso = "falhou:" + e.getMessage();
            }
        });
    }

    @UsedByGodot
    public void concluir() {
        final Activity act = getActivity();
        if (act == null) return;
        act.runOnUiThread(() -> {
            try {
                gerente().completeUpdate();
            } catch (Exception e) {
                progresso = "falhou:" + e.getMessage();
            }
        });
    }

    // a pessoa respondeu à janela da Play Store
    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        super.onMainActivityResult(requestCode, resultCode, data);
        if (requestCode != PEDIDO) return;
        if (resultCode == Activity.RESULT_CANCELED) {
            progresso = "cancelado";
        } else if (resultCode != Activity.RESULT_OK) {
            progresso = "falhou:" + resultCode;
        }
    }

    // voltou para o jogo: se já baixou, avisa; se a obrigatória estava no meio, continua
    @Override
    public void onMainResume() {
        super.onMainResume();
        if (gerente == null) return;
        try {
            gerente.getAppUpdateInfo().addOnSuccessListener(i -> {
                info = i;
                if (i.installStatus() == InstallStatus.DOWNLOADED) {
                    progresso = "baixado";
                } else if (i.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                    estado = "em_andamento";
                }
            });
        } catch (Exception e) {
            Log.w(TAG, "resume", e);
        }
    }

    @Override
    public void onMainDestroy() {
        if (gerente != null && ouvindo) {
            try { gerente.unregisterListener(ouvinte); } catch (Exception ignored) { }
        }
        super.onMainDestroy();
    }
}
