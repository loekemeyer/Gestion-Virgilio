Attribute VB_Name = "ListaPreciosSupabase"
' =============================================================================
'  A Costos VIGENTES -> Supabase (GP2)                               v32.09
'  Idea 7358 (Thomas 02/10, retomada por Luis 07/10). Libro entero: 16/10.
'
'  Al GUARDAR el Excel, si se toco CUALQUIER hoja:
'   1) sube "Lista de Precios " a "GP2".lista_precios_subir. La base la compara
'      contra la subida anterior (por la col A, comparando la col G) y manda a
'      Telegram (grupo de gerencia) los aumentos, bajas, nuevos, sacados y el
'      cambio de dolar.
'   2) sube TODAS las demas hojas del libro a "GP2".planilla_hojas_cargar, en
'      tandas, sobre la misma foto. Valores y formulas; no avisa por Telegram.
'
'  No cambia nada del Excel. Si no hay internet, avisa y el Excel queda guardado
'  igual; al proximo guardado se vuelve a mandar.
'
'  INSTALACION: ver INSTALAR.md en la misma carpeta.
' =============================================================================
Option Explicit

' --- CONFIGURACION -----------------------------------------------------------
Private Const SUPA_URL As String = "https://hrxfctzncixxqmpfhskv.supabase.co/rest/v1/rpc/lista_precios_subir"
Private Const SUPA_KEY As String = "sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT"   ' clave PUBLICA del proyecto
Private Const LP_TOKEN As String = "__TOKEN__"      ' "GP2".planilla_token (secreto: no compartir, no subir al repo)
Private Const HOJA As String = "Lista de Precios "  ' ojo: termina en espacio
Private Const CELDA_DOLAR As String = "H3"
Private Const ULTIMA_COL As Long = 16               ' A..P (solo Lista de Precios)
Private Const SUPA_URL_HOJAS As String = "https://hrxfctzncixxqmpfhskv.supabase.co/rest/v1/rpc/planilla_hojas_cargar"
Private Const TANDA_MAX As Long = 700000             ' caracteres por envio de las demas hojas
Private Const HOJAS_FUERA As String = "|Renta Pond|"  ' no se suben (Thomas 16/10: no se usa hoy; 17 MB)
' -----------------------------------------------------------------------------

Private mTocada As Boolean
Private mUltimo As Object     ' hoja -> JSON enviado la ultima vez (mientras el Excel esta abierto)

' Llamar desde ThisWorkbook.Workbook_SheetChange (cualquier hoja marca; se suben las hojas que cambiaron)
Public Sub LPMarcarHoja(ByVal Sh As Object)
    mTocada = True
End Sub

' Llamar desde ThisWorkbook.Workbook_AfterSave
Public Sub LPDespuesDeGuardar(ByVal Success As Boolean)
    If Not Success Or Not mTocada Then Exit Sub
    Dim r As String
    r = LPSubir(True)
    If Left$(r, 3) = "OK " Then
        mTocada = False
        Application.StatusBar = "A Costos subido a Supabase: " & r
    Else
        MsgBox "El Excel se guardo bien, pero NO se pudo subir a Supabase:" & vbLf & r & vbLf & vbLf & _
               "Se vuelve a intentar al proximo guardado.", vbExclamation, "Lista de Precios"
    End If
End Sub

' Manual (Alt+F8): sube y avisa por Telegram si hay cambios
Public Sub SubirListaPrecios()
    MsgBox LPSubir(True), vbInformation, "Lista de Precios"
End Sub

' Manual (Alt+F8): la PRIMERA vez. Sube sin mandar aviso (la foto vieja de la base
' se armo distinto y la comparacion contra ella daria cambios que no son reales).
Public Sub SubirListaPreciosSinAviso()
    MsgBox LPSubir(False), vbInformation, "Lista de Precios"
End Sub

