Attribute VB_Name = "ConciliacionSupabase"
' =============================================================================
'  Conciliacion bancaria -> Supabase (Gestion Virgilio)            v22.88
'
'  Al GUARDAR el Excel, manda a Supabase las hojas "CONCILIACION <año>" que se
'  tocaron desde el ultimo guardado. Cada envio REEMPLAZA ese año de ese banco,
'  asi que una correccion en el Excel queda corregida en la base.
'
'  No cambia nada del Excel. Si no hay internet, avisa y el Excel queda guardado
'  igual; al proximo guardado (o con SubirTodasLasHojas) se vuelve a mandar.
'
'  INSTALACION: ver INSTALAR.md en la misma carpeta.
' =============================================================================
Option Explicit

' --- CONFIGURACION -----------------------------------------------------------
' Banco de ESTE archivo. Dejar "" para detectarlo por el nombre del archivo.
'   credicoop_lk | santander_lk | credicoop_ch | santander_ch
Private Const CONC_BANCO As String = ""

Private Const SUPA_URL As String = "https://hrxfctzncixxqmpfhskv.supabase.co/rest/v1/rpc/gv_conc_cargar"
Private Const SUPA_KEY As String = "__CLAVE_PUBLICA__"      ' sb_publishable_... del proyecto
Private Const CONC_TOKEN As String = "__TOKEN__"           ' GV_Conc_Token (secreto: no compartir)
' -----------------------------------------------------------------------------

Private mHojasTocadas As Object   ' Scripting.Dictionary: nombre de hoja -> True

' Llamar desde ThisWorkbook.Workbook_SheetChange
Public Sub ConcMarcarHoja(ByVal Sh As Object)
    If mHojasTocadas Is Nothing Then Set mHojasTocadas = CreateObject("Scripting.Dictionary")
    If ConcAnioDeHoja(Sh.Name) > 0 Then mHojasTocadas(Sh.Name) = True
End Sub

' Llamar desde ThisWorkbook.Workbook_AfterSave
Public Sub ConcDespuesDeGuardar(ByVal Success As Boolean)
    If Not Success Then Exit Sub
    If mHojasTocadas Is Nothing Then Exit Sub
    If mHojasTocadas.Count = 0 Then Exit Sub
    Dim k As Variant, errores As String, ok As String, r As String
    For Each k In mHojasTocadas.Keys
        r = ConcSubirHoja(ThisWorkbook.Worksheets(CStr(k)))
        If Left$(r, 3) = "OK " Then ok = ok & vbLf & r Else errores = errores & vbLf & r
    Next k
    If Len(errores) = 0 Then
        mHojasTocadas.RemoveAll
        Application.StatusBar = "Conciliacion subida a Supabase:" & Replace(ok, vbLf, "  ")
    Else
        ' las que fallaron quedan marcadas y se reintentan al proximo guardado
        Dim k2 As Variant
        For Each k2 In mHojasTocadas.Keys
            If InStr(ok, CStr(k2)) > 0 Then mHojasTocadas.Remove k2
        Next k2
        MsgBox "El Excel se guardo bien, pero NO se pudo subir a Supabase:" & errores & vbLf & vbLf & _
               "Se vuelve a intentar al proximo guardado.", vbExclamation, "Conciliacion"
    End If
End Sub

' Manual: sube TODAS las hojas de año del archivo (Alt+F8 -> SubirTodasLasHojas)
Public Sub SubirTodasLasHojas()
    Dim ws As Worksheet, res As String
    For Each ws In ThisWorkbook.Worksheets
        If ConcAnioDeHoja(ws.Name) > 0 Then res = res & vbLf & ConcSubirHoja(ws)
    Next ws
    MsgBox "Resultado:" & res, vbInformation, "Conciliacion"
End Sub

' Manual: sube sólo la hoja activa
Public Sub SubirHojaActiva()
    If ConcAnioDeHoja(ActiveSheet.Name) = 0 Then
        MsgBox "La hoja activa no es una hoja de año (CONCILIACION 2026, AÑO 2026...).", vbExclamation
        Exit Sub
    End If
    MsgBox ConcSubirHoja(ActiveSheet), vbInformation, "Conciliacion"
End Sub

' ---------------------------------------------------------------------------
Private Function ConcAnioDeHoja(ByVal nombre As String) As Integer
    Dim n As String: n = Trim$(nombre)
    ConcAnioDeHoja = 0
    If InStr(n, "(") > 0 Then Exit Function              ' copias "2026 (2)" no se suben
    If Len(n) < 4 Then Exit Function
    Dim a As String: a = Right$(n, 4)
    If a Like "20##" Then ConcAnioDeHoja = CInt(a)
End Function

Private Function ConcBanco() As String
    If CONC_BANCO <> "" Then ConcBanco = CONC_BANCO: Exit Function
    Dim f As String: f = UCase$(ThisWorkbook.Name)
    Dim chef As Boolean: chef = (InStr(f, "CHEF") > 0)
    If InStr(f, "CREDICOOP") > 0 Then
        ConcBanco = IIf(chef, "credicoop_ch", "credicoop_lk")
    ElseIf InStr(f, "SANTANDER") > 0 Or InStr(f, "RIO") > 0 Then
        ConcBanco = IIf(chef, "santander_ch", "santander_lk")
    Else
        ConcBanco = ""
    End If
End Function

