
# =====================================================================================
#
# Data criação: 28/08/2025
# Autor: Luciano Patrao
# Ultima actualização: v1.1 29/08/2025
#
# Objetivo: Limpar uma VM Windows após a migração, removendo dispositivos de hardware
#           VMware antigos e ocultos ("ghost") para prevenir conflitos de drivers.
#
# UTILIZAÇÃO: Executar como Administrador na nova VM em Hyper-V, ANTES de restaurar
#             a configuração de rede. Um reinício após a execução é recomendado.
# =====================================================================================

Clear-Host

# 0. Check if the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges."
    exit 1
}

# Get system information
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Host "Checking virtualization platform...   Hypervisor = $($computerSystem.Manufacturer)" -ForegroundColor Cyan
Write-Host ""


# --- Platform / Hypervisor check ---
if ($computerSystem.Manufacturer -like "*VMware*") {

    Write-Warning "This VM is running on VMware. This script should not be executed on VMware environments."

    Write-Host ""
    do {
        $resp1 = (Read-Host "Are you sure you want to continue? (y/n)").ToLower().Trim()
    } while (-not @('y','n','yes','no').Contains($resp1))

    if ($resp1.StartsWith('n')) {
        Write-Host ""
        Write-Host "Operation canceled by user." -ForegroundColor Red
        return
    }

    Write-Host ""
    do {
        $resp2 = (Read-Host "Confirm again to continue (second confirmation). Continue? (y/n)").ToLower().Trim()
    } while (-not @('y','n','yes','no').Contains($resp2))

    if ($resp2.StartsWith('n')) {
        Write-Host ""
        Write-Host "Operation canceled by user." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "User confirmed twice. Continuing script execution..." -ForegroundColor Green
}
else {
    # Do not validate Microsoft/Proxmox/other. Just inform and continue.
    $man   = $computerSystem.Manufacturer
    $model = $computerSystem.Model

    Write-Host ("[INFO] Detected hypervisor: {0} | Model: {1}. " -f $man, $model) -ForegroundColor Yellow -NoNewline
    Write-Host "Continuing..." -ForegroundColor Green
    Write-Host ""
}

Write-Host "============================================================"
Write-Host "--- Início do Script de Limpeza de Dispositivos VMware ---"
Write-Host "============================================================"


    $vmwareTools = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "VMware Tools" }
    if ($vmwareTools) {
        Write-Host "  > VMware Tools encontradas. Não é possivel continuar..."
        #exit 1
        }
     

# 1. Definir os padrões de nomes de dispositivos VMware a procurar
$vmwareDevicePatterns = @(
    "*VMware*",                  # Captura a maioria dos dispositivos (SVGA, SCSI, etc.)
    "vmxnet3*",                 # Captura o adaptador de rede VMXNET3
    "Intel(R) 82574L*"          # Captura o adaptador de rede E1000 comummente emulado pelo VMware
)

Write-Host "`n[PASSO 1/3] A procurar por dispositivos VMware antigos..." -ForegroundColor Cyan

# 2. Encontrar todos os dispositivos (incluindo os ocultos) que correspondem aos padrões
$devicesToRemove = @()
foreach ($pattern in $vmwareDevicePatterns) {
    # Adiciona os dispositivos encontrados à lista, evitando duplicados
    $found = Get-PnpDevice -FriendlyName $pattern -ErrorAction SilentlyContinue
    if ($found) {
        $devicesToRemove += $found
    }
}
$devicesToRemove = $devicesToRemove | Sort-Object -Property InstanceId -Unique

# 3. Remover os dispositivos encontrados
if ($devicesToRemove) {
    Write-Host "`n[PASSO 2/3] Os seguintes dispositivos VMware serão removidos:" -ForegroundColor Yellow
    $devicesToRemove | Format-Table Name, Class, Status, InstanceId -AutoSize
    
    Read-Host "Prima Enter para continuar com a remoção..."

    foreach ($device in $devicesToRemove) {
        Write-Host "A remover dispositivo: '$($device.Name)'..."
        # Usa o Start-Process para uma execução mais controlada do pnputil.exe
        $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/remove-device `"$($device.InstanceId)`" /force" -Wait -PassThru -WindowStyle Hidden
        
        if ($proc.ExitCode -eq 0) {
            Write-Host "  > Removido com sucesso." -ForegroundColor Green
        } else {
            # O código de erro 3010 significa que um reinício é necessário, o que é um sucesso.
            if ($proc.ExitCode -eq 3010) {
                 Write-Host "  > Removido com sucesso. (Reinício pendente)" -ForegroundColor Green
            } else {
                 Write-Warning "  > Falha ao remover o dispositivo. Código de Saída: $($proc.ExitCode)"
            }
        }
    }

    Write-Host "`n[PASSO 3/3] A re-analisar o hardware do sistema..." -ForegroundColor Cyan
    # Pede ao Windows para re-analisar o barramento de dispositivos
    Start-Process -FilePath "pnputil.exe" -ArgumentList "/scan-devices" -Wait -NoNewWindow
    
} else {
    Write-Host "`n[INFO] Nenhum dispositivo VMware antigo foi encontrado." -ForegroundColor Green
    Write-Host "`n[SUCESSO] O processo de limpeza foi concluído." -ForegroundColor Green
    exit 1
}

Write-Host "`n[SUCESSO] O processo de limpeza foi concluído." -ForegroundColor Green
Write-Host "É recomendado reiniciar a VM antes de restaurar a rede."