Private Function LPSubir(ByVal avisar As Boolean) As String
    On Error GoTo fallo
    Dim ws As Worksheet, body As String, dolar As String, http As Object, resp As String
    Set ws = ThisWorkbook.Worksheets(HOJA)
    dolar = NumTxt(ws.Range(CELDA_DOLAR).Value2)

    body = "{""p_filas"":{""" & JsonEsc(HOJA) & """:" & FilasJson(ws) & "}" & _
           ",""p_subido_por"":""" & JsonEsc(Environ$("USERNAME")) & """" & _
           ",""p_avisar"":" & IIf(avisar, "true", "false") & _
           ",""p_token"":""" & LP_TOKEN & """"
    If dolar <> "" Then body = body & ",""p_dolar"":" & dolar
    body = body & "}"

    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 10000, 10000, 60000, 60000
    http.Open "POST", SUPA_URL, False
    http.setRequestHeader "apikey", SUPA_KEY
    http.setRequestHeader "Authorization", "Bearer " & SUPA_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.setRequestHeader "Content-Profile", "GP2"     ' la funcion vive en el schema GP2
    http.send body
    resp = http.responseText

    If Not (http.Status = 200 And InStr(resp, """ok"": true") + InStr(resp, """ok"":true") > 0) Then
        LPSubir = "HTTP " & http.Status & ": " & Left$(resp, 400)
        Exit Function
    End If

    ' 2) las demas hojas, sobre la foto que acaba de crear el paso 1
    Dim snap As String, r2 As String
    snap = JsonNum(resp, "snapshot_new")
    If snap = "" Then
        LPSubir = "Lista de Precios OK, pero la base no devolvio snapshot_new: " & Left$(resp, 300)
        Exit Function
    End If
    r2 = SubirOtrasHojas(snap)
    If Left$(r2, 3) = "OK " Then
        LPSubir = "OK " & resp & " | " & r2
    Else
        LPSubir = "Lista de Precios OK, pero fallaron las demas hojas: " & r2
    End If
    Exit Function
fallo:
    LPSubir = "Error: " & Err.Description
End Function

