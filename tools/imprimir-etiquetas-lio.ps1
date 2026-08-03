# =====================================================================
#  imprimir-etiquetas-lio.ps1  -  Produccion Virgilio - idea 5290
# ---------------------------------------------------------------------
#  Imprime SOLO las etiquetas de lio pendientes en la Zebra S4M.
#  Deja esta ventana ABIERTA en la PC que tiene la impresora.
#
#  Compatible con PowerShell viejo (2.0 / Windows 7): NO usa Invoke-RestMethod
#  ni ConvertFrom-Json; habla directo con .NET (WebClient + JavaScriptSerializer).
#
#  PASOS (una sola vez):
#   1) Pone abajo el NOMBRE EXACTO de tu impresora S4M
#      (Panel de control - Dispositivos e impresoras - nombre tal cual).
#   2) Doble clic al .bat
#
#  Manda ZPL crudo directo a la S4M (no pasa por dialogos, no toca los remitos).
# =====================================================================

# >>>>>>>>>>>>>>  CAMBIAR ESTO  <<<<<<<<<<<<<<
$PrinterName = "ZDesigner S4M-203dpi ZPL"
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

$SupabaseUrl = "https://hrxfctzncixxqmpfhskv.supabase.co"
$ApiKey      = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT"
$PollSeconds = 6   # cada cuanto mira la cola; una etiqueta un poco mas tarde no molesta a nadie

$Base = "$SupabaseUrl/rest/v1/Etiquetas_Lio"

# TLS 1.2 (Supabase lo exige). 3072 = Tls12; se usa el numero por si el enum no existe
# en el .NET viejo. Se intenta combinar y, si falla, setear directo.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
try { if (([int][Net.ServicePointManager]::SecurityProtocol -band 3072) -ne 3072) { [Net.ServicePointManager]::SecurityProtocol = 3072 } } catch {}

# Parser JSON que funciona en PowerShell 2.0 (no depende de ConvertFrom-Json)
Add-Type -AssemblyName System.Web.Extensions
$JsonSer = New-Object System.Web.Script.Serialization.JavaScriptSerializer

function Get-Pendientes($url) {
  $wc = New-Object System.Net.WebClient
  # Esta PC vieja cacheaba la respuesta HTTP y repetia SIEMPRE el mismo resultado (por
  # eso quedaba pegado en "1 pendiente" para siempre aunque la cola cambiara). Se
  # desactiva el cache del WebClient. OJO: NO se agrega un parametro extra a la URL
  # (tipo "_=...") porque Supabase/PostgREST interpreta CUALQUIER parametro desconocido
  # como un filtro por columna, y da 400 "Solicitud incorrecta" al no existir esa columna.
  $wc.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
  $wc.Headers.Add("Cache-Control", "no-cache, no-store")
  $wc.Headers.Add("Pragma", "no-cache")
  $wc.Headers.Add("apikey", $ApiKey)
  $wc.Headers.Add("Authorization", "Bearer " + $ApiKey)
  $txt = $wc.DownloadString($url)
  return $JsonSer.DeserializeObject($txt)
}
function Marcar-Impreso($id) {
  $body = '{"estado":"impreso","impreso_en":"' + (Get-Date).ToUniversalTime().ToString("o") + '"}'
  $req = [System.Net.HttpWebRequest]::Create("$Base" + "?id=eq." + $id)
  $req.Method = "PATCH"
  $req.Headers.Add("apikey", $ApiKey)
  $req.Headers.Add("Authorization", "Bearer " + $ApiKey)
  $req.Headers.Add("Prefer", "return=minimal")
  $req.ContentType = "application/json"
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $req.ContentLength = $bytes.Length
  $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
  $resp = $req.GetResponse(); $resp.Close()
}

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

# Chequeo de conexion al arrancar
try {
  $chk = Get-Pendientes("$Base" + "?estado=eq.pendiente&select=id")
  Write-Host ("  Conectado OK. Pendientes en cola ahora: {0}" -f @($chk).Count) -ForegroundColor Green
} catch {
  Write-Host ("  NO me pude conectar a la cola: {0}" -f $_.Exception.Message) -ForegroundColor Red
}
Write-Host ""

$tick = 0
while ($true) {
  try {
    $raw = Get-Pendientes("$Base" + "?estado=eq.pendiente&order=creado_en.asc&select=id,zpl&limit=20")
    # @() fuerza SIEMPRE un arreglo (cola vacia = $null en algunos .NET viejos; con @()
    # nunca se rompe el foreach de abajo, sea $null, un solo item, o varios).
    $items = @()
    if ($null -ne $raw) { $items = @($raw) }
    # Senal de vida cada ~1 minuto: para VER que sigue mirando la cola de verdad (no
    # una ventana congelada) y que el numero cambia (no quedo pegado por cache).
    $tick++
    if (($tick % 10) -eq 0) {
      Write-Host ("  ... {0} - sigo mirando - pendientes ahora: {1}" -f (Get-Date -Format "HH:mm:ss"), $items.Count) -ForegroundColor DarkGray
    }
    foreach ($row in $items) {
      if ($null -eq $row) { continue }
      try {
        $zpl = [string]$row["zpl"]
        $id  = $row["id"]
        if (-not $zpl) { continue }
        $ok = [RawPrinter]::Send($PrinterName, $zpl)
        if ($ok) {
          try { Marcar-Impreso $id } catch {}
          Write-Host ("  [{0}] etiqueta #{1} impresa" -f (Get-Date -Format "HH:mm:ss"), $id) -ForegroundColor Cyan
        } else {
          Write-Host ("  ! no pude imprimir #{0} - revisa el NOMBRE de la impresora de arriba" -f $id) -ForegroundColor Yellow
        }
      } catch {
        # Una etiqueta con problema NO frena a las demas ni deja la cola trabada.
        Write-Host ("  ! error con una etiqueta puntual: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
      }
    }
  } catch {
    Write-Host ("  error con la cola: {0}" -f $_.Exception.Message) -ForegroundColor Red
  }
  Start-Sleep -Seconds $PollSeconds
}
