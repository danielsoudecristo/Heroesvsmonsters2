# CONVERTE os videos .avi do gravador (Godot Movie Maker) para .mp4 (H.264 + AAC) com NO MAXIMO 179 MB.
# A qualidade e a melhor que cabe no limite: a taxa de bits e calculada pela duracao de cada video.
# Uso:  powershell -ExecutionPolicy Bypass -File ferramentas\converter_mp4.ps1 videos\batalha_x.avi [-ApagarAvi]
#       powershell -ExecutionPolicy Bypass -File ferramentas\converter_mp4.ps1 videos            (todos os .avi da pasta)
# Precisa do FFmpeg (winget install Gyan.FFmpeg).
param(
	[Parameter(Mandatory = $true)][string]$Alvo,
	[switch]$ApagarAvi,
	[double]$LimiteMB = 179
)

$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
$ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg -or -not $ffprobe) {
	Write-Host "FFmpeg nao encontrado. Instale com:  winget install Gyan.FFmpeg   (depois feche e abra o terminal)" -ForegroundColor Yellow
	exit 1
}

if (Test-Path $Alvo -PathType Container) {
	$arquivos = Get-ChildItem $Alvo -Filter *.avi
} else {
	$arquivos = @(Get-Item $Alvo)
}

foreach ($a in $arquivos) {
	if ($a.Length -lt 1MB) {
		Write-Host "Pulando $($a.Name) (gravacao vazia/interrompida)"
		continue
	}
	$mp4 = [IO.Path]::ChangeExtension($a.FullName, ".mp4")
	$dur = [double](& $ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $a.FullName)
	if ($dur -le 0) {
		Write-Host "Pulando $($a.Name) (nao deu para ler a duracao: arquivo corrompido?)"
		continue
	}
	# orcamento: 95% do limite (margem do container), menos o audio (192 kb/s)
	$audio_k = 192
	$video_k = [math]::Floor(($LimiteMB * 0.95 * 8 * 1024) / $dur - $audio_k)
	$video_k = [math]::Min($video_k, 24000)             # (mais que isso nao melhora nada em 1080p30)
	$buf_k = $video_k * 2
	Write-Host "Convertendo $($a.Name)  ($([math]::Round($dur,1)) s, ate $video_k kb/s)..."
	& $ffmpeg -y -v error -stats -i $a.FullName -c:v libx264 -preset slow -crf 18 -maxrate "${video_k}k" -bufsize "${buf_k}k" `
		-pix_fmt yuv420p -c:a aac -b:a "${audio_k}k" -movflags +faststart $mp4
	if ($LASTEXITCODE -ne 0 -or -not (Test-Path $mp4)) {
		Write-Host "  ERRO ao converter $($a.Name)" -ForegroundColor Red
		continue
	}
	$mb = (Get-Item $mp4).Length / 1MB
	if ($mb -gt $LimiteMB) {                              # (quase impossivel) passou do limite: refaz em 2 passadas exatas
		$alvo_k = [math]::Floor(($LimiteMB * 0.92 * 8 * 1024) / $dur - $audio_k)
		& $ffmpeg -y -v error -i $a.FullName -c:v libx264 -preset slow -b:v "${alvo_k}k" -pass 1 -an -f null NUL
		& $ffmpeg -y -v error -stats -i $a.FullName -c:v libx264 -preset slow -b:v "${alvo_k}k" -pass 2 `
			-pix_fmt yuv420p -c:a aac -b:a "${audio_k}k" -movflags +faststart $mp4
		Remove-Item ffmpeg2pass-0.log* -ErrorAction SilentlyContinue
		$mb = (Get-Item $mp4).Length / 1MB
	}
	Write-Host ("  OK: {0}  ({1:N1} MB)" -f (Split-Path $mp4 -Leaf), $mb) -ForegroundColor Green
	if ($ApagarAvi -and $mb -le $LimiteMB) {
		Remove-Item $a.FullName
	}
}
