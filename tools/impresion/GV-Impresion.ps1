# =====================================================================
#  GV-Impresion.ps1  -  Gestion Virgilio - v26.12 (Luis, 02/10/2026)
# ---------------------------------------------------------------------
#  Imprime en ESTA PC las hojas que GV le manda (picking, armado, facturado),
#  cada una en la impresora elegida en GV -> Configuracion -> Impresoras.
#  Sin el kiosco de Chrome y sin cuadro de impresion.
#
#  Se usa desde la CARPETA COMPARTIDA: en cada PC que tenga una impresora para GV,
#  doble clic en "Iniciar GV-Impresion.bat" y dejar la ventana abierta (minimizada).
#  La 1a vez pide la CLAVE que muestra GV (Configuracion -> Impresoras) y la guarda
#  en clave.txt, en esta misma carpeta: sirve para todas las PCs.
#
#  Como imprime: guarda la hoja como .html, la dibuja con el Chrome (o Edge) de la PC
#  sin abrir ninguna ventana (headless) y manda esa imagen a la impresora por su NOMBRE.
#  No cambia la impresora predeterminada de Windows ni la de Chrome.
#
#  Compatible con PowerShell 2.0 / Windows 7 (no usa Invoke-RestMethod ni ConvertTo-Json):
#  lo que hace falta de .NET va en la clase GvImp de abajo.
# =====================================================================
param(
  [string]$Nombre = "",        # nombre con el que aparece la PC en GV (por defecto, el de Windows)
  [string]$Chrome = "",        # ruta de chrome.exe / msedge.exe si no la encuentra solo
  [switch]$Prueba              # imprime una hoja de prueba en la predeterminada y sale
)

$Version      = "1.0 (v26.12)"
$SupabaseUrl  = "https://hrxfctzncixxqmpfhskv.supabase.co"
$ApiKey       = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT"   # clave PUBLICA (la misma de la app)
$PollSeconds  = 5      # cada cuanto pregunta si hay hojas
$LatidoCada   = 30     # cada cuanto avisa que vive y manda sus impresoras

$Carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
$Pc = $env:COMPUTERNAME
if ($Nombre) { $Pc = $Nombre }
$Pc = $Pc.Trim().ToUpper()
$Tmp = Join-Path $env:TEMP "gv-impresion"
if (-not (Test-Path $Tmp)) { New-Item -ItemType Directory -Path $Tmp -Force | Out-Null }
$Perfil = Join-Path $Tmp "perfil-chrome"
$LogFile = Join-Path $Tmp "gv-impresion.log"
$ClaveFile = Join-Path $Carpeta "clave.txt"

try { $Host.UI.RawUI.WindowTitle = "GV Impresion - $Pc" } catch {}

# Una sola ventana por PC (dos ventanas no imprimen doble -la base lo impide- pero confunden)
$creado = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\GVImpresionVirgilio", [ref]$creado)
if (-not $creado) {
  Write-Host ""
  Write-Host "  Ya hay un programa de impresion de GV abierto en esta PC." -ForegroundColor Yellow
  Write-Host "  Esta ventana se cierra sola." -ForegroundColor Yellow
  Start-Sleep -Seconds 8
  exit
}

# TLS 1.2 (Supabase lo exige). 3072 = Tls12; el numero por si el enum no existe en .NET viejo.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
try { if (([int][Net.ServicePointManager]::SecurityProtocol -band 3072) -ne 3072) { [Net.ServicePointManager]::SecurityProtocol = 3072 } } catch {}

Add-Type -AssemblyName System.Web.Extensions
Add-Type -AssemblyName System.Drawing
$refs = @(
  ([System.Web.Script.Serialization.JavaScriptSerializer]).Assembly.Location,
  ([System.Drawing.Bitmap]).Assembly.Location
)