' ---- las demas hojas que CAMBIARON desde el ultimo envio (la 1ra vez que se abre el Excel: todas).
'      Chicas: juntas en tandas de TANDA_MAX. Grandes: partidas por filas (la 1ra parte reemplaza,
'      las siguientes agregan). La base guarda solo lo que llega; GP2.v_planilla_actual arma el libro.
Private Function SubirOtrasHojas(ByVal snap As String) As String
    Dim ws As Worksheet, filas() As String, k As Long, j As String, nom As String
    Dim tanda As String, enTanda As New Collection, jsTanda As New Collection
    Dim parte As String, primera As Boolean, i As Long
    Dim nH As Long, nE As Long, r As String, cambia As Boolean
    If mUltimo Is Nothing Then Set mUltimo = CreateObject("Scripting.Dictionary")

    For Each ws In ThisWorkbook.Worksheets
        If ws.Name <> HOJA And InStr(HOJAS_FUERA, "|" & ws.Name & "|") = 0 Then
            k = HojaFilas(ws, filas)
            If k > 0 Then j = "[" & Join(filas, ",") & "]" Else j = "[]"
            nom = ws.Name
            cambia = True
            If mUltimo.Exists(nom) Then cambia = (mUltimo(nom) <> j)
        Else
            cambia = False
        End If
        If cambia Then
            nH = nH + 1
            If Len(j) <= TANDA_MAX Then
                If Len(tanda) > 0 And Len(tanda) + Len(j) > TANDA_MAX Then
                    r = PostHojas(snap, tanda, True)
                    If r <> "" Then SubirOtrasHojas = r: Exit Function
                    Recordar enTanda, jsTanda
                    tanda = "": nE = nE + 1
                End If
                If Len(tanda) > 0 Then tanda = tanda & ","
                tanda = tanda & """" & JsonEsc(nom) & """:" & j
                enTanda.Add nom: jsTanda.Add j
            Else
                parte = "": primera = True
                For i = 1 To k
                    If Len(parte) > 0 And Len(parte) + Len(filas(i)) > TANDA_MAX Then
                        r = PostHojas(snap, """" & JsonEsc(nom) & """:[" & parte & "]", primera)
                        If r <> "" Then SubirOtrasHojas = r: Exit Function
                        nE = nE + 1: parte = "": primera = False
                    End If
                    If Len(parte) > 0 Then parte = parte & ","
                    parte = parte & filas(i)
                Next i
                If Len(parte) > 0 Then
                    r = PostHojas(snap, """" & JsonEsc(nom) & """:[" & parte & "]", primera)
                    If r <> "" Then SubirOtrasHojas = r: Exit Function
                    nE = nE + 1
                End If
                mUltimo(nom) = j
            End If
        End If
    Next ws
    If Len(tanda) > 0 Then
        r = PostHojas(snap, tanda, True)
        If r <> "" Then SubirOtrasHojas = r: Exit Function
        Recordar enTanda, jsTanda
        nE = nE + 1
    End If
    SubirOtrasHojas = "OK " & nH & " hojas cambiadas en " & nE & " envios"
End Function

Private Sub Recordar(enTanda As Collection, jsTanda As Collection)
    Dim i As Long
    For i = 1 To enTanda.Count: mUltimo(enTanda(i)) = jsTanda(i): Next i
    For i = enTanda.Count To 1 Step -1: enTanda.Remove i: jsTanda.Remove i: Next i
End Sub

' ---- un envio a planilla_hojas_cargar; devuelve "" si salio bien ----
Private Function PostHojas(ByVal snap As String, ByVal hojasJson As String, ByVal reemplazar As Boolean) As String
    On Error GoTo fallo
    Dim http As Object, resp As String
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 10000, 10000, 120000, 120000
    http.Open "POST", SUPA_URL_HOJAS, False
    http.setRequestHeader "apikey", SUPA_KEY
    http.setRequestHeader "Authorization", "Bearer " & SUPA_KEY
    http.setRequestHeader "Content-Type", "application/json"
    http.setRequestHeader "Content-Profile", "GP2"
    http.send "{""p_snapshot_id"":" & snap & ",""p_token"":""" & LP_TOKEN & """" & _
              ",""p_reemplazar"":" & IIf(reemplazar, "true", "false") & _
              ",""p_filas"":{" & hojasJson & "}}"
    resp = http.responseText
    If http.Status = 200 And InStr(resp, """ok"": true") + InStr(resp, """ok"":true") > 0 Then
        PostHojas = ""
    Else
        PostHojas = "HTTP " & http.Status & ": " & Left$(resp, 400)
    End If
    Exit Function
fallo:
    PostHojas = "Error: " & Err.Description
End Function

' ---- una hoja cualquiera: filas() = "[fila,{valores},null,{formulas}]" hasta la ultima celda con algo.
'      Devuelve cuantas filas con datos hay (0 = hoja vacia).
Private Function HojaFilas(ws As Worksheet, filas() As String) As Long
    Dim ultF As Range, ultC As Range, rng As Range
    Set ultF = ws.Cells.Find("*", , xlFormulas, , xlByRows, xlPrevious)
    If ultF Is Nothing Then Exit Function
    Set ultC = ws.Cells.Find("*", , xlFormulas, , xlByColumns, xlPrevious)
    Set rng = ws.Range(ws.Cells(1, 1), ws.Cells(ultF.Row, ultC.Column))

    Dim v2 As Variant, vv As Variant, fo As Variant
    If rng.Cells.CountLarge = 1 Then
        ReDim v2(1 To 1, 1 To 1): ReDim vv(1 To 1, 1 To 1): ReDim fo(1 To 1, 1 To 1)
        v2(1, 1) = rng.Value2: vv(1, 1) = rng.Value: fo(1, 1) = rng.Formula
    Else
        v2 = rng.Value2: vv = rng.Value: fo = rng.Formula
    End If

    Dim nF As Long, nC As Long, r As Long, c As Long, k As Long
    nF = UBound(v2, 1): nC = UBound(v2, 2)
    Dim celdas() As String, forms() As String
    Dim nCel As Long, nFor As Long, col As String, txt As String, f As String
    ReDim filas(1 To nF): ReDim celdas(1 To nC): ReDim forms(1 To nC)

    For r = 1 To nF
        nCel = 0: nFor = 0
        For c = 1 To nC
            If Not IsError(v2(r, c)) Then
                If Not IsEmpty(v2(r, c)) Then
                    txt = ValorTxt(v2(r, c), vv(r, c))
                    If Len(txt) > 0 Then
                        col = ColLetra(c)
                        nCel = nCel + 1
                        celdas(nCel) = """" & col & """:""" & JsonEsc(txt) & """"
                        f = CStr(fo(r, c))
                        If Left$(f, 1) = "=" Then
                            nFor = nFor + 1
                            forms(nFor) = """" & col & """:""" & JsonEsc(f) & """"
                        End If
                    End If
                End If
            End If
        Next c
        If nCel > 0 Then
            k = k + 1
            If nFor > 0 Then f = "{" & UnirN(forms, nFor) & "}" Else f = "null"
            filas(k) = "[" & r & ",{" & UnirN(celdas, nCel) & "},null," & f & "]"
        End If
    Next r
    If k = 0 Then Exit Function
    ReDim Preserve filas(1 To k)
    HojaFilas = k
End Function

' ---- valor de celda: fechas en ISO, numeros con PUNTO, el resto como texto ----
Private Function ValorTxt(ByVal v2 As Variant, ByVal v As Variant) As String
    If VarType(v) = vbDate Then
        ValorTxt = Format$(v, "yyyy-mm-dd")
    ElseIf VarType(v2) = vbDouble Or VarType(v2) = vbCurrency Then
        ValorTxt = NumTxt(v2)
    ElseIf VarType(v2) = vbBoolean Then
        ValorTxt = IIf(v2, "true", "false")
    Else
        ValorTxt = Trim$(CStr(v2))
    End If
End Function

Private Function UnirN(arr() As String, ByVal n As Long) As String
    Dim t() As String, i As Long
    ReDim t(1 To n)
    For i = 1 To n: t(i) = arr(i): Next i
    UnirN = Join(t, ",")
End Function

Private Function ColLetra(ByVal c As Long) As String
    Dim s As String
    Do While c > 0
        s = Chr$(65 + ((c - 1) Mod 26)) & s
        c = (c - 1) \ 26
    Loop
    ColLetra = s
End Function

' ---- "clave": 123  ->  "123" (lee un numero del JSON de respuesta) ----
Private Function JsonNum(ByVal js As String, ByVal clave As String) As String
    Dim p As Long, i As Long, ch As String
    p = InStr(js, """" & clave & """")
    If p = 0 Then Exit Function
    p = InStr(p, js, ":")
    If p = 0 Then Exit Function
    For i = p + 1 To Len(js)
        ch = Mid$(js, i, 1)
        If ch Like "[0-9]" Then
            JsonNum = JsonNum & ch
        ElseIf Len(JsonNum) > 0 Or ch <> " " Then
            Exit For
        End If
    Next i
End Function

' ---- [[fila,{celdas},null,null], ...] con las filas que tienen algo en A..P ----
Private Function FilasJson(ws As Worksheet) As String
    Dim ultFila As Long, r As Long, c As Long, rr As Long
    Dim sb As String, celdas As String, v As Variant, col As String, txt As String, primera As Boolean

    For c = 1 To ULTIMA_COL
        rr = ws.Cells(ws.Rows.Count, c).End(xlUp).Row
        If rr > ultFila Then ultFila = rr
    Next c

    sb = "["
    primera = True
    For r = 1 To ultFila
        celdas = ""
        For c = 1 To ULTIMA_COL
            v = ws.Cells(r, c).Value2
            If Not IsError(v) Then
                If Not IsEmpty(v) And Len(Trim$(CStr(v))) > 0 Then
                    col = Chr$(64 + c)
                    txt = CeldaTxt(ws.Cells(r, c), col)
                    If Len(txt) > 0 Then
                        If Len(celdas) > 0 Then celdas = celdas & ","
                        celdas = celdas & """" & col & """:""" & JsonEsc(txt) & """"
                    End If
                End If
            End If
        Next c
        If Len(celdas) > 0 Then
            If Not primera Then sb = sb & ","
            sb = sb & "[" & r & ",{" & celdas & "},null,null]"
            primera = False
        End If
    Next r
    FilasJson = sb & "]"
End Function

' ---- fechas I/N en ISO; numeros con PUNTO decimal; el resto, el texto visible ----
Private Function CeldaTxt(celda As Range, col As String) As String
    Dim v As Variant
    v = celda.Value2
    If (col = "I" Or col = "N") And IsDate(celda.Value) Then
        CeldaTxt = Format$(celda.Value, "yyyy-mm-dd")
    ElseIf VarType(v) = vbDouble Or VarType(v) = vbCurrency Then
        CeldaTxt = NumTxt(v)
    Else
        CeldaTxt = CStr(celda.Value)
    End If
End Function

' ---- numero -> texto con PUNTO decimal y sin miles (Str usa siempre punto) ----
Private Function NumTxt(v As Variant) As String
    If VarType(v) <> vbDouble And VarType(v) <> vbCurrency And VarType(v) <> vbLong And VarType(v) <> vbInteger Then
        NumTxt = "": Exit Function
    End If
    NumTxt = Trim$(Str$(v))
    If Left$(NumTxt, 1) = "." Then NumTxt = "0" & NumTxt
    If Left$(NumTxt, 2) = "-." Then NumTxt = "-0" & Mid$(NumTxt, 2)
End Function

Private Function JsonEsc(ByVal s As String) As String
    Dim t As String
    t = Replace(s, "\", "\\")
    t = Replace(t, """", "\""")
    t = Replace(t, vbCrLf, "\n")
    t = Replace(t, vbCr, "\n")
    t = Replace(t, vbLf, "\n")
    t = Replace(t, vbTab, "\t")
    JsonEsc = t
End Function
