// ImpresionVirgilio.cs — Helper local de impresión para Gestión Virgilio.
//
// Gestión Virgilio es una web app en la nube que genera hojas de picking, armado y
// facturado a medida que los pedidos avanzan por el pipeline. Para imprimirlas sin el
// cuadro de impresión habría que poner Chrome en modo kiosco en cada PC. Este programa
// reemplaza ese kiosco: corre en la PC de depósito, abre un servidor HTTP chico en
// 127.0.0.1 y, cuando la página le manda una hoja (PDF + tipo), la imprime sola en la
// impresora que el usuario asignó a ese tipo, con SumatraPDF, sin cuadro y sin tocar la
// impresora predeterminada de Windows.
//
// Se compila a un único .exe con csc.exe (ver build.txt). No necesita instalar nada ni
// permisos de administrador: el servidor usa TcpListener sobre loopback (no HttpListener),
// así que no hace falta reservar la URL con netsh.
//
// Contrato HTTP (lo que la página de Virgilio debe llamar):
//   GET  /                      -> 200 "Impresion Virgilio OK" (ping: saber si corre).
//   OPTIONS /print              -> 204 con CORS (preflight del navegador).
//   POST /print?tipo=picking    -> body = el PDF (crudo, empieza con %PDF) o en base64.
//                                  Respuesta 200 JSON { ok, tipo, impreso[], errores[], motivo }.
//   El tipo también puede ir en el header X-Virgilio-Tipo.
//
// Las reglas (tipo -> impresora) se guardan en virgilio-impresion-<PC>.json, junto al .exe.
// La ventana muestra una fila fija por tipo de hoja y guarda sola cada cambio.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Printing;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace ImpresionVirgilio
{
    static class Program
    {
        public const string VERSION = "1.2.0";

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    // Una regla: el tipo de hoja de Virgilio y a qué impresora de esta PC va.
    public class Regla
    {
        public string Tipo = "";
        public string Impresora = "";
        public int Copias = 1;
        public string Papel = "A4";
        public bool Activa = true;
    }

    // Resultado de procesar un trabajo, que se devuelve a la página como JSON.
    public class Resultado
    {
        public bool ok = false;
        public string tipo = "";
        public List<string> impreso = new List<string>();
        public List<string> errores = new List<string>();
        public string motivo = "";
    }

    // Opción de un combo: el valor que se guarda y el texto que se ve.
    public class Opcion
    {
        public string Valor { get; set; }
        public string Texto { get; set; }
        public Opcion(string valor, string texto) { Valor = valor; Texto = texto; }
        public override string ToString() { return Texto; }
    }

    // Una fila de la ventana: un tipo de hoja y a qué impresora va. Tildada = regla activa.
    public class FilaTipo
    {
        public string Tipo;     // lo que manda Virgilio: picking | armado | facturado
        public string Titulo;   // lo que se ve
        public CheckBox Chk;
        public ComboBox CboImp, CboCop;
        public Label LblAviso;
    }

    public class MainForm : Form
    {
        // Las hojas que genera Virgilio: valor que manda la página y texto que se ve.
        static readonly string[,] TIPOS = { { "picking", "Picking" }, { "armado", "Armado" }, { "facturado", "Facturado" } };

        static readonly Color VerdeFondo = Color.FromArgb(226, 243, 228), VerdeTexto = Color.FromArgb(27, 94, 32);
        static readonly Color NaranjaFondo = Color.FromArgb(255, 240, 214), NaranjaTexto = Color.FromArgb(150, 80, 0);
        static readonly Color RojoFondo = Color.FromArgb(253, 228, 226), RojoTexto = Color.FromArgb(165, 30, 30);
        static readonly Color Gris = Color.FromArgb(110, 110, 110);

        // --- impresión / servidor ---
        ServidorImpresion servidor;
        string errorServidor = "";
        volatile List<Regla> reglasVigentes = new List<Regla>();
        volatile string ajusteVigente = "fit";
        volatile string papelVigente = "A4";   // tamaño de hoja, global (se configura en Opciones avanzadas)
        int puertoVigente = 17777;
        readonly object printLock = new object();
        int recibidos = 0, impresos = 0, erroresImp = 0;

        // --- rutas ---
        string baseDir, sumatraPath, reglasPath, logPath, tempDir;

        // --- configuración en pantalla ---
        List<FilaTipo> filas = new List<FilaTipo>();
        // Reglas del .json de otros tipos (cargadas a mano): se siguen usando y se guardan tal cual.
        List<Dictionary<string, object>> reglasExtra = new List<Dictionary<string, object>>();
        List<string> instaladas = new List<string>();

        // --- UI ---
        TableLayoutPanel banner, tablaReglas;
        Label lblTitulo, lblDetalle, lblGuardado;
        Button btnReintentar;
        bool cargando = false, sinGuardar = false;
        object logLock = new object();
        StringBuilder logBuf = new StringBuilder();   // historial de actividad, se muestra en Opciones avanzadas
        volatile TextBox logView;                      // cuadro de Actividad del diálogo, mientras está abierto
        volatile Label lblContadorDlg;                 // contador del diálogo, mientras está abierto

        public MainForm()
        {
            Text = "Impresión Virgilio";
            Font = new Font("Segoe UI", 9.75f);
            BackColor = Color.White;
            ClientSize = new Size(960, 620);
            StartPosition = FormStartPosition.CenterScreen;

            ResolvePaths();

            TableLayoutPanel raiz = new TableLayoutPanel();
            raiz.Dock = DockStyle.Fill;
            raiz.ColumnCount = 1;
            raiz.RowCount = 3;
            raiz.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            raiz.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            raiz.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            raiz.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            raiz.Controls.Add(ArmarBanner(), 0, 0);
            raiz.Controls.Add(ArmarReglas(), 0, 1);
            raiz.Controls.Add(ArmarBotonera(), 0, 2);
            Controls.Add(raiz);

            FormClosing += OnClosing;
            Load += delegate
            {
                CargarImpresoras();
                CargarReglas();
                IniciarServidor();
                // ventana compacta: que entre justo el contenido (tabla entera incluida)
                int cromoW = Width - ClientSize.Width, cromoH = Height - ClientSize.Height;
                int ancho = Math.Max(tablaReglas.PreferredSize.Width + 40, 460) + cromoW;
                int alto = raiz.PreferredSize.Height + 16 + cromoH;
                MinimumSize = new Size(ancho, alto);
                Size = new Size(ancho, alto);
                CenterToScreen();
            };
        }

        // ================= Armado de la ventana =================

        // Cartel de arriba: dice en una línea si esta PC está lista para imprimir.
        Control ArmarBanner()
        {
            banner = new TableLayoutPanel();
            banner.Dock = DockStyle.Fill;
            banner.AutoSize = true;
            banner.Margin = new Padding(0);
            banner.Padding = new Padding(18, 12, 18, 12);
            banner.ColumnCount = 2;
            banner.RowCount = 2;
            banner.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            banner.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            lblTitulo = new Label();
            lblTitulo.AutoSize = true;
            lblTitulo.Font = new Font("Segoe UI", 15, FontStyle.Bold);
            lblTitulo.Margin = new Padding(0);
            lblTitulo.Text = "Iniciando...";
            lblDetalle = new Label();
            lblDetalle.AutoSize = true;
            lblDetalle.Font = new Font("Segoe UI", 10.5f);
            lblDetalle.Margin = new Padding(2, 4, 0, 0);
            lblDetalle.MaximumSize = new Size(700, 0);

            btnReintentar = new Button();
            btnReintentar.Text = "Reintentar";
            btnReintentar.AutoSize = true;
            btnReintentar.Padding = new Padding(10, 4, 10, 4);
            btnReintentar.Anchor = AnchorStyles.Right;
            btnReintentar.UseVisualStyleBackColor = true;
            btnReintentar.Visible = false;
            btnReintentar.Click += delegate { ReiniciarServidor(); };

            banner.Controls.Add(lblTitulo, 0, 0);
            banner.Controls.Add(lblDetalle, 0, 1);
            banner.Controls.Add(btnReintentar, 1, 0);
            banner.SetRowSpan(btnReintentar, 2);
            banner.SizeChanged += delegate { lblDetalle.MaximumSize = new Size(Math.Max(300, banner.Width - 200), 0); };
            return banner;
        }

        // Una fila fija por tipo de hoja: tilde, impresora, copias y cómo quedó.
        Control ArmarReglas()
        {
            TableLayoutPanel sec = new TableLayoutPanel();
            sec.Dock = DockStyle.Fill;
            sec.AutoSize = true;
            sec.ColumnCount = 1;
            sec.Padding = new Padding(14, 8, 14, 6);

            tablaReglas = new TableLayoutPanel();
            tablaReglas.AutoSize = true;
            tablaReglas.ColumnCount = 4;
            for (int c = 0; c < 4; c++) tablaReglas.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            string[] cabeceras = { "Hoja", "Impresora", "Copias", "" };
            for (int c = 0; c < cabeceras.Length; c++)
            {
                Label h = new Label();
                h.Text = cabeceras[c];
                h.AutoSize = true;
                h.ForeColor = Gris;
                h.Font = new Font("Segoe UI", 9);
                h.Margin = new Padding(3, 0, 3, 0);
                tablaReglas.Controls.Add(h, c, 0);
            }
            for (int i = 0; i < TIPOS.GetLength(0); i++)
            {
                FilaTipo f = ArmarFila(TIPOS[i, 0], TIPOS[i, 1]);
                filas.Add(f);
                tablaReglas.Controls.Add(f.Chk, 0, i + 1);
                tablaReglas.Controls.Add(f.CboImp, 1, i + 1);
                tablaReglas.Controls.Add(f.CboCop, 2, i + 1);
                tablaReglas.Controls.Add(f.LblAviso, 3, i + 1);
            }

            sec.Controls.Add(tablaReglas);
            return sec;
        }

        FilaTipo ArmarFila(string tipo, string titulo)
        {
            FilaTipo f = new FilaTipo();
            f.Tipo = tipo;
            f.Titulo = titulo;

            f.Chk = new CheckBox();
            f.Chk.Text = titulo;
            f.Chk.AutoSize = true;
            f.Chk.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);
            f.Chk.Anchor = AnchorStyles.Left;
            f.Chk.Margin = new Padding(3, 6, 18, 6);

            f.CboImp = Combo(280);
            f.CboCop = Combo(90);
            for (int n = 1; n <= 5; n++) f.CboCop.Items.Add(new Opcion(n.ToString(), n == 1 ? "1 copia" : n + " copias"));
            Seleccionar(f.CboCop, "1");

            f.LblAviso = new Label();
            f.LblAviso.AutoSize = true;
            f.LblAviso.Anchor = AnchorStyles.Left;
            f.LblAviso.Margin = new Padding(8, 3, 3, 3);
            f.LblAviso.MinimumSize = new Size(170, 0);

            f.Chk.CheckedChanged += delegate { if (!cargando) Cambio(f); };
            f.CboImp.SelectedIndexChanged += delegate
            {
                if (cargando) return;
                // elegir una impresora = querer que esa hoja salga: se tilda sola
                if (ImpresoraDe(f) != "" && !f.Chk.Checked) { cargando = true; f.Chk.Checked = true; cargando = false; }
                Cambio(f);
            };
            f.CboCop.SelectedIndexChanged += delegate { if (!cargando) Cambio(f); };
            return f;
        }

        static ComboBox Combo(int ancho)
        {
            ComboBox c = new ComboBox();
            c.DropDownStyle = ComboBoxStyle.DropDownList;
            c.Width = ancho;
            c.Anchor = AnchorStyles.Left;
            c.Margin = new Padding(3, 5, 6, 5);
            return c;
        }

        static Button BotonChico(string texto)
        {
            Button b = new Button();
            b.Text = texto;
            b.AutoSize = true;
            b.Padding = new Padding(6, 1, 6, 1);
            b.UseVisualStyleBackColor = true;
            return b;
        }

        Control ArmarBotonera()
        {
            FlowLayoutPanel p = new FlowLayoutPanel();
            p.Dock = DockStyle.Fill;
            p.AutoSize = true;
            p.Padding = new Padding(14, 4, 14, 8);

            Button actualizar = BotonChico("Actualizar impresoras");
            actualizar.Click += delegate
            {
                CargarImpresoras();
                Log("Lista de impresoras actualizada (" + instaladas.Count + " en esta PC).");
            };
            Button avanzadas = BotonChico("Opciones avanzadas…");
            avanzadas.Click += delegate { OpcionesAvanzadas(); };
            lblGuardado = new Label();
            lblGuardado.AutoSize = true;
            lblGuardado.ForeColor = Gris;
            lblGuardado.Margin = new Padding(14, 8, 3, 3);

            p.Controls.AddRange(new Control[] { actualizar, avanzadas, lblGuardado });
            return p;
        }

        void ResolvePaths()
        {
            baseDir = AppDomain.CurrentDomain.BaseDirectory;
            // SumatraPDF.exe junto al .exe; si no, en .\dist\
            string cand1 = Path.Combine(baseDir, "SumatraPDF.exe");
            string cand2 = Path.Combine(Path.Combine(baseDir, "dist"), "SumatraPDF.exe");
            sumatraPath = File.Exists(cand1) ? cand1 : cand2;
            reglasPath = Path.Combine(baseDir, "virgilio-impresion-" + Environment.MachineName + ".json");
            logPath = Path.Combine(baseDir, "virgilio-impresion.log");
            tempDir = Path.Combine(Path.GetTempPath(), "virgilio-print");
            try { Directory.CreateDirectory(tempDir); } catch { }
        }

        // ================= Servidor HTTP =================

        void IniciarServidor()
        {
            servidor = new ServidorImpresion(puertoVigente, Log, Procesar);
            errorServidor = servidor.Iniciar();
            if (errorServidor == "")
                Log("Servidor iniciado en http://127.0.0.1:" + puertoVigente + " (PC " + Environment.MachineName + ")");
            else
                Log("ERROR al abrir el puerto " + puertoVigente + ": " + errorServidor);
            ActualizarEstado();
        }

        void ReiniciarServidor()
        {
            if (servidor != null) servidor.Detener();
            IniciarServidor();
        }

        // Procesa un trabajo: busca las reglas del tipo e imprime. Devuelve el resultado
        // que el servidor serializa como JSON para la página. Corre en un hilo del servidor.
        Resultado Procesar(string tipo, byte[] pdf)
        {
            Interlocked.Increment(ref recibidos);
            Resultado r = new Resultado();
            r.tipo = tipo;

            List<Regla> todas = reglasVigentes;
            List<Regla> match = new List<Regla>();
            string nt = Normalizar(tipo);
            foreach (Regla g in todas)
                if (g.Activa && g.Impresora != "" && Normalizar(g.Tipo) == nt) match.Add(g);

            if (match.Count == 0)
            {
                r.ok = false;
                r.motivo = "sin regla activa para el tipo \"" + tipo + "\" en esta PC";
                Log("RECIBIDO tipo=" + tipo + " (" + pdf.Length + " bytes) -> sin regla, no se imprime");
                RefrescarEstado();
                return r;
            }

            string ruta = Path.Combine(tempDir, Normalizar(tipo) + "-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + ".pdf");
            try { File.WriteAllBytes(ruta, pdf); }
            catch (Exception ex)
            {
                r.ok = false;
                r.motivo = "no se pudo guardar el PDF temporal: " + ex.Message;
                Log("ERROR guardando temporal: " + ex.Message);
                RefrescarEstado();
                return r;
            }

            lock (printLock)
            {
                foreach (Regla g in match)
                {
                    string err = ImprimirConSumatra(ruta, g.Impresora, g.Copias, g.Papel, ajusteVigente);
                    if (err == "")
                    {
                        r.impreso.Add(g.Impresora);
                        Interlocked.Increment(ref impresos);
                        Log("IMPRESO tipo=" + tipo + " -> " + g.Impresora + " (" + g.Copias + "x, " + NombrePapel(g.Papel) + ")");
                    }
                    else
                    {
                        r.errores.Add(g.Impresora + ": " + err);
                        Interlocked.Increment(ref erroresImp);
                        Log("ERR IMPRESION tipo=" + tipo + " -> " + g.Impresora + " :: " + err);
                    }
                }
            }
            r.ok = r.impreso.Count > 0;
            RefrescarEstado();
            return r;
        }

        // Mismo comando que el agente ISIS (src/imprimir.mjs). Devuelve "" si Windows aceptó el trabajo.
        string ImprimirConSumatra(string pdf, string impresora, int copias, string papel, string ajuste)
        {
            if (!File.Exists(sumatraPath)) return "falta SumatraPDF.exe (" + sumatraPath + ")";
            string appdata = Path.Combine(Path.GetTempPath(), "virgilio-sumatra");
            string ajustes = copias + "x," + ajuste + ",paper=" + (string.IsNullOrEmpty(papel) ? "auto" : papel);
            System.Diagnostics.ProcessStartInfo psi = new System.Diagnostics.ProcessStartInfo(sumatraPath,
                "-appdata " + Q(appdata) + " -print-to " + Q(impresora) + " -print-settings " + Q(ajustes)
                + " -silent -exit-on-print " + Q(pdf));
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            try
            {
                using (System.Diagnostics.Process p = System.Diagnostics.Process.Start(psi))
                {
                    if (!p.WaitForExit(60000)) { try { p.Kill(); } catch { } return "Sumatra tardó más de 60 s"; }
                    return p.ExitCode == 0 ? "" : "Sumatra salió con código " + p.ExitCode + " (¿la impresora existe en esta PC?)";
                }
            }
            catch (Exception ex) { return ex.Message; }
        }

        static string Q(string s) { return "\"" + s + "\""; }

        static string NombrePapel(string p)
        {
            switch (p)
            {
                case "A3": return "A3"; case "A4": return "A4"; case "A5": return "A5";
                case "letter": return "carta"; case "legal": return "legal/oficio";
                default: return "papel del PDF";
            }
        }

        // Normaliza un tipo: minúsculas, sin acentos, sin espacios al borde.
        static string Normalizar(string s)
        {
            if (s == null) return "";
            s = s.Trim().ToLowerInvariant();
            string n = s.Normalize(NormalizationForm.FormD);
            StringBuilder sb = new StringBuilder();
            foreach (char c in n)
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
            return sb.ToString();
        }

        // ================= Estado / log =================

        void RefrescarEstado()
        {
            try
            {
                if (InvokeRequired) BeginInvoke((Action)ActualizarEstado);
                else ActualizarEstado();
            }
            catch { }
        }

        // Cartel de arriba: en una línea, si esta PC está lista, + el puerto. El detalle de errores
        // y el contador quedan para Opciones avanzadas. "Documento configurado" = la hoja está
        // tildada y con una impresora que existe en esta PC.
        void ActualizarEstado()
        {
            bool corriendo = servidor != null && servidor.Corriendo;
            int configurados = 0, total = filas.Count;
            foreach (FilaTipo f in filas)
            {
                string imp = ImpresoraDe(f);
                if (f.Chk.Checked && imp != "" && instaladas.Contains(imp)) configurados++;
            }

            string titulo, detalle;
            Color fondo, texto;
            string puerto = "Puerto " + puertoVigente;
            if (!corriendo)
            {
                titulo = "✗  NO ESTÁ RECIBIENDO HOJAS";
                detalle = servidor != null && servidor.PuertoOcupado
                    ? "El puerto " + puertoVigente + " ya está en uso: seguramente el programa ya está abierto en otra ventana (mirá la barra de tareas)."
                    : "No se pudo abrir el puerto " + puertoVigente + ": " + errorServidor;
                fondo = RojoFondo; texto = RojoTexto;
            }
            else if (!File.Exists(sumatraPath))
            {
                titulo = "✗  FALTA SumatraPDF.exe";
                detalle = "Copiá SumatraPDF.exe en la carpeta del programa.   ·   " + puerto;
                fondo = RojoFondo; texto = RojoTexto;
            }
            else if (configurados >= total)
            {
                titulo = "✓  TODOS LOS DOCUMENTOS CONFIGURADOS";
                detalle = puerto;
                fondo = VerdeFondo; texto = VerdeTexto;
            }
            else
            {
                titulo = "⚠  FALTAN CONFIGURAR DOCUMENTOS";
                detalle = configurados + " de " + total + " listos   ·   " + puerto;
                fondo = NaranjaFondo; texto = NaranjaTexto;
            }

            banner.BackColor = fondo;
            lblTitulo.Text = titulo;
            lblTitulo.ForeColor = texto;
            lblDetalle.Text = detalle;
            lblDetalle.ForeColor = texto;
            btnReintentar.Visible = !corriendo;

            Label c = lblContadorDlg;
            if (c != null) c.Text = TextoContador();
        }

        string TextoContador()
        {
            return "Desde que se abrió: " + recibidos + " recibidas, " + impresos + " impresas, " + erroresImp + " con error.";
        }

        public void Log(string s)
        {
            string line = "[" + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss") + "] " + s;
            lock (logLock)
            {
                try { File.AppendAllText(logPath, line + "\r\n", Encoding.UTF8); } catch { }
                logBuf.Append(line).Append("\r\n");
                if (logBuf.Length > 200000) logBuf.Remove(0, logBuf.Length - 150000); // acota el historial en memoria
            }
            TextBox v = logView;
            if (v == null) return;
            try
            {
                if (v.InvokeRequired) v.BeginInvoke((Action)delegate { AppendLog(v, line); });
                else AppendLog(v, line);
            }
            catch { }
        }

        static void AppendLog(TextBox v, string line)
        {
            v.AppendText(line + "\r\n");
            v.SelectionStart = v.TextLength;
            v.ScrollToCaret();
        }

        // ================= Impresoras =================

        void CargarImpresoras()
        {
            List<string> nombres = new List<string>();
            string pred = "";
            try { pred = new PrinterSettings().PrinterName; } catch { }
            try { foreach (string n in PrinterSettings.InstalledPrinters) nombres.Add(n); } catch { }
            instaladas = nombres;

            bool antes = cargando;
            cargando = true;
            foreach (FilaTipo f in filas)
            {
                string sel = ImpresoraDe(f);
                f.CboImp.Items.Clear();
                f.CboImp.Items.Add(new Opcion("", nombres.Count == 0 ? "(no hay impresoras en esta PC)" : "— elegí una impresora —"));
                foreach (string n in nombres) f.CboImp.Items.Add(new Opcion(n, n == pred ? n + "  (predeterminada)" : n));
                SeleccionarImpresora(f, sel);
            }
            cargando = antes;
            foreach (FilaTipo f in filas) ActualizarFila(f);
            ActualizarEstado();
        }

        // Selecciona la impresora en el combo de la fila. Si no está en esta PC la agrega marcada,
        // para que se vea cuál era y se pueda cambiar.
        void SeleccionarImpresora(FilaTipo f, string imp)
        {
            if (!Seleccionar(f.CboImp, imp))
            {
                f.CboImp.Items.Add(new Opcion(imp, imp + "  (no está en esta PC)"));
                Seleccionar(f.CboImp, imp);
            }
            int w = f.CboImp.Width;
            foreach (object o in f.CboImp.Items) w = Math.Max(w, TextRenderer.MeasureText(o.ToString(), f.CboImp.Font).Width + 24);
            f.CboImp.DropDownWidth = w;
        }

        static bool Seleccionar(ComboBox c, string valor)
        {
            for (int i = 0; i < c.Items.Count; i++)
            {
                Opcion o = c.Items[i] as Opcion;
                if (o != null && o.Valor == valor) { c.SelectedIndex = i; return true; }
            }
            return false;
        }

        static string ValorDe(ComboBox c)
        {
            Opcion o = c.SelectedItem as Opcion;
            return o == null ? "" : o.Valor;
        }

        static string ImpresoraDe(FilaTipo f) { return ValorDe(f.CboImp); }

        static int CopiasDe(FilaTipo f)
        {
            int n;
            int.TryParse(ValorDe(f.CboCop), out n);
            return Math.Max(1, Math.Min(5, n));
        }

        // ================= Reglas: cargar / editar / guardar =================

        int IndiceFila(string tipo)
        {
            string nt = Normalizar(tipo);
            for (int i = 0; i < filas.Count; i++) if (filas[i].Tipo == nt) return i;
            return -1;
        }

        static Regla LeerRegla(Dictionary<string, object> r)
        {
            Regla g = new Regla();
            g.Tipo = Texto(r, "tipo");
            g.Impresora = Texto(r, "impresora");
            try { g.Copias = Math.Max(1, Math.Min(5, Convert.ToInt32(r["copias"]))); } catch { g.Copias = 1; }
            g.Papel = r.ContainsKey("papel") ? Texto(r, "papel") : "A4";
            if (Array.IndexOf(new string[] { "A4", "A5", "A3", "letter", "legal", "" }, g.Papel) < 0) g.Papel = "A4";
            try { g.Activa = r.ContainsKey("activa") ? Convert.ToBoolean(r["activa"]) : true; } catch { g.Activa = true; }
            return g;
        }

        void CargarReglas()
        {
            object[] reglas = new object[0];
            string ajuste = "fit";
            string papel = null;   // null = el archivo no trae tamaño global; se toma de la 1ª regla o A4
            int puerto = 17777;
            string errLeer = null;
            if (File.Exists(reglasPath))
            {
                try
                {
                    string txt = File.ReadAllText(reglasPath, Encoding.UTF8).Replace("﻿", "");
                    Dictionary<string, object> cfg = new JavaScriptSerializer().DeserializeObject(txt) as Dictionary<string, object>;
                    if (cfg != null)
                    {
                        if (cfg.ContainsKey("ajuste")) ajuste = Convert.ToString(cfg["ajuste"]);
                        if (cfg.ContainsKey("papel")) papel = Convert.ToString(cfg["papel"]);
                        if (cfg.ContainsKey("puerto")) { try { puerto = Convert.ToInt32(cfg["puerto"]); } catch { } }
                        if (cfg.ContainsKey("reglas") && cfg["reglas"] is object[]) reglas = (object[])cfg["reglas"];
                    }
                }
                catch (Exception ex) { errLeer = ex.Message; }
            }

            // Cada hoja toma la primera regla de su tipo (una impresora por hoja). Las de otros tipos
            // se guardan aparte y se siguen usando.
            cargando = true;
            reglasExtra = new List<Dictionary<string, object>>();
            List<string> repetidas = new List<string>();
            List<string> otrosTipos = new List<string>();
            bool[] asignada = new bool[filas.Count];
            foreach (FilaTipo f in filas)
            {
                f.Chk.Checked = false;
                SeleccionarImpresora(f, "");
                Seleccionar(f.CboCop, "1");
            }
            foreach (object o in reglas)
            {
                Dictionary<string, object> r = o as Dictionary<string, object>;
                if (r == null) continue;
                Regla g = LeerRegla(r);
                int i = IndiceFila(g.Tipo);
                if (i < 0) { reglasExtra.Add(r); otrosTipos.Add(g.Tipo); continue; }
                if (asignada[i]) { repetidas.Add(filas[i].Titulo + " -> " + g.Impresora); continue; }
                asignada[i] = true;
                if (papel == null) papel = g.Papel;   // sin tamaño global: se toma el de la 1ª regla
                FilaTipo fila = filas[i];
                fila.Chk.Checked = g.Activa && g.Impresora != "";
                SeleccionarImpresora(fila, g.Impresora);
                Seleccionar(fila.CboCop, g.Copias.ToString());
            }
            if (Array.IndexOf(new string[] { "fit", "noscale", "shrink" }, ajuste) < 0) ajuste = "fit";
            if (papel == null || Array.IndexOf(new string[] { "A4", "A5", "A3", "letter", "legal", "" }, papel) < 0) papel = "A4";
            cargando = false;

            ajusteVigente = ajuste;
            papelVigente = papel;
            puertoVigente = Math.Max(1024, Math.Min(65535, puerto));
            reglasVigentes = ReglasDePantalla();
            foreach (FilaTipo f in filas) ActualizarFila(f);
            ActualizarEstado();

            if (errLeer != null)
            {
                MarcarGuardado("No se pudo leer " + Path.GetFileName(reglasPath) + ": " + errLeer, true);
                Log("ERROR leyendo " + Path.GetFileName(reglasPath) + ": " + errLeer);
            }
            else MarcarGuardado(File.Exists(reglasPath) ? "Configuración: " + Path.GetFileName(reglasPath) : "Todavía sin configurar en esta PC.", false);
            if (repetidas.Count > 0)
                Log("Aviso: el archivo tenía más de una impresora para la misma hoja. Se usa la primera; quedan sin usar: "
                    + string.Join(", ", repetidas.ToArray()) + ".");
            if (otrosTipos.Count > 0)
                Log("Aviso: el archivo tiene reglas de otros tipos de hoja (" + string.Join(", ", otrosTipos.ToArray()) + "); se siguen usando tal cual.");
        }

        static string Texto(Dictionary<string, object> r, string k)
        {
            return r.ContainsKey(k) && r[k] != null ? Convert.ToString(r[k]).Trim() : "";
        }

        // Reglas que valen según lo que está en pantalla (+ las de otros tipos del archivo).
        List<Regla> ReglasDePantalla()
        {
            List<Regla> l = new List<Regla>();
            foreach (FilaTipo f in filas)
            {
                string imp = ImpresoraDe(f);
                if (imp == "") continue;
                Regla g = new Regla();
                g.Tipo = f.Tipo; g.Impresora = imp; g.Copias = CopiasDe(f); g.Papel = papelVigente; g.Activa = f.Chk.Checked;
                l.Add(g);
            }
            foreach (Dictionary<string, object> r in reglasExtra) l.Add(LeerRegla(r));
            return l;
        }

        // Cómo quedó la fila, en palabras, al lado de la impresora.
        void ActualizarFila(FilaTipo f)
        {
            string imp = ImpresoraDe(f);
            f.Chk.ForeColor = f.Chk.Checked ? SystemColors.ControlText : Gris;
            if (!f.Chk.Checked) Aviso(f, "No se imprime en esta PC", Gris);
            else if (imp == "") Aviso(f, "⚠ Falta elegir impresora", NaranjaTexto);
            else if (!instaladas.Contains(imp)) Aviso(f, "⚠ No está en esta PC", RojoTexto);
            else Aviso(f, "✓ Se imprime", VerdeTexto);
        }

        static void Aviso(FilaTipo f, string texto, Color color)
        {
            f.LblAviso.Text = texto;
            f.LblAviso.ForeColor = color;
        }

        void Cambio(FilaTipo f)
        {
            ActualizarFila(f);
            Guardar();
            ActualizarEstado();
        }

        void MarcarGuardado(string texto, bool alerta)
        {
            lblGuardado.Text = texto;
            lblGuardado.ForeColor = alerta ? RojoTexto : Gris;
        }

        // Guarda lo que está en pantalla. Vale al instante (aunque falle el archivo).
        bool Guardar()
        {
            List<Regla> vigentes = ReglasDePantalla();
            reglasVigentes = vigentes;

            List<object> reglasJson = new List<object>();
            foreach (Regla g in vigentes)
            {
                if (IndiceFila(g.Tipo) < 0) continue;   // las de otros tipos van abajo, tal cual estaban
                Dictionary<string, object> r = new Dictionary<string, object>();
                r["tipo"] = g.Tipo; r["impresora"] = g.Impresora; r["copias"] = g.Copias; r["papel"] = g.Papel; r["activa"] = g.Activa;
                reglasJson.Add(r);
            }
            foreach (Dictionary<string, object> r in reglasExtra) reglasJson.Add(r);

            Dictionary<string, object> cfg = new Dictionary<string, object>();
            cfg["pc"] = Environment.MachineName;
            cfg["actualizado"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " por " + Environment.UserName;
            cfg["puerto"] = puertoVigente;
            cfg["ajuste"] = ajusteVigente;
            cfg["papel"] = papelVigente;
            cfg["reglas"] = reglasJson;
            try
            {
                string tmp = reglasPath + ".tmp";
                File.WriteAllText(tmp, new JavaScriptSerializer().Serialize(cfg), new UTF8Encoding(false));
                if (File.Exists(reglasPath)) File.Replace(tmp, reglasPath, null);
                else File.Move(tmp, reglasPath);
            }
            catch (Exception ex)
            {
                sinGuardar = true;
                MarcarGuardado("⚠ NO se pudo guardar: " + ex.Message, true);
                Log("ERROR guardando " + reglasPath + ": " + ex.Message);
                return false;
            }

            sinGuardar = false;
            MarcarGuardado("Guardado ✓ " + DateTime.Now.ToString("HH:mm:ss"), false);
            Log("Reglas guardadas por " + Environment.UserName + ": " + Resumen());
            return true;
        }

        string Resumen()
        {
            List<string> partes = new List<string>();
            foreach (FilaTipo f in filas)
            {
                string imp = ImpresoraDe(f);
                if (!f.Chk.Checked) partes.Add(f.Titulo + " -> no se imprime");
                else if (imp == "") partes.Add(f.Titulo + " -> sin impresora");
                else partes.Add(f.Titulo + " -> " + imp + " (" + CopiasDe(f) + "x, " + NombrePapel(papelVigente) + ")");
            }
            return string.Join(" | ", partes.ToArray());
        }

        // Manda un PDF elegido a mano a una impresora (1 copia), con el tamaño y la escala globales.
        // Se usa desde Opciones avanzadas. owner = la ventana sobre la que se muestran los diálogos.
        void Probar(IWin32Window owner, string impresora)
        {
            if (string.IsNullOrEmpty(impresora)) return;
            OpenFileDialog dlg = new OpenFileDialog();
            dlg.Filter = "PDF (*.pdf)|*.pdf";
            dlg.Title = "Elegí un PDF para probar la impresora " + impresora;
            if (dlg.ShowDialog(owner) != DialogResult.OK) return;
            string pdf = dlg.FileName;
            string papel = papelVigente, ajuste = ajusteVigente;
            Thread t = new Thread(delegate()
            {
                string res = ImprimirConSumatra(pdf, impresora, 1, papel, ajuste);
                try
                {
                    BeginInvoke((Action)delegate
                    {
                        if (res == "")
                        {
                            Log("PRUEBA -> " + impresora + ": " + Path.GetFileName(pdf));
                            MessageBox.Show("Prueba enviada a " + impresora + ".", "Impresión Virgilio", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        }
                        else
                        {
                            Log("ERR PRUEBA -> " + impresora + " :: " + res);
                            MessageBox.Show("La prueba no salió:\n" + res, "Impresión Virgilio", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        }
                    });
                }
                catch { }
            });
            t.IsBackground = true;
            t.Start();
        }

        // ================= Opciones avanzadas (puerto, tamaño de hoja, escala, inicio, probar, registro) =================

        void OpcionesAvanzadas()
        {
            using (Form d = new Form())
            {
                d.Text = "Opciones avanzadas";
                d.Font = Font;
                d.BackColor = Color.White;
                d.FormBorderStyle = FormBorderStyle.Sizable;
                d.MaximizeBox = true;
                d.MinimizeBox = false;
                d.ShowInTaskbar = false;
                d.StartPosition = FormStartPosition.CenterParent;
                d.ClientSize = new Size(640, 600);
                d.MinimumSize = new Size(560, 520);

                TableLayoutPanel t = new TableLayoutPanel();
                t.Dock = DockStyle.Fill;
                t.ColumnCount = 1;
                t.Padding = new Padding(16);
                t.RowCount = 9;
                for (int i = 0; i < 9; i++) t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                t.RowStyles[6] = new RowStyle(SizeType.Percent, 100);   // la fila del registro crece

                // --- grilla de ajustes (puerto / tamaño de hoja / escala) ---
                TableLayoutPanel g = new TableLayoutPanel();
                g.AutoSize = true;
                g.ColumnCount = 2;
                NumericUpDown num = new NumericUpDown();
                num.Minimum = 1024;
                num.Maximum = 65535;
                num.Value = puertoVigente;
                num.Width = 90;
                num.Anchor = AnchorStyles.Left;
                ComboBox cboPapel = Combo(200);
                cboPapel.Items.AddRange(new object[] {
                    new Opcion("A4", "A4"), new Opcion("A5", "A5"), new Opcion("A3", "A3"),
                    new Opcion("letter", "Carta"), new Opcion("legal", "Legal / Oficio"),
                    new Opcion("", "El del PDF") });
                if (!Seleccionar(cboPapel, papelVigente)) Seleccionar(cboPapel, "A4");
                ComboBox cboEscala = Combo(260);
                cboEscala.Items.AddRange(new object[] {
                    new Opcion("fit", "Ajustar a la hoja (recomendado)"),
                    new Opcion("noscale", "Tamaño real"),
                    new Opcion("shrink", "Reducir solo si no entra") });
                if (!Seleccionar(cboEscala, ajusteVigente)) cboEscala.SelectedIndex = 0;

                g.Controls.Add(Etiqueta("Puerto:"), 0, 0);
                g.Controls.Add(num, 1, 0);
                Label notaPuerto = Nota("Virgilio manda las hojas a http://127.0.0.1:" + puertoVigente + "/print. Cambialo solo si "
                    + "otro programa usa ese puerto, y avisá a quien mantiene Virgilio: la página tiene que usar el mismo.");
                g.Controls.Add(notaPuerto, 1, 1);
                g.Controls.Add(Etiqueta("Tamaño de hoja:"), 0, 2);
                g.Controls.Add(cboPapel, 1, 2);
                g.Controls.Add(Etiqueta("Tamaño en la hoja:"), 0, 3);
                g.Controls.Add(cboEscala, 1, 3);
                t.Controls.Add(g, 0, 0);

                // --- iniciar con Windows ---
                CheckBox chk = new CheckBox();
                chk.Text = "Iniciar con Windows";
                chk.AutoSize = true;
                chk.Margin = new Padding(3, 8, 3, 2);
                chk.Checked = AutostartActivo();
                chk.CheckedChanged += delegate
                {
                    if (!SetAutostart(chk.Checked))
                    { bool a = cargando; cargando = true; chk.Checked = AutostartActivo(); cargando = a; }
                };
                t.Controls.Add(chk, 0, 1);

                // --- probar una impresora ---
                FlowLayoutPanel probar = new FlowLayoutPanel();
                probar.AutoSize = true;
                probar.Margin = new Padding(0, 8, 0, 2);
                probar.Controls.Add(Etiqueta("Probar impresión:"));
                ComboBox cboProbar = Combo(260);
                cboProbar.Items.Clear();
                foreach (string n in instaladas) cboProbar.Items.Add(new Opcion(n, n));
                if (cboProbar.Items.Count > 0) cboProbar.SelectedIndex = 0;
                Button btnProbar = BotonChico("Enviar PDF de prueba…");
                btnProbar.Click += delegate { Probar(d, ValorDe(cboProbar)); };
                probar.Controls.Add(cboProbar);
                probar.Controls.Add(btnProbar);
                t.Controls.Add(probar, 0, 2);

                // --- info de archivos ---
                Label info = Nota("Versión " + Program.VERSION + "   ·   PC " + Environment.MachineName
                    + "\r\nConfiguración: " + reglasPath + "\r\nRegistro: " + logPath);
                info.Margin = new Padding(3, 12, 3, 4);
                t.Controls.Add(info, 0, 3);

                FlowLayoutPanel archivos = new FlowLayoutPanel();
                archivos.AutoSize = true;
                Button carpeta = BotonChico("Abrir carpeta del programa");
                carpeta.Click += delegate { Abrir("explorer.exe", baseDir); };
                Button registro = BotonChico("Abrir registro en Bloc de notas");
                registro.Click += delegate { Abrir("notepad.exe", logPath); };
                archivos.Controls.AddRange(new Control[] { carpeta, registro });
                t.Controls.Add(archivos, 0, 4);

                // --- actividad (registro en vivo) ---
                Label hAct = new Label();
                hAct.Text = "Actividad";
                hAct.AutoSize = true;
                hAct.ForeColor = Gris;
                hAct.Font = new Font("Segoe UI", 9, FontStyle.Bold);
                hAct.Margin = new Padding(3, 10, 3, 2);
                t.Controls.Add(hAct, 0, 5);

                TextBox txt = new TextBox();
                txt.Multiline = true;
                txt.ScrollBars = ScrollBars.Vertical;
                txt.ReadOnly = true;
                txt.BackColor = Color.FromArgb(247, 247, 247);
                txt.ForeColor = Color.FromArgb(40, 40, 40);
                txt.Font = new Font("Consolas", 9);
                txt.Dock = DockStyle.Fill;
                lock (logLock) txt.Text = logBuf.ToString();
                txt.SelectionStart = txt.TextLength;
                txt.ScrollToCaret();
                t.Controls.Add(txt, 0, 6);

                Label lblCont = new Label();
                lblCont.AutoSize = true;
                lblCont.ForeColor = Gris;
                lblCont.Margin = new Padding(3, 4, 3, 2);
                lblCont.Text = TextoContador();
                t.Controls.Add(lblCont, 0, 7);

                // --- aceptar / cancelar ---
                FlowLayoutPanel botones = new FlowLayoutPanel();
                botones.AutoSize = true;
                botones.Dock = DockStyle.Fill;
                botones.FlowDirection = FlowDirection.RightToLeft;
                botones.Margin = new Padding(3, 8, 3, 0);
                Button cancelar = BotonChico("Cancelar");
                cancelar.DialogResult = DialogResult.Cancel;
                Button aceptar = BotonChico("Aceptar");
                aceptar.DialogResult = DialogResult.OK;
                botones.Controls.AddRange(new Control[] { cancelar, aceptar });
                t.Controls.Add(botones, 0, 8);

                d.AcceptButton = aceptar;
                d.CancelButton = cancelar;
                d.Controls.Add(t);

                // mientras el diálogo está abierto, el registro y el contador se actualizan en vivo
                logView = txt;
                lblContadorDlg = lblCont;
                DialogResult dr;
                try { dr = d.ShowDialog(this); }
                finally { logView = null; lblContadorDlg = null; }
                if (dr != DialogResult.OK) return;

                int puerto = (int)num.Value;
                string ajuste = ValorDe(cboEscala);
                string papel = ValorDe(cboPapel);
                if (puerto == puertoVigente && ajuste == ajusteVigente && papel == papelVigente) return;
                bool reiniciar = puerto != puertoVigente;
                puertoVigente = puerto;
                ajusteVigente = ajuste;
                papelVigente = papel;
                Guardar();
                if (reiniciar) ReiniciarServidor();
            }
        }

        static Label Etiqueta(string texto)
        {
            Label l = new Label();
            l.Text = texto;
            l.AutoSize = true;
            l.Anchor = AnchorStyles.Left;
            l.Margin = new Padding(3, 6, 12, 3);
            return l;
        }

        static Label Nota(string texto)
        {
            Label l = new Label();
            l.Text = texto;
            l.AutoSize = true;
            l.MaximumSize = new Size(460, 0);
            l.ForeColor = Gris;
            l.Margin = new Padding(3, 2, 3, 12);
            return l;
        }

        void Abrir(string programa, string ruta)
        {
            try { System.Diagnostics.Process.Start(programa, Q(ruta)); }
            catch (Exception ex) { MessageBox.Show("No se pudo abrir " + ruta + ":\n" + ex.Message, "Impresión Virgilio", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        }

        // ================= Iniciar con Windows (sin admin: acceso directo en shell:startup) =================

        string RutaAccesoDirecto()
        {
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Impresion Virgilio.lnk");
        }

        bool AutostartActivo()
        {
            try { return File.Exists(RutaAccesoDirecto()); } catch { return false; }
        }

        // Devuelve true si quedó como se pedía. Si falla, avisa y devuelve false (quien llama revierte el tilde).
        bool SetAutostart(bool on)
        {
            string lnk = RutaAccesoDirecto();
            try
            {
                if (on)
                {
                    Type t = Type.GetTypeFromProgID("WScript.Shell");
                    object shell = Activator.CreateInstance(t);
                    object sc = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
                    Type st = sc.GetType();
                    st.InvokeMember("TargetPath", BindingFlags.SetProperty, null, sc, new object[] { Application.ExecutablePath });
                    st.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, sc, new object[] { baseDir });
                    st.InvokeMember("Description", BindingFlags.SetProperty, null, sc, new object[] { "Helper de impresión de Gestión Virgilio" });
                    st.InvokeMember("Save", BindingFlags.InvokeMethod, null, sc, new object[0]);
                }
                else
                {
                    if (File.Exists(lnk)) File.Delete(lnk);
                }
                Log(on ? "Iniciar con Windows: activado." : "Iniciar con Windows: desactivado.");
                return true;
            }
            catch (Exception ex)
            {
                MessageBox.Show("No se pudo cambiar el inicio con Windows:\n" + ex.Message, "Impresión Virgilio", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
        }

        void OnClosing(object sender, FormClosingEventArgs e)
        {
            // Si el usuario cierra (X o Alt+F4), ofrecer minimizar: cerrado = deja de imprimir.
            if (e.CloseReason == CloseReason.UserClosing)
            {
                DialogResult r = MessageBox.Show(
                    "Si cerrás el programa, las hojas de Virgilio dejan de imprimirse en esta PC.\n\n"
                    + "¿Minimizarlo y dejarlo funcionando en vez de cerrarlo?\n\n"
                    + "Sí = minimizar (sigue imprimiendo)\nNo = cerrar\nCancelar = volver",
                    "Impresión Virgilio", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (r == DialogResult.Yes) { e.Cancel = true; WindowState = FormWindowState.Minimized; return; }
                if (r == DialogResult.Cancel) { e.Cancel = true; return; }
            }
            if (sinGuardar)
            {
                DialogResult r = MessageBox.Show("El último cambio no se pudo guardar en " + Path.GetFileName(reglasPath)
                    + ".\nSi cerrás, al volver a abrir el programa no va a estar.\n\n¿Cerrar igual?",
                    "Impresión Virgilio", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (r == DialogResult.No) { e.Cancel = true; return; }
            }
            if (servidor != null) servidor.Detener();
        }
    }

    // ================= Servidor HTTP mínimo sobre TcpListener (loopback, sin admin) =================
    public class ServidorImpresion
    {
        TcpListener listener;
        Thread hilo;
        volatile bool corriendo = false;
        volatile bool puertoOcupado = false;
        int puerto;
        Action<string> log;
        Func<string, byte[], Resultado> handler;

        public bool Corriendo { get { return corriendo; } }
        // true si Iniciar falló porque otro programa (u otra ventana de este) ya usa el puerto.
        public bool PuertoOcupado { get { return puertoOcupado; } }

        public ServidorImpresion(int puerto, Action<string> log, Func<string, byte[], Resultado> handler)
        {
            this.puerto = puerto;
            this.log = log;
            this.handler = handler;
        }

        public string Iniciar()
        {
            try
            {
                listener = new TcpListener(IPAddress.Loopback, puerto);
                listener.Start();
                corriendo = true;
                hilo = new Thread(AcceptLoop);
                hilo.IsBackground = true;
                hilo.Start();
                return "";
            }
            catch (SocketException ex)
            {
                corriendo = false;
                puertoOcupado = ex.SocketErrorCode == SocketError.AddressAlreadyInUse;
                return ex.Message;
            }
            catch (Exception ex) { corriendo = false; return ex.Message; }
        }

        public void Detener()
        {
            corriendo = false;
            try { if (listener != null) listener.Stop(); } catch { }
        }

        void AcceptLoop()
        {
            while (corriendo)
            {
                TcpClient c;
                try { c = listener.AcceptTcpClient(); }
                catch { break; }
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try { Atender(c); }
                    catch (Exception ex) { if (log != null) log("conexión: " + ex.Message); }
                });
            }
        }

        void Atender(TcpClient client)
        {
            using (client)
            using (NetworkStream ns = client.GetStream())
            {
                ns.ReadTimeout = 20000;
                ns.WriteTimeout = 20000;

                // Leer hasta el fin de los headers (\r\n\r\n)
                MemoryStream buf = new MemoryStream();
                byte[] tmp = new byte[8192];
                int finHeaders = -1;
                while (finHeaders < 0)
                {
                    int n;
                    try { n = ns.Read(tmp, 0, tmp.Length); }
                    catch { return; }
                    if (n <= 0) break;
                    buf.Write(tmp, 0, n);
                    finHeaders = BuscarDobleCrlf(buf.GetBuffer(), (int)buf.Length);
                    if (buf.Length > 1048576 && finHeaders < 0) { Responder(ns, 400, "Bad Request", "text/plain", Encoding.ASCII.GetBytes("header grande")); return; }
                }
                byte[] all = buf.ToArray();
                if (finHeaders < 0) { Responder(ns, 400, "Bad Request", "text/plain", Encoding.ASCII.GetBytes("sin headers")); return; }

                string cab = Encoding.ASCII.GetString(all, 0, finHeaders);
                string[] lineas = cab.Replace("\r\n", "\n").Split('\n');
                string[] partes = lineas[0].Split(' ');
                if (partes.Length < 2) { Responder(ns, 400, "Bad Request", "text/plain", Encoding.ASCII.GetBytes("request line")); return; }
                string metodo = partes[0].ToUpperInvariant();
                string ruta = partes[1];

                Dictionary<string, string> headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                for (int i = 1; i < lineas.Length; i++)
                {
                    int dp = lineas[i].IndexOf(':');
                    if (dp > 0) headers[lineas[i].Substring(0, dp).Trim()] = lineas[i].Substring(dp + 1).Trim();
                }

                // Preflight CORS
                if (metodo == "OPTIONS") { Responder(ns, 204, "No Content", null, null); return; }

                // Ping / salud
                if (metodo == "GET")
                {
                    byte[] b = Encoding.UTF8.GetBytes("Impresion Virgilio OK v" + Program.VERSION);
                    Responder(ns, 200, "OK", "text/plain; charset=utf-8", b);
                    return;
                }

                if (metodo != "POST") { Responder(ns, 405, "Method Not Allowed", "text/plain", Encoding.ASCII.GetBytes("usar POST")); return; }

                // ruta + query
                string path = ruta;
                string query = "";
                int iq = ruta.IndexOf('?');
                if (iq >= 0) { path = ruta.Substring(0, iq); query = ruta.Substring(iq + 1); }
                if (!path.StartsWith("/print")) { Responder(ns, 404, "Not Found", "text/plain", Encoding.ASCII.GetBytes("usar /print")); return; }

                // Leer el body completo (Content-Length)
                int largo = 0;
                if (headers.ContainsKey("Content-Length")) int.TryParse(headers["Content-Length"], out largo);
                int inicioBody = finHeaders + 4;
                int yaHay = all.Length - inicioBody;
                if (largo <= 0) largo = Math.Max(0, yaHay);
                byte[] body = new byte[largo];
                int copiar = Math.Min(yaHay, largo);
                if (copiar > 0) Array.Copy(all, inicioBody, body, 0, copiar);
                int tengo = copiar;
                while (tengo < largo)
                {
                    int n;
                    try { n = ns.Read(body, tengo, largo - tengo); }
                    catch { break; }
                    if (n <= 0) break;
                    tengo += n;
                }

                // tipo: query ?tipo= o header X-Virgilio-Tipo
                string tipo = ValorQuery(query, "tipo");
                if (tipo == "" && headers.ContainsKey("X-Virgilio-Tipo")) tipo = headers["X-Virgilio-Tipo"];
                tipo = tipo.Trim();

                // decodificar el PDF (crudo o base64)
                byte[] pdf = DecodificarPdf(body);
                if (pdf == null)
                {
                    Resultado rbad = new Resultado();
                    rbad.tipo = tipo; rbad.ok = false; rbad.motivo = "el body no es un PDF (ni crudo ni base64)";
                    Responder(ns, 400, "Bad Request", "application/json; charset=utf-8", Encoding.UTF8.GetBytes(Json(rbad)));
                    return;
                }

                Resultado r = handler(tipo, pdf);
                Responder(ns, 200, "OK", "application/json; charset=utf-8", Encoding.UTF8.GetBytes(Json(r)));
            }
        }

        static byte[] DecodificarPdf(byte[] body)
        {
            if (body == null || body.Length < 4) return null;
            if (EsPdf(body)) return body;
            try
            {
                string s = Encoding.UTF8.GetString(body).Trim();
                int c = s.IndexOf("base64,");
                if (c >= 0) s = s.Substring(c + 7);
                StringBuilder sb = new StringBuilder(s.Length);
                foreach (char ch in s) if (!char.IsWhiteSpace(ch)) sb.Append(ch);
                byte[] dec = Convert.FromBase64String(sb.ToString());
                return EsPdf(dec) ? dec : null;
            }
            catch { return null; }
        }

        static bool EsPdf(byte[] b)
        {
            return b.Length >= 4 && b[0] == (byte)'%' && b[1] == (byte)'P' && b[2] == (byte)'D' && b[3] == (byte)'F';
        }

        static string ValorQuery(string query, string clave)
        {
            if (query == "") return "";
            foreach (string par in query.Split('&'))
            {
                int eq = par.IndexOf('=');
                string k = eq >= 0 ? par.Substring(0, eq) : par;
                string v = eq >= 0 ? par.Substring(eq + 1) : "";
                if (k == clave) { try { return Uri.UnescapeDataString(v.Replace('+', ' ')); } catch { return v; } }
            }
            return "";
        }

        static int BuscarDobleCrlf(byte[] b, int largo)
        {
            for (int i = 0; i + 3 < largo; i++)
                if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
            return -1;
        }

        void Responder(NetworkStream ns, int code, string texto, string contentType, byte[] body)
        {
            StringBuilder h = new StringBuilder();
            h.Append("HTTP/1.1 " + code + " " + texto + "\r\n");
            h.Append("Access-Control-Allow-Origin: *\r\n");
            h.Append("Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n");
            h.Append("Access-Control-Allow-Headers: Content-Type, X-Virgilio-Tipo\r\n");
            h.Append("Access-Control-Allow-Private-Network: true\r\n");
            h.Append("Access-Control-Max-Age: 86400\r\n");
            if (body != null && body.Length > 0)
            {
                h.Append("Content-Type: " + contentType + "\r\n");
                h.Append("Content-Length: " + body.Length + "\r\n");
            }
            else h.Append("Content-Length: 0\r\n");
            h.Append("Connection: close\r\n\r\n");
            try
            {
                byte[] hb = Encoding.ASCII.GetBytes(h.ToString());
                ns.Write(hb, 0, hb.Length);
                if (body != null && body.Length > 0) ns.Write(body, 0, body.Length);
                ns.Flush();
            }
            catch { }
        }

        static string Json(Resultado r)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("{");
            sb.Append("\"ok\":" + (r.ok ? "true" : "false"));
            sb.Append(",\"tipo\":\"" + Esc(r.tipo) + "\"");
            sb.Append(",\"impreso\":[" + Lista(r.impreso) + "]");
            sb.Append(",\"errores\":[" + Lista(r.errores) + "]");
            sb.Append(",\"motivo\":\"" + Esc(r.motivo) + "\"");
            sb.Append("}");
            return sb.ToString();
        }

        static string Lista(List<string> xs)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < xs.Count; i++) { if (i > 0) sb.Append(","); sb.Append("\"" + Esc(xs[i]) + "\""); }
            return sb.ToString();
        }

        static string Esc(string s)
        {
            if (s == null) return "";
            StringBuilder sb = new StringBuilder();
            foreach (char c in s)
            {
                if (c == '"' || c == '\\') sb.Append('\\').Append(c);
                else if (c == '\n') sb.Append("\\n");
                else if (c == '\r') sb.Append("\\r");
                else if (c == '\t') sb.Append("\\t");
                else if (c < 32) sb.Append("\\u").Append(((int)c).ToString("x4"));
                else sb.Append(c);
            }
            return sb.ToString();
        }
    }
}
