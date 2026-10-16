@tool
extends EditorScript
## ATIVAR "VOLTAR PARA O JOGO" (Android)
## Faz o botão "Voltar para o jogo" da página de login do site abrir o app (endereço heroesvsmonsters://login).
##
## Antes (uma vez só):
##   1) Projeto > Instalar Modelo de Compilação Android... > Instalar
##   2) Projeto > Exportar > Android > Gradle Build > "Usar Compilação Gradle" ligado
## Depois abra este arquivo e aperte Ctrl+Shift+X. Pode rodar de novo sem problema.

const MANIFESTOS := ["res://android/build/src/main/AndroidManifest.xml", "res://android/build/AndroidManifest.xml"]
const MARCA := "heroesvsmonsters"
const FILTRO := """
            <!-- VOLTAR_PARA_O_JOGO: o site (godot-login.html) abre o jogo por heroesvsmonsters://login -->
            <intent-filter>
				<action android:name="android.intent.action.VIEW" />
				<category android:name="android.intent.category.DEFAULT" />
				<category android:name="android.intent.category.BROWSABLE" />
				<data android:scheme="heroesvsmonsters" android:host="login" />
            </intent-filter>
"""

func _run() -> void:
	var MANIFESTO := ""
	for m in MANIFESTOS:
		if FileAccess.file_exists(m):
			MANIFESTO = m
			break
	if MANIFESTO == "":
		printerr("NÃO ACHEI o AndroidManifest.xml.\nFaça antes: Projeto > Instalar Modelo de Compilação Android... > Instalar. Depois rode de novo.")
		return
	var txt := FileAccess.get_file_as_string(MANIFESTO)
	if MARCA in txt:
		print("PRONTO: o \"Voltar para o jogo\" já estava ativado. Agora é só exportar o APK.")
		return
	# coloca o filtro logo depois do intent-filter do LAUNCHER (dentro da activity do jogo)
	var i := txt.find("android.intent.category.LAUNCHER")
	if i < 0:
		printerr("Não achei a parte do LAUNCHER no AndroidManifest.xml. Mande um print para o Claude.")
		return
	var fim := txt.find("</intent-filter>", i)
	if fim < 0:
		printerr("AndroidManifest.xml diferente do esperado. Mande um print para o Claude.")
		return
	fim += "</intent-filter>".length()
	txt = txt.substr(0, fim) + "\n" + FILTRO + txt.substr(fim)
	var f := FileAccess.open(MANIFESTO, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	print("PRONTO! \"Voltar para o jogo\" ativado no Android.")
	print("Confira: Projeto > Exportar > Android > Gradle Build > Usar Compilação Gradle = ligado. Depois exporte o APK.")
