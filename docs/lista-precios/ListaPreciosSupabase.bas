Attribute VB_Name = "ListaPreciosSupabase"
' =============================================================================
'  A Costos VIGENTES -> Supabase (GP2)                               v27.66
'  Idea 7358 (Thomas 02/10, retomada por Luis 07/10)
'
'  Al GUARDAR el Excel, si se toco la hoja "Lista de Precios " la sube a
'  Supabase ("GP2".lista_precios_subir). La base la compara contra la subida
'  anterior (por la col A, comparando la col G) y manda a Telegram (grupo de
'  gerencia) los aumentos, bajas, nuevos, sacados y el cambio de dolar.
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
Private Const ULTIMA_COL As Long = 16               ' A..P
' -----------------------------------------------------------------------------

Private mTocada As Boolean

' Llamar desde ThisWorkbook.Workbook_SheetChange
Public Sub LPMarcarHoja(ByVal Sh As Object)
    If Sh.Name = HOJA Then mTocada = True
End Sub

' Llamar desde ThisWorkbook.Workbook_AfterSave
Public Sub LPDespuesDeGuardar(ByVal Success As Boolean)
    If Not Success Or Not mTocada Then Exit Sub
    Dim r As String
    r = LPSubir(True)
    If Left$(r, 3) = "OK " Then
        mTocada = False
        Application.StatusBar = "Lista de Precios subida a Supabase: " & r
    Else
        MsgBox "El Excel se guardo bien, pero NO se pudo subir la Lista de Precios:" & vbLf & r & vbLf & vbLf & _
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

    If http.Status = 200 And InStr(resp, """ok"": true") + InStr(resp, """ok"":true") > 0 Then
        LPSubir = "OK " & resp
    Else
        LPSubir = "HTTP " & http.Status & ": " & Left$(resp, 400)
    End If
    Exit Function
fallo:
    LPSubir = "Error: " & Err.Description
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
