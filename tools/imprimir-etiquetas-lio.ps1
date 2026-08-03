# =====================================================================
#  imprimir-etiquetas-lio.ps1  -  Produccion Virgilio - idea 5290
# ---------------------------------------------------------------------
#  Imprime SOLO las etiquetas de lio pendientes en la Zebra S4M.
#  Deja esta ventana ABIERTA en la PC que tiene la impresora.
#
#  PASOS (una sola vez):
#   1) Pone abajo el NOMBRE EXACTO de tu impresora S4M
#      (Panel de control - Dispositivos e impresoras - nombre tal cual).
#   2) Doble clic al .bat
#      (o consola:  powershell -ExecutionPolicy Bypass -File imprimir-etiquetas-lio.ps1 )
#
#  Manda ZPL crudo directo a la S4M (no pasa por dialogos, no toca los remitos).
# =====================================================================

# >>>>>>>>>>>>>>  CAMBIAR ESTO  <<<<<<<<<<<<<<
$PrinterName = "ZDesigner S4M-203dpi ZPL"
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

$SupabaseUrl = "https://hrxfctzncixxqmpfhskv.supabase.co"
$ApiKey      = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT"
$PollSeconds = 4

$Base    = "$SupabaseUrl/rest/v1/Etiquetas_Lio"
$Headers = @{ apikey = $ApiKey; Authorization = "Bearer $ApiKey" }

# Windows PowerShell 5.1 usa TLS viejo por default y Supabase exige TLS 1.2.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# --- Envio RAW: manda los bytes del ZPL a la impresora sin pasar por el driver GDI ---
if (-not ("RawPrinter" -as [type])) {
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class RawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DOCINFO { [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDataType; }
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool OpenPrinter(string src, out IntPtr h, IntPtr pd);
  [DllImport("winspool.drv", SetLastError=true)] static extern bool ClosePrinter(IntPtr h);
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool StartDocPrinter(IntPtr h, int level, ref DOCINFO di);
  [DllImport("winspool.drv", SetLastError=true)] static extern bool EndDocPrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError=true)] static extern bool StartPagePrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError=true)] static extern bool EndPagePrinter(IntPtr h);
  [DllImport("winspool.drv", SetLastError=true)] static extern bool WritePrinter(IntPtr h, IntPtr buf, int count, out int written);
  public static bool Send(string printer, string data) {
    IntPtr h; DOCINFO di = new DOCINFO(); di.pDocName = "EtiquetaLio"; di.pDataType = "RAW";
    if (!OpenPrinter(printer, out h, IntPtr.Zero)) return false;
    bool ok = false;
    try {
      if (StartDocPrinter(h, 1, ref di) && StartPagePrinter(h)) {
        byte[] bytes = System.Text.Encoding.UTF8.GetBytes(data);
        IntPtr p = Marshal.AllocCoTaskMem(bytes.Length);
        Marshal.Copy(bytes, 0, p, bytes.Length);
        int w; ok = WritePrinter(h, p, bytes.Length, out w);
        Marshal.FreeCoTaskMem(p);
        EndPagePrinter(h); EndDocPrinter(h);
      }
    } finally { ClosePrinter(h); }
    return ok;
  }
}
'@
}

Write-Host ""
Write-Host "  Imprimidor de etiquetas de lio  ->  '$PrinterName'" -ForegroundColor Green
Write-Host "  Mirando la cola cada $PollSeconds s. Ctrl+C para salir." -ForegroundColor Green
Write-Host ""

# Chequeo de conexion al arrancar (para ver enseguida si el problema es la red/TLS)
try {
  $chk = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$Base?estado=eq.pendiente&select=id"
  Write-Host ("  Conectado OK. Pendientes en cola ahora: {0}" -f @($chk).Count) -ForegroundColor Green
} catch {
  Write-Host ("  NO me pude conectar a la cola: {0}" -f $_.Exception.Message) -ForegroundColor Red
}
Write-Host ""

while ($true) {
  try {
    $pend = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$Base?estado=eq.pendiente&order=creado_en.asc&select=id,zpl&limit=20"
    foreach ($row in $pend) {
      if (-not $row.zpl) { continue }
      $ok = [RawPrinter]::Send($PrinterName, [string]$row.zpl)
      if ($ok) {
        $body = '{"estado":"impreso","impreso_en":"' + (Get-Date).ToUniversalTime().ToString("o") + '"}'
        Invoke-RestMethod -Method Patch -Uri "$Base?id=eq.$($row.id)" -Body $body -Headers ($Headers + @{ "Content-Type" = "application/json"; "Prefer" = "return=minimal" }) | Out-Null
        Write-Host ("  [{0}] etiqueta #{1} impresa" -f (Get-Date -Format "HH:mm:ss"), $row.id) -ForegroundColor Cyan
      } else {
        Write-Host ("  ! no pude imprimir #{0} - revisa el NOMBRE de la impresora de arriba" -f $row.id) -ForegroundColor Yellow
      }
    }
  } catch {
    Write-Host ("  error con la cola: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
  Start-Sleep -Seconds $PollSeconds
}