if (-not ("GvImp" -as [type])) {
Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Printing;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

public class GvImp {
  static JavaScriptSerializer Ser() { JavaScriptSerializer s = new JavaScriptSerializer(); s.MaxJsonLength = int.MaxValue; return s; }

  // ---- JSON ----
  public static string Json(object o) { return Ser().Serialize(o); }
  public static object Parse(string s) { return Ser().DeserializeObject(s); }
  public static Dictionary<string, object> Dic() { return new Dictionary<string, object>(); }

  // ---- impresoras de esta PC: [{"nombre":"HP","predeterminada":true}] ----
  public static List<object> Impresoras() {
    List<object> l = new List<object>();
    string pred = "";
    try { pred = new PrinterSettings().PrinterName; } catch (Exception) { }
    foreach (string n in PrinterSettings.InstalledPrinters) {
      Dictionary<string, object> d = new Dictionary<string, object>();
      d["nombre"] = n; d["predeterminada"] = (n == pred);
      l.Add(d);
    }
    return l;
  }

  // ---- POST a una RPC de Supabase. Devuelve el texto; si falla tira con el mensaje de la base ----
  public static string Post(string url, string apikey, string body) {
    HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
    req.Method = "POST";
    req.Timeout = 30000; req.ReadWriteTimeout = 30000;
    req.ContentType = "application/json; charset=utf-8";
    req.Headers.Add("apikey", apikey);
    req.Headers.Add("Authorization", "Bearer " + apikey);
    req.Headers.Add("Cache-Control", "no-cache");
    byte[] b = Encoding.UTF8.GetBytes(body);
    req.ContentLength = b.Length;
    using (Stream s = req.GetRequestStream()) { s.Write(b, 0, b.Length); }
    try {
      using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
      using (StreamReader r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) { return r.ReadToEnd(); }
    } catch (WebException ex) {
      string msg = ex.Message;
      if (ex.Response != null) {
        try {
          using (StreamReader r = new StreamReader(ex.Response.GetResponseStream(), Encoding.UTF8)) {
            string t = r.ReadToEnd();
            try { Dictionary<string, object> d = Ser().DeserializeObject(t) as Dictionary<string, object>; if (d != null && d.ContainsKey("message")) msg = Convert.ToString(d["message"]); else msg = t; }
            catch (Exception) { msg = t; }
          }
        } catch (Exception) { }
      }
      throw new Exception(msg);
    }
  }

  // ---- alto real del dibujo: ultima fila que no es blanca ----
  public static int ContenidoAlto(Bitmap bmp) {
    Rectangle rc = new Rectangle(0, 0, bmp.Width, bmp.Height);
    BitmapData bd = bmp.LockBits(rc, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    try {
      int stride = Math.Abs(bd.Stride);
      byte[] fila = new byte[stride];
      for (int y = bmp.Height - 1; y >= 0; y--) {
        Marshal.Copy(new IntPtr(bd.Scan0.ToInt64() + (long)y * bd.Stride), fila, 0, stride);
        for (int x = 0; x < bmp.Width; x++) {
          int i = x * 4;   // B G R A
          if (fila[i + 3] > 20 && (fila[i] < 235 || fila[i + 1] < 235 || fila[i + 2] < 235)) return Math.Min(bmp.Height, y + 12);
        }
      }
      return 0;
    } finally { bmp.UnlockBits(bd); }
  }

  // ---- imprime la imagen en la impresora por NOMBRE, a lo ancho de la hoja, en tantas paginas como haga falta ----
  public static string Imprimir(string png, string impresora, int copias, string titulo) {
    try {
      PrinterSettings ps = new PrinterSettings();
      ps.PrinterName = impresora;
      if (!ps.IsValid) return "La impresora \"" + impresora + "\" no existe en esta PC";
      using (Bitmap bmp = new Bitmap(png)) {
        int alto = ContenidoAlto(bmp);
        if (alto < 20) return "La hoja salio en blanco (no se pudo dibujar)";
        int n = Math.Max(1, Math.Min(copias, 5));
        for (int c = 0; c < n; c++) {
          PrintDocument doc = new PrintDocument();
          doc.PrinterSettings = ps;
          doc.DocumentName = titulo;
          doc.PrintController = new StandardPrintController();   // sin el cartelito "Imprimiendo..."
          doc.DefaultPageSettings.Margins = new Margins(47, 47, 47, 47);   // 12 mm, como la hoja de GV
          Paginador pg = new Paginador(bmp, alto);
          doc.PrintPage += new PrintPageEventHandler(pg.Pagina);
          doc.Print();
        }
      }
      return "";
    } catch (Exception ex) { return ex.Message; }
  }
}

public class Paginador {
  Bitmap b; int alto; int y;
  public Paginador(Bitmap bmp, int altoContenido) { b = bmp; alto = altoContenido; y = 0; }
  public void Pagina(object sender, PrintPageEventArgs e) {
    Rectangle m = e.MarginBounds;                    // centesimos de pulgada
    float esc = (float)m.Width / b.Width;            // unidades de pagina por pixel de la imagen
    int corte = (int)Math.Floor(m.Height / esc);     // pixeles de imagen que entran en una pagina
    int h = Math.Min(corte, alto - y);
    e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
    e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
    e.Graphics.DrawImage(b, new RectangleF(m.Left, m.Top, m.Width, h * esc), new RectangleF(0, y, b.Width, h), GraphicsUnit.Pixel);
    y += h;
    e.HasMorePages = y < alto;
  }
}
'@
}

function Escribir($texto, $color) {
  $linea = (Get-Date -Format "HH:mm:ss") + "  " + $texto
  if ($color) { Write-Host ("  " + $linea) -ForegroundColor $color } else { Write-Host ("  " + $linea) }
  try { Add-Content -Path $LogFile -Value ((Get-Date -Format "yyyy-MM-dd ") + $linea) } catch {}
}

function Rpc($nombre, $cuerpo) {
  # los valores van con cast explicito ([string], [long], [bool]): sin eso PowerShell puede
  # pasarlos envueltos (PSObject) y el serializador los manda mal
  $txt = [GvImp]::Post("$SupabaseUrl/rest/v1/rpc/$nombre", $ApiKey, [GvImp]::Json($cuerpo))
  if (-not $txt) { return $null }
  return [GvImp]::Parse($txt)
}

function Buscar-Chrome {
  if ($Chrome -and (Test-Path $Chrome)) { return $Chrome }
  # Windows de 32 bits no tiene ProgramFiles(x86): las bases vacias se saltean (Join-Path con "" corta el programa)
  $pares = @(
    @($env:ProgramFiles,          "Google\Chrome\Application\chrome.exe"),
    @(${env:ProgramFiles(x86)},   "Google\Chrome\Application\chrome.exe"),
    @($env:LOCALAPPDATA,          "Google\Chrome\Application\chrome.exe"),
    @(${env:ProgramFiles(x86)},   "Microsoft\Edge\Application\msedge.exe"),
    @($env:ProgramFiles,          "Microsoft\Edge\Application\msedge.exe")
  )
  foreach ($p in $pares) {
    if (-not $p[0]) { continue }
    $c = Join-Path $p[0] $p[1]
    if (Test-Path $c) { return $c }
  }
  return ""
}

function Leer-Clave {
  if (Test-Path $ClaveFile) {
    $k = ([IO.File]::ReadAllText($ClaveFile)).Trim()
    if ($k) { return $k }
  }
  Write-Host ""
  Write-Host "  Falta la CLAVE del programa." -ForegroundColor Yellow
  Write-Host "  Abri GV -> Configuracion -> Impresoras, copia la clave y pegala aca." -ForegroundColor Yellow
  $k = (Read-Host "  Clave").Trim()
  if ($k) { try { [IO.File]::WriteAllText($ClaveFile, $k) } catch { Escribir ("no pude guardar clave.txt: " + $_.Exception.Message) "Red" } }
  return $k
}

# Dibuja el .html a una imagen con Chrome/Edge sin ventana. Devuelve "" si salio bien o el error.
function Dibujar($html, $png) {
  if (-not $ChromeExe) { return "No encontre Chrome ni Edge en esta PC" }
  if (Test-Path $png) { Remove-Item $png -Force -ErrorAction SilentlyContinue }
  $uri = (New-Object System.Uri($html)).AbsoluteUri
  $argumentos = "--headless --disable-gpu --no-first-run --no-default-browser-check --disable-extensions " +
                "--hide-scrollbars --mute-audio --user-data-dir=`"$Perfil`" --force-device-scale-factor=2 " +
                "--window-size=703,3030 --default-background-color=FFFFFFFF --virtual-time-budget=3000 " +
                "--screenshot=`"$png`" `"$uri`""
  $psi = New-Object System.Diagnostics.ProcessStartInfo($ChromeExe, $argumentos)
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch {}; return "Chrome tardo mas de 90 s en dibujar la hoja" }
  if (-not (Test-Path $png)) { return "Chrome no genero la imagen de la hoja" }
  return ""
}

