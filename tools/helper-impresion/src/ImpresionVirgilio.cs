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
// Se compila a un único .exe con csc.exe (ver compilar.bat / README). No necesita instalar
// nada ni permisos de administrador: el servidor usa TcpListener sobre loopback (no
// HttpListener), así que no hace falta reservar la URL con netsh.
//
// Contrato HTTP (lo que la página de Virgilio debe llamar):
//   GET  /                      -> 200 "Impresion Virgilio OK vX" (ping: saber si corre).
//   OPTIONS /print              -> 204 con CORS (preflight del navegador).
//   POST /print?tipo=picking    -> body = el PDF (crudo, empieza con %PDF) o en base64.
//                                  Respuesta 200 JSON { ok, tipo, impreso[], errores[], motivo }.
//   El tipo también puede ir en el header X-Virgilio-Tipo.
//
// Las reglas (tipo -> impresora) se guardan en virgilio-impresion-<PC>.json, junto al .exe.

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
        public const string VERSION = "1.0.0";

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

    public class MainForm : Form
    {
        // --- impresión / servidor ---
        ServidorImpresion servidor;
        volatile List<Regla> reglasVigentes = new List<Regla>();
        volatile string ajusteVigente = "fit";
        int puertoVigente = 17777;
        readonly object printLock = new object();
        int recibidos = 0, impresos = 0, erroresImp = 0;

        // --- rutas ---
        string baseDir, sumatraPath, reglasPath, logPath, tempDir;

        // --- UI ---
        Label lblEstado, lblListener, lblImp;
        TextBox txtLog;
        NumericUpDown numPuerto;
        ListBox lstImpresoras;
        DataGridView grid;
        DataGridViewComboBoxColumn colTipo, colImp, colCop, colPapel;
        DataGridViewCheckBoxColumn colAct;
        ComboBox cboAjuste;
        Button btnAgregar, btnQuitar, btnProbar, btnGuardar, btnReiniciar, btnActualizar;
        CheckBox chkInicio;
        bool dirty = false, cargando = false;
        object logLock = new object();

        public MainForm()
        {
            Text = "Impresión Virgilio v" + Program.VERSION + " — hojas de picking / armado / facturado";
            ClientSize = new Size(820, 620);
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(700, 540);
            Font = new Font("Segoe UI", 9);

            ResolvePaths();

            // Estado general (arriba del todo)
            lblEstado = new Label();
            lblEstado.AutoSize = true;
            lblEstado.Location = new Point(14, 10);
            lblEstado.Font = new Font("Segoe UI", 11, FontStyle.Bold);
            lblEstado.Text = "Iniciando...";
            Controls.Add(lblEstado);

            // Panel superior: listener + puerto + impresoras
            Panel arriba = new Panel();
            arriba.Dock = DockStyle.Top;
            arriba.Height = 150;
            arriba.Padding = new Padding(12, 36, 12, 4);

            lblListener = new Label();
            lblListener.AutoSize = true;
            lblListener.Location = new Point(12, 38);
            lblListener.Font = new Font("Segoe UI", 9, FontStyle.Bold);

            Label lPuerto = new Label();
            lPuerto.Text = "Puerto:";
            lPuerto.AutoSize = true;
            lPuerto.Location = new Point(12, 64);
            numPuerto = new NumericUpDown();
            numPuerto.Minimum = 1024;
            numPuerto.Maximum = 65535;
            numPuerto.Value = puertoVigente;
            numPuerto.Location = new Point(66, 61);
            numPuerto.Width = 80;
            btnReiniciar = new Button();
            btnReiniciar.Text = "Reiniciar servidor";
            btnReiniciar.Location = new Point(156, 59);
            btnReiniciar.Size = new Size(130, 26);
            btnReiniciar.Click += delegate { ReiniciarServidor(); };

            chkInicio = new CheckBox();
            chkInicio.Text = "Iniciar con Windows";
            chkInicio.AutoSize = true;
            chkInicio.Location = new Point(300, 63);
            chkInicio.Checked = AutostartActivo();
            chkInicio.CheckedChanged += delegate { if (!cargando) SetAutostart(chkInicio.Checked); };

            Label lImp = new Label();
            lImp.Text = "Impresoras de esta PC (" + Environment.MachineName + "):";
            lImp.AutoSize = true;
            lImp.Location = new Point(12, 92);
            lstImpresoras = new ListBox();
            lstImpresoras.Location = new Point(12, 110);
            lstImpresoras.Size = new Size(660, 34);
            lstImpresoras.IntegralHeight = false;
            lstImpresoras.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            btnActualizar = new Button();
            btnActualizar.Text = "Actualizar";
            btnActualizar.Location = new Point(680, 110);
            btnActualizar.Size = new Size(110, 26);
            btnActualizar.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            btnActualizar.Click += delegate { CargarImpresoras(); };

            arriba.Controls.AddRange(new Control[] { lblListener, lPuerto, numPuerto, btnReiniciar, chkInicio, lImp, lstImpresoras, btnActualizar });
            Controls.Add(arriba);

            // Panel inferior: botones + escala + estado reglas
            Panel abajo = new Panel();
            abajo.Dock = DockStyle.Bottom;
            abajo.Height = 72;
            abajo.Padding = new Padding(12, 6, 12, 6);

            btnAgregar = Boton("Agregar regla", 12, delegate { AgregarRegla(); });
            btnQuitar = Boton("Quitar", 132, delegate { QuitarRegla(); });
            btnProbar = Boton("Probar...", 222, delegate { Probar(); });
            btnGuardar = Boton("Guardar", 322, delegate { Guardar(); });
            btnGuardar.Font = new Font("Segoe UI", 9, FontStyle.Bold);
            Label lAj = new Label();
            lAj.Text = "Escala:";
            lAj.AutoSize = true;
            lAj.Location = new Point(430, 10);
            cboAjuste = new ComboBox();
            cboAjuste.DropDownStyle = ComboBoxStyle.DropDownList;
            cboAjuste.Width = 180;
            cboAjuste.Location = new Point(478, 6);
            cboAjuste.Items.AddRange(new object[] {
                new Opcion("fit", "Ajustar a la hoja"),
                new Opcion("noscale", "Tamaño real"),
                new Opcion("shrink", "Reducir solo si no entra") });
            cboAjuste.SelectedIndex = 0;
            cboAjuste.SelectedIndexChanged += delegate { if (!cargando) MarcarCambios(); };

            lblImp = new Label();
            lblImp.AutoSize = true;
            lblImp.Location = new Point(12, 42);
            lblImp.ForeColor = Color.DimGray;

            abajo.Controls.AddRange(new Control[] { btnAgregar, btnQuitar, btnProbar, btnGuardar, lAj, cboAjuste, lblImp });
            Controls.Add(abajo);

            // Centro: grilla de reglas (arriba) + log (abajo)
            SplitContainer split = new SplitContainer();
            split.Dock = DockStyle.Fill;
            split.Orientation = Orientation.Horizontal;
            split.SplitterDistance = 210;

            grid = new DataGridView();
            grid.Dock = DockStyle.Fill;
            grid.AllowUserToAddRows = false;
            grid.AllowUserToDeleteRows = false;
            grid.AllowUserToResizeRows = false;
            grid.RowHeadersVisible = false;
            grid.EditMode = DataGridViewEditMode.EditOnEnter;
            grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.AllCells;
            grid.BackgroundColor = SystemColors.Window;

            colTipo = new DataGridViewComboBoxColumn();
            colTipo.HeaderText = "Tipo de hoja";
            colTipo.FlatStyle = FlatStyle.Flat;
            colTipo.DataSource = new List<Opcion> {
                new Opcion("picking", "Picking"),
                new Opcion("armado", "Armado"),
                new Opcion("facturado", "Facturado") };
            colTipo.ValueMember = "Valor";
            colTipo.DisplayMember = "Texto";
            colImp = new DataGridViewComboBoxColumn();
            colImp.HeaderText = "Impresora";
            colImp.FlatStyle = FlatStyle.Flat;
            colCop = new DataGridViewComboBoxColumn();
            colCop.HeaderText = "Copias";
            colCop.FlatStyle = FlatStyle.Flat;
            colCop.Items.AddRange("1", "2", "3", "4", "5");
            colPapel = new DataGridViewComboBoxColumn();
            colPapel.HeaderText = "Papel";
            colPapel.FlatStyle = FlatStyle.Flat;
            colPapel.DataSource = new List<Opcion> {
                new Opcion("A4", "A4"), new Opcion("A5", "A5"), new Opcion("A3", "A3"),
                new Opcion("letter", "Carta"), new Opcion("legal", "Legal / Oficio"),
                new Opcion("", "El del PDF") };
            colPapel.ValueMember = "Valor";
            colPapel.DisplayMember = "Texto";
            colAct = new DataGridViewCheckBoxColumn();
            colAct.HeaderText = "Activa";
            grid.Columns.AddRange(colTipo, colImp, colCop, colPapel, colAct);
            grid.DataError += delegate(object s, DataGridViewDataErrorEventArgs e) { e.ThrowException = false; };
            grid.CurrentCellDirtyStateChanged += delegate
            {
                if (grid.IsCurrentCellDirty) grid.CommitEdit(DataGridViewDataErrorContexts.Commit);
            };
            grid.CellValueChanged += delegate { if (!cargando) MarcarCambios(); };
            split.Panel1.Controls.Add(grid);
            Label hGrid = new Label();
            hGrid.Text = "Reglas: cada tipo de hoja va a una impresora de esta PC. Varios tipos pueden ir a la misma impresora.";
            hGrid.Dock = DockStyle.Top;
            hGrid.Height = 18;
            hGrid.ForeColor = Color.DimGray;
            split.Panel1.Controls.Add(hGrid);
            hGrid.BringToFront();

            txtLog = new TextBox();
            txtLog.Multiline = true;
            txtLog.ScrollBars = ScrollBars.Vertical;
            txtLog.ReadOnly = true;
            txtLog.BackColor = Color.FromArgb(24, 24, 24);
            txtLog.ForeColor = Color.Gainsboro;
            txtLog.Font = new Font("Consolas", 9);
            txtLog.Dock = DockStyle.Fill;
            split.Panel2.Controls.Add(txtLog);
            Label hLog = new Label();
            hLog.Text = "Trabajos recibidos:";
            hLog.Dock = DockStyle.Top;
            hLog.Height = 18;
            hLog.ForeColor = Color.DimGray;
            split.Panel2.Controls.Add(hLog);
            hLog.BringToFront();

            Controls.Add(split);
            split.BringToFront();

            FormClosing += OnClosing;
            Load += delegate
            {
                CargarImpresoras();
                CargarReglas();
                IniciarServidor();
            };
        }

        Button Boton(string texto, int x, EventHandler click)
        {
            Button b = new Button();
            b.Text = texto;
            b.Location = new Point(x, 6);
            b.Size = new Size(x == 12 ? 110 : (x == 132 ? 80 : (x == 222 ? 90 : 90)), 28);
            b.Click += click;
            return b;
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
            puertoVigente = (int)numPuerto.Value;
            servidor = new ServidorImpresion(puertoVigente, Log, Procesar);
            string err = servidor.Iniciar();
            if (err == "")
            {
                lblListener.Text = "Escuchando en  http://127.0.0.1:" + puertoVigente + "/print   ✓";
                lblListener.ForeColor = Color.FromArgb(30, 120, 40);
                Log("Servidor iniciado en http://127.0.0.1:" + puertoVigente + " (PC " + Environment.MachineName + ")");
            }
            else
            {
                lblListener.Text = "NO se pudo abrir el puerto " + puertoVigente + ": " + err;
                lblListener.ForeColor = Color.FromArgb(170, 40, 40);
                Log("ERROR al abrir el puerto " + puertoVigente + ": " + err);
            }
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

        void ActualizarEstado()
        {
            bool corriendo = servidor != null && servidor.Corriendo;
            lblEstado.Text = (corriendo ? "ESCUCHANDO" : "DETENIDO")
                + "   |   recibidos: " + recibidos + "   impresos: " + impresos + "   errores: " + erroresImp;
            lblEstado.ForeColor = corriendo ? Color.FromArgb(30, 120, 40) : Color.FromArgb(160, 40, 40);
        }

        public void Log(string s)
        {
            string line = "[" + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss") + "] " + s;
            try
            {
                lock (logLock) { File.AppendAllText(logPath, line + "\r\n", Encoding.UTF8); }
            }
            catch { }
            try
            {
                if (txtLog.InvokeRequired) txtLog.BeginInvoke((Action)delegate { AppendLog(line); });
                else AppendLog(line);
            }
            catch { }
        }

        void AppendLog(string line)
        {
            txtLog.AppendText(line + "\r\n");
            txtLog.SelectionStart = txtLog.TextLength;
            txtLog.ScrollToCaret();
        }

        // ================= Impresoras =================

        void CargarImpresoras()
        {
            List<string> nombres = new List<string>();
            string pred = "";
            try { pred = new PrinterSettings().PrinterName; } catch { }
            try { foreach (string n in PrinterSettings.InstalledPrinters) nombres.Add(n); } catch { }

            lstImpresoras.Items.Clear();
            foreach (string n in nombres) lstImpresoras.Items.Add(n == pred ? n + "   (predeterminada)" : n);
            if (nombres.Count == 0) lstImpresoras.Items.Add("(no se encontró ninguna impresora)");

            foreach (string n in nombres) if (!colImp.Items.Contains(n)) colImp.Items.Add(n);
        }

        bool ImpresoraInstalada(string n)
        {
            try { foreach (string i in PrinterSettings.InstalledPrinters) if (i == n) return true; } catch { }
            return false;
        }

        // ================= Reglas: cargar / editar / guardar =================

        void CargarReglas()
        {
            object[] reglas = new object[0];
            string ajuste = "fit";
            int puerto = 17777;
            string errLeer = null;
            if (File.Exists(reglasPath))
            {
                try
                {
                    string txt = File.ReadAllText(reglasPath, Encoding.UTF8).Replace("\uFEFF", "");
                    Dictionary<string, object> cfg = new JavaScriptSerializer().DeserializeObject(txt) as Dictionary<string, object>;
                    if (cfg != null)
                    {
                        if (cfg.ContainsKey("ajuste")) ajuste = Convert.ToString(cfg["ajuste"]);
                        if (cfg.ContainsKey("puerto")) { try { puerto = Convert.ToInt32(cfg["puerto"]); } catch { } }
                        if (cfg.ContainsKey("reglas") && cfg["reglas"] is object[]) reglas = (object[])cfg["reglas"];
                    }
                }
                catch (Exception ex) { errLeer = ex.Message; }
            }

            // una impresora guardada que ya no está se agrega igual al combo para que se vea
            foreach (object o in reglas)
            {
                Dictionary<string, object> r = o as Dictionary<string, object>;
                if (r == null) continue;
                string imp = Texto(r, "impresora");
                if (imp != "" && !colImp.Items.Contains(imp)) colImp.Items.Add(imp);
            }

            cargando = true;
            grid.Rows.Clear();
            List<Regla> vigentes = new List<Regla>();
            foreach (object o in reglas)
            {
                Dictionary<string, object> r = o as Dictionary<string, object>;
                if (r == null) continue;
                string tipo = Texto(r, "tipo");
                string imp = Texto(r, "impresora");
                int copias = 1;
                try { copias = Math.Max(1, Math.Min(5, Convert.ToInt32(r["copias"]))); } catch { }
                string papel = r.ContainsKey("papel") ? Texto(r, "papel") : "A4";
                if (Array.IndexOf(new string[] { "A4", "A5", "A3", "letter", "legal", "" }, papel) < 0) papel = "A4";
                bool activa = true;
                try { activa = r.ContainsKey("activa") ? Convert.ToBoolean(r["activa"]) : true; } catch { }
                grid.Rows.Add(tipo == "" ? null : tipo, imp == "" ? null : imp, copias.ToString(), papel, activa);

                Regla reg = new Regla();
                reg.Tipo = tipo; reg.Impresora = imp; reg.Copias = copias; reg.Papel = papel; reg.Activa = activa;
                vigentes.Add(reg);
            }
            for (int i = 0; i < cboAjuste.Items.Count; i++)
                if (((Opcion)cboAjuste.Items[i]).Valor == ajuste) cboAjuste.SelectedIndex = i;
            numPuerto.Value = Math.Max(numPuerto.Minimum, Math.Min(numPuerto.Maximum, puerto));
            cargando = false;

            reglasVigentes = vigentes;
            ajusteVigente = ajuste;
            dirty = false;
            if (errLeer != null) Estado("No se pudo leer " + Path.GetFileName(reglasPath) + ": " + errLeer, true);
            else RevisarReglas();
        }

        static string Texto(Dictionary<string, object> r, string k)
        {
            return r.ContainsKey(k) && r[k] != null ? Convert.ToString(r[k]).Trim() : "";
        }

        void RevisarReglas()
        {
            if (dirty) return;
            foreach (DataGridViewRow row in grid.Rows)
            {
                string imp = Convert.ToString(row.Cells[colImp.Index].Value);
                if (imp != "" && !ImpresoraInstalada(imp))
                {
                    Estado("Ojo: la impresora \"" + imp + "\" no está en esta PC. Elegí otra y Guardá.", true);
                    return;
                }
            }
            Estado(grid.Rows.Count == 0
                ? "Sin reglas: esta PC no imprime nada. «Agregar regla» para empezar."
                : grid.Rows.Count + " regla(s) en " + Path.GetFileName(reglasPath) + ". Los cambios valen al Guardar.", false);
        }

        void Estado(string texto, bool alerta)
        {
            lblImp.Text = texto;
            lblImp.ForeColor = alerta ? Color.FromArgb(180, 90, 0) : Color.DimGray;
        }

        void MarcarCambios()
        {
            dirty = true;
            Estado("Cambios SIN GUARDAR.", true);
        }

        void AgregarRegla()
        {
            int i = grid.Rows.Add(null, null, "1", "A4", true);
            grid.CurrentCell = grid.Rows[i].Cells[colTipo.Index];
            MarcarCambios();
        }

        void QuitarRegla()
        {
            if (grid.CurrentRow == null) return;
            grid.Rows.Remove(grid.CurrentRow);
            MarcarCambios();
        }

        string AjusteActual()
        {
            Opcion o = cboAjuste.SelectedItem as Opcion;
            return o == null ? "fit" : o.Valor;
        }

        bool Guardar()
        {
            grid.EndEdit();
            List<object> reglasJson = new List<object>();
            List<Regla> vigentes = new List<Regla>();
            foreach (DataGridViewRow row in grid.Rows)
            {
                string tipo = Convert.ToString(row.Cells[colTipo.Index].Value);
                string imp = Convert.ToString(row.Cells[colImp.Index].Value);
                if (tipo == "" || imp == "")
                {
                    MessageBox.Show("La regla " + (row.Index + 1) + " no tiene " + (tipo == "" ? "tipo" : "impresora") + ".",
                        "Impresión", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    grid.CurrentCell = row.Cells[tipo == "" ? colTipo.Index : colImp.Index];
                    return false;
                }
                int copias = 1;
                int.TryParse(Convert.ToString(row.Cells[colCop.Index].Value), out copias);
                copias = Math.Max(1, Math.Min(5, copias));
                string papel = Convert.ToString(row.Cells[colPapel.Index].Value);
                bool activa = row.Cells[colAct.Index].Value is bool ? (bool)row.Cells[colAct.Index].Value : true;

                Dictionary<string, object> r = new Dictionary<string, object>();
                r["tipo"] = tipo; r["impresora"] = imp; r["copias"] = copias; r["papel"] = papel; r["activa"] = activa;
                reglasJson.Add(r);

                Regla reg = new Regla();
                reg.Tipo = tipo; reg.Impresora = imp; reg.Copias = copias; reg.Papel = papel; reg.Activa = activa;
                vigentes.Add(reg);
            }

            int puerto = (int)numPuerto.Value;
            Dictionary<string, object> cfg = new Dictionary<string, object>();
            cfg["pc"] = Environment.MachineName;
            cfg["actualizado"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " por " + Environment.UserName;
            cfg["puerto"] = puerto;
            cfg["ajuste"] = AjusteActual();
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
                MessageBox.Show("No se pudo guardar " + reglasPath + ":\n" + ex.Message, "Impresión", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            reglasVigentes = vigentes;
            ajusteVigente = AjusteActual();
            Log("Reglas guardadas (" + vigentes.Count + ") por " + Environment.UserName);
            dirty = false;

            if (puerto != puertoVigente) ReiniciarServidor();
            RevisarReglas();
            return true;
        }

        // Manda un PDF elegido a mano a la impresora de la regla marcada (1 copia).
        void Probar()
        {
            grid.EndEdit();
            if (grid.CurrentRow == null) { Estado("Marcá una regla para probar su impresora.", true); return; }
            string imp = Convert.ToString(grid.CurrentRow.Cells[colImp.Index].Value);
            if (imp == "") { Estado("Esa regla no tiene impresora.", true); return; }
            string papel = Convert.ToString(grid.CurrentRow.Cells[colPapel.Index].Value);
            OpenFileDialog dlg = new OpenFileDialog();
            dlg.Filter = "PDF (*.pdf)|*.pdf";
            dlg.Title = "Elegir un PDF para imprimir de prueba en " + imp;
            if (dlg.ShowDialog(this) != DialogResult.OK) return;
            string pdf = dlg.FileName;
            string ajuste = AjusteActual();
            Estado("Mandando " + Path.GetFileName(pdf) + " a " + imp + "...", false);
            Thread t = new Thread(delegate()
            {
                string res = ImprimirConSumatra(pdf, imp, 1, papel, ajuste);
                try
                {
                    BeginInvoke((Action)delegate
                    {
                        if (res == "") Estado("Prueba enviada a " + imp + ": " + Path.GetFileName(pdf), false);
                        else
                        {
                            Estado("La prueba NO salió: " + res, true);
                            MessageBox.Show("La prueba no salió:\n" + res, "Impresión", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        }
                    });
                }
                catch { }
            });
            t.IsBackground = true;
            t.Start();
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

        void SetAutostart(bool on)
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
            }
            catch (Exception ex)
            {
                MessageBox.Show("No se pudo cambiar el inicio con Windows:\n" + ex.Message, "Impresión", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                cargando = true; chkInicio.Checked = AutostartActivo(); cargando = false;
            }
        }

        void OnClosing(object sender, FormClosingEventArgs e)
        {
            if (dirty)
            {
                DialogResult r = MessageBox.Show("Hay cambios en las reglas sin guardar.\n¿Guardarlos antes de cerrar?",
                    "Impresión", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (r == DialogResult.Cancel || (r == DialogResult.Yes && !Guardar())) { e.Cancel = true; return; }
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
        int puerto;
        Action<string> log;
        Func<string, byte[], Resultado> handler;

        public bool Corriendo { get { return corriendo; } }

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