Private Function ConcSubirHoja(ByVal ws As Worksheet) As String
    Dim banco As String: banco = ConcBanco()
    If banco = "" Then ConcSubirHoja = "? no se reconoce el banco por el nombre del archivo: completar CONC_BANCO": Exit Function
    Dim anio As Integer: anio = ConcAnioDeHoja(ws.Name)

    Dim ur As Range: Set ur = ws.UsedRange
    Dim v As Variant: v = ur.Value2
    If Not IsArray(v) Then ConcSubirHoja = "? " & ws.Name & ": hoja vacia": Exit Function
    Dim r0 As Long: r0 = ur.Row
    Dim c0 As Long: c0 = ur.Column

    Dim filas() As String, nf As Long, i As Long, j As Long, ultima As Long
    ReDim filas(1 To UBound(v, 1))
    For i = 1 To UBound(v, 1)
        ultima = 0
        For j = UBound(v, 2) To 1 Step -1
            If Not ConcVacia(v(i, j)) Then ultima = j: Exit For
        Next j
        If ultima > 0 Then
            Dim celdas() As String
            ' la columna A es siempre la 0, aunque el UsedRange empiece mas a la derecha
            ReDim celdas(0 To c0 - 1 + ultima - 1)
            For j = 0 To c0 - 2: celdas(j) = """""": Next j
            For j = 1 To ultima: celdas(c0 - 2 + j) = ConcJson(v(i, j)): Next j
            nf = nf + 1
            filas(nf) = "{""fila"":" & (r0 + i - 1) & ",""c"":[" & Join(celdas, ",") & "]}"
        End If
    Next i
    If nf = 0 Then ConcSubirHoja = "? " & ws.Name & ": hoja vacia": Exit Function
    ReDim Preserve filas(1 To nf)

    Dim body As String
    body = "{""p_banco"":""" & banco & """,""p_anio"":" & anio & _
           ",""p_archivo"":" & ConcJson(ThisWorkbook.Name & " - hoja " & ws.Name & " - " & Environ$("USERNAME")) & _
           ",""p_token"":""" & CONC_TOKEN & """,""p_filas"":[" & Join(filas, ",") & "]}"

    On Error GoTo fallo
    Application.StatusBar = "Subiendo " & ws.Name & " a Supabase..."
    Dim http As Object: Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 10000, 10000, 120000, 120000
    http.Open "POST", SUPA_URL, False
    http.setRequestHeader "Content-Type", "application/json; charset=utf-8"
    http.setRequestHeader "apikey", SUPA_KEY
    http.setRequestHeader "Authorization", "Bearer " & SUPA_KEY
    http.send ConcUtf8(body)
    Application.StatusBar = False
    If http.Status = 200 Then
        ConcSubirHoja = "OK " & ws.Name & ": " & ConcCampo(http.responseText, "filas") & " movimientos"
    Else
        ConcSubirHoja = "X " & ws.Name & ": " & http.Status & " " & Left$(http.responseText, 300)
    End If
    Exit Function
fallo:
    Application.StatusBar = False
    ConcSubirHoja = "X " & ws.Name & ": " & Err.Description
End Function

Private Function ConcVacia(ByVal x As Variant) As Boolean
    If IsError(x) Then ConcVacia = True: Exit Function
    If IsEmpty(x) Then ConcVacia = True: Exit Function
    If VarType(x) = vbString Then ConcVacia = (Len(Trim$(x)) = 0) Else ConcVacia = False
End Function

' valor de celda -> JSON (numeros con punto decimal; fechas llegan como numero de serie)
Private Function ConcJson(ByVal x As Variant) As String
    If IsError(x) Or IsEmpty(x) Then ConcJson = """""": Exit Function
    Select Case VarType(x)
        Case vbDouble, vbSingle, vbInteger, vbLong, vbCurrency, vbDecimal
            ConcJson = Trim$(Str$(x))
            If Left$(ConcJson, 1) = "." Then ConcJson = "0" & ConcJson
            If Left$(ConcJson, 2) = "-." Then ConcJson = "-0" & Mid$(ConcJson, 2)
        Case vbBoolean
            ConcJson = IIf(x, """VERDADERO""", """FALSO""")
        Case Else
            Dim s As String: s = CStr(x)
            s = Replace(s, "\", "\\")
            s = Replace(s, """", "\""")
            s = Replace(s, vbCrLf, "\n")
            s = Replace(s, vbCr, "\n")
            s = Replace(s, vbLf, "\n")
            s = Replace(s, vbTab, "\t")
            ConcJson = """" & s & """"
    End Select
End Function

Private Function ConcUtf8(ByVal s As String) As Variant
    Dim st As Object: Set st = CreateObject("ADODB.Stream")
    st.Type = 2: st.Charset = "utf-8": st.Open
    st.WriteText s
    st.Position = 0: st.Type = 1: st.Position = 3        ' salta el BOM
    ConcUtf8 = st.Read
    st.Close
End Function

Private Function ConcCampo(ByVal json As String, ByVal campo As String) As String
    Dim p As Long: p = InStr(json, """" & campo & """:")
    If p = 0 Then Exit Function
    p = p + Len(campo) + 3
    Dim q As Long: q = p
    Do While q <= Len(json) And InStr(",}", Mid$(json, q, 1)) = 0: q = q + 1: Loop
    ConcCampo = Trim$(Mid$(json, p, q - p))
End Function