function Imprimir-Trabajo($t) {
  $id = $t["id"]; $tipo = [string]$t["tipo"]; $ref = [string]$t["ref"]
  $imp = [string]$t["impresora"]; $cop = 1
  try { $cop = [int]$t["copias"] } catch {}
  $html = [string]$t["html"]
  $err = ""
  if (-not $html) { $err = "La hoja vino vacia (tiene mas de 7 dias)" }
  $fHtml = Join-Path $Tmp ("hoja-" + $id + ".html")
  $fPng  = Join-Path $Tmp ("hoja-" + $id + ".png")
  if (-not $err) {
    try { [IO.File]::WriteAllText($fHtml, $html, (New-Object System.Text.UTF8Encoding($false))) }
    catch { $err = "No pude guardar la hoja: " + $_.Exception.Message }
  }
  if (-not $err) { $err = Dibujar $fHtml $fPng }
  if (-not $err) { $err = [GvImp]::Imprimir($fPng, $imp, $cop, ("GV " + $tipo + " " + $ref)) }
  $ok = (-not $err)
  if ($ok) { Escribir ("impresa  " + $tipo + " " + $ref + "  ->  " + $imp + $(if ($cop -gt 1) { " (x" + $cop + ")" } else { "" })) "Cyan" }
  else     { Escribir ("NO salio " + $tipo + " " + $ref + "  ->  " + $imp + " : " + $err) "Yellow" }
  try {
    $c = [GvImp]::Dic(); $c["p_clave"] = [string]$Clave; $c["p_pc"] = [string]$Pc; $c["p_id"] = [long]$id; $c["p_ok"] = [bool]$ok; $c["p_error"] = [string]$err
    Rpc "gv_imp_agente_resultado" $c | Out-Null
  } catch { Escribir ("no pude avisar el resultado de la hoja #" + $id + ": " + $_.Exception.Message) "Red" }
  Remove-Item $fHtml, $fPng -Force -ErrorAction SilentlyContinue
}

function Latido {
  $c = [GvImp]::Dic()
  $c["p_clave"] = [string]$Clave; $c["p_pc"] = [string]$Pc; $c["p_impresoras"] = [GvImp]::Impresoras()
  $c["p_version"] = [string]$Version; $c["p_chrome"] = [string]$ChromeExe
  return (Rpc "gv_imp_agente_latido" $c)
}

# ---------------------------------------------------------------------
$ChromeExe = Buscar-Chrome
Write-Host ""
Write-Host "  GV - Programa de impresion  $Version" -ForegroundColor Green
Write-Host "  Esta PC aparece en GV como:  $Pc" -ForegroundColor Green
if ($ChromeExe) { Write-Host "  Dibuja las hojas con:  $ChromeExe" -ForegroundColor Green }
else { Write-Host "  ! No encontre Chrome ni Edge: no voy a poder imprimir. Instala Chrome o usa -Chrome <ruta>" -ForegroundColor Red }
Write-Host "  Impresoras de esta PC:" -ForegroundColor Green
foreach ($i in [GvImp]::Impresoras()) { Write-Host ("     - " + $i["nombre"] + $(if ($i["predeterminada"]) { "   (predeterminada)" } else { "" })) }
Write-Host ""

if ($Prueba) {
  $pred = ""
  foreach ($i in [GvImp]::Impresoras()) { if ($i["predeterminada"]) { $pred = $i["nombre"] } }
  $f = Join-Path $Tmp "prueba.html"; $png = Join-Path $Tmp "prueba.png"
  [IO.File]::WriteAllText($f, "<!doctype html><html><body style='width:703px;font:28px Arial;background:#fff'><h1>Prueba GV</h1><p>$Pc - $(Get-Date)</p></body></html>", (New-Object System.Text.UTF8Encoding($false)))
  $e = Dibujar $f $png
  if (-not $e) { $e = [GvImp]::Imprimir($png, $pred, 1, "GV prueba") }
  if ($e) { Escribir ("la prueba NO salio: " + $e) "Red" } else { Escribir ("prueba mandada a " + $pred) "Cyan" }
  Start-Sleep -Seconds 5
  exit
}

$Clave = Leer-Clave
$ultimoLatido = [DateTime]::MinValue
$avisoReglas = ""
$tick = 0
Escribir "Mirando si GV manda hojas cada $PollSeconds s. Cerrar la ventana = no se imprime nada en esta PC." "Green"

while ($true) {
  try {
    if (((Get-Date) - $ultimoLatido).TotalSeconds -ge $LatidoCada) {
      $r = Latido
      $ultimoLatido = Get-Date
      $txt = ""
      if ($r -and $r["reglas"]) {
        foreach ($g in $r["reglas"]) { $txt += ("   " + $g["tipo"] + " -> " + $g["impresora"] + $(if ($g["auto"]) { "" } else { " (automatico APAGADO)" })) }
      }
      if (-not $txt) { $txt = "   (GV todavia no le asigno ninguna hoja a esta PC: Configuracion -> Impresoras)" }
      if ($txt -ne $avisoReglas) { Escribir ("Conectado. En esta PC:" + $txt) "Green"; $avisoReglas = $txt }
    }
    $c = [GvImp]::Dic(); $c["p_clave"] = [string]$Clave; $c["p_pc"] = [string]$Pc; $c["p_limite"] = [int]5
    $trabajos = Rpc "gv_imp_agente_tomar" $c
    if ($trabajos) { foreach ($t in @($trabajos)) { if ($t) { Imprimir-Trabajo $t } } }
    $tick++
    if (($tick % 120) -eq 0) { Escribir "... sigo mirando" "DarkGray" }
  } catch {
    $m = $_.Exception.Message
    if ($m -match "CLAVE_INVALIDA") {
      Escribir "La CLAVE no es la de GV. Te la vuelvo a pedir." "Red"
      Remove-Item $ClaveFile -Force -ErrorAction SilentlyContinue
      $Clave = Leer-Clave
      $ultimoLatido = [DateTime]::MinValue
    } else {
      Escribir ("sin conexion con GV: " + $m) "Red"
      Start-Sleep -Seconds 10
    }
  }
  Start-Sleep -Seconds $PollSeconds
}